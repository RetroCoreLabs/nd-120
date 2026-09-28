# Tang Nano 20K - debugging options for the ND-120

**Full path:** `Verilog/fpga/tang-nano-20k/DEBUG-OPTIONS.md`
Written 17-JUL-2026, during the masked-grant hunt. Status column tells you what
exists TODAY vs what is planned. Pick the lightest tool that answers the
question; the heavier ones cost rebuilds, resources, or wiring.

## Summary table

| # | Tool | Sees | Controls | Needs rebuild? | Status |
|---|------|------|----------|----------------|--------|
| 1 | OPCOM console debugger | registers, memory, per-level state | run/step/breakpoints/deposit | no | WORKS (use first) |
| 2 | ndcomm | scripted OPCOM (load/verify/trace) | same as OPCOM | no | WORKS |
| 3 | On-chip 512x16 analyzer | any 16 internal nets (retarget map) | trigger choice | yes (map edit) | WORKS (proven) |
| 4 | Gowin GAO | internal nets over JTAG, waveform GUI | triggers only | yes (insert core) | IN PROGRESS |
| 5 | Gowin GVIO | - | drive internal signals over JTAG | yes | PLANNED |
| 6 | UART-BREAK remote reset | - | CPU reset | in bitstream | RTL works (vtest-proven); BREAK does NOT arrive through the current FTDI/usbipd chain - unusable until the transport is fixed |
| 7 | JTAG reflash | - | full reset (loses RAM) | no | WORKS (the current remote reset) |
| 8 | Physical reset pin + Pi Pico | - | reset now; halt/step/IRQ-inject later | yes (pin + 5 lines) | PLANNED (Picos on hand) |
| 9 | External logic analyzer on GPIOs | real at-speed waveforms of chosen nets | - | yes (route pins) | PLANNED (needs an LA) |
| 10 | Halt/step debug-control block | - | clock-enable halt, 1-cycle / 1-instr step | yes (core CE seam) | DESIGN ONLY |

## 1-2. OPCOM: the built-in software debugger (use this first)

The microprogram's operator communication IS a debugger, live over
/dev/ttyUSB1 at 115200 7E1 (9600 on bitstreams older than 27-AUG-2026).
Command reference: https://nd110.hackercorp.no/Terminal; the boot commands
are in `NorskData-Doc/OPCOM-Boot-Reference.md`. Highlights measured working
on this board:

- Examine/deposit memory (`addr/`, value CR), range dump `start<end` (the
  full-image verify: `0<54730` ~3.5 min, diff against the BPUN file).
- Registers incl. per-level (`7P/`) and internal (`I1/`=STS, `I5/`=IIC,
  `I6/`=PID, `I7/`=PIE). `IRD` dump.
- Single-step `Z` / `nZ`, breakpoints `addr.` (free-run, stops AT the
  address, console comes back). The step-compare protocol (step + read
  registers + diff against a Verilator tverify reference) found the
  masked-grant bug in 10 instructions - script pattern in the session log,
  reference generator: runSim with ND120_TRACE_VERIFY + TVERIFY_ARM_ADDR.
- `ndcomm` (fpga/tools/ndcomm/) scripts all of this: BPUN load/verify (-l -v),
  instruction trace (-t N -r), MW/MR command mode.

LIMITS: needs the CPU microcode alive (a hard hang kills the console);
stepping hides pure-timing bugs; breakpoint runs are unrecoverable if the
CPU hangs before the address (costs a reset).
PROTOCOL RULES (learned the hard way): never free-run from a parked/hung
state - reset first; `20!` restarts a loaded test program, `0!` is cold
start; on an EMPTY machine `n!` executes garbage and kills the console.

## 3. The on-chip 512x16 ring analyzer (ours, proven)

Guide: `Verilog/fpga/tang-nano-20k/TRACE-CAPTURE-GUIDE.md`.
A 512-sample x 16-bit ring buffer in `src/ND120_TANG20K_TOP.v`, sampling a
retargetable debug bus (`assign DBG_MEMW` in
`Verilog/CPU-BOARD-3202/circuit/ND3202D.v` -
READ THE CURRENT MAP BEFORE DECODING), trigger = rising bit[7] after an arm
delay, dump over the console UART. Solved the memory-write mystery. Cost:
one map edit + `make gowin` + reflash per investigation; console dies after
the dump (reset to recover).

## 4-5. Gowin GAO / GVIO (vendor embedded logic analyzer / virtual IO)

GAO = Gowin's ILA: capture internal nets on trigger conditions, view
waveforms over JTAG in the Gowin tool on Windows. GVIO = drive internal
control signals over JTAG (reset/halt/step without pins). Integration into
our SCRIPTED build (gowin_build.tcl, not the IDE) is in progress - see
`Verilog/fpga/tang-nano-20k/GAO-HOWTO.md`
(being written). Probe nets for the current hunt are already marked with
`syn_keep` in the RTL: the interrupt-request-enable FF (HIRL/LORL), the
claim outputs, CSA_12_0 at the top.
Caveats: capture UI runs on the Windows side; the analyzer must talk to OUR
FT2232 JTAG (verify - the Gowin tool may expect its own dongle protocol);
costs LUTs/BSRAM (we are at 88% LUT in the OSS flow, the GAO build is
Gowin-flow only).
LIMIT: GAO observes and triggers; it cannot halt or step the CPU - that
needs #10.

## 6-8. Reset control

- UART-BREAK (in the bitstream now): console RX low >=200 ms = Master Clear,
  RAM survives. Proven in the Tang vtest end-to-end. BUT: neither
  termios.tcsendbreak nor TIOCSBRK produces a break the board sees through
  the current FTDI + usbipd chain (measured; suspicion: the BL616 also
  drives/loads the RX net so a long low never reaches the pin - the wiring
  needs checking). Until fixed, BREAK is a sim feature.
- JTAG reflash (`make load-gowin`): the working remote reset; full FPGA
  reconfig, SDRAM content decays -> reload the program after. ~15 s.
- Physical reset pin (PLANNED, next wiring session): `ext_reset_n` GPIO with
  PULL_MODE=UP, OR'd into the por logic next to S1; driven by a Pi Pico GPIO
  (3.3 V, shared GND). Pico runs MicroPython with a one-letter USB-serial
  protocol (R = 100 ms reset pulse; H/S/I reserved for halt/step/IRQ once
  #10 exists). This kills the walk-to-the-board button dependency. Free
  header pins: everything except 4, 15-20, 69-70, 82-84, 87-88 (see
  src/nd120_tang20k.cst; SDRAM pins are on-package "magic" names).

## 9. External logic analyzer

Route suspects to spare GPIOs (`assign debug_pin[..] = ...` + cst lines) and
clip any 3.3 V-capable logic analyzer (sigrok-compatible clones work). The
only tool that shows REAL at-speed timing relative to external events -
the right instrument for bugs that vanish under stepping (like the current
grant bug). Not yet wired; needs an LA on the desk.

## 10. Halt / step / instruction-step debug-control block (design)

A small block gating the CPU's clock-ENABLE (never the clock net):
run/halt/single-cycle/single-instruction, plus breakpoint compare, driven
by GVIO (#5) or the Pico (#8). Requires a clean clock-enable seam at the
core boundary - the FF-mode *_EN pulse structure (CYC_36) is the natural
attachment point; gating those enables halts the CPU coherently. Not
implemented; do after the grant bug closes so the seam is added calmly, not
mid-hunt.

## Choosing

- "What is the CPU doing / where does it die?" -> 1-2 (OPCOM step/breakpoint
  + reference diff).
- "What are these internal signals doing at that moment?" -> 4 (GAO) or 3
  (ring analyzer) if the GAO flow fights back.
- "Is it a pure timing effect?" -> 9 (real probes), plus compare stepped vs
  free-run behavior with 1-2.
- "I need to reset / control it remotely" -> 7 today, 8 as soon as one wire
  is soldered, 5+10 for the full debugger experience.

## Proving a probe survived synthesis

Moved here 28-SEP-2026 from the finished page-fault campaign plans. A build
reporting success proves NOTHING about whether a diagnostic block is in it.
Three mechanisms have removed one while the bitstream still flashed cleanly
and streamed constants: (1) the new file is not in `nd120_tang20k.gprj`, so
it is a black box - caught by `yosys hierarchy -check`; (2) two drivers on
the shared debug port `XMIC_DBG_15_0` (Gowin stops with EX2000; a Verilator
lint of one module misses it - see `gowin_build.ps1`); (3) the TX mux does not
select `dbg_txd` for that define, so everything feeding it is dead code (see
the comment in `src/ND120_TANG20K_TOP.v`). **The check that works:** search
the post-synthesis netlist `build/nd120_tang20k_build/impl/gwsynthesis/*.vg`
for the block's signals, and compare the register count against a build
without the define (the page-fault capture added +174 registers).

## Gate-level timing simulation with Gowin SDF (recipe, not yet used)

Moved here 28-SEP-2026 from the answered masked-grant question sheet;
confirmed available 18-JUL-2026 on the Gowin V1.9.10.02 install, not
re-checked since. The one simulation that models real delays:

- The PnR option "Generate SDF File" exists (`IDE/data/config/
  rtlplacerouteoptions.xml`, id PNR01, command `-sdf`), but the scripted build
  emits only the post-synthesis `.vg`, not a post-PnR `.vo` + `.sdf`. Enable
  both in `gowin_build.tcl` to use this.
- The timing primitive library is `IDE/simlib/gw2a/prim_tsim.v` in the Gowin
  install (gw2a = the Tang's GW2AR die; 284 `specify` blocks).
- iverilog does `$sdf_annotate` and specify delays (Verilator does not):
  `iverilog -o gate <proj>.vo <gowin>/IDE/simlib/gw2a/prim_tsim.v tb.v` with
  `initial $sdf_annotate("<proj>.sdf", dut);` in the testbench.
- Keep it unit-level (e.g. one `CGA_INTR` wrapper through PnR): a full-chip
  gate sim is heavy, and the SDRAM main memory is not in the FPGA netlist.
