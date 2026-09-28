# ND-120 Boot Golden Spec — Microcode Execution Reference

**Full path:** `Verilog/docs/boot-golden-spec.md`
**Last updated:** 2026-07-03 (stale FPGA-failure notes removed 28-SEP-2026:
the Tang Nano 20K and Nexys 4 DDR boot SINTRAN, so the phase 3 stall below is history)

Ground-truth description of the ND-120 microcode boot flow: what address the
CPU executes, in what order, and the per-phase assertions that let tooling
**detect when the boot does NOT do what it should**. Built by cross-checking
three sources that agree:

1. **Observed trace** — `MA/CSA` path from microcode address 0, extracted from
   the Verilator run (`sim/trace_latch.csv`, `sim/waveform.fst`).
2. **ND-120 microcode listing** (version L, what the ROMs hold) — `Code/Microcode/ND-120-DELILAH-L.LISTING.txt` (column 2 = octal WCS address).
3. **ND-110 microcode source** (clean, ROM-validated) —
   `$ND_REPOS/ND110Compile/ND110Compile/uCode/ND-110-RASK.uc`.
   Same label names as ND-120; use it to decode OCR ambiguities. NOTE: ND-110 is
   *similar in principle, not identical* to ND-120 — trust the trace + ND-120
   listing for exact addresses, use ND-110 for semantics/labels.

---

## 0. The execution model (READ FIRST)

- The microcode address the CPU is executing is **`MA_12_0[12:0]`**, produced in
  `CGA_MIC` (`DELILAH-CPU/CGA_MIC/circuit/CGA_MIC.v`, port line 63).
- **Trace convention: sample `MA_12_0` once per microinstruction at
  `posedge MACLK`** — NOT every sysclk (that oversamples ~68x). This is only a
  sampling point. `MACLK` is the micro-address latch strobe: the address
  latches are transparent while it is high and capture on its **falling**
  edge (`SIGNALS.md`, `RETRACTED.md`). Do not read the rising edge as the
  moment a microinstruction "commits".
- `CSA_12_0` at board level is the same address: `SignalReport.md:178` —
  `XMA_12_0 from CGA <= MA_12_0 from CGA.MIC`. So `MA` (inside CGA) and `CSA`
  (board) are the same value; sample whichever is convenient at `posedge MACLK`.
- Address generation path (`mic-calculation.md`):
  `MASEL (jmp/ret/next/repeat) -> W[12:0] -> IPOS mux -> MA[12:0]`. The `IPOS`
  mux can overlay an opcode dispatch (`CD[15:6]`), a control-store write (`WCA`),
  or a **trap vector** (`TVEC[3:0]`), selected by `TRAPN`/`MAPN`/`EWCAN`.
- Only genuinely async steer during a clean boot is the **RTC interrupt** ->
  trap vector -> microcode **octal 16** (see Phase 5). Everything else is
  deterministic.

Golden trace = the sequence of `(MA_12_0 @ posedge MACLK)` values, plus the
branch-condition context at each step.

---

## 1. Boot phase flow

```mermaid
flowchart TD
    P0["Phase 0: POR\nMA=000000\nMASTER CLEAR / POWER CLEAR\nAB,MACL -> MACL"]
    P1["Phase 1: uCode load\nLCS_n=0\nMA ramps 000000..017777\n~68 sysclk/addr (hardware, not MACLK exec)"]
    P2["Phase 2: Init\nMA=002001 MACL:\nseq + calls, jmp 005660/005670"]
    P3["Phase 3: Delay loop\nMA=002045/002046 (SEQFS/STRSW)\nALU countdown F=A-Q"]
    P4["Phase 4: Self-test\nMA=002116..002123 loop x16\nCOND,LC=0 exit"]
    P5["Phase 5: OPCOM ready\nRTC -> MA=000016 PANEL INT\nCOMM,LDLC -> PANEL -> PANVC"]

    P0 --> P1 --> P2 --> P3
    P3 -->|"ZF=1 at 002046 -> 002047"| P4
    P4 --> P5
    P5 -->|"RTC every ~8192 sysclk"| P5

    classDef start fill:#E3F2FD,stroke:#0D47A1,color:#0D47A1;
    classDef proc  fill:#E0F7FA,stroke:#00838F,color:#00838F;
    classDef done  fill:#E8F5E9,stroke:#2E7D32,color:#2E7D32;
    classDef special fill:#F3E5F5,stroke:#7B1FA2,color:#7B1FA2;
    classDef hot   fill:#FFF3E0,stroke:#E65100,color:#E65100;
    class P0 start;
    class P1,P2 proc;
    class P3 hot;
    class P4 done;
    class P5 special;
```

---

## 2. Phase-by-phase reference (observed addresses, octal)

All addresses verified against the Verilator trace from address 0. Ticks are
`sim/trace_latch.csv` cycle numbers (sysclk samples) for orientation only.

### Phase 0 — Power-on / Master Clear
- `MA=000000` = `MACL:` (MASTER CLEAR / POWER CLEAR). Trap vector 0.
- ND-110 ref: `ND-110-RASK.uc:15` (`0/  % MASTER CLEAR / POWER CLEAR  AB,MACL ... MACL;`).
- Entered on reset deassert (`test_nd120.cpp:188`, `btn1=true` at cnt=100).

### Phase 1 — Microcode (WCS) load
- `LCS_n=0`. `MA/CSA` counts **sequentially 000000 -> 017777** (all 8192 words),
  ~68 sysclk per address. This is the hardware load state machine
  (`MR_n -> LCS_n`, `CYC_36`/`PAL_44403C`), **not** MACLK-driven execution.
- After 017777 it wraps to 000000 and `LCS_n -> 1`.
- Observed: ramp begins ~cycle 16,415; wrap at ~cycle 573,403. (`boot-sequence.md`.)

### Phase 2 — Initialization
- First executed address after load: **`MA=002001`** (`MACL:`).
- Observed path (trace, collapsed): `002001 -> ...seq... -> 002017`,
  jmp `005660 -> 005670 -> 002020`, then CALLs `001006`, `001020`, `003707`,
  `001021`, `001163-001165`, `001022-001027`, `001112-001116`, `002173-002201`,
  falling through `002042 -> 002044`.
- This is CPU + MOPC (operator comms) variable init.

### Phase 3 — Delay loop (ALU countdown)
- `MA=002045 / 002046` (labels `SEQFS` / `STRSW`). ALU countdown: `Q` preloaded
  (e.g. 0x3FFF), each iteration `F = A - Q`; loop while `ZF=0`.
- Reusable subroutine, called 3x during boot (136 / 6 / ~180,213 iters). The big
  3rd call is the ~0.5-1 s power-up delay.
- **SHOULD:** at `002046`, when `ZF=1` (F reached 0), branch to **`002047`**.
- Historical: in July 2026 the FPGA build stuck oscillating `002045/002046`
  here and never reached `002047`. Solved; the Tang and Nexys boot SINTRAN.

### Phase 4 — CPU self-test
- Exit `002047 -> 003710` (util) `-> 001035-001037 -> 002050 ... 002115` (setup)
  `-> 002116-002123` **self-test loop**.
- Self-test loop `002116-002123`: iterates ~16 times; `COND,LC=0` at `002123`
  exits when the loop counter reaches 0. (`002116` area in ND-120 listing
  lines 6560-6610; error path `STERR1` at `002121`.)
- This loop is self-test TEST 6 (loop counter / shift-right-double via GPR),
  a pure CPU-core test. It does NOT touch memory parity - the `IDBS,PEA`
  select in the `002123` loop-back word is a don't-care (`ALUD,NONE`); no
  self-test subtest exercises memory parity at all. Full evidence:
  `docs/nd120-parity-analysis.md`.
- Then UART output routines run (self-test result banner).

### Phase 5 — OPCOM ready + RTC async
- CPU reaches OPCOM (operator communication) ready and waits for a UART command.
- **RTC interrupt** now fires periodically -> trap vector -> **`MA=000016`**
  = PANEL INTERRUPT: `IDBS,PANEL COMM,LDLC T,JMP -> PANEL -> PANVC`
  (`ND-110-RASK.uc:90` `16/`, and lines 234-250; ND-120:
  `Code/Microcode/ND-120-DELILAH-L.LISTING.txt` lines 90-96). The trap vector
  reaches o000016 through the `CGA_MIC_IPOS` override (`MA = TVEC`), not
  through MASEL. `COMM,LDLC` (CSCOMM o17; `LDLCN` = CSCOMM o17 AND `LCS_n`=1,
  decoded in `CGA_DCD.v`) loads the loop counter LC from `CD[5:0]` at the next
  MCLK rise; LC then indexes the PANVC jump table at o003760 (L listing lines
  10254-10278): `0:STOP 1:MS20 2:PRQ 3:SING2 4:LOAD 5:CONT 6:RSTRT 7:MACL`.
  The 20 ms RTC interrupt loads LC = o01, so it runs o003761 -> MS20
  (o002333 in DELILAH-L, o002261 in RASK). Path:
  `PANEL(o000050) -> o000051 -> o000052 -> o003761 -> MS20 -> MOPC/MRET1`.
  Verilator shows LC = o01 loaded at the first PANVC dispatch (14-APR-2026);
  the ND110Compile emulator asserts the same in its unit test
  `PanelInterruptDispatch_TakesPanvcEntry1_MS20` (commit 4376d46, both RASK
  and DELILAH-L).
- Observed RTC/PANVC dispatches begin ~cycle 755,233 in the trace.

---

## 3. Detection rule — "did it do what it should?"

Reduce a run (sim or FPGA) to `MA @ posedge MACLK` and check against the phases
above. Classify every divergence:

- **STRUCTURAL divergence = BUG** — same `(MA, branch condition)` yields a
  different next `MA` than the golden spec. Detection examples:
  - Phase 2: first post-load `MA != 002001`, or the `002017 -> 005660 -> 005670
    -> 002020` jump chain is wrong -> IPOS/MASEL address selection broken.
  - **Phase 3: `MA` stays in {002045, 002046} beyond the max expected iteration
    count and never reaches `002047`** -> the July 2026 FPGA stall. Concretely: at
    `002046` with `ZF=1`, observed next `MA=002045` instead of `002047`.
  - Phase 4: self-test loop `002116-002123` does not exit after LC reaches 0.
- **BENIGN divergence = IGNORE** — different delay-loop iteration counts,
  different RTC dispatch timing/count, different absolute ticks. These follow
  from clock/RTC phase, not from logic errors.

Minimum signals to log per step for this rule: `MA_12_0`, `MACLK` (edge),
`LCS_n`, `ZF` (or `COND`), `TVEC_3_0`, `TRAPN`, and an RTC-active flag.

---

## 4. How to capture the golden trace (sim)

The harness (`sim/test_nd120.cpp`) already reads `top->CSA_12_0` every tick and
already event-logs the delay-loop exit (`:204-209`). To produce the per-step
golden trace, add a hook that, **on `posedge MACLK`**, appends
`{tick, MA, ZF, TVEC, TRAPN, rtc}` to `boot_trace.json`. Expose `MACLK`, `ZF`,
`TVEC`, `TRAPN`, RTC as top-level `s_debug_*` signals (some already are), or read
them via `rootp` as `latch_ff_compare.cpp` does.

Then the FPGA ILA capture (same signals, `s_debug_csa` = `MA`) reduces to the
same form, and `compare_boot_trace.py` applies the Section 3 rule.

---

## 5. Source references

- `Verilog/mic-calculation.md` — `MA_12_0` generation (MASEL/W/IPOS).
- `Verilog/cycle_clock.md` — `MACLK_n`/`MCLK_n` cycle-state timing.
- `Verilog/sim/boot_analysis.md` — boot timeline Phases 1-5.
- `Verilog/boot-sequence.md` — PROM -> WCS microcode load.
- `Verilog/SignalReport.md` — signal cross-ref (`CSA_12_0 = MA_12_0`).
- `Code/Microcode/ND-120-DELILAH-L.LISTING.txt` — ND-120 listing, version L (addresses).
- `$ND_REPOS/ND110Compile/ND110Compile/uCode/ND-110-RASK.uc` — clean ND-110 source (label/semantic decode).
- `Verilog/sim/FPGA_DEBUG_RUNBOOK.md` — last section: the golden-model comparison method and scripted ILA capture (moved from the retired FPGA-BRINGUP-PLAN.md).
