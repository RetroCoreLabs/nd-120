# SOLVED 01-SEP-2026 - the WCS read was one clock too slow on the MiSTer

**Root cause.** `Shared/support/IDT6168A_20.v` then built the WCS from an
`altsyncram` megafunction in a section ONLY the MiSTer build compiled, and it
specified `outdata_reg_a("CLOCK0")`. `altsyncram` ALWAYS registers the address
in synchronous mode (`ram_block_type("M10K")`, and an M10K physically cannot
read asynchronously - the same constraint that forces the async cache RAMs
onto MLAB). `outdata_reg_a` adds an OPTIONAL SECOND register, so the read took
TWO clocks where the plain-Verilog model every other target runs takes ONE.

Ronny called it: "i meant SRAM!!!! not DRAM - data needs to come out from WCS
ASAP as address changes."

**Consequence.** Every microinstruction reached the microsequencer a clock
late, so the sequencer ran one step out of step with the cycle controller. A
nested microsubroutine `T,RETURN` then popped the wrong address - 001015
instead of the 002027 MACL pushed at 002026 - MACL never resumed, and the CPU
looped forever in the interrupt-register microcode
(`RIIE1`/`RPIE1`/`RPID1`/`CHKIT`/`PICFM`) instead of reaching MACL2 and OPCOM.
(Addresses octal; listing `Code/Microcode/ND-120-DELILAH-L.LISTING.txt`.)

**First fix (board v44).** `outdata_reg_a("UNREGISTERED")` in both
Quartus-only sections (`IDT6168A_20.v` = WCS, `MEM_RAM_49_BLOCKRAM.v` = main
memory). Main memory also had `rden_a(1'b1)` with
`read_during_write_mode("DONT_CARE")`, reading on every write cycle and
returning undefined data where the plain model holds - fixed to
`rden_a(win && MWRITE50_n)`.

**Measured on the board (v44):**

| | before | after |
|---|---|---|
| CPU green lamp (set only at MACL2, i.e. self-test PASSED) | dark | **LIT** |
| MIPS | 00.00 | **00.43** |
| Active level | 000000 | 000001 |
| 001020 `NOTI2` `T,RETURN` | -> 001015 (wrong) | **-> 002027 (correct)** |
| after the return | 31-state loop | **02030, 02031, 03707 - matches the golden trace** |

**Final fix, same day.** The altsyncram arm is gone. Both files now carry a
`QUARTUS_RAM_INFER` arm: the same array and the same 1-clock behaviour as the
reference model, in plain Verilog shaped so Quartus 17.0 maps it onto M10K
(`IDT6168A_20.v`, `MEM_RAM_49_BLOCKRAM.v`; the note in `IDT6168A_20.v`
explains why a `ramstyle` attribute alone was not enough). No altsyncram is
left in the ND-120 RTL.

**Why it hid for so long, and the gate that guards it now.** Only MiSTer
compiled that section, so no simulation could ever execute it. The
equivalence check of the day compared it against a hand-written stub that
was itself wrong by one clock, so the test passed with the bug present. The
gate today is `Shared/support/sim/run_quartus_ram_equiv.sh`, registered as
`test-quartus-ram-equiv` in `tests/run_all_tests.sh`: it compiles and runs
BOTH the `QUARTUS_RAM_INFER` arm and the reference model and proves them
cycle-identical.

The 31-microinstruction loop the board was stuck in, and the golden-window
comparison that located it, are in git history.
