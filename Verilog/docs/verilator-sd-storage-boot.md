# Booting SINTRAN in Verilator THROUGH the SD/FAT stack

Status: **built and lint-clean; not yet run to a banner.** Added 21-AUG-2026.
Whether a `probe-wd-sd` run has reached the banner since is not recorded
anywhere (UNVERIFIED). The same SD Winchester path WAS run in the dmaSim rig
on 24-AUG-2026 (target `rig-nexys-wd`, see
`Verilog/fpga/nexys4ddr/HANDOFF-floppy-dma-investigation.md`, "24-AUG ~18:45",
retired 28-SEP-2026, in git at `c4896a4`):
the mass load, the seek and the following reads complete with correct
end-address readbacks.

## 1. The hole this closes

The Verilator Winchester boot (`Verilog/sim`, target `probe-wd`) does not use
the SD/FAT storage stack at all. The disc image is handed to the C file server
`process_verilog_wd()` in `Verilog/simDevices/NDBus.cpp`, which opens the host
file named by `ND120_WD_IMG` and answers each block request with an `fread`.

That means none of this executes during a sim boot:

```
sd_card_ctrl            Verilog/SD-FAT/circuit/sd_file_reader.v
sd_file_reader          FAT16/FAT32 mount + root-directory scan
nd_storage_engine       Verilog/SD-FAT/circuit/nd_storage_engine.v
nd_storage_cache        Verilog/SD-FAT/circuit/nd_storage_cache.v  (Phase 4)
nd_storage_disc_adapter Verilog/SD-FAT/circuit/nd_storage_disc_adapter.v
```

On the Tang, every disc block SINTRAN reads travels that whole chain. So a
defect in it cannot appear in simulation - it can only appear on silicon,
where the instrument is a 128-entry IOX ring dumped over a UART.

The storage testbenches in `Verilog/SD-FAT/sim/` do drive the chain, and all
of them pass, but against a **16384-byte** stand-in `WD0.IMG`
(`make_storage_image.sh`, `WD_BYTES=16384`) with hand-written access patterns.
A real Winchester image is about 75 MB - roughly 4800 times larger - and
SINTRAN's access pattern is nothing like a testbench's.

There is a specific open question this is meant to answer. From the comment in
`Verilog/SD-FAT/circuit/nd_storage_devices.v` (09-AUG-2026): on silicon the
Winchester read returns **zeros with a perfectly clean status** while block 0
of `WD0.IMG` demonstrably holds data, and the same RTL chain **passes in
simulation**. The one structural difference between the client that works on
silicon (the tape, DIRECT) and the one that does not (the Winchester, CACHED)
is `CACHE_MASK`. A full SINTRAN boot with the cache in the path is the test
that has never been run.

## 2. What was added

| file | change |
|------|--------|
| `Verilog/ND120_TOP.v` | New define `ND120_SD_WD`. The core's `WDISK_`/`WDBUF_` **return** path now comes from an `s_wdisk_*`/`s_wdbuf_*` seam instead of straight off the top-level ports; under `ND120_SD_WD` that seam is driven by `nd_storage_devices` client 6 instead of by the C model. Also `INCLUDE_WD(1)` on that instance, and `ND120_SD_CARD_BYTES` to size `sd_card_model`. |
| `Verilog/simDevices/NDBus.cpp` | `process_verilog_wd()` is skipped under `ND120_SD_WD`, exactly as `process_verilog_tape()` already is under `ND120_SD_STORAGE`. |
| `Verilog/SD-FAT/sim/make_wd_card.sh` | **New.** Builds a FAT16 card carrying a real `WD0.IMG` (and optionally `BOOT.BPUN`), sized and cluster-sized automatically, and refuses to emit it unless every file is verifiably contiguous with an intact end-of-chain and `fsck.vfat -n` is clean. |
| `Verilog/sim/Makefile` | **New target** `probe-wd-sd`, own `obj_dir_probe_wd_sd`. Never touches `probe`, `probe-floppy` or `probe-wd`. |

Nothing about the existing default path changed: with `ND120_SD_WD` undefined
the seam is a straight pass-through to the same top-level ports as before.

## 3. How to run it

The Winchester image lives outside the repository, so its path must be given
explicitly - the script refuses to guess which image is meant.

```bash
# 1. build the card (prints the CARD_BYTES value you need next)
Verilog/SD-FAT/sim/make_wd_card.sh /path/to/WD0.IMG

# 2. build the engine
cd Verilog/sim
make probe-wd-sd SD_CARD_BYTES=<the CARD_BYTES it printed>

# 3. run it - note there is NO ND120_WD_IMG any more
./obj_dir_probe_wd_sd/VND120_TOP
```

`SD_CARD_IMG` defaults to `../SD-FAT/sim/nd_wd_card.img`. The target refuses
to build if the card is missing, or if the card file is larger than
`SD_CARD_BYTES` - `sd_card_model.v` slurps the whole card into a byte array at
time 0 and reads every sector past `MAX_BYTES` back as `0xFF`, which would
look like a successful mount followed by garbage.

## 4. The comparison this makes possible

`probe-wd` and `probe-wd-sd` are the same CPU build with the same disc image
and differ **only** in which backend answers `WDISK_*`. Run both and diff the
traces: any difference is the storage stack, because nothing else changed.
That is the measurement the Tang cannot give.

## 5. What is proven so far, and what is not

Proven:

- All three configurations lint clean under Verilator 5.025 with `-Wall`:
  `probe-wd-sd` (SD path), `probe-wd` (C model, the regression check on the
  seam edit), and plain `sim` with no device chain.
- `make_wd_card.sh` builds and self-verifies a card at both a small size and
  a realistic 78,643,200-byte one (79 MB card, 4 sectors/cluster = 2048-byte
  clusters, exactly one `nd_storage` block per cluster, 38400 clusters,
  contiguous, `fsck.vfat -n` clean).

NOT proven - do not report these as working until someone has measured them:

- **No boot has been run through this path yet.** Whether SINTRAN reaches its
  banner over the SD/FAT/cache stack is exactly the open question.
- Run time is unknown and will be worse than `probe-wd`. Every block now costs
  a simulated SD transaction instead of an `fread`, and on a cache miss four
  card sectors. Budget accordingly - the C-backed boot already needs on the
  order of a billion ticks.
- Host memory: `sd_card_model` holds the entire card as a byte array, so a
  79 MB card costs about 79 MB of RAM on top of the normal sim footprint.

## 6. Related

- `Verilog/docs/nd-storage-design.md` section 2.7 - the block cache this
  exercises, and why the region stopped being a copy of the image.
- `Verilog/SD-FAT/CARD-LAYOUT.md`, `Verilog/SD-FAT/README.md`
- `Verilog/SD-FAT/sim/make_storage_image.sh` - the 16 KB testbench cards this
  is the full-size counterpart to.
- `Verilog/dmaSim/` target `rig-nexys-wd` - run-time controls read by
  `dma_p3_main.cpp`: `ND120_OPCOM_SCRIPT` (types a script into OPCOM),
  `ND120_OPCOM_PACE` (keep it >= 20000 or characters drop), `ND120_OPCOM_BIT`
  (3472 = 2 x `ND120_UART_DELAY_FRAMES=1736`, 16.67 MHz / 9600),
  `ND120_FLP_TRACE`, `ND120_WCS_DUMP`, `ND120_INTP_TRACE`.
