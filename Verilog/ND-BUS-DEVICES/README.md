# ND-BUS-DEVICES - external ND-100 bus devices

Devices that attach to the ND-100 external bus of the CPU board, the way
real ND-100 bus controller cards did. Nothing in here touches the CPU
trees (DELILAH-CPU/, DECODE-GateArray/, CPU-BOARD-3202/) - the devices
connect to the bus ports that ND120_TOP.v already exposes.

Reference behavior: `Verilog/simDevices/NDBus.cpp` (bus handshake) and
`Verilog/simDevices/NDDevices.cpp` (device registers) - the WORKING C
models that runSim boots with today. The Verilog devices must match them;
the runSim console golden gates the swap.

Storage design: `Verilog/docs/nd-storage-design.md`.

## Structure

```
BUS-IF/     ND_BUS_SLAVE.v - the one bus adapter: BAPR/BIOXE/BINPUT/
            BINACK/BDAP/BDRY/OUTIDENT handshake FSM + BINT10-13 drivers.
            Presents a simple synchronous device bus to the device cores.
TAPE-400/   ND_TAPE_400.v - papertape reader, IOX 400-403, ident 02,
            level 12. Byte source is a port (file model in sim, SD-FAT
            streamer on hardware).
FLOPPY/     floppy PIO controller, IOX 1560-1567, ident 021, level 11.
FLOPPY-DMA/ ND_FLOPPY_DMA.v - floppy controller 3112, DMA interface
            (register semantics per ND-11.021.01; IOX 1560 base).
DMA/        ND_DMA_MASTER.v - the DMA bus master (request/grant + one
            memory reference per grant) that FLOPPY-DMA and SMD use.
SMD/        ND_SMD.v - SMD disc controller (ND632 / PCB 3043+3044), DMA.
WINCHESTER/ ND_WINCHESTER.v - Winchester DMA block device, IOX 500-507,
            ident 1, level 11. oracle/ holds its reference trace.
testdata/   README only: which disk images the testbenches read (the
            images themselves are not in git).
portable/   git submodule (RetroCoreLabs/NDDeviceCore): the portable C
            device cores the RTL is proven against. Not documented here -
            see its own README.
```

## Disc geometry - Winchester vs SMD

The two block devices are within 0.5% of the same capacity by coincidence of
completely different geometries. They are easy to confuse and are NOT
interchangeable: a CHS->LBA calculation done with the wrong sectors-per-
cylinder lands about 25% away from the intended block, and it does so
SILENTLY - the transfer reports success, it just reads or writes the wrong
part of the disc.

| | Winchester (DISC-74-1) | SMD (75 MB unit) |
|---|---|---|
| Drive | Micropolis 1325 | CDC-type SMD pack |
| Heads | **8** | **5** |
| Sectors per track | **9** | **18** |
| Cylinders | **1024** | **823** |
| Bytes per sector | 1024 | 1024 |
| **Sectors per cylinder** | **72** | **90** |
| Total sectors | 73,728 | 74,070 |
| Capacity | 75,497,472 B (75.50 MB) | 75,847,680 B (75.85 MB) |
| Pages of 2048 B | 36,864 | 37,035 |
| IOX base | 500 | 1540 |
| Image | `WD0.IMG`, `WD1.IMG` | `SMD0.IMG` .. `SMD2.IMG` |

### Where the numbers come from

Both are RTL parameters, not constants buried in logic:

- `WINCHESTER/circuit/ND_WINCHESTER.v` - `GEO_HEADS=8`, `GEO_SPT=9`,
  `GEO_MAX_CYL=1024`
- `SMD/circuit/ND_SMD.v` - `GEO_HEADS=5`, `GEO_SPT=18`, `GEO_MAX_CYL=823`

Both match the nd100x C emulator, which is the oracle for this:
`src/devices/winchester/diskWinchester.h` documents the 1325 as
8 x 9 x 1024 x 1024 = 75,497,472 bytes, and
`src/devices/smd/diskSMD.c` `DISK_75_MB` sets 5 / 18 / 823.

The SMD's other supported packs (same file) are 38 MB (5/18/411), 150 MB
(10/18/823), 288 MB (19/18/823), 474 MB (20/24/842), 515 MB (24/26/711) and
825 MB (16/44/1024). The Winchester family holds several drives too - the
1325 is the one SINTRAN boots from.

### One adapter, two geometries

There is no `nd_storage_wd_adapter.v`. The Winchester reuses
`SD-FAT/circuit/nd_storage_disc_adapter.v`, which takes `GEO_HEADS` and
`GEO_SPT` as parameters precisely so the same CHS->LBA arithmetic can serve
both drives. The Winchester binding overrides them at two places, and both
must agree:

- `Verilog/ND120_CORE.v` (the ND_WINCHESTER instance)
- `Verilog/ND-BUS-DEVICES/TAPE-400/circuit/nd_storage_devices.v` (the
  adapter instance for client 6)

`WINCHESTER/sim/nd_winchester_adapter_tb.v` guards this: it instantiates the
adapter twice, once at Winchester geometry and once at the SMD default, and
checks the SAME CHS gives DIFFERENT block numbers - so a parameter that
silently fails to reach the arithmetic is caught.

### The image file may be LARGER than the geometry

This is expected and harmless. `WD0.IMG` on the SD card does not have to be
exactly 75,497,472 bytes - a bigger file is fine, and the extra bytes are
simply never touched.

The reason is that the bound is enforced by the CONTROLLER against its own
GEO_* parameters, not by the size of the backing file. `ND_WINCHESTER.v`
checks every command before it reaches the storage backend:

```verilog
((w_lba > w_max_lba) || (s_head >= GEO_HEADS) || (w_sector >= GEO_SPT))
    -> b8 address mismatch, operation refused, no backend request issued
```

with `w_max_lba = chs2lba(GEO_MAX_CYL, GEO_HEADS, GEO_SPT)` = 73,728. A CHS
address beyond the drive cannot be expressed, so sectors past the geometry
are unreachable however large the file is. The same holds for the SMD via its
own GEO_* parameters. SINTRAN only ever addresses what the drive claims to
have, so it never asks.

The file-size range check further down (`nd_storage_disc_adapter.v`, and
`n_blocks` in the engine) is a SECOND, independent bound. On an oversized
image it is simply looser than the geometry check and never fires.

**Ceiling: 128 MiB.** `nd_storage_mount.v:511` stores the block count as

```verilog
r_nblk[cur_client] <= s_size[26:11] + {15'd0, |s_size[10:0]};
```

`s_size[26:11]` is 16 bits, so any file size at or above 2^27 bytes
(134,217,728 = 128 MiB) has its high bits DISCARDED and the block count wraps
silently:

| Image size | True blocks | Stored `n_blocks` | Result |
|-----------|-------------|-------------------|--------|
| 72 MiB (exact geometry) | 36,864 | 36,864 | fine |
| 75 MiB (oversized) | 38,400 | 38,400 | fine |
| 128 MiB | 65,536 | **0** | every read refused |
| 150 MiB | 76,800 | **11,264** | most reads refused |

So "bigger is fine" holds comfortably for any realistic ND disc image - the
largest SMD pack in the table is 825 MB of geometry but no single ND unit
image approaches 128 MiB today - but it is not unlimited, and the failure
mode is silent truncation rather than an error. Worth a mount-time guard that
refuses an image >= 128 MiB with `NDS_ERR_RANGE` instead of quietly
mis-sizing it; not implemented yet.

### Sanity-checking against a running machine

The File System Investigator (`400$`, then `DISC-74MB-1`, unit `0`) prints

```
Total no. of disk pages is 107054
```

**That is OCTAL** - like every number the FSI prints - so it is 36,396
pages, against the 36,864 the geometry gives. The 468-page difference is
exactly 13.0 cylinders (1.27%), i.e. the bad-track and reserved-area
allowance. A number in that shape CONFIRMS the geometry; reading it as
decimal makes it look like a 219 MB drive and sends you chasing a
discrepancy that does not exist.

## Running the Winchester against the CPU in Verilator

A device with a green unit bench and no entry in `BUSDEV_COMPONENTS`
(`Verilog/sim/Makefile`, `Verilog/runSim/Makefile`) has never met the CPU -
check that list before believing any "it works". The Winchester went from
unit benches straight to the Tang until 06-AUG-2026 for that reason.

    cd Verilog/sim
    make probe-wd USE_LATCHES=0 EXTRA_WD_DEFINES=-DND120_DEV_DELAY_TICKS=216000
    cd ../ND-BUS-DEVICES/WINCHESTER/sim
    ND120_WD_IMG=<75 MB Winchester image> ND120_WD_TRACE_FILE=wd_trace.log \
    python3 wd_disctema.py disctema_console.log

`wd_disctema.py` boots `1560&`, then types `disc`, `DU-DI-C`, `DIS-74-1`,
unit/cylinder/surface/sector 0, amount 1. About 50 minutes.

Both build flags are needed:

- `USE_LATCHES=0`: `Verilog/sim/Makefile` defaults to 1 (latch mode), which
  never floppy-boots. Symptom: the prompt appears, `1560&` echoes, then
  nothing.
- `ND120_DEV_DELAY_TICKS=216000`: the disc delay in `ND120_CORE.v` is 8 ms of
  wall-clock time, `(DEV_CLK_HZ/1000) * SMD_DELAY_MS`. `DEV_CLK_HZ` is 27 MHz on
  the Tang but falls back to 100 MHz in Verilator, so the same 8 ms is 216,000
  cycles on silicon and 800,000 in the sim. The CPU runs per cycle, so
  DISC-TEMA's status-wait loop gets 3.7x more passes and its software timeout
  fires before the transfer is programmed. The define makes the sim
  cycle-identical to silicon; it is a diagnostic lever, left undefined by
  default.

`ND120_WD_TRACE_FILE` makes `Verilog/simDevices/NDBus.cpp` log whether the
image opened, every IOX to 500-507, every IDENT with the level and the answer,
and every disc-side START / REQ / READ DONE.

## Device bus (between ND_BUS_SLAVE and the device cores)

All in the sysclk domain. Read data is an OR-bus: a core drives 0 when
not addressed (FPGA rule - no z).

```
iox_addr[15:0]   IOX address (11 significant bits), valid with strobes
iox_wr           1-cycle write strobe, iox_wdata valid
iox_rd           1-cycle read strobe; addressed core must present
                 iox_rdata combinationally during the strobe
int_pending_10..13  level lines, OR of all cores (drives BINT1x_n)
ident_strobe     1-cycle IDENT poll, ident_level = 10..13
ident_grant_in/out  daisy chain priority (first core wins);
                 a granted core with a pending interrupt on that level
                 answers with its ident code and CLEARS its pending bit
                 and its interrupt-enable bit (same rule as the C model)
```

## Chain ordering - the cascade rule (ND-06.016.01 V.3, IV.2.3, F.2)

Both cascades on the real backplane - the DMA grant token
(INGRANT/OUTGRANT) and the IDENT search token (BINIDENT/BOUTIDENT) -
follow SLOT POSITION: the token originates at the CPU and daisy-chains
outward, so THE CONTROLLER CARD CLOSEST TO THE CPU WINS when several
request/interrupt at once. Empty slots break the chain; modules that do
not participate strap the token straight through (V.3 notes 1-3).

Our Verilog convention (the "slot order"): chain position = the order
the device instances are ATTACHED in the top level. The first instance
wired to the CPU-side token (ident_grant_in = 1'b1 for IDENT, INGRANT_n
from the CPU's OUTGRANT_n for DMA) is "closest to the CPU" = highest
priority; each instance's grant_out feeds the next one's grant_in.
Priority is therefore changed by REWIRING THE CHAIN ONLY - swap the
order of the grant hookups at the top; nothing inside the devices, no
parameters, no other signals move. That is the knob to "rotate" device
priority when needed.

Freeze rule (same pattern in both cascades): DMA requests freeze at the
BMEM leading edge; interrupt status for IDENT freezes at BAPR of the
IDENT address cycle (IV.2.3, "STOPIDENT" = interrupt-on-level AND the
status frozen at BAPR). A request/interrupt raised after the freeze
edge waits for the next round. ND_DMA_MASTER implements the DMA freeze
exactly; the IDENT path samples pending during the ident strobe (one
sysclk after the level code was captured at BAPR) - synchronous
equivalent of the 100 ns settle window the manual gives the interfaces.

## IDENT / interrupt rules (from NDDevices.cpp, confirmed vs nd100x)

- A device raises its assigned level's pending flag when its interrupt
  condition is true (tape: interruptEnabled AND readyForTransfer).
- BINT<level>_n is simply the NOR of every device's pending flag for
  that level (NDBus.cpp intended this; its `== 1` comparison bug meant
  the C sim never asserted the lines - the Verilog implements the
  intent).
- IDENT PL<level>: the bus captures the level from the address strobed
  at BAPR (004->10, 011->11, 022->12, 043->13). The FIRST device in the
  daisy chain with a pending interrupt on that exact level returns its
  ident code, and clearing happens AT THAT MOMENT (grant time), not at
  OUTIDENT release.
- A device with no pending interrupt on the polled level passes the
  grant on and returns nothing.

## Bus protocol references (IOX / IDENT / DMA)

Explainers for the three bus phases these devices implement. Both are in
`../docs/` (repo-root: `Verilog/docs/`):

- **`../docs/nd100-bus-deck.pptx`** - 16-slide deck covering all bus phases
  (IOX read/write, IDENT poll, DMA read/write + the recovery gap and
  CPU-vs-DMA arbitration). Editable PowerPoint; the verbatim manual text
  from ND-06.016.01 is baked into each slide's notes. Native-drawn timing
  waveforms are reconstructions - trust the RTL and the manual over the
  drawing.
- **`../docs/nd100-bus-dma.md`** - the authoritative ND-100 bus + DMA
  writeup. Section 10.8 holds the MEASURED findings ("every second read
  lost", read-data-capture window). Read this before touching
  `DMA/circuit/ND_DMA_MASTER.v`.

Cited manual: `ND-06.016.01 NORD-100 Input/Output System` - Section III
(IOX register access), Section IV + F.2 (IDENT PL<level>, poll codes
004/011/022/043 octal - NOTE the poll code is NOT the level integer),
Section V (DMA + the grant daisy chain).
