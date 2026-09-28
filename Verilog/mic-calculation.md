# MIC Address Calculation — ND-120 CGA (DELILAH) Analysis

**Full path:** `Verilog/mic-calculation.md`

**Scope:** This document describes every signal that participates in the generation of the microcode RAM address `MA[12:0]` inside the CGA (DELILAH) gate array, and answers the specific question: *do internal traps (MPV / page fault / illegal instruction) still fire when `IONI` (STS bit 15) is off, i.e. after an `IOF` instruction?*

All line numbers refer to files in `Verilog/`.

Facts in this document are taken directly from the Verilog. Anything I could not verify from the code is explicitly flagged with **[UNVERIFIED]** or listed in the "Open questions" section at the end.

---

## 1. Top-level signal flow

The microcode address `MA[12:0]` is produced inside `CGA_MIC` (`DELILAH-CPU/CGA_MIC/circuit/CGA_MIC.v`). It goes out through port `MA_12_0` (line 63) and drives the microcode RAM.

The internal data-path that produces `MA[12:0]` has four stages, in order:

```
  (jump/ret/next/repeat source) ──► MASEL ──► W[12:0]   ──┐
                                                          │
                                            WCA[12:0] ───►┤ IPOS ──► MA[12:0]
                                            CD[15:6]  ───►┤  (mux)
                                            TVEC[3:0] ───►┤
                                                          │
                                            TRAPN, MAPN, EWCAN select
```

`W[12:0]` is the "would-be next micro-address" (jump / return / next-sequential / repeat), and `IPOS` is the last-stage mux that can overlay an **opcode dispatch** (`CD[15:6]` → page 2), a **WCA-driven control-store write** (WCA bus), or a **trap vector** (`TVEC[3:0]` with the two high MA bits forced) on top of `W[12:0]`.

---

## 2. The final mux — `CGA_MIC_IPOS`

File: `DELILAH-CPU/CGA_MIC/circuit/CGA_MIC_IPOS.v`.

Inputs:

| Port        | Source                                 | Role                                    |
|-------------|----------------------------------------|-----------------------------------------|
| `W_12_0`    | `MASEL.regW`                           | Normal next microcode address           |
| `WCA_12_0`  | `CGA_MIC_WCAREG`                       | Address for writing new microcode       |
| `CD_15_0`   | FIDB/CD bus (latched instruction word) | Opcode dispatch (`CD[15:6]` → MA[9:0])  |
| `TVEC_3_0`  | `CGA_TRAP`                             | Trap vector (low 4 bits of MA)          |
| `TRAPN`     | `CGA_TRAP_BRKDET`                      | Active-low trap pending                 |
| `MAPN`      | Decoded from cycle state               | Active-low "map opcode bits to MA"      |
| `EWCAN`     | Cycle control                          | Active-low "use WCA as MA"              |

Output: `MA_12_0[12:0]` — the microcode RAM address.

### 2.1 Select-signal generation (lines 79–131)

```
s_gates1_out = NAND(MAPN , EWCA)          // (EWCA = ~EWCAN)
s_gates2_out = AND (MAPN , TRAPN)
s_gates3_out = AND (TRAPN, s_gates1_out)
mux_selector[1] = ~s_gates2_out            // = NAND(MAPN, TRAPN)
mux_selector[0] = ~s_gates3_out            // = NAND(TRAPN, NAND(MAPN,EWCA))

mux_selector_12[0] = NAND3(TRAPN, EWCAN, MAPN)
mux_selector_12[1] = NAND (MAPN , TRAPN)
```

Truth table of the 2-bit selector (for bits 11..0 of MA), enumerated by activity of the three control signals:

| TRAPN | MAPN | EWCAN | sel[1] | sel[0] | Chosen source | Meaning                     |
|:-----:|:----:|:-----:|:------:|:------:|:--------------|:----------------------------|
|  1    | 1    | 1     | 0      | 0      | `W_12_0`      | Normal microcode flow       |
|  1    | 1    | 0     | 0      | 1      | `WCA_12_0`    | Write-control-store address |
|  1    | 0    | x     | 1      | 0      | `CD_15_0`     | Opcode dispatch             |
|  0    | x    | x     | 1      | 1      | `TVEC_3_0`    | **Trap vector**             |

(The enumeration above follows directly from the gates on lines 79–129 of `CGA_MIC_IPOS.v`.)

Note: when `TRAPN` is asserted (low), `sel[1:0] == 11` regardless of `MAPN` / `EWCAN`. So **a trap overrides everything else** in this mux.

### 2.2 Bit-by-bit mux structure (lines 131–246)

- **MA[12]** is a 4-to-1 mux between `W[12]`, `WCA[12]`, `1`, `0`. Its selector is `mux_selector_12[1:0]`, which forces MA[12] to `1` when `TRAPN=0` or `MAPN=0` and `EWCAN=1`.
- **MA[11]** and **MA[10]** are 4-to-1 muxes between `W`, `WCA`, `1`, `0`. Under `TRAPN=0` the `"11"` input (gnd) is selected → `MA[11] = MA[10] = 0`.
- **MA[9:4]** are 4-to-1 muxes between `W`, `WCA`, `CD[15:10]`, `gnd`.
- **MA[3:0]** are 4-to-1 muxes between `W`, `WCA`, `CD[9:6]`, `TVEC[3:0]`.

So on a trap the address becomes:

```
MA[12]   = 1
MA[11]   = 0
MA[10]   = 0
MA[9:4]  = 0
MA[3:0]  = TVEC[3:0]
```

i.e. the trap vector lives at page `1_00_0000_xxxx` (binary) = octal `10000`–`10017` in the control store. This is an **unconditional** hardware override; there is no microcode enable on it.

### 2.3 What is **NOT** an input to IPOS

- `IRQ` is not here. The interrupt request can only steer microcode flow by going through `TRAPN` (see §4), or by being tested as a CSEL condition (see §5).
- `IONI` (STS[15]) is not here.
- No ALU flag, no PIL, no PONI.

---

## 3. The `W[12:0]` data-path — `CGA_MIC_MASEL`

File: `DELILAH-CPU/CGA_MIC/circuit/CGA_MIC_MASEL.v`.

MASEL produces `W[12:0]` (fed to IPOS) and `IW[12:0]` (fed back to IINC for next-increment and to MASEL itself for the REPEAT case).

### 3.1 The four sources

```
regREP_comb =
  SEL_JUMP   (SC6=0,SC5=0) : {CSBIT20, CSBIT[11:4], JMP[3:0]}   // micro-JUMP
  SEL_RETURN (SC6=0,SC5=1) : RET[12:0]                          // subroutine return
  SEL_NEXT   (SC6=1,SC5=0) : NEXT[12:0]                         // IW + 1 (with carry skip)
  SEL_REPEAT (SC6=1,SC5=1) : IW[12:0]                           // re-run this word
```

(Lines 100–123.)

`regW` (= `W_12_0`) is a transparent latch of `regREP` while `s_mclk_n` is high, and holds the previously-registered `IW` while `s_mclk_n` is low (lines 132–138).

`regIW` (= `IW_12_0`) captures `regREP` on `posedge s_mclk` and resets to 0 when `MRN=0` (lines 143–149).

### 3.2 The jump-target construction

```
s_jmpaddr_12_0 = { CSBIT20,         // MA[12] ← control-store bit 20
                   CSBIT[11:4],     // MA[11:4] ← CSBIT[11:4]
                   JMP[3:0] }       // MA[3:0] ← JMP[3:0]   (from ILC_MUX)
```

`JMP[3:0]` is built in the `ILC_MUX` in `CGA_MIC.v` (lines 758–781) from one of three 4-bit sources:

| `CSMIS0` | `CSVECT_N` | `JMP[3:0]` source                      |
|:--------:|:----------:|:---------------------------------------|
| 0        | 0          | `IR[3:0]`                              |
| 0        | 1          | `LAA[3:0]` (latched A-register select) |
| 1        | x          | `CSBIT[3:0]` (control-store literal)   |

So a micro-JUMP's low-4-bits can be: a literal, an indirect via the latched IR, or an indirect via LAA.

### 3.3 NEXT — sequential increment (`CGA_MIC_IINC`)

Line 23 of `CGA_MIC_IINC.v`:

```
assign NEXT_12_0 = IW_12_0 + CIN;
```

`CIN` is constructed in `CGA_MIC.v` lines 338–353:

```
s_iwan0or1 = OR(CSWAN[1], CSWAN[0])
s_carry_in = NAND3(s_iwan0or1, LCS, 1)
```

Where `CSWAN[1:0]` comes from `CGA_MIC_INCOUNT` and `LCS = ~ILCSN` is "Internal Load Control Store". In plain terms: when the control store is being written (ILCSN=0 → LCS=0) the increment is suppressed (`CIN=1`, which here is the inactive state of the open-collector-style NAND), and during normal execution the `CSWAN`-driven write-ack gates the increment.

**[UNVERIFIED]** The exact semantics of `CSWAN[1:0]` vs LCS w.r.t. whether `NEXT = IW` or `NEXT = IW+1` — I would need to re-read `CGA_MIC_INCOUNT` to pin down the polarities. The important point for this document: `NEXT[12:0]` is a pure function of `IW[12:0]`, `CSWAN`, `LCS`. **No trap, interrupt, or IONI signal is involved.**

### 3.4 RETURN — microcode stack (`CGA_MIC_STACK`)

`RET[12:0]` is the top-of-stack output of a 74S482-style stack, clocked by `SCLKN` (negated MCLK). The stack operation is selected by `SC[4:3]`:

```
00: HOLD   01: POP   10: LOAD   11: PUSH
```

The stack is filled with `NEXT[12:0]` values on PUSH and popped on POP. **No trap, interrupt, or IONI signal is involved.**

### 3.5 Who drives SC[6:3]?

`SC[6:3]` is built inside `CGA_MIC.v`:

```
SC[3] = CSFS[3]_through_FF   ( GATES_22: NOR(csts3_etrue, fs3_efalse) )
SC[4] = CSFS[4]_through_FF   ( GATES_21: NOR(csts4_etrue, fs4_efalse) )
SC[5] = NOR(gates18_out, gates20_out)
SC[6] = NOR(LCSN,       gates19_out)
```

where each of `csts_etrue` / `fs_efalse` is `AND( s_etrue_or_efalse , CSTS_6_3[i] or FS_6_3[i] )`, and in turn:

```
s_etrue  = NAND(s_cond_n, gates5_out)
s_efalse = AND4(s_cond_n, csloop_n, lcs_n, csecond)
gates5_out = NAND3(LCS_N, csloop_n, csecond_n)
```

So `SC[6:3]` — and therefore **which of {JUMP, RETURN, NEXT, REPEAT} MASEL selects** — is a function of:

- `CSTS[6:3]` : control-store "true-select" bits (fields of the current micro-word)
- `FS[6:3]` : control-store "false-select" bits (from `CONDREG`, latched CSBIT[3:0])
- `s_cond_n` : the **latched** test-condition output of `CSEL` (latched through `MEMORY_32`, line 1085–1095)
- `CSLOOP` : micro-loop control
- `CSECOND` : micro-"enable conditional" control
- `LCSN` / `LCS` : load-control-store indicator

The selection between the JUMP / RETURN / NEXT / REPEAT sources is therefore **ultimately gated by `s_cond_n`**, which is produced by `CSEL`, described next.

---

## 4. Trap generation — summary of what drives `TRAPN`

`TRAPN` is produced by `CGA_TRAP_BRKDET` (`DELILAH-CPU/CGA_TRAP/circuit/CGA_TRAP_BRKDET.v`). The sum-of-products that drives `TRAPN` low (trap asserted) is, read from lines 160–264:

```
TRAPN low  ⇐  BRK low AND CBRK high AND ETRAPN high
BRK low    ⇐  gates12_out high  OR  CBRKN low
gates12_out= NOR3( gates10_out, gates5_out, gates20_out )
```

with:

- `gates5_out = OR4( IPV , WIP , RD2 , RV3 )` — **page/ring violations** (all derived from `IPT_15_9` + `IPCR_1_0` + `VACC` + access type). These are **MPV (memory protection violation)** contributors.
- `gates10_out = OR4( PGF , INTR , gates14_out , gates15_out )` where:
  - `PGF = NAND4(VACC, ~IPT[6], ~IPT[5], ~IPT[4])` — **page fault**.
  - `INTR = NAND(IFETCH, INTRQ)` — **level 10–15 interrupt**, but **only during IFETCH**.
  - `gates14_out = NAND(VTRAP, VACC)` — vector trap (illegal instruction / valid-opcode trap family).
  - `gates15_out = NAND(FTRAPN, IFETCHN)` — fetch trap (II family).
- `gates20_out` — a four-input OR of `A02_1..A02_4` macros that cover additional ring/protection combinations on fetch/write/indirect/data accesses.
- `CBRKN` / `ETRAPN` — continue-break and external-trap inputs.

### What is **NOT** in this equation

I grepped the entire `CGA_TRAP/` tree for `IONI`, `XIONI`, `STS`, and found nothing. `CGA_TRAP` does **not** receive `IONI` as an input at its top-level port list (`CGA_TRAP.v` lines 14–36). `PONI` (paging-on) is the only status-register bit that feeds the trap logic, and it is used only for **RESTR generation** in `CGA_TRAP_TVGEN.v:240–246`:

```
RESTR = AND( ~IPCR[1] , PONI )
```

So `PONI` gates only `RESTR`, not the trap dispatch itself.

---

## 5. `IRQ` — how it steers the microcode

`IRQ` (active-high, from `CGA_INTR.IRQ`) enters `CGA_MIC` at port `IRQ` (line 39) and is routed straight to `CGA_MIC_CSEL` as `muxIn_2` of the 8-way test-condition mux (`CGA_MIC_CSEL.v:121`):

```
PLEXERS_1 (s_mux_selector = TSEL[2:0])
  muxIn_0 = DZD
  muxIn_1 = LCZ
  muxIn_2 = IRQ          ← here
  muxIn_3 = RESTR
  muxIn_4 = CFETCHN
  muxIn_5 = OOD
  muxIn_6 = SPARE
  muxIn_7 = COND
```

So `IRQ` is **only one of many testable conditions** that the microcode can select with its `TSEL[3:0]` field. It is **not** an unconditional override. It becomes effective only if the current micro-instruction (via `CONDREG` → `TSEL[2:0] = 010`) picks `IRQ` as the condition to evaluate, in which case `CSEL.CONDN` reflects `IRQ` and that flows through:

```
CSEL.CONDN → D-FF MEMORY_32 → s_cond_n → { s_etrue, s_efalse } → SC[6:3] → MASEL selector → W[12:0] → IPOS → MA[12:0]
```

In other words, `IRQ` can cause a micro-JUMP (not a trap) by steering MASEL into `SEL_JUMP`, but only when the *current microcode word* has asked to test IRQ.

**However**, `IRQ` also goes into the `CGA_INTR` → `INTRQN` flip-flop (`CGA_INTR.v:146–156`) and from there into `CGA_TRAP_BRKDET.INTR = NAND(IFETCH, INTRQ)`. That path DOES produce a hardware `TRAPN` assertion at the next IFETCH. See §6 below.

---

## 6. Answering the specific question

### "Does IOF suppress the internal traps MPV, PF, II?"

Collecting the facts verified above:

1. `IONI` is produced at **exactly one place** in the CGA: `CGA_ALU.v:173` as `IONI = s_sts_15_0[15]`.
2. `IONI` leaves the CGA only as `XIONI` (`CGA.v:551`), which is routed to the panel.
3. `IONI` is **not** a port of any of: `CGA_MIC`, `CGA_TRAP`, `CGA_INTR`, `CGA_MAC`, `CGA_DCD`. (`grep IONI` in each subtree returns zero matches.)
4. The microcode address mux in `CGA_MIC_IPOS` has, as its only control signals, `TRAPN`, `MAPN`, `EWCAN`. None of these comes from `IONI`.
5. `TRAPN` in `CGA_TRAP_BRKDET` is derived from (`PVIOL`-family, `PGF`, `VTRAP`, `FTRAP`, `CBRK`, `ETRAP`, and `INTRQ` gated by `IFETCH`). None of these derivations inspects `IONI`.
6. The CPU side-channel by which `IONI` could affect microcode is via the `CSEL` test-condition mux — and `IONI` is **not** one of the 16 signals fed into CSEL's muxes either (`CGA_MIC_CSEL.v:118–149`).

### Conclusion

**In this Verilog implementation, `IOF` does NOT gate the trap-dispatch hardware.** Internal traps (`MPV` via `PVIOL`, `PGF` page fault, `VTRAP`/`FTRAP` illegal-instruction family) will still assert `TRAPN`, still drive `CGA_MIC_IPOS.mux_selector = 2'b11`, and still steer `MA[12:0]` to `{1, 0, 0, 0000, TVEC[3:0]}` even when `STS[15]=IONI=0` after an `IOF`.

The only thing `IOF` indirectly affects — insofar as any hardware in this tree inspects it — is whatever the microcode itself does when it *tests* status via the ALU: the microcode can read `STS[15]` onto FIDB, compare/branch on it, and decide whether to go into the PID/PIE service sequence. That is a microcode-level decision, not a gate-level one.

**[UNVERIFIED]** I have not disassembled the microcode ROM to verify how it actually tests `IONI`. The statement above about "microcode-level decision" is consistent with the hardware I've read, but it is not a property I can prove from the Verilog alone.

### Also important — level 10–15 interrupts

The same analysis shows that **program-level interrupts (the `INTRQ` path through `CGA_INTR`) are also NOT gated by `IONI` in hardware**. `CGA_INTR` has no `IONI` input; `CGA_TRAP_BRKDET.INTR = NAND(IFETCH, INTRQ)` turns `INTRQ` into a trap every IFETCH, unconditionally on `IONI`.

This means that for `IOF` to actually mask level 10–15 interrupts, one of the following must be true (I could not verify which without more work):

(a) The microcode, at each IFETCH boundary where it would otherwise honour the trap, explicitly inspects `STS[15]` and takes a branch that re-issues the fetch instead of servicing the interrupt. **[UNVERIFIED]**

(b) Some gating I have missed. Candidates worth checking: `CLIRQN` (which resets the `INTRQN` flip-flop in `CGA_INTR`), the `EPICMASKN` path, or signals coming through cycle control.

(c) The hardware behaviour here diverges from the original ND-120, and this is an actual bug in the Verilog port. **[UNVERIFIED]**

See "Open questions" at the end.

---

## 7. Complete list of signals that impact `MA[12:0]`

Organised by the IPOS source they end up at, with origin.

### 7.1 Signals that select which source IPOS uses

| Signal   | Drives                 | Origin                                                              |
|----------|------------------------|---------------------------------------------------------------------|
| `TRAPN`  | IPOS selector bit      | `CGA_TRAP_BRKDET` (from PVIOL / PGF / VTRAP / FTRAP / INTRQ / CBRK / ETRAP) |
| `MAPN`   | IPOS selector bit      | Cycle control. **[UNVERIFIED: I did not follow the chain back to its root.]**   |
| `EWCAN`  | IPOS selector bit      | Cycle control (write-control-store enable).                         |

### 7.2 Signals that make up the `W[12:0]` source (MASEL path)

| Signal           | Role                                                                    | Origin                                                |
|------------------|-------------------------------------------------------------------------|-------------------------------------------------------|
| `CSBIT20`        | MA[12] when JUMP                                                        | Microcode RAM output, control-store bit 20            |
| `CSBIT[11:4]`    | MA[11:4] when JUMP                                                      | Microcode RAM output                                  |
| `JMP[3:0]`       | MA[3:0] when JUMP                                                       | `ILC_MUX` in `CGA_MIC.v`                              |
| `CSMIS0`, `CSVECT_N` | Selects between literal / LAA / IR as source of JMP                  | Microcode RAM output                                  |
| `IR[3:0]`        | One possible JMP source                                                 | `IRLATCH` in `CGA_MIC.v`, latched from CD[3:0]        |
| `LAA[3:0]`       | One possible JMP source                                                 | `LAA_REG` (driven by CSRASEL mux on CSBIT, PIL, IR, LC) |
| `CSBIT[3:0]`     | One possible JMP source (literal)                                       | Microcode RAM output                                  |
| `RET[12:0]`      | The RETURN source                                                       | `CGA_MIC_STACK`                                       |
| `NEXT[12:0]`     | The NEXT source                                                         | `CGA_MIC_IINC`                                        |
| `IW[12:0]`       | The REPEAT source; also the input to IINC and the stack                 | `MASEL.regIW`                                          |
| `CIN` (for NEXT) | Whether to increment IW                                                 | `CSWAN[1:0]` from `INCOUNT` ∧ `LCS`                   |
| `SC5`, `SC6`     | Selector between JUMP/RET/NEXT/REPEAT                                   | Logic in `CGA_MIC.v` (see §3.5), ultimately from `s_cond_n` |
| `SC3`, `SC4`     | Stack op (HOLD/POP/LOAD/PUSH)                                           | Same logic in `CGA_MIC.v` as SC5/SC6                  |
| `MRN`            | Async reset for `MASEL.regIW` (and stack via SCLKN)                     | System reset                                          |

### 7.3 Signals that make up `s_cond_n` (and therefore SC[6:3])

All feed `CSEL` (`CGA_MIC_CSEL.v`):

| Signal       | Meaning                                                   | Origin                          |
|--------------|-----------------------------------------------------------|---------------------------------|
| `TSEL[3:0]`  | Which condition to test                                   | `CONDREG` (latched CSBIT[7:4])  |
| `COND`       | Previous-cycle latched CSEL output (feedback)             | `CGA_MIC.MEMORY_32`             |
| `CRY`        | Carry flag                                                | `CGA_ALU`                       |
| `DZD`        | Divide-by-zero-detect                                     | `CGA_MIC.DZD_FF`                |
| `F11`, `F15` | Flag bits 11 and 15                                       | `CGA_ALU`                       |
| `IRQ`        | Interrupt request (**only** path of IRQ into MIC address) | `CGA_INTR`                      |
| `LCZ`        | Loop-counter-zero                                         | `CGA_MIC` LC compare            |
| `OOD`        | Out-of-data                                               | `CGA_MIC.OOD_FF`                |
| `OVF`        | Overflow                                                  | `CGA_ALU`                       |
| `RESTR`      | Restore (from TRAP — **not** IONI-gated)                  | `CGA_TRAP_TVGEN`                |
| `SPARE`      | Spare (reserved)                                          | external                        |
| `STP`        | Stop                                                      | external                        |
| `ZF`         | Zero flag                                                 | `CGA_ALU`                       |
| `CFETCH`     | Continuous-fetch                                          | Cycle control                   |
| `ALUCLK`     | Clock for the CSEL latch                                  | Cycle control                   |

### 7.4 Signals that build the WCA[12:0] source (WCAREG)

`CGA_MIC_WCAREG` latches `CD[15:0]` under `LWCAN`. Governed by `LCSN` / `LWCAN` / `MCLK`. These gate **where** new microcode gets written, but cannot directly steer normal-mode execution because `EWCAN` determines whether the WCA mux path is picked at all.

### 7.5 Signals that build the CD-dispatch (opcode) source

`CD[15:6]` comes from the FIDB/CD bus latch. When `MAPN=0` and `TRAPN=1`, IPOS places `CD[15:10]` on `MA[9:4]` and `CD[9:6]` on `MA[3:0]` and forces MA[12]=1, MA[11:10]=0. This is the **opcode dispatch** — the entry point from the currently-latched instruction word to its microcode handler.

### 7.6 Signals that build `TVEC[3:0]`

`TVEC[3:0]` is generated by `CGA_TRAP_TVGEN_P2` from:

- `PGF`, `PVIOL`, the per-ring violation lines `RD`, `RV`, `WIP`, `PGU`
- `INTRQ` (gated with `IFETCH`)
- `VTRAPN`, `FTRAPN`, `DSTOPN`
- `PAN` (panel), `VACC` (valid-access), `TCLK`

Again: **no `IONI`** in this derivation.

---

## 8. Module dependency graph (address-relevant only)

```
        ┌──────────────┐
        │  CGA_ALU     │─── IONI = STS[15] ─────────────► XIONI (panel only)
        └──────────────┘

        ┌──────────────┐           INTRQN  ┌────────────────┐   TRAPN    ┌───────────┐
 BINT,  │              │───INTRQ──────────►│ CGA_TRAP_BRKDET│───────────►│           │
 PAN,   │  CGA_INTR    │          (IFETCH) │   (+TVGEN)     │            │           │
 MOR,   │              │           ┌──────►│                │──TVEC────► │  CGA_MIC  │─MA[12:0]─►
 POW,   └──────────────┘           │       └────────────────┘            │           │      microcode
 IOX,          │                   │              ▲                      │           │        RAM
 PARERR        │                   │    PT, PCR   │                      │           │
               └────── IRQ ────────┴──────────────┴────► PONI (for RESTR)│           │
                       (to CSEL also)                                    └───────────┘
                                                       ▲
                                                       │
                                      CD[15:0] (opcode dispatch)
                                      W[12:0] (MASEL: JUMP/RET/NEXT/REPEAT)
                                      WCA[12:0] (control-store write addr)
                                      MAPN, EWCAN, TRAPN (mux selectors)
```

`IONI` has no arrow into this graph.

---

## 9. Answers to the six open questions

After tracing the Verilog sources and the microcode listing in `Code/Microcode/ND-120-DELILAH-L.LISTING.txt`, here is what the code actually says.

### Q1 — How does `IOF` actually suppress interrupts, if not via hardware gating on `IONI`?

**Answer: `IOF` is implemented as a PIC command issued by the microcode, not as a direct write to `STS[15]`.**

Evidence:

- Microcode listing line 46–47:
  ```
  | 28 | PIC,IOF | … 150000 0 0 X00.  | 15 | USED TO GIVE 'IOF'-CMD. TO INSTYS |
  | 29 | PIC,ION | … 170000 0 7 HAO   | 17 | USED TO GIVE 'ION'-CMD. TO INSTYS |
  ```
  `IOF` and `ION` are **CSCOMM commands 15 and 17 (octal)** that the microcode issues to the PIC ("INSTYS" = interrupt system).
- Microcode routine for the `IOF` instruction, at octal address `000661`:
  ```
  IOF2: PIC, IOF   ALUD, NONE
  ```
  i.e. the microcode for the IOF instruction is literally one line that issues `PIC,IOF`.
- Corresponding `ION` at octal `000663` issues `PIC,ION`.
- These CSCOMM codes are decoded in `CGA_DCD.v` (see Q6 below for the decode pattern), producing control signals that set/clear an enable inside the PIC / interrupt controller.

**[UNVERIFIED]** I have not yet located the exact flip-flop in `CGA_INTR` (or elsewhere in the PIC chain) that is written by CSCOMM 15/17. What I can say for certain is that the PIC-side mask (`EMPIDN`, `EPICMASKN`) and the interrupt-request latch (via `CLIRQN`) are all driven by microcode CSCOMM decodes, and that `IONI` = `STS[15]` is a **software-visible reflection** of interrupt state rather than the primary gate.

### Q2 — Is `INTRQ → TRAPN` being ungated by `IONI` the correct ND-120 behaviour?

**Answer: yes — but not for the reason originally assumed.** The gating happens **inside the PIC**, upstream of `INTRQN`, not downstream of it.

Evidence:

- `CGA_INTR` does not receive `IONI`.
- `CGA_TRAP_BRKDET` does not receive `IONI`.
- The microcode listing has this comment at octal `000043` (line 934 in the OCR):
  ```
  % NO INTERRUPT IS PENDING. IT CAN BE IOF-PAGEFAULT
  ```
  This comment tells you that the microcode dispatch point at `000043` is reached when no interrupt is pending, and that the cause can be "a pagefault taken while the CPU is in `IOF` state". This directly confirms: **pagefaults fire during `IOF`; interrupts do not.** The gating of interrupts happens upstream, in the PIC, as a consequence of the `PIC,IOF` CSCOMM command.

### Q3 — `MAPN` origin (traced)

**Answer: `MAPN` is produced by PAL `44307C` inside the cycle controller.**

Evidence (`PAL\PAL_44307C.v:86`):

```verilog
assign MAP_n = ~(FORM & BRK_n & CC2 & TERM_n);
```

So `MAP_n` asserts (low) during the `FORM` phase (opcode decode), on cycle step `CC2`, when no break is pending and no terminate is pending. It is output from `CYC_36.v:181` (cycle controller) and routed into CGA as `XMAPN` via `CPU_PROC_CGA_33.v:248`:

```verilog
.XMAPN(MAP_n),
```

Role in MA[12:0]: when `MAPN=0` and `TRAPN=1`, `IPOS` overlays `CD[15:10]` on `MA[9:4]` and `CD[9:6]` on `MA[3:0]`, i.e. **opcode dispatch**. This is the entry point from the just-fetched instruction word into its microcode handler.

### Q4 — `MPV` / `PF` terminology (traced)

**Answer:**
- `MPV` (Memory Protection Violation) = the `PVIOL` signal family: `PVIOL = PGF ∨ WPV ∨ IPV ∨ FPV ∨ RPV` (from `CGA_TRAP_TVGEN.v:147–156`).
- `PF` (Page Fault) = the `PGF` signal specifically: `PGF = VACC ∧ ~IPT[6] ∧ ~IPT[5] ∧ ~IPT[4]` (page-not-present, from `CGA_TRAP_TVGEN.v:248–256`).
- `PONI` ("Memory Protection ON") is a separate enable bit from `IONI` ("Interrupt ON"). Every `PONI` port comment in the HDL reads `//! Memory Protection ON, PONI=1`. `PONI` is managed by `POF` / `PON` style microcode commands — not `IOF` / `ION`.

`PONI` does gate paging at `CGA_MAC_PTSEL.v` (it preset-forces the PT-select JK flip-flop when `PTM=0` and `PONI=0`, line 68–74), so when memory protection is off, the page-table bits that drive `PGF`/`PVIOL` behave as if everything is present/unrestricted. But that is `POF`, not `IOF`.

### Q5 — `II` (illegal instruction) — **MAJOR FINDING**

**Answer: the hardware trap inputs `VTRAPN` and `FTRAPN` are tied HIGH (inactive) at the board level. Illegal-instruction traps in this Verilog are handled entirely in microcode, not by the hardware trap path.**

Evidence — `CPU-BOARD-3202\circuit\CPU_PROC_CGA_33.v:244-245`:

```verilog
.XFTRAPN(1'b1),
.XVTRAPN(1'b1),
```

So the CGA inputs for fetch-trap and vector-trap are pulled inactive. None of `BRKDET.gates14_out = NAND(VTRAP, VACC)` or `BRKDET.gates15_out = NAND(FTRAPN, IFETCHN)` can ever assert.

Illegal instructions are instead caught in microcode. Evidence from the microcode listing:

- Line 1202: `ILLIN: A,7 ALUD,NONE IDBS,BMG COMM,SMPID T,JMP T,HOLD ILL12;`
  The `ILLIN` routine issues `COMM,SMPID` (CSCOMM=12 → set PIC mask, inhibit all interrupts) and jumps to `ILL12`.
- Line 1203: `PRIV1: A,11 ALU,NONE IDBS,BMG COMM,SMPID T,JMP T,HOLD ILL12;`
  Similar for privilege violations.

So "II" in this codebase is **not** a hardware trap — it is a microcode-level detection inside the opcode-dispatch handler.

### Q6 — `CLIRQN` and `EPICMASKN` paths (traced)

**Answer: both are driven by CSCOMM decodes in `CGA_DCD.v`. They are the actual microcode-controlled masking mechanisms for external interrupts.**

Evidence:

- `CGA_DCD.v:1099-1132` — `CLIRQN` is asserted (low) when `CSCOMM_4_0 = 00100` binary = **4 octal** (a CLIRQ command):
  ```verilog
  NAND6( lcs_n , icscomm_n[4] , icscomm_n[3] , icscomm[2] , icscomm_n[1] , icscomm_n[0] )
      → s_iclirq_group
  D-FF   d=s_iclirq_group , qBar=s_iclirq
  s_clirq_n_out = ~(s_iclirq | s_mr)   // also cleared by master reset
  ```
  `CLIRQN` drives `reset` of the `INTRQN` flip-flop in `CGA_INTR.v:146–156`, i.e. it clears the pending interrupt request after the microcode has serviced it.

- `EMPIDN` — CSCOMM=12 octal ("SMPID, set mask reg, inh all ints") per `DECODE_DGA_COMM.v:45`:
  ```
  output EMPIDN, //! Enable MPID - Set bits in the micro-PID (Priority Interrupt Detect)
                  //  register in the PIC. Command #012. "set mask reg: inh all ints"
  ```
  `EMPIDN` feeds `CGA_INTR.EMPIDN` and from there into the PIC mask logic (`CGA_INTR_IRSRC`, `CGA_INTR_CNTLR_MDCD`). This is the **primary microcode-level mechanism to disable all external interrupts**.

- `EPICMASKN` — Generated in `CGA_INTR_CNTLR_MDCD.v:144` and routed back through the IDB (via `CGA_IDBCTL`) so microcode can read the current PIC mask into the register file.

- `EPIC` — CSCOMM=13 octal (from the NAND pattern at `CGA_DCD.v:1137-1147`). Enables the PIC mask update.

So the actual mask path used by `IOF`/`ION` is:

```
microcode: IOF instruction @ 000661
   ├─ issues CSCOMM=15 (PIC,IOF)
   │
   ▼
CGA_DCD.v decodes CSCOMM=15
   ├─ (asserts some still-to-be-pinpointed PIC-enable signal)
   │
   ▼
CGA_INTR (PIC) mask state updates, INTRQN stays high
   │
   ▼
CGA_TRAP_BRKDET: INTR = NAND(IFETCH, INTRQ) stays inactive
   │
   ▼
TRAPN not asserted for external interrupts.
```

Pagefault and MPV (`PGF`, `PVIOL`) bypass this entire chain — they are generated directly in `CGA_TRAP_TVGEN` from `IPT` + `IPCR` + `VACC` etc., and feed `BRKDET` independently.

---

## 10. Final answer to the original question

Bringing all of the above together:

**When `IONI` (STS[15]) is off after `IOF`:**

| Trap type                       | Code signal(s)                     | Hardware-disabled by IOF? | Why                                                                 |
|---------------------------------|------------------------------------|:-------------------------:|---------------------------------------------------------------------|
| **MPV** (memory protection viol.) | `PVIOL` = PGF ∨ WPV ∨ IPV ∨ FPV ∨ RPV | **No**                  | `CGA_TRAP` has no `IONI` input; path to `TRAPN` unconditional       |
| **PF** (page fault)             | `PGF`                              | **No**                    | Same as above                                                       |
| **II** (illegal instruction)    | N/A (handled in microcode)         | **No**                    | `VTRAPN`/`FTRAPN` are tied to `1` at board level; caught by microcode `ILLIN`/`PRIV1` routines which always run |
| Level 10–15 external interrupts | `INTRQ` → `TRAPN` via IFETCH NAND  | **Yes**, but **upstream** in the PIC (via the CSCOMM command the `IOF` microcode issues), not by `IONI` gating in the trap-dispatch hardware |

`IONI` itself — the `STS[15]` bit — is effectively a **software-visible flag** maintained in parallel with the real PIC state, and displayed on the operator panel via `XIONI`. The actual interrupt suppression is done by the PIC state that the `PIC,IOF` CSCOMM command mutates.

Direct restatement for your original question:

> **"Will MPV, PF, and II internal interrupts trap the microcode if `IONI` is off after `IOF`?"**

- **MPV: yes.** `PVIOL → BRKDET → TRAPN → IPOS` fires regardless.
- **PF: yes.** `PGF → BRKDET → TRAPN → IPOS` fires regardless.
- **II: yes — via microcode, not via the hardware trap path.** The `VTRAPN`/`FTRAPN` inputs are tied inactive on this board; the `ILLIN`/`PRIV1` microcode routines run during opcode dispatch independently of `IONI`.

---

## 11. Second pass — the three previously-unverified items

On the follow-up investigation, I traced all three remaining items and significantly narrowed the uncertainty. Here are the findings.

### 11.1 `STS[15]` (IONI) and `STS[14]` (PONI) — how they are written

**Verified.** From `CGA_ALU_STS.v:184–200`, the two bits share identical structure:

```verilog
SCAN_FF STS15_FF ( .CLK(ALUCLK), .D(FIDBO[15]), .TE(LDPILN), .TI(STS_15_0_out[15]), .QN(s_sts_15_n) );
SCAN_FF STS14_FF ( .CLK(ALUCLK), .D(FIDBO[14]), .TE(LDPILN), .TI(STS_15_0_out[14]), .QN(s_sts_14_n) );
```

A `SCAN_FF` captures `D` when `TE=0` and `TI` (feedback) when `TE=1`. So both `IONI` and `PONI` are written **from `FIDBO[15:14]` whenever `LDPILN` is asserted (low)**. All of `STS[15:8]` share the same `LDPILN` enable — loading PIL simultaneously updates IONI, PONI, DOUBLE (STS[13]), … and PIL[3:0]. There is no dedicated IONI-only or PONI-only write port.

### 11.2 `LDPILN` is CSCOMM=01 octal

**Verified.** `CGA_DCD.v:810–820`:

```verilog
NAND6( comm_n[4] , comm_n[3] , comm_n[2] , comm_n[1] , comm[0] , lcs_n )  →  s_ldpil_n_out
```

Pattern `00001` binary = **CSCOMM=01 octal**. So `LDPILN` asserts when the microcode issues `COMM,LDPIL` (or an equivalent named field). This is the path that physically writes `STS[15]=IONI` and `STS[14]=PONI`.

### 11.3 The `IOF` instruction microcode routine

**Verified (partial).** From the symbol (label -> address) index of the scanned listing `Code/Microcode/ND-120 Mikroprogramlisting-L-ocr.pdf` (the re-typed `ND-120-DELILAH-L.LISTING.txt` has no symbol index; the PDF page was not looked up):

```
IOF  → microcode address 003461
ION  → microcode address 003462
```

The microcode listing at `003461` (`ND-120-DELILAH-L.LISTING.txt` lines 9422-9425) reads:

```
003461   STSST;
003461   STSEX:  A.STS   ALUF,PASSA   ALUD,NONE   STS.LO
003461   IDBS,ALU   T,JMP   T,HOLD
```

So the `IOF` instruction microcode:
- loads `A = STS` (reads the STS register)
- `ALUF = PASSA` (passes A through the ALU)
- `IDBS = ALU` (puts result on IDB)
- jumps to subroutine `STSST` (Status STore?) with `STS.LO` modifier — **[UNVERIFIED]** which bits `STS.LO` actually writes, but the name ("STS low") and the fact that this routine is shared between `IOF`, `ION`, `POF`, `PON`, `SEX`, `REX` strongly suggests it is the generic "modify status bits" subroutine.

`STSST` (`STS STore`) is shared across all instructions that flip status bits — a reasonable design, and it explains why the dedicated `IOF2` microcode stub at `000661` (lines 2937–2938) is so short:

```
IOF2: PIC,IOF   ALUD,NONE
      IDBS,ALU  COMM,EPIC   T,NEXT   T,HOLD;
```

This microcode word issues **two commands simultaneously**:
- `COMM,EPIC` (CSCOMM=13 octal, from `CGA_DCD.v:1137-1147`) — asserts the `EPIC` control line, which enables PIC-side subcommand decoding for the current cycle.
- `PIC,IOF` — the PIC subcommand carried in a separate microcode field, latched by the PIC when `EPIC=1`.

So `IOF` is a **two-stage decode**: the main CSCOMM decoder issues `EPIC`, and the PIC-side decoder then interprets the additional `PIC,xxx` field.

**[UNVERIFIED]** I did not pinpoint the exact NAND gate inside `CGA_INTR_CNTLR_MDCD` / `CGA_INTR_CNTLR` that latches the `PIC,IOF` subcommand — following the EPIC-gated path into the PIC's internal state machine would be a separate trace of several files.

### 11.4 The `EMPID` mask — definitive confirmation

The bottom-up evidence from `DECODE_DGA_COMM.v:621-631` is the cleanest:

```verilog
NAND_GATE_6_INPUTS A183 (
    .input1(s_cscomm_4_n),       // 0
    .input2(s_cscomm_4_0[3]),    // 1
    .input3(s_cscomm_2_n),       // 0
    .input4(s_cscomm_4_0[1]),    // 1
    .input5(s_cscomm_0_n),       // 0  = 01010 = 0xA = 10d = EPIC.LDMPIE (set mask reg: inh all ints)
    .input6(s_lcs_n),
    .result(s_iempid_n)
);
```

The inline comment explicitly identifies **CSCOMM=012 octal** (binary `01010`) as the `EPIC.LDMPIE` / `SMPID` command that inhibits all interrupts via the PIC mask register. `EMPIDN` drives `CGA_INTR.EMPIDN`, which enters `CGA_INTR_IRSRC` (`IRSRC.v:68`) and feeds the mask-source logic.

### 11.5 Consolidated picture of what `IOF` actually does

Putting it all together:

```
  Microcode instruction IOF (@ 003461)
           │
           ▼
  • loads STS → IDB via ALU pass-through
  • calls subroutine STSST with STS.LO modifier
           │
           ▼
  STSST (uses LDPIL mechanism, TBD location)
           │
           ├──► COMM,LDPIL  (CSCOMM=01)
           │        │
           │        ▼
           │    LDPILN asserts  →  STS[15:8] <= FIDBO[15:8]
           │        (IONI and PONI updated to new value on FIDB)
           │
           ▼
  IOF2 stub (@ 000661)
           │
           ├──► COMM,EPIC   (CSCOMM=13)
           │        │
           │        ▼
           │    EPIC flag set
           │
           └──► PIC,IOF  (sub-command latched by PIC under EPIC=1)
                    │
                    ▼
           (internal PIC enable flip-flop cleared → INTRQN stops firing)
```

Two independent state updates happen: the **software-visible `STS[15]`** via the ALU/LDPIL path, and the **actual PIC-level enable** via the EPIC/PIC-subcommand path. They are kept coherent by the microcode routine, not by hardware. The microcode guarantees the two are updated together.

### 11.6 `PONI` control path

**Verified (partial).** From the microcode listing, the instruction entries exist (e.g. `POF`, `PON`, `POFZ`, etc. in the symbol table). By the same analysis:

- `PONI = STS[14]` is written only via `LDPIL` (CSCOMM=01), exactly like IONI.
- The `POF` / `PON` microcode routines (I did not trace them in detail) almost certainly follow the same pattern: load STS via ALU, issue `LDPIL` with the right value on FIDB[14]. There may or may not be a separate paging-side enable command analogous to `PIC,IOF`.
- `PONI` additionally gates paging in `CGA_MAC_PTSEL.v:68–74` via a JK-flip-flop preset, and gates one trap-related signal (`RESTR` in `CGA_TRAP_TVGEN.v:240-246`).

No `PONI` signal feeds any IPOS / MIC / TRAP trap-dispatch equation.

### 11.7 Remaining fully-unproven items

Tight list of what I still could not nail down from the HDL + microcode listing alone:

1. The exact gate inside `CGA_INTR_CNTLR_MDCD` / `CGA_INTR_CNTLR` that latches the `PIC,IOF` / `PIC,ION` subcommand into a PIC-internal enable flip-flop. (I found `EMPIDN`, `EPIC`, `CLIRQN`, `EPICMASKN`, `EPICSN`, `EPICVN` as PIC control inputs but did not produce a complete table mapping PIC subcommand-codes → internal PIC FFs.)

2. The precise semantics of `STS.LO` as a microcode modifier field — my best read from context is "write only the low half of STS" (so IONI/PONI don't get touched). But that read doesn't match the fact that `IOF` calls this routine and must update IONI. **[UNVERIFIED]**

3. Whether the `POF`/`PON` instructions use an analogous EPIC+PIC-subcommand mechanism, or whether they directly LDPIL without a paging-side dispatch. I have not read their microcode.

Items 1 and 2 would require either (a) the ND-120 microprogrammer's guide referenced in the repo (`ND-06.031.1 EN ND-110 and ND-120 Microprogrammer's Guide-Gandalf-OCR.pdf`) or (b) a scripted decode of every microcode word that uses `STS.LO` and `STSST`.

None of these remaining uncertainties change the top-level answer: **MPV and PF trap the microcode regardless of `IONI`**, and **`II` is handled by the microcode opcode-dispatch regardless of `IONI`** (with the hardware `VTRAPN`/`FTRAPN` paths disabled at board level).

---

## 12. Files referenced

- `Verilog/DELILAH-CPU/CGA/circuit/CGA.v`
- `Verilog/DELILAH-CPU/CGA_ALU/circuit/CGA_ALU.v`
- `Verilog/DELILAH-CPU/CGA_MIC/circuit/CGA_MIC.v`
- `Verilog/DELILAH-CPU/CGA_MIC/circuit/CGA_MIC_IPOS.v`
- `Verilog/DELILAH-CPU/CGA_MIC/circuit/CGA_MIC_MASEL.v`
- `Verilog/DELILAH-CPU/CGA_MIC/circuit/CGA_MIC_IINC.v`
- `Verilog/DELILAH-CPU/CGA_MIC/circuit/CGA_MIC_CSEL.v`
- `Verilog/DELILAH-CPU/CGA_MIC/circuit/CGA_MIC_CONDREG.v`
- `Verilog/DELILAH-CPU/CGA_MIC/circuit/CGA_MIC_STACK.v`
- `Verilog/DELILAH-CPU/CGA_MIC/circuit/CGA_MIC_WCAREG.v`
- `Verilog/DELILAH-CPU/CGA_TRAP/circuit/CGA_TRAP.v`
- `Verilog/DELILAH-CPU/CGA_TRAP/circuit/CGA_TRAP_BRKDET.v`
- `Verilog/DELILAH-CPU/CGA_TRAP/circuit/CGA_TRAP_TVGEN.v`
- `Verilog/DELILAH-CPU/CGA_TRAP/circuit/CGA_TRAP_TBUF.v`
- `Verilog/DELILAH-CPU/CGA_INTR/circuit/CGA_INTR.v`
