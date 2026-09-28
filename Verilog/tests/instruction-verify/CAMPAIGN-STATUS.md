# Instruction-verify campaign status (table 13-JUL-2026, RUN row 15-JUL-2026)

Two verification layers per INSTRUCTION-B area:
- **Deep verdict**: run the area to its own `== END OF TEST ==` and count
  error lines (the area's full case sweep, tens of thousands of
  instructions; catches what the golden window cannot).
- **Golden gate**: `run_area_test.sh <AREA>` - first 400 instructions
  trace-compared against the ND-110 reference, mechanical comparator.

Only the golden gate is automated (`make test-instr`, the 13 areas in
`INSTR_AREAS`). The deep verdicts were measured by hand on 13-JUL-2026 in an
FF-mode build (`USE_LATCHES=0`); their logs were never committed, so the
"0 err" column cannot be re-checked from this repository - re-run an area to
its END OF TEST to confirm it today.

| Area | Deep END-OF-TEST | Golden 400 gate |
|---|---|---|
| ARGUMENT | PASS, 0 err | PASS |
| MEMORY-REFERENCE | PASS, 0 err (post MPY fix dc61bd6) | PASS |
| REGISTER-OPERATIONS | PASS, 0 err | PASS |
| SHIFT-INSTRUCTIONS | PASS, 0 err (post SSEL fix 2e2ea37; was 3988) | PASS |
| BIT-OPERATIONS | PASS, 0 err | PASS (12-JUL batch) |
| SEQUENCE | PASS, 0 err | PASS (12-JUL batch) |
| STACK | PASS, 0 err | PASS (12-JUL batch) |
| BYTE-STRING | PASS, 0 err | PASS (12-JUL batch) |
| BCD | PASS, 0 err | PASS |
| ND100-24BIT | PASS, 0 err | PASS |
| ND100-CX | PASS, 0 err | PASS |
| PRIVILEGED | PASS, 0 err | PASS |
| 32-BITS-FLOATING | PASS, 0 err | PASS |
| 48-BITS-FLOATING | **N/A** - machine is 32-bit-float configured (see docs/48bit-float-not-configured.md) | not gated (the 400 window ends before the float instructions, so a pass there proves nothing) |
| RUN | **NOT proven.** On 15-JUL-2026 (commit 3acef36: FIDBO status-fence swap fixed, Am2914 fence default, MOR wired to level 12) RUN handled IOX-ERROR and reached LEVEL 13 / ARGUMENT `== END OF TEST ==` - one area's end inside RUN's level loop, not the end of RUN. No error count was recorded and no log committed | not gated - not in `INSTR_AREAS` nor in `tests/run_all_tests.sh`; see `Verilog/docs/RUN-level14-livelock-analysis.md` |

Bugs found and fixed by the campaign:
1. `CGA_ALU_QREG` MUXQ15.D3 - multiply product/overflow
   (docs/MPY-dynamic-overflow-rootcause.md, commit dc61bd6).
2. `CGA_CPU_ALU_CONTR` MEMORY_46/47 - shift-type capture
   (docs/SHIFT-serial-input-rootcause.md, commit 2e2ea37).

Both have Logisim-drawing regeneration hazards tracked in TODO.md.
CPU self-test: 0 execution-phase STERR visits.
