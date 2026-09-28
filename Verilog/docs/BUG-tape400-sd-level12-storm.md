# `400$` tape boot: the "level-12 interrupt storm" (C device model)

Solved 13-JUL-2026 (landed in the squashed commit cd9b94f). Confirmed on a
rebuild: the `400$` boot log dropped from ~9.5 MB of interrupt messages to 59
lines, and ARGUMENT ran all 9 levels to `== END OF TEST ==` in 60M cycles.
Since then the default runSim build uses the Verilog tape device
(`VERILOG_TAPE ?= 1`, `runSim/Makefile`); this bug lived in the legacy C
papertape model, still built with `VERILOG_TAPE=0`.

## Root cause

It was console `printf` output, not the CPU looping in an interrupt handler:

- `simDevices/NDBus.cpp` drove the interrupt lines as
  `BINTxx_n = !((interruptBits & 1<<xx) == 1)`. `interruptBits & (1<<12)` is 0
  or 4096 - never `== 1` - so BINT10..13 were always deasserted. C-device
  interrupts never reached the CPU; `400$` booted by polling. The bug dates
  from commit 468aec0 (2025-03-24), before the SD/FAT work it was first blamed
  on.
- `simDevices/NDDevices.h` (`GenerateInterrupt`/`ClearInterrupt`/`TickIODelay`)
  printed on every call, and the header forced the `DEBUG_*` channels on. Every
  tape byte printed several lines; ~46K bytes made hundreds of thousands of
  console writes.

## Fix

1. The per-byte prints are opt-in: the `DEBUG_*` channels are off by default,
   and the interrupt/IDENT prints are behind `#ifdef DEBUG_INTERRUPT` /
   `if (DEBUG_BIF)`. The `test-full` console golden gate compiles them back in
   with `-DDEBUG_INTERRUPT` (see `Verilog/Makefile`), because the golden log
   holds those lines.
2. The BINT lines are driven correctly (`NDBus.cpp`, one interrupt per byte,
   cleared by IDENT), under `NDBUS_ASSERT_C_INTERRUPTS` in `NDBus.h` (default 1).
   Setting it to 0 restores the old poll-only behaviour for a regression
   check; the prints stay quiet either way.
