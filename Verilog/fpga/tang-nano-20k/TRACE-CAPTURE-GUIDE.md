# Tang Nano 20K - on-chip trace capture and analysis guide

**Full path:** `Verilog/fpga/tang-nano-20k/TRACE-CAPTURE-GUIDE.md`

How to capture 512-sample signal traces from the ND-120 running on the Tang
Nano 20K silicon and decode them. Written to be followed step by step. This is the tool that solved the memory-write mystery in
one evening after weeks of blind builds - prefer it over guessing.

---

## 1. What the analyzer is

A 512 x 16-bit ring buffer inside `src/ND120_TANG20K_TOP.v` ("On-chip
write-path analyzer"), sampling a 16-bit debug bus on every `clk2x` edge
(~74 ns per sample at the G1 slow-bring-up clock; two consecutive samples
per CPU clock). After a trigger it keeps a configurable number of
post-trigger samples, then dumps all 512 samples as hex lines over the
console UART at `UART_BAUD_RATE` - 115200 on every bitstream since
27-AUG-2026, 9600 before (taking the TX pin over from the CPU; the divider is
`src/ND120_TANG20K_TOP.v:1747`).

- **Debug bus source:** `assign DBG_MEMW = {...}` in
  `CPU-BOARD-3202/circuit/ND3202D.v` (inside `ifdef MAIN_RAM_SDRAM`).
  THE BIT MAP LIVES THERE - always read the current assign before decoding
  a dump; the map changes per investigation (v1 = WRITE-generation chain,
  v2 = DD write-data path, v3 = AA/BANK address path...).
- **Trigger:** rising edge of bus bit [7] after a ~2.5 s arm delay (the
  delay skips boot noise). Bit [7] is by convention the trigger signal -
  currently `wdec`, the recomputed microcode write-command decode, which
  fires exactly once per OPCOM deposit. Keep the trigger at [7] when
  retargeting and the top level never needs to change.
- **Capture shape:** 64 pre-trigger + 448 post-trigger samples
  (`cap_post <= 9'd448` in the top). ~33 us of post-trigger visibility.
- **Dump hold-off:** after the trigger the console stays on the CPU for
  ~10 s (`hold_cnt`) so the deposit echo and a follow-up examine remain
  visible, THEN the dump takes over TX and prints 512 lines of 4 hex
  digits (oldest sample first). After the dump the console stays dead
  until S1 (reset) or reprogramming - that is expected.
- **LEDs (active low):** LED1 = trigger signal live, LED2 = sticky
  "WRITE seen since arm", LED3 = sticky "trigger decode seen since arm",
  LED4 = dump ran, LED6 = heartbeat. A dark LED3 after a deposit is
  itself a measurement (the decode never fired).

## 2. Hardware setup (WSL2)

One-time per Windows boot (PowerShell as admin on the host):

```powershell
usbipd attach --wsl --busid 3-3     # Tang Nano 20K (Basys3 is 1-7, same VID:PID)
```

Then in WSL:

```bash
ls /dev/ttyUSB*                     # expect ttyUSB0 (JTAG) + ttyUSB1 (UART)
sudo chmod 666 /dev/ttyUSB1         # if permissions block you
```

## 3. Build and program

```bash
cd Verilog/fpga/tang-nano-20k

# Optional fast gate: compile the EXACT Gowin file list with iverilog
cd sim && make nd120_tang20k_tb.vvp && cd ..     # seconds; catches syntax/port errors

# Bitstream (Gowin gw_sh on the Windows host via gowin_build.ps1, callable
# from WSL, ~3 min)
make gowin VARIANT=slow

# Verify the bitstream is FRESH before programming (stale .fs = wasted run)
ls -la build/nd120_tang20k_build/impl/pnr/nd120_tang20k_build.fs

# Program the Gowin bitstream into SRAM (volatile); 'make load' is the OSS one
PATH=$PATH:~/oss-cad-suite/bin make load-gowin
```

## 4. Run a capture session

One self-contained shell block (runnable as a script). Keep ONE listener
attached for the entire session; never program while listening.

```bash
SCRATCH=/tmp                                    # or your scratch dir
stty -F /dev/ttyUSB1 115200 raw -echo -echoe -echok   # 9600 for pre-27-AUG bitstreams
timeout 75 cat /dev/ttyUSB1 > $SCRATCH/capture.log &
sleep 6                                          # boot (~1 s) + 2.5 s arm + margin
# examine cell 22 (OPCOM chars must be paced ~0.3 s/char or MOPC drops them)
for c in 2 2 /; do printf "%s" "$c" > /dev/ttyUSB1; sleep 0.35; done
sleep 1
# deposit 054321 - the CR executes the write and fires the wdec trigger
for c in 0 5 4 3 2 1; do printf "%s" "$c" > /dev/ttyUSB1; sleep 0.35; done
printf "\r" > /dev/ttyUSB1
sleep 2
# readback examine while the 10 s hold keeps the console alive
for c in 2 2 /; do printf "%s" "$c" > /dev/ttyUSB1; sleep 0.35; done
sleep 16                                         # rest of hold + ~3.5 s dump
wc -c $SCRATCH/capture.log                       # expect ~3.1 KB (echo + 512 lines)
```

The log contains the console echo first (`22/000000 054321` etc.), then
512 lines of 4 uppercase hex digits.

## 5. Decode and analyze

Adapt the field lambda to the CURRENT bit map in `ND3202D.v`:

```python
import re
raw  = open('capture.log').read()
vals = [int(x, 16) for x in re.findall(r'\b([0-9A-F]{4})\b', raw)]
assert len(vals) == 512, len(vals)

# EDIT THIS to match the DBG_MEMW assign in ND3202D.v (v3 shown):
def fld(v):
    return dict(aa=(v >> 8) & 0xFF, wdec=(v >> 7) & 1, write=(v >> 6) & 1,
                bank0=(v >> 5) & 1, bank1=(v >> 4) & 1, bank2=(v >> 3) & 1,
                mw50_n=(v >> 2) & 1, cas=(v >> 1) & 1, ras=v & 1)

trig = next(i for i, v in enumerate(vals) if (v >> 7) & 1)  # ~64 by design
for i in range(max(0, trig - 8), min(512, trig + 60)):
    print(i, f"{vals[i]:04X}", fld(vals[i]))
```

Reading the trace:

- Every value appears **twice in a row** (2 samples per CPU clock at G1
  speeds). A signal that changes every sample is suspect (metastable or
  clock-domain junk).
- Index the access against the known-good sequence: write decode ->
  `WRITE` rises at next CLK -> `ECREQ` -> `CGNT_n` low (grant) -> `RAS`
  rises (row on AA) -> `CAS` rises (column on AA, write data on DD) ->
  window ends. See `../../docs/nd120-dram-memory.md` for the protocol
  ground truth (the v1/v2 annotated traces of the 8-JUL write bug were in
  `Verilog/docs/HANDOFF-basys3-memory-write.md`, deleted 28-SEP-2026 - git
  history keeps them).
- Compare against the Verilator/iverilog sim of the same access when in
  doubt - the sim is the working reference.

## 6. Retargeting at a new signal set

1. Pick signals visible in `ND3202D.v` (or extend `MEM_43.v`'s
   `DBG_MEMW` assign and overlay in `ND3202D.v`, as v3 does). No new
   ports are needed for anything already at board level.
2. Keep the trigger signal on bit [7] and `WRITE` on bit [6]; then
   `ND120_TANG20K_TOP.v` (trigger, LEDs, dump) needs no edits.
3. Update the bit-map comment in the assign - it is the decode key.
4. Rebuild + program (section 3), rerun (section 4).
5. If you need a different trigger event, change the edge detect on
   `s_dbg_memw[7]` in the top's capture block (`wdec_d2` logic).

## 7. Gotchas (all learned the hard way)

- **Verify the `.fs` timestamp before programming** - gw_sh leaves the
  old bitstream in place when it fails early.
- **One listener per session.** A second `cat` steals bytes. And a
  `pkill cat` inside a composite command kills its own shell.
- **Never program while a listener is attached** - you get NUL junk.
- **OPCOM input pacing:** >= 0.3 s between characters or MOPC drops them.
- **After the dump the console is dead** (dump_fin latches TX over)
  until S1 or reprogram. LED4 on = the dump ran.
- **The arm delay is 2.5 s** - anything you type earlier can trigger on
  boot activity instead of your deposit.
- **`\r` is not a Verilog escape** - in testbenches use `8'h0D`.
- **Sim first:** `sim/make nd120_tang20k_tb.vvp` compiles the exact
  Gowin file list in seconds and catches port/syntax errors before the
  3-minute synthesis.

## 8. Case study (why this works)

The 8-JUL-2026 memory-write investigation, three capture generations in
one evening, each build ~10 min end-to-end:

- **v1 (WRITE-generation chain):** disproved the standing theory - the
  microcode write decode fires and `WRITE` asserts on silicon, correctly
  captured by the DGA F924 at the CLK edge.
- **v2 (DD write-data path):** write data (054321) present and stable on
  `DD` through the whole RAS/CAS window, `MWRITE_n` asserted - the
  MEM_43-level write is perfect, yet readback still returned 000000.
- **v3 (AA/BANK):** moved the probe to the address/bank-select path,
  the last layer between MEM_43 and the SDRAM bridge.

Each generation eliminated a whole subsystem by measurement instead of
inference. That is the method: probe, decode, move one layer, repeat.

## 9. The nd100x oracle traces (the reference side)

Moved here 28-SEP-2026 from the finished page-fault campaign plans (git
history keeps them). Recorded 23-AUG-2026; the files live outside the repo
under `$ND120_ORACLE_DIR` and were not re-checked since.

- **Oracle side = trace files, not debugger stepping.** `oracle_full.trc` =
  25,000,001 lines with full register columns, past the banner threshold
  (~17-18M instructions) - the reference boot trace. `oracle_simimg.trc` =
  25,000,001 lines, compact mode. `oracle_trace_full.log` = 1,955,151 lines
  only (~2M instructions, readable, NOT a full boot). The source disc image of
  each existing trace is not recorded in the files - verify or regenerate
  before any image-dependent conclusion.
- **Regenerate** with `$ND120_ORACLE_DIR/oracle_make.sh <max-instr>
  <abs-outfile> [compact] [img]` (nd100x `--trace`). FULL is ~104 B/line,
  COMPACT ~63 B/line. Always trace a COPY of the disc image - booting
  modifies it.
- **Compare tools** in the same place: `lockstep.py` (timing-tolerant
  lockstep, ND-120 trace vs oracle), `boot_compare.py`, `ctxdiff.py` /
  `ctxdiff_tight.py` (first differing opcode/next-PC for the same context).
  Both sides emit the same columns:
  `PIL PC OPCODE A D T X B L STS PIE PID IIE IID PGS MMU INT SEX`.
  The ND-120 side of that rig has always been Verilator, never the Tang.
- **nd100x facts:** `--cputype=ND120CX` works; untraced speed ~2.9 M
  instructions/s; boot to `SINTRAN III RUNNING` takes 10M-20M instructions;
  `-t` costs ~190 B/instruction raw. `--watch=[phys:]ADDR[:r|w|rw]` (32 max)
  and `-B ADDR` exist; octal needs a LEADING ZERO (`--watch=0175740:w`, not
  `175740`).
