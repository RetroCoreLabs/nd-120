# SD-FAT - reusable SD card + FAT filesystem library

Board-independent SD card access for the ND-120 project. It is the
storage backend of the ND-100 bus devices (paper tape reader 400, floppy,
SMD, Winchester) and of the standalone board test projects.

Consumers: `Verilog/fpga/tang-nano-20k/sd-fat-test/` (interactive UART
menu; proven on hardware 11-JUL-2026), and `nd_storage` - the multi-client
storage facade for the ND-100 bus devices (spec, validation and design in
`Verilog/docs/nd-storage-*.md`). SINTRAN III boots on the Tang Nano 20K
from a Winchester image on the SD card through `nd_storage`
(24-AUG-2026, `Verilog/docs/nd-storage-design.md`).

## Contents

Everything in this library is ORIGINAL project code under the repository's
MIT license. `sd_file_reader.v` and `sd_writer.v` are clean-room
implementations written from the public SD Physical Layer Simplified
Specification and the Microsoft FAT specification.

SD/FAT code lives ONLY in `Verilog/SD-FAT/` (the generic library) and
`fpga/<board>/` (board glue) - never in `DELILAH-CPU/`, `DECODE-GateArray/`
or `CPU-BOARD-3202/`.

| File | Origin | Function |
|---|---|---|
| `circuit/sd_file_reader.v` | project (MIT) | CLEAN-ROOM card init (CMD0/8/55/ACMD41/2/3/7/16, SDv1/SDv2/SDHC, SD-native 1-bit) + MBR/DBR parse, FAT16/FAT32 mount, root-directory scan (8.3 + VFAT long names), cluster-chain following, whole-file byte stream (CMD18 multi-block runs, per-block CRC16 verify; 13.5 MHz data clock at CLK_DIV=1). Includes the `sd_card_ctrl` command/data bit engine (same file). |
| `circuit/sd_writer.v` | project (MIT) | CLEAN-ROOM sector engine on an already-initialized card: CMD24 write + CMD17 read (single-sector API, unchanged), plus CMD25/CMD18 multi-block bursts with ACMD23 and CMD12 (burst_len/rca/block_next ports; default 13.5 MHz bit clock). Optional 4-bit DAT bus (`use_4bit` input; ACMD6 per op, nibbles on DAT3..DAT0, CRC16 per line, status/busy on DAT0) - unconnected/0 keeps the original 1-bit engine bit-exact. |
| `circuit/sd_fat_rewrite.v` | project (MIT) | FAT16/FAT32 in-place file replacement: frees the old cluster chain, allocates a contiguous new one, patches the directory entry (size + first cluster, both FAT copies) - the "delete + recreate" behind COPY. |
| `circuit/sd_fat_check.v` | project (MIT) | Read-only cluster-chain validator ("fsck-lite"): walks each file's FAT chain, reports length vs expected, flags free/out-of-range/looping pointers. |
| `sim/sd_card_model.v` | project | Behavioral SD card for iverilog testbenches: serves sector reads from a raw image file, ACCEPTS CMD24 writes and CMD25 bursts into the image (CRC16 checked, per-block busy), streams CMD18 bursts, handles ACMD23/CMD12 (counted), checks command CRC7, answers with real CRCs; ACMD6 4-bit bus mode (nibble framing, CRC16 per DAT line, per-line CRC-error injection via `corrupt_line`, status/busy on DAT0 only) |
| `sim/sd_writer_tb.v` + `sim/Makefile` | project | sd_writer unit test incl. the CMD25/CMD18 burst cases, a mid-burst CRC-status abort, and the 4-bit phase (single + burst both ways, injected per-line CRC error, DAT1-3 discipline monitor) after the full 1-bit suite as regression (registered in the global test registry as `SD-FAT/sim :: test-writer`) |
| `circuit/nds_sync.v` | project (MIT) | 2-flop toggle/pulse + level CDC primitives for nd_storage |
| `circuit/nd_storage_engine.v` | project (MIT) | nd_storage block engine: round-robin arbiter (up to 8 clients; `nd_storage` sets 8), per-client clk_cpu front-ends, CDC word bridge, cache fill, FAT-chain resolve, write-through (spec: docs/nd-storage-interface-spec.md, design: docs/nd-storage-design.md) |
| `circuit/nd_storage_mount.v` | project (MIT) | nd_storage open FSM: per-open reader re-init, root-file scan, geometry latch, reader park (no preload since 04-AUG-2026; `M_LOAD` is dead code) |
| `circuit/nd_storage.v` | project (MIT) | nd_storage top: reader+writer instances, phase_write SD pin mux, mount/engine mem-port mux, fatchk writer-command mux (rd_mode=1 while chk_busy), FILEn/SLOTn parameter set, CACHE_MASK / cache directory, sd_status/card_type/fs_type |
| `circuit/nd_storage_fatchk.v` | project (MIT) | Mount-time contiguity checker (SDFAT_STORAGE_CHECK): verifies FAT[c]=c+1 over the opened file's whole chain + end-of-chain via sd_writer CMD17 reads (FAT16 + FAT32, cached FAT sector); machine ok/bad verdict. Diagnostic only since 07-AUG-2026 (`-DSDFAT_FORCE_STORAGE_CHECK`); the engine walks the FAT chain, so fragmented files work |
| `circuit/nd_storage_cache.v` | project (MIT) | tag/LRU directory of the shared block cache (design: docs/nd-storage-design.md 2.7) |
| `sim/nds_mem_model.v` | project | behavioral SDRAM device-port model (randomized latency) |
| `sim/nd_storage_cdc_tb.v`, `nd_storage_engine_tb.v`, `nd_storage_write_tb.v` | project | registered gates test-nds-cdc / test-nds-engine / test-nds-write |
| `sim/nd_storage_tb.v` + `sim/make_storage_image.sh` | project | full-stack mount gate test-nds-mount (real FAT16 image: open/preload, missing/oversize/SMD open_err, block read, reopen); the image script also builds the deliberately fragmented FRAG.IMG and REFUSES to emit it unless a python FAT re-walk proves the fragmentation |
| `sim/nd_storage_fatchk_unit_tb.v`, `sim/nd_storage_fatchk_tb.v` | project | registered fatchk gates test-nds-fatchk-unit (checker vs scripted engine stub: FAT16/FAT32 formats, EOC thresholds, read-count/cache, guards) and test-nds-fatchk (full stack vs FRAG.IMG: open_err, contiguous neighbor opens, retry; + feature-off elaboration lint) |

## The reader's interface (binding feature set)

`sd_file_reader.v` (clean-room, 12-JUL-2026; it replaced an earlier
vendored reader and had to keep its interface) provides:

1. `scan_done` output - the internal filesystem FSM reached DONE
   (file fully streamed, file not found, or unmountable filesystem).
2. `found_file_size` output - byte size of the found file.
3. Runtime target file name (`target_name`, byte 0 in the low byte,
   case-insensitive + `target_len`). `target_len = 0` never matches:
   directory scan only ("LIST" mode).
4. Directory-entry outputs (`dir_entry_valid` / `dir_entry_name` /
   `dir_entry_len` / `dir_entry_size` / `dir_entry_date` /
   `dir_entry_cluster` / `dir_entry_is_dir`) - every plain file AND
   subdirectory root entry walked during a scan is reported (long name
   if present, else 8.3, uppercase; raw FAT date word; full first
   cluster; directory flag).
5. `found_file_first_sector` output - absolute first data sector of the
   found file (valid with `file_found`); with the contiguity convention
   this is the base of the block map below.
6. Filesystem geometry exports (`fs_cluster_size`, `fs_fat0_sector`,
   `fs_sectors_per_fat`, `fs_num_fats`, `fs_data_base_sector` (biased),
   `fs_total_sectors`, `fs_root_cluster`) plus the found entry's
   directory location (`found_dir_entry_sector`/`_index`) and full
   32-bit first cluster (`found_file_cluster`) - everything
   sd_fat_rewrite.v needs. No trailing '.' on extension-less 8.3 names;
   the `sdcmd` pin is split into `sdcmd_i/_o/_oe` (repo rule: the only
   tristate lives at the board top level).

The data phase runs at clk/2 (13.5 MHz at 27 MHz, CLK_DIV=1), and file
bytes stream through CMD18 multi-block reads across contiguous cluster
runs.

## WRITE-PATH SAFETY POLICY (mandatory, 11-JUL-2026)

Born from a real destroyed card: `sd_fat_rewrite.v` state `S_DIR_W`
wrote the patched directory sector to the raw `dir_sector` input (0 on
a cold-start create) instead of the internal `dsec_r`, so CMD24 went to
sector 0 - the boot sector. The happy-path test sequence masked it
because an earlier command had already populated the registers. NO bitstream containing SD write
functionality is loaded or flashed onto hardware unless the simulation
gates prove ALL of:

1. Registered unit tests of the write path (TB_RESULT: PASS).
2. The card model's ALWAYS-ON legal-target assertion: every sector
   written during the run must be inside the computed legal set (the
   target file's data sectors, the FAT copies, the specific directory
   sector). Any other write fails the gate even if fsck passes.
3. Post-run card health: boot sector bytes 0..511 (and the FAT32
   backup boot region) byte-identical to pre-run, directory readable,
   fsck.vfat clean.
4. Cold-start coverage: every destructive command exercised as the
   FIRST command after reset, not only inside a longer sequence.

New write features extend the legal-target assertion FIRST.

## Compile-time feature flags

`circuit/sd_fat_features.vh` - every feature ON by default, stripped
with `SDFAT_NO_*` defines (`make SDFAT_FEATURES="-DSDFAT_NO_CHECK"`,
same `-D` syntax for yosys/iverilog/the C++ simulator). Dependencies
resolve automatically (REWRITE and SPEED need WRITE):

| Flag | Strips | Menu keys affected |
|---|---|---|
| `SDFAT_NO_WRITE` | sector write engine + everything below | 3,4,5,6,7 |
| `SDFAT_NO_REWRITE` | FAT surgeon (replace/create files) | 3,6,7 |
| `SDFAT_NO_CHECK` | cluster-chain validator | 5 |
| `SDFAT_NO_SPEED` | IO speed tests + KB/s divider | 6,7 |

Stripped commands answer `NOT IMPLEMENTED`; all configurations are
elaboration-checked by the registered `lint-configs` target.

## Full FAT client / FORMAT - the decision (11-JUL-2026 research)

A FULL client (create/delete/rename/mkdir/subdirectory traversal/LFN
write/format/exFAT - the complete 34-function FatFs API) does not
exist in pure HDL anywhere; this library is already the closest thing.
The researched, evidence-backed route for the full feature set is
ChaN's FatFs (BSD-style license, ~33 KB ROM with EVERYTHING on incl.
f_mkfs formatting and exFAT, ~4 KB RAM) on a small RISC-V softcore
(picorv32 ~2K Gowin LUT4s - proven with FatFs on this exact board by
nand2mario's NESTang), with a one-page mailbox diskio driving THIS
library's sector engine. FatFs's ffconf.h config model mirrors the
feature-flag philosophy above. The pure-Verilog ops in this library
remain the fast boot/device path; the softcore tier is not built and no
live plan schedules it (the old device plan was retired 28-SEP-2026).

## Block access (ND-120 1-kiloword blocks)

Convention used by the device emulation stack: 1 block = 1024 x 16-bit
words = 2048 bytes = 4 SD sectors. For a CONTIGUOUS file (the card
recipes create them contiguously on a fresh card):

    block N of file  <->  SD sectors (found_file_first_sector + 4*N) .. (+3)
    valid N          =    0 .. file_size/2048 - 1  (writers must refuse
                          any block that does not lie entirely inside
                          the file - past the cluster chain is the
                          NEXT file's data)

Reads: `sd_file_reader` streams whole files; sector-level random
reads go through `sd_writer`'s CMD17 read mode (`rd_mode=1`). Writes:
`sd_writer` (CMD24) writes any single sector of an already-initialized
card; the sd-fat-test menu command 4 demonstrates the full
locate-file -> block-address -> 4-sector write chain and its
out-of-range guard. The general random-access block device with its
own sector buffer (floppy/SMD emulation) builds on exactly this
mapping - see the plan document, Milestone 3.

## Using the library on a board

The modules are plain Verilog with the SD signals as ports - nothing is
board- or pin-specific. Per board you provide:

1. Pin locations in that board's constraint file.
2. A top level that drives `sd_dat1/2/3 = 1` (keeps the card in
   SD-native mode) and connects `sdclk/sdcmd/sddat0`.
3. `CLK_DIV` parameter for your clock (3'd1 up to 25 MHz, 3'd2 for
   25-50 MHz, see the header of `sd_file_reader.v`).

Proven: Tang Nano 20K on-board microSD slot (CLK=83, CMD=82, DAT0=84,
DAT1=85, DAT2=80, DAT3=81, all LVCMOS33 - see
`Verilog/fpga/tang-nano-20k/sd-fat-test/src/nano20k_sd.cst`).

Planned: Basys3 with a Digilent Pmod MicroSD on header JA. The Pmod
wires all six card lines, so the same SD-native 1-bit core works
unchanged - only the XDC differs (pin table, UNVERIFIED until the
adapter is in hand, in `Verilog/docs/sd-bpun-device-plan.md` 6.2).

## Simulating against the library

- iverilog: instantiate `sim/sd_card_model.v` on the SD pins (needs a
  `pullup` on `sd_cmd`), serve a real FAT16 image built with
  `mkfs.vfat -F 16 -s 1` + `mcopy`. Working example incl. image build
  script: `Verilog/fpga/tang-nano-20k/sd-fat-test/sim/`.
- Verilator: the event-driven Verilog card model cannot run under
  Verilator; use the C++ card model in
  `Verilog/fpga/tang-nano-20k/sd-fat-test/sim/test_sd_fat.cpp`
  (same protocol subset) plus the tristate-resolving wrapper
  `sd_fat_test_vtop.v` there.

## Pitfalls (cost real time)

- Verilator rejects a delayed assignment to an array inside a `for` loop
  (BLKLOOPINIT). Use a walking clear and a combinationally built mask.
- A `for`-loop reset over an array forces flip-flops, not block RAM
  (~26k FF at 512 sets in the first cache directory).
- An asynchronous reset anywhere in the process that writes an array also
  stops block-RAM inference, even if the array itself is never reset. Write
  the array in its own `always @(posedge clk)` with no reset.
- Never split a directory's valid/rank bits into their own indexed arrays
  read combinationally (187,283 AND gates at 512x4). Keep one word per set.
- `file_found` in sd_file_reader.v is a LEVEL, not a pulse: an
  `if (file_found) ... else if (scan_done)` chain never reaches the second
  branch.
- sd_writer.v is a sector READ/WRITE engine: `rd_mode=1` gives CMD17/CMD18
  with an `rx_we/rx_addr/rx_data` sink. `burst_len` 0 and 1 are the same.
- Never stop the reader in the middle of a transfer: it leaves the card inside
  a CMD17 and the next card user fails. Wait for `scan_done`.
- A testbench check can go blind without failing: after an architecture
  change, re-derive what each check looks at, do not just confirm it is green.
- The mount test image (sim/make_storage_image.sh) holds only TAPE.BPUN,
  FLOPPY1.IMG and FRAG.IMG - no SMD0.IMG, so a client-3 open legitimately
  fails as not-found.

## Known limitations (by construction)

- The reader never writes (all writes go through the separate
  `sd_writer.v`, and only into existing file data sectors - see
  "Write path status").
- Root directory only; one file target per scan.
- FAT32 first clusters are captured in full 32-bit width (top nibble
  masked per the FAT spec). Historical note: the pre-replacement core
  truncated them to 16 bits, which on big used cards made the surgeon
  free the WRONG chain - the bug that bit the first real-card COPY
  test; the registered fat32big gate covers it since.
- Entries with attribute bits beyond Archive (0x20) / Directory (0x10)
  are skipped (e.g. read-only or hidden files).
- LFN names up to 52 bytes ASCII; non-ASCII UTF-16 units or broken
  LFN chains fall back to the 8.3 name.
- No card-detect pin: a missing card is only seen when a command fails.

## Write path status

IMPLEMENTED:
- `sd_writer.v`: raw sector engine (CMD24 write / CMD17 read).
- In-place data rewrites of contiguous files (COPY fast path, 1KW
  block updates).
- `sd_fat_rewrite.v`: file REPLACEMENT when the target's allocation is
  too small - frees the old chain, allocates a fresh CONTIGUOUS chain,
  patches the directory entry, updates both FAT copies. Works on FAT16
  and FAT32. Verified in simulation with an fsck.vfat gate over the
  post-operation card image.

Known limits of the rewrite path:
- The new chain must be contiguous; a heavily fragmented full card can
  fail with "no space" even when scattered free clusters exist.
- The target file must already exist (a directory entry to reuse);
  creating brand-new files/subdirectories is still out of scope.
- FAT32: the FSInfo free-cluster summary is not updated (fsck fixes
  the count; the structure itself stays consistent).

Full card-side file management (create, subdirectories) remains the
Route A decision (block-level SD + picorv32 softcore running ChaN's
FatFs); see `Verilog/docs/sd-bpun-device-plan.md` section 6.4.
