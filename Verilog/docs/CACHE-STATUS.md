# The ND-120 cache: status, root causes and how to test it

> **Solved 31-AUG-2026.** All 8 tests of the machine's own cache diagnostic
> (`CACHE-1X0-A00` under TPE) pass on the Nexys 4 DDR, and the cache is
> compiled in by default there (`fpga/nexys4ddr/build.tcl`, runtime on/off on
> slide switch `sw[4]`). Four separate RTL faults had to be fixed; they are
> listed below with the evidence. The day-by-day hunt (28-30 AUG) is in git
> history.

## Where the cache runs

| Board | Cache |
|---|---|
| Nexys 4 DDR | compiled in by default since 29-AUG-2026; deployed at 33.333 MHz (build 24, 7.52 MIPS). `-tclargs nocache` compiles the RAMs out (`ND120_NO_CACHE`). |
| Tang Nano 20K | out (`ND120_NO_CACHE`): a live cache needs 28330 logic cells against the GW2AR-18's 20736 (`build-defines.md`). |

Build facts, measured on the Nexys: the cache builds, fits and boots (first
cache build 28-AUG: WNS +0.166 ns, about 0.1 ns less margin than the same
build without it). The four cache tag/data RAMs read asynchronously
(`TMM2018D_25 #(.ASYNC_READ(1))` in `CPU_MMU_CACHE_25.v`), so on Xilinx they
are distributed RAM: +1014 LUTs (+961 LUT-as-memory), -2 BRAM tiles. With the
cache in, the routed worst path is about 28.0 ns, a ceiling near 35.6 MHz;
45 MHz with the cache is not reachable (`fpga/nexys4ddr/timing.md`).

## How a cache hit works (the chain, read from the RTL and the sheets)

`HIT` requires the used bit (`CPU_MMU_CACHE_25.v`):

```verilog
assign s_hit = !s_used_n & !s_hit_1_0_n[0] & !s_hit_1_0_n[1] & !s_cwr;
```

On sheet 25 HIT is a 74S260 5-input NOR (21H): pin 1 `USED~`, pins 2/3
`HIT~1`/`HIT~0`, pin 12 the net `CWR`, pin 13 ground. HIT is high only when
all five are LOW. So if the used bit never sets, the hit rate is a true 0%.

A cache write is `PAL_44402D` asserting WCA
(`DesignDocuments/PAL-Code/SRC/44402D.txt`):

```
WCA = /RT * DT * EWC * CYD * /FMISS * /LSHADOW    ; WRITE OUTSIDE SHADOW
    + RT * /IHIT * EWC * CYD * /FMISS * /LSHADOW  ; FETCH/READ WITHOUT HIT
```

and the rest of the write chain is:

```
inhibit-bit RAM CHIP_20G  ->  WCINH_n   (CPU_MMU_PT_29.v)
  -> s_ewc_n = ~(s_brk_n & s_con & s_wcinh_n)   (CPU_MMU_CACHE_25.v)
  -> PAL_44402D: WCA
  -> PAL_44511A: CWR = MREQ * WCA + CWR * /CLK
  -> /CUP := /CWR * MREQ                         -> Cache Status bit 0
```

In `PAL_44402D` only `IHIT`, `NUBI`, `NUBD` are registered (`:=`, pins
14-17); `WCA` and `USED` are combinational (pins 18/19). The used-bit RAM is
`Am9150 CHIP_21F`; bit 1 is the data half (NUBD), bit 0 the instruction half
(NUBI). CA10 selects the instruction/data half.

### The cache-inhibit map

Measured in Verilator (`ND120_WCLIM_TRACE=1`), 29-AUG-2026. Three microwords
carry the WCHIM command: **01071, 02046 and 03713**.

- Power-up: microwords 02045/02046 sweep all 16384 pages with data 0, so
  after reset **every page is cache-inhibited** until the limits are set.
- `TRR LCIL` / `TRR UCIL` each re-sweep the whole map through microword
  01071. Limits `0:037777` leave 0 pages enabled; limits `000100:000200`
  leave exactly the 65 pages 100..200 inhibited.

The PPN OR at `CPU_MMU_PT_29.v` (`s_ppn_25_10_in | s_ppn_25_10_out`) is a
correct wired-OR model of the one bidirectional `PPN(25:10)` bus on sheet 29:
the CPU side drives all zeroes whenever `LAPA_n` is high (`CPU_15.v`), and
`CPU_MMU_PPNX_28` drives PPN25-PPN18 (the inhibit bit is PPN25) from the IDB.

### DMA and stale lines - the HIT gate (26-JUL-2026)

The schematic drives the cache data SRAMs (23F/24F, `CS~ = ECD~`,
`W~ = WCA~`, `OE = GND`) onto the wired-OR `CD` bus for the whole first part
of every read, with no HIT gate - by design (PAL 44306A: "ENABLE IN THE FIRST
PART OF READ/FETCH CYCLES"). On a miss the refill (`WCA`) forces the SRAM
output to 0 while it writes, so memory data survives the OR. On a
**cache-inhibit page** there is no refill, and DMA writes bypass the cache, so
a line still holding old non-zero data (cached during an earlier init-clear,
then overwritten in memory by floppy DMA) jammed the OR over the correct word
(the TPE banner printed `INST\x7f\x7fCTION`). Fix, not hardware-faithful:
`CD_15_0_OUT = s_hit ? s_cd_15_0_out : 0` in `CPU_MMU_CACHE_25.v`; the raw
schematic behaviour is `-DND120_CACHE_DRIVE_UNGATED`. The hardware-faithful
alternative - never hold stale data for a page that becomes inhibited (clear
the data SRAM on CCLR, which today resets only the Am9150 used bits, or
invalidate on DMA writes) - is not done.

## The four faults, and what else was fixed on the way

| # | Where | What was wrong | Fix |
|---|---|---|---|
| 1 | `PAL/PAL_44511A(_EN).v` CWR | The listing's `CWR = MREQ*WCA + CWR*/CLK` is a level latch (PALASM `=` is combinational; a PAL16R4 has flip-flops only on Q0-Q3). The RTL clocked it, then held it only at the CLK rise, four cycle states after WCA (state d) had gone, so `/CUP := /CWR * MREQ` never saw it: "CUP does not work". | CWR modelled as the level latch: set on MREQ*WCA, held while CLK is low. First step `e178f04`, tb from the listing `5cec840`. |
| 2 | `PAL/PAL_44511A(_EN).v` pin 19 | Pin 19 was driven as `~CWR`. Sheet 34 wires pin 19 straight to net `CWR` with no inverter, and the sheet-25 NOR needs it LOW on a read, so HIT could only fire while the cache was being written - never on a read ("DATA is taken FROM MEMORY when present in DATA CACHE"). The listing declares the pin `/CWR`, the schematic draws `CWR`; the measurement decided. | `assign CWR_n = OE_n ? 1'b0 : CWR;` |
| 3 | `Shared/support/Am9150.v` | The model cleared its array with a 1024-step sweep after every cache clear and dropped every write during it. The diagnostic clears and then writes a few hundred clocks later, so the line ended tag-valid, data-valid, used = 0. The real Am9150 clears "in two cycle times". | One valid flip-flop per location; /R clears all in one clock; a write sets its valid bit; nothing is dropped. |
| 4 | `DECODE-GateArray/DGA/circuit/DECODE_DGA_IDBS.v` EPANSN | A combinational decode of the live CSIDBS field for o20 (MIPANS). During an RWCS read the control store outputs the DATA word, and a word whose bits 41:37 = o20 turned on the panel status driver (74LS244 33B, `{PRES, FUL~, READ, VAL}` on IDB 15:12, 68705 status on 11:8), which was OR-ed into the read-back: test 1 failed with found = expected OR a panel word (`163400` on the board, `100000` = PRES alone in Verilator, whose panel is a stub). | The combinational window stays (OPCOM input needs it with our 1-sysclk control-store read) but is shut for the whole RWCS microinstruction by `RWCSN` from the 44408B on sheet 34 - an input the real gate array does not have. `-DND120_EPANS_REGISTERED` gives the pin-exact registered EPANSN (OPCOM console dead, measured on board and in Verilator). |

Also real and kept:

- **Async cache RAM read.** The TMM2018D model read synchronously, so the tag
  arrived a state late: HIT was too late to end the cycle at states b/c (PAL
  44601) but early enough to stop the memory request at state d, and test 2
  ended in `UNEXPECTED INTERNAL INTERRUPT level 2, code 4` at 177006B. The
  real TMM2018 is a 25 ns async SRAM; `.ASYNC_READ(1)` on the four cache
  chips only.
- **The 26-JUL HIT gate** (above).

Found on the way and still worth knowing: the `PAL/sim` provenance gate
("22 PALs agree with their listing on every output") passed throughout and did
not catch fault 1, so what it compares does not include
combinational-vs-registered intent. `PAL/sim/PAL_44511A_EN_tb.v` had even
pinned the fault as an accepted "DEVIATION 1".

## Ruled out - do not re-check

Each was measured, not inspected.

| Excluded | Evidence |
|---|---|
| `CON` (SW1 cache switch) | `SW1_CONSOLE` comes from the board top's `CACHE_SW` (`ND120_CORE.v`): Nexys slide switch `sw[4]`, down = on; tied high in Verilator (`ND120_TOP.v`) and on the Tang |
| `PD1`, `PD2` | tied 0 in `ND3202D.v`; PD2 stayed low for the whole WCA pulse (Verilator, 29-AUG) |
| `FMISS`, `LSHADOW` | 0 in all 1024 board ILA samples, two captures |
| `BRK_n` | high in all but 7 of 1024 |
| inhibit map addressing / data / write strobe | full sweeps counted in Verilator (above) |
| `PAL_44402D` transcription | both WCA terms and the registered/combinational split checked against `44402D.txt` |
| "the cache RAMs are not built" | that block is inside `ifdef ND120_NO_CACHE`; a cache build takes the `else` branch |
| CA10 cleared too late on a data write | the DGA clears it in time (Verilator, 29-AUG); it is a DGA flop with an async clear on WRITE & UCLK (A237), by design |
| test 1 as a WCS bank mix-up | the same 16-bit constant was OR-ed into every group, so it is on the IDB side (fault 4) |

## CACHE-1X0-A00 results

The diagnostic is on the TPE floppy (`FLOPPY1.IMG`): `1560&` -> TPE ->
`LOAD-PROGRAM CACHE-1X0-A00`, then `RUN 1-8`.

| Test | Result |
|---|---|
| 1 Control store (upper 1K, the microinstruction cache store) | PASS - 0 error lines (was 20062) after fault 4 |
| 2 Basic functions | PASS after faults 1-3 (board build 4, 29-AUG 23:55; Verilator run 19) |
| 3 Inhibit limits | PASS on the board (31-AUG-2026, `fpga/nexys4ddr/README.md`). Before that it hung on the Nexys at `P=124563B` (builds 4, 7, 8) while passing in Verilator. Which change cured it is not known: the 01-SEP board notes say it was last seen failing on a 16.667 MHz build and not re-run on the board after the 30-AUG RTL fixes until it passed. If it comes back, re-test at `clk=16` first to see whether it depends on the clock. |
| 4-8 | PASS (build 8, 30-AUG-2026, and again 31-AUG) |

The load-time line `Cache updated bit: Working` is not evidence: it printed
`Working` on the same bitstream where test 2 reported CUP dead.

## Running the diagnostic in Verilator

What worked, 29-AUG-2026:

```
cd Verilog/runSim
make compile VERILOG_TAPE=0 SD_STORAGE=0 DEVICECORE=1 DEVICECORE_FLOPPY=1 \
     USE_LATCHES=0 EXTRA_VDEFINES="-DND120_SIM_RAM_64K" \
     SDFAT_SUPPRESS="-Wno-PINMISSING -Wno-IMPLICIT -Wno-DECLFILENAME -Wno-BLKSEQ -Wno-TIMESCALEMOD"
mkfifo /tmp/nd_in; sleep 100000 > /tmp/nd_in &
ND120_FLOPPYCORE_IMG=FLOPPY1.IMG ./obj_dir/VND120_TOP < /tmp/nd_in > out.log &
printf '1560&' > /tmp/nd_in                                  # wait for TPE>
printf 'LOAD-PROGRAM CACHE-1X0-A00\r' > /tmp/nd_in           # wait for the 2nd TPE>
printf 'RUN 2\r' > /tmp/nd_in
```

- `Initialize memory : >` is NOT a prompt: TPE clears all memory before the
  run, one `>` per bank, about 600M sim cycles (~35 min) whatever the sim RAM
  size. Anything typed there reaches TPE afterwards as a command. The program
  never echoes.
- `--public-flat-rw` is not needed and makes the sim about 4x slower.
- Probes in `runSim/Run120.cpp`, all environment variables:
  `ND120_CACHE_TRACE` (every WCA/CWR/CUP transition), `ND120_CACHE_WIN=n:count`
  (from the n-th WCA on: CA, PPN, tag/data read back, used bits, both HIT
  comparators, CD into MMU and CPU), `ND120_CACHE_PPN=<page>` and
  `ND120_CACHE_PPN_DT=1` (one line per cycle / per clock on one page),
  `ND120_CWIN_PPN` / `ND120_CWIN_WRITE`, `ND120_WCLIM_TRACE`,
  `ND120_WCS_RD` and `ND120_WCS_TRACE` (control-store reads),
  `ND120_CYC_WINDOW` (cycle states).
- **Probe trap:** the probe block runs once per sysclk period with
  `top->sysclk == 1`. A probe gated on `top->sysclk == 0` never fires and reads
  as "this never happens".
- **Verilator folds plain alias wires** (`assign s_x = X`) even under
  `--public-flat-rw`; wires the probes need carry a
  `/* verilator public_flat_rd */` mark (six in `CPU_MMU_CACHE_25.v`).
- On the board the matching ILA probe set is `-tclargs ilacache`
  (`DBG_CACHE`: `[0] LSHADOW [1] FMISS [2] CYD [3] BRK_n [4] WCINH_n [5] WCA_n
  [6] WCLIM_n [7] PPN25`). In `IMS1403_25.v` the RAM output is forced low for
  the whole of a write, so a `WCINH_n = 0` seen during a write is the model,
  not the stored bit.

Open panel/tooling items found during this work are in
[`PLAN-cache-and-panel.md`](PLAN-cache-and-panel.md).
