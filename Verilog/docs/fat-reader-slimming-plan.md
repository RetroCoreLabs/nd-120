# ND-120 SD/FAT reader slimming plan

Target: shrink the hardware FAT reader
`Verilog/SD-FAT/circuit/sd_file_reader.v`, the
single biggest logic block on the Tang Nano 20K (GW2AR-18C) and the reason the
OSS (yosys/nextpnr) placer runs out of room (July 2026).

**Status (checked against the code, 28-SEP-2026):** Lever 1 is DONE
(`SDFAT_NO_LFN`, set in `fpga/tang-nano-20k/src/tang20k_defines.v`).
Lever 2 is DONE and went further than planned: the contiguity checker is
retired from every build since the engine walks the FAT chain itself
(07-AUG-2026; it now needs `-DSDFAT_FORCE_STORAGE_CHECK`). Lever 3 was NOT
done and no longer applies: since the block cache (04-AUG-2026) `sd_writer`
is also the engine that reads every block from the card, so a storage build
cannot drop it (`SDFAT_NO_WRITE` exists in `sd_fat_features.vh` but only the
sd-fat-test lint build uses it). Lever 4 (raw-LBA boot) is not built and is
the one lever still open. The defines are documented in
`Verilog/docs/build-defines.md` and `tang20k_defines.v`.

## How the numbers were produced (so they can be trusted / reproduced)

All LUT figures below are from **yosys `synth_gowin -noflatten`** (the Gowin
GW2A LUT4 + ALU carry-cell architecture), run in a scratch tree on ext4
(`/tmp/fatscan`), never against the repo build. The flow per module:

```
read_verilog <file>
hierarchy -top sd_file_reader
setattr -mod -set keep_hierarchy 1      # baseline only, to split the sub-instance
synth_gowin -noflatten
stat
```

- yosys is an **estimator**, not the Gowin vendor mapper. Its LUT4 count and
  the Gowin toolchain's count differ in absolute terms; the **relative
  attribution between sub-functions** is what this plan relies on.
- Gowin counts an **ALU** carry cell as occupying a LUT slot, so the honest
  "logic cells" figure is **LUT + ALU**. On Gowin's own synth Ronny observed
  ~8930 cells for the reader; yosys gives **7718 LUT + 1429 ALU = 9147** — the
  same ballpark, which is the cross-check that the attribution is sound.
- The 512-byte sector buffer `secbuf` (`sd_file_reader.v:289`) maps to **1
  BSRAM (SDP) block, not LUTs** — confirmed by `SDP 1` in the baseline stat. It
  is not a LUT lever.

Scratch scripts and raw stat dumps: `/tmp/fatscan/*.ys`, `/tmp/fatscan/stat_*.txt`.

---

## (a) sd_file_reader LUT breakdown by function

`sd_file_reader.v` contains **two** modules: `sd_file_reader` (the FAT brain)
and `sd_card_ctrl` (the SD bit engine), in the same file. yosys, keeping the
hierarchy, splits them cleanly:

| Block | Where (file:line) | LUT | ALU | LUT+ALU | Share |
|---|---|---:|---:|---:|---:|
| **`sd_card_ctrl`** SD bit engine: CMD/response shifter, R2 shadow, CRC7, CRC16, CMD17/18/12 data FSM, bit clock | `sd_file_reader.v:1245-1537` | 533 | 205 | **738** | ~8% |
| **`sd_file_reader`** FAT brain: card-init FSM, mount/BPB/MBR parse, root-dir scan, VFAT+8.3 entry parser, FAT-entry fetch, cluster-chain walk + run merge, CSD decode, geometry math | `sd_file_reader.v:60-1214` | 7185 | 1224 | **8409** | ~92% |
| **Whole reader** | | **7718** | **1429** | **9147** | 100% |

**The bit engine is small (~8%). The FAT-parsing brain is 92% of the cost.**
That is where every lever lives.

### Finer attribution inside the FAT brain (measured by ablation)

Because almost everything lives in one Verilog module, sub-functions were
attributed by **synthesizing scratch variants** with a feature forced off and
diffing against the 9147 baseline:

| Sub-function | Measurement | LUT+ALU delta | Notes |
|---|---|---:|---|
| **VFAT long-filename (LFN) parser** | force the `pattr==0x0F` branch to skip; opt_clean removes `lfn_buf`, `P_LFNU`, `lfn_off`, the `plo/phi` variable part-selects | **~1800** (1751 LUT + 51 ALU) | baseline 9147 → **7345**. Biggest single removable chunk. |
| **FAT32 support** | force `is32` constant 0 (`sd_file_reader.v:971`) | **~0** (measured +370 LUT — mapping noise, ALU unchanged at 1429) | The cluster/sector datapath is **32-bit wide for FAT16 too**; FAT32 only adds narrow muxes, so removing it frees almost nothing. **Not a lever.** |

The remaining ~5500 LUT of the FAT brain is spread across the wide
`proc[255:0]` / `raw[247:0]` variable bit-selects in the entry parser
(`sd_file_reader.v:333-341`, states `P_SFN`..`P_CMP` `:625-712`), the 32-bit
geometry math including a **32-bit multiply** `fatarea = nfat * spf_v`
(`sd_file_reader.v:404`, part of the 1224 ALU), the field-fetch/secbuf
addressing, and the card-init + streaming FSMs. These do not decompose further
without a rewrite; they are not cheap single-`ifdef` wins.

### Explicit answer: subdirectory traversal

**Our reader does NOT implement subdirectory descent, so there is no
subdirectory-traversal logic to remove — that lever yields 0 LUT.**

- The root directory is scanned linearly (FAT16 root region) or by walking the
  **root directory's own cluster chain** on FAT32 (`H_DIR_HOP`,
  `sd_file_reader.v:1067-1075`). That HOP follows the root dir when it spans
  clusters; it does **not** descend into nested folders.
- `dir_entry_is_dir` (`sd_file_reader.v:97`, set at `:639`) is *reported* but
  never acted on — nothing ever re-points the scan at a subdirectory's cluster.
- So "keep root-dir lookup, drop subdir traversal" is **already the design**.
  BOOT.BPUN / TAPE.BPUN living in the root is found by the existing root scan.
  No edit, no saving — the feature was never built.

---

## (b) What was dead weight in the Tang build (July 2026)

At the time the Tang build compiled the full stack with no `SDFAT_NO_*`
macro. Measured with yosys, for the tape-only case:

| block | LUT | ALU | LUT+ALU | outcome |
|---|---:|---:|---:|---|
| `sd_writer` (CMD24 write engine) | 954 | 127 | 1081 | still in every storage build - it is the block read engine too since Phase 4 |
| `nd_storage_fatchk` (contiguity checker) | 868 | 309 | 1177 | retired from builds |
| VFAT long-name parser in the reader | 1751 | 51 | ~1800 | stripped by `SDFAT_NO_LFN` on the Tang |

The reader never drives DAT0 and has no CMD24 of its own; the write path is
the separate `sd_writer` instance in `nd_storage.v`. FAT32 costs essentially
nothing (section (a)), so it stays.

---

## (c) Ranked slimming levers

Ordered by (saving ÷ risk). Savings are yosys LUT+ALU deltas.

### Lever 1 — Strip VFAT long-filename parsing (8.3 names only)  ~1800 LUT - DONE
`SDFAT_NO_LFN` in `sd_file_reader.v`; measured 9147 -> 7345. Files must have
8.3 short names (all the fixed card names are).

### Lever 2 — Drop the contiguity checker  ~1177 LUT - DONE (retired from builds)

### Lever 3 — Remove the write engine for a read-only build  ~1081 LUT - NOT APPLICABLE
The planned `SDFAT_WRITE` gate on the `sd_writer` instance in `nd_storage.v`
was never added, and since Phase 4 `sd_writer` in `rd_mode` fetches every
block from the card, so it cannot be removed from a storage build.

### Lever 4 (ultimate) — RAW-BLOCK boot mode: reserved LBAs, NO FAT parse  ~7500 LUT
- **Saving (analytic estimate):** everything except the SD bit engine + card
  init + a fixed-range CMD18 streamer survives. That is ~`sd_card_ctrl` (738) +
  card-init FSM `H_BOOT`..`H_CMD16` (`:737-889`, a few hundred LUT) + a small
  sector counter ≈ **1200–1600 LUT+ALU total**, i.e. **~7500 LUT saved** vs the
  9147 baseline. This removes the entire mount/BPB/MBR parse (`:892-1025`), the
  whole entry parser incl. LFN (`:297-732`), FAT-entry fetch (`:1078-1106`),
  cluster-chain walk + run merge (`:1108-1159`), and CSD decode (`:846-867`).
- **Edit point:** a new lean top (e.g. `sd_block_reader.v`) reusing
  `sd_card_ctrl` unchanged, or an `SDFAT_RAW_LBA` mode in the reader that jumps
  from `H_CMD16` straight to a fixed-`e_arg` CMD18 stream. New module, not a
  one-line `ifdef`.
- **Functional cost:** the card must be prepared by writing the image to known
  reserved physical sectors (`dd` to LBA N), no FAT filesystem — you lose the
  "drop a .BPUN file on the card" convenience.
- **Risk:** medium (new RTL to write + verify) but conceptually simple and the
  bit engine is already silicon-proven at 13.5 MHz.
- **This is also the floppy/SMD path** in Ronny's plan: reserved physical blocks
  (raw LBA), no FAT, one lean reader shared by every device.

### Lever 5 (do NOT bother) — Drop FAT32
- **Measured saving ~0** (see (a)). The 32-bit datapath is shared with FAT16.
  Keep dual-format support; it is effectively free.

### Minor levers (small, optional)
- **CSD capacity decode** (`card_capacity_mb`, `H_CSD`/`H_CSD1` `:846-867`,
  decode wires `:226-238`): already written bit-serial to *avoid* a ~200-LUT
  barrel shifter (see the author's note `:236-237`). Removing capacity
  reporting entirely (tie `card_capacity_mb` off, skip CMD9) saves ~100-200 LUT.
  Cosmetic only. Low priority.
- **`dir_entry_*` LIST enumeration outputs** are already unconnected in
  `nd_storage.v:188-194`; yosys prunes the unused output ports in-context, but
  the internal 8.3 name-build feeds the target compare and cannot be pruned.
  No meaningful standalone lever.

---

## (d) Internet comparison

Our reader is a **clean-room MIT rewrite** (`sd_file_reader.v:1-58`) that
replaced the GPL WangXuan95 core. Comparing scope fairly:

| Core | FAT16 | FAT32 | Dir scope | Long names (LFN) | Write | Extra outputs | Reported LUTs |
|---|---|---|---|---|---|---|---|
| **ours (`sd_file_reader.v`)** | yes | yes | **root only** | **yes (VFAT)** | no (reader) | CSD capacity, MBR partition walk, full `dir_entry_*` LIST enumeration, rich `fs_*` geometry | ~9147 (yosys) / ~8930 (Gowin) |
| **WangXuan95 FPGA-SDcard-Reader** (the GPL core we replaced) | yes | yes | root only | **no (8.3 only)** | no | file locate + length only | none published |
| WangXuan95 FPGA-SDcard-Reader-SPI | yes | yes | root only | no | no | minimal | none published |
| sd2snes / retro FAT cores | typ. FAT32 | — | root/table | usually no | some write | core-specific | none in a comparable form |

Key takeaways:
- **We match the reference on the fundamentals** (FAT16+FAT32, root-only, 1-bit
  DAT0, no tristate) — so on those axes we are **not** bloated.
- **We carry weight the reference does NOT:** (1) **VFAT long-filename
  parsing** — the WangXuan95 core is 8.3-only; our LFN overlay is the ~1800-LUT
  Lever 1. (2) **CSD capacity decode**, **MBR partition-table walk**, and a full
  **`dir_entry_*` directory-LIST enumeration** with dates/sizes — the reference
  just locates one file. These extras are real logic the baseline doesn't spend.
- None of these public cores publish a LUT table, so a like-for-like number
  comparison isn't available — but the **feature delta is unambiguous**: strip
  LFN (Lever 1) and our reader's feature set lands back on the WangXuan95
  baseline, minus the CSD/MBR/LIST extras.

Verdict: **the reader is not fundamentally bloated for what a FAT16/32
root-directory read-by-name core costs — but it does carry ~1800 LUT of VFAT
long-name logic and a few hundred LUT of capacity/partition/LIST conveniences
that the tape-boot job never uses.**

Sources:
- [WangXuan95/FPGA-SDcard-Reader](https://github.com/WangXuan95/FPGA-SDcard-Reader) — FAT16/FAT32, root-dir only, 8.3 names only, read-only, no LUT table published (confirmed via its [README](https://github.com/WangXuan95/FPGA-SDcard-Reader/blob/main/README.md)).
- [WangXuan95/FPGA-SDcard-Reader-SPI](https://github.com/WangXuan95/FPGA-SDcard-Reader-SPI) — SPI variant, same feature scope.
- [Reading FAT32 inside an FPGA core (ws0.org)](https://ws0.org/reading-fat32-inside-a-fpga-core/) — context on keeping in-core FAT parsing small.

---

## (e) What remains: raw-LBA boot

Tier A of this plan (levers 1-3) is done as far as it applies (see the status
at the top). Tier B is still open:

### Tier B — raw-LBA boot (maximum saving, needs new RTL)
Lever 4: a lean `sd_card_ctrl`-based block reader that streams a fixed reserved
LBA range. No FAT at all.

- **Est. saving: ~7500 LUT+ALU** (reader collapses to ~1200-1600).
- Card recipe: `dd` the image to a reserved sector; no filesystem.
- This is the same core the **floppy and SMD** devices should share (Ronny's
  reserved-physical-block plan), so the cost is amortized across every future
  device — build it once.

Note: the storage stack now walks the FAT chain per access and serves disc
images from the card by name, so the case for a raw-LBA reader is only the
LUT saving; it would give up the drop-a-file-on-the-card workflow.

---

*Analysis produced from source at `SD-FAT/circuit/sd_file_reader.v`,
`nd_storage.v`, `sd_fat_features.vh` and the Tang gprj; LUT figures from yosys
`synth_gowin` in a scratch tree. Line numbers refer to the July 2026 sources.*
