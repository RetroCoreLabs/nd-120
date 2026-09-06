# PLAN - Tang Nano 20K silicon hangs: 0!, RUN, BYTE-STRING, STACK, SEGMENT

**Full path:** `Verilog/fpga/tang-nano-20k/PLAN-tang-silicon-hangs.md`
Date: 17-JUL-2026. Board state: Gowin bitstream (SRAM load) built 16-JUL 03:19,
INSTRUCTION-B.BPUN on card as BOOT.BPUN, loads byte-perfect (verified 99.9%
over OPCOM dump `0<54730`), starts via `20!`, full menu.

## Measured facts (all on silicon, 17-JUL session)

- `400$` tape load completes byte-perfectly (22988/23001 sampled words match
  the file; remainder = runtime-initialized cells) but the program NEVER
  auto-starts after the load.
- `0!` (cold start, entry address 0) dies silently; console dead until S1/btn1.
- `20!` (warm restart, entry 020) starts instantly, prints the greeting +
  full menu; HELP and most test areas run fine.
- Areas that run clean: ARGUMENT, MEMORY-REFERENCE, SEQUENCE,
  REGISTER-OPERATIONS, BIT-OPERATIONS, SHIFT-INSTRUCTIONS, 32-BITS-FLOATING,
  48-BITS-FLOATING(?), PRIVILEGED, ND100-24BIT, BCD, ND100-CX.
- Areas that hang: RUN, BYTE-STRING, STACK, SEGMENT. Plus `0!` and (earlier,
  with CONFIGURATIO loaded) LIST-ALL-DEVICES - Ronny observed a genuine hang.
- Verilator FF-mode passes ALL of these (RUN to EOT since commit 3acef36;
  BYTE-STRING full pass 17-JUL with widened cycle counter).
- SDRAM exonerated: OPCOM write/readback across all 64K words = 16/16 clean.
- RQBIT V2 (loop-free interrupt request bits, commit 9d5a1cb) did NOT fix
  these hangs.

## Why these five, and not the others - the suspect threads

Thread A - **internal-interrupt / trap machinery under real timing**:
RUN exercises IOX-error/level-14/IIC; STACK exercises stack-demon traps
(level 14); SEGMENT exercises paging traps and does a DELIBERATE RESTART;
`0!` cold start initializes and turns ON the interrupt system (ION/PON/SEX)
before printing. The passing areas are exactly the ones that lean least on
traps/internal interrupts. The interrupt block still contains async
SR-latch structures beyond RQBIT (PICMASK etc.) - the historical Gowin
glitch suspects.

Thread B - **console/terminal re-init kills UART TX** (Ronny's print-crash
theory): cold start programs the terminal controller via IOX control writes
before printing the banner; the warm entry (020) skips that re-init and
prints fine. LIST-ALL-DEVICES (CONFIGURATIO) probes terminal controllers
with IOX writes too. If an IOX write to the console control register wedges
the Tang UART transmit side, `0!` "hangs" spinning on a ready flag.
Does NOT obviously explain RUN/STACK/SEGMENT.

Thread C - **BYTE-STRING may not be hung at all**: proven in sim 17-JUL that
the area repeats each sub-test ~127x per level BY DESIGN and needs ~500M
cycles for level 1 alone, multi-billion for the full area. At the Tang CPU
clock that is minutes-per-level. Must be re-tested with a patience budget
before being counted as a hang.

Thread D - **bitstream provenance**: confirm the flashed .fs (built 16-JUL
03:19) actually contains 3acef36 (FIDBO swap fix + status fence + MOR) and
9d5a1cb (RQBIT V2). If the fence/FIDBO fixes are missing from the bitstream,
RUN would fail on silicon for the already-fixed reason. Verify, do not
assume - rebuild once from current HEAD if in doubt.

## The plan, in order

### Phase 0 - cheap decisive checks (no rebuild)

0.1 **Bitstream provenance** (Thread D): check the build log / git state used
    for `build/nd120_tang20k_build/impl/pnr/nd120_tang20k_build.fs`. If not
    provable, `make gowin` from current HEAD once, reflash, re-test the four
    areas. Everything after this runs on a KNOWN bitstream.
0.2 **BYTE-STRING patience run** (Thread C): start BYTE-STRING, wait >= 10
    minutes wall, watching for the level-1 `== END OF TEST ==`. Compute the
    expected time from the actual CPU clock first. If it completes -> it was
    never hung; remove from the bug list.
0.3 **Characterize each true hang**: for RUN, STACK, SEGMENT (and 0!): note
    LED state, try ESC and CR, note whether console echoes. One line per
    hang in this doc. Distinguishes CPU-dead vs output-dead vs busy-loop.

### Phase 1 - instruction-level embedded debugger (ndcomm, no rebuild)

The tool exists: `Verilog/fpga/tools/ndcomm/ndcomm
-t N -r /dev/ttyUSB1` single-steps N instructions via OPCOM (Z-step) dumping
IR/STS/D/B/L/A/T/X each step. 9600 baud console; the port must be free.

1.1 **Cold-start trace**: btn1 -> step ~2000 instructions from P=0. The trace
    ends AT the death: either spinning on a UART ready flag after a console
    IOX write (proves Thread B) or vanishing into the interrupt/trap system
    after ION (points to Thread A). This is the single highest-value
    measurement and needs no RTL change.
1.2 **Compare against sim**: run the identical first ~2000 cold-start
    instructions in Verilator (tverify trace armed at P=0) and diff. First
    divergent instruction = the bug's address. Comparator + symbol map exist
    (tests/instruction-verify/).
1.3 If RUN/STACK/SEGMENT hangs are reachable by stepping into the area a
    bounded distance (they may be millions of instructions in), skip
    stepping and go to Phase 2 for those.

### Phase 2b - onboard debug agent (Ronny 17-JUL: full remote debugger)

Goal: read pins/signals/memory, capture traces, and reset - remotely, over
the existing console UART, even with the CPU hung. Build one small always-on
monitor core in `ND120_TANG20K_TOP.v` from the pieces that already exist:

- Entry: the UART-BREAK detector switches the console mux from the CPU to
  the monitor (console-takeover precedent: the analyzer dump already does
  this). CPU keeps running (or stays hung) - the monitor is clocked from
  sys_clk and does not depend on CPU state.
- Command set (single letters, 9600 baud, human-typeable):
    g<N>  read probe group N (16-bit muxed buses: CSA, P-path, IRQ/PIL,
          UART status, tape/storage state - map documented in the top)
    m<addr> / M<addr> <val>  read/write memory via the nd_storage SDRAM
          device port (second memory master, no CPU involvement)
    t     arm/dump the 512-sample ring analyzer (existing block)
    R     reset the CPU (what a long BREAK does today)
    c     hand the console back to the CPU
- Validation: every command exercised in the Tang vtest
  (`sim/nd120_tang20k_tb.v`) before any bitstream is built.
- Budget check: Gowin flow has LUT headroom (the OSS flow does not - this
  agent is for the Gowin bitstream).

NOTE (vtest rot, fixed 17-JUL): the vtest gate had been failing to COMPILE
since the FAT-slimming commit (missing -I for sd_fat_features.vh, missing
-DND_STORAGE_PORT/-DSDFAT_NO_STORAGE_CHECK in sim/Makefile DEFS) - i.e. the
"Tang vtest" line of `make test-full` was broken. Keep sim/Makefile DEFS in
lockstep with src/tang20k_defines.v when defines change.

### Phase 2 - signal-level embedded analyzer (one-file retarget + rebuild)

The 512x16 on-chip analyzer already exists in
`Verilog/fpga/tang-nano-20k/src/ND120_TANG20K_TOP.v`
(ring buffer, trigger = rising bit[7] after arm delay, dump over console
UART). Bit map = `assign DBG_MEMW` in
`Verilog/CPU-BOARD-3202/circuit/ND3202D.v`.
Guide: `Verilog/fpga/tang-nano-20k/TRACE-CAPTURE-GUIDE.md`.

2.1 **Map v4 (cold start / console)**: bits = console IOX strobe (trigger),
    UART TBMT, IOX device address low bits, CSA low bits. Reproduce `0!`.
    The capture shows whether TBMT ever returns after the terminal-init
    IOX write (Thread B verdict).
2.2 **Map v5 (trap/interrupt)**: bits = IREQ14/IRQ, PIL bits, TRAP request,
    CSA low bits; trigger = level-14 request (or first trap) while running
    STACK. Shows whether the trap fires, vectors, and where the microcode
    goes off the rails (Thread A verdict).
2.3 Each retarget: edit ND3202D.v bit map only, `make gowin`, reflash
    (SRAM load), reproduce, decode per the guide. Budget one investigation
    per retarget - the map changes are cheap, the discipline of reading the
    current map before decoding is not optional.

### Phase 3 - fix by class

Whatever Phase 1/2 names:
- Async-latch class (Thread A): convert the remaining CGA_INTR async
  SR-latches (PICMASK etc.) the RQBIT-V2 way - sysclk catcher-FF, proven
  pattern, testbench first, then swap.
- UART/IOX class (Thread B): fix the console controller's control-write
  handling in the Tang UART glue (IO_37/tang top), sim-test with the same
  IOX sequence the cold start issues.
- Constraint class: if the capture shows clean logic but wrong values at
  speed, revisit Gowin timing constraints on the involved paths (the
  CDC/false-path set), not the logic.

### Phase 4 - regression gate

After any fix: `0!` cold boot must print the banner; `400$` must auto-start;
RUN, STACK, SEGMENT each to their own `== END OF TEST ==`; BYTE-STRING
level-1 EOT within its computed time budget; plus the standard sim suite
(`make test`) stays green - silicon fixes must not regress the reference.

## Remote reset (NEW, 17-JUL - so no more btn1 round-trips)

`ND120_TANG20K_TOP.v` reset block now also fires on a UART BREAK: console RX
held LOW >= 200 ms acts exactly like S1 (por restarts, CPU reboots; RAM
survives). Host side: `termios.tcsendbreak` / picocom `C-a C-\`. BREAK is
out-of-band - typed commands and ndcomm binary streams cannot fake it.
Validated in the Tang vtest (`fpga/tang-nano-20k/sim/nd120_tang20k_tb.v`):
boot -> deposit -> BREAK -> reboot to '#' -> deposit survives. Needs a
`make gowin` rebuild + reflash before it exists on the board.

## Fix-loop principle (Ronny 17-JUL)

Every silicon finding gets (1) reproduced/validated against Verilator with
the same stimulus, (2) fixed in RTL, (3) re-proven on BOTH: the sim gate
suite stays green and the silicon symptom is gone. No fix ships on the board
that is not first demonstrated in the simulator.

## Session practicalities

- After every board power cycle: `make usb` (new target) then reflash
  (`make load-gowin`) - SRAM bitstream does not survive power-off.
  `make flash-gowin` writes it persistently if preferred.
- Console = /dev/ttyUSB1, 9600 8N1. OPCOM range dump `n<y` (e.g. `0<54730`)
  is the memory-verify tool; full-image compare script pattern lives in this
  session's scratchpad and should be promoted into fpga/tools/ if reused.
- btn1 = the only recovery from a true hang; every hang costs one manual
  press - batch the experiments accordingly.
