# RUN area level-14 livelock and IIC mis-decode: measured analysis (13/15-JUL-2026)

Solved 15-JUL-2026, commit `3acef36` (status-fence wiring + FIDBO swap fix;
MOR wired to level 12 in the same commit). What remains open is only that RUN
has never been run to its end and is not gated - see
`tests/instruction-verify/CAMPAIGN-STATUS.md`. The superseded theories and
the step-by-step log that led here are in git history.

INSTRUCTION-B `RUN` stalls right after `== DUMMY OUTPUT STARTED ==` and never
prints `IOX-ERROR STARTED`. Everything below is probe-measured on the FF-mode
runSim build (probes: `ND120_PROBE_RUNIDENT` in `runSim/Run120.cpp`), after
the tape-storm fix (C-device interrupts now actually assert BINT lines) and
both CPU fixes (QREG dc61bd6, SSEL 2e2ea37).

## Measured chain

1. RUN starts its stressors. The dummy-output phase performs IOX writes that
   raise real IOX-error internal interrupts (`ioxerr_n` input pulses,
   ~every 1000 evals).
2. Each pulse latches request bit 10 in `CGA_INTR` (IRSRC bit map: bits 0-3 =
   external levels 10-13; bits 8-13 = internal detects: 8=Z, 10=IOXERR,
   11=PARERR, 12=NOR, 13=POWFAIL; latched in IRQ_REG RQBITs, set/hold until
   CLRQ).
3. The CPU switches to PIL 14 correctly (measured PIL trace: ...10, 13, 12,
   then 14).
4. THE FAULT: at PIL 14, EVERY macro instruction boundary re-dispatches the
   internal-interrupt service (csa 03756 -> EXT14 -> PLINT -> MACRI):
   measured 14,487 EXT14 dispatches for 14,486 MACRI boundaries in 1.1M
   evals, while TAIIC (the `TRA IIC` microcode at csa 03665, which ends in
   `CLR14: R1:=037760; CLRXX: PIC,MCLPID` = the internal-detect clear) stays
   FROZEN at 21 entries. The level-14 handler never executes its dismissal,
   the detect bit is immortal, levels 10-13 starve.

## Why re-dispatch is not suppressed

`CGA_INTR` has NO PIL input - suppression of requests at-or-below the
current level is done via the PIC mask register (MPIE, `PICMASK` in
CNTLR/IRQ_MASK). The level-switch microcode reloads it on every switch
(PLINT -> PLVO -> PICFM/PICF2, `PIC,LMSK`); for a switch TO level 14 the
mask must disable the internal detect bits (the microcode's own constant
077760 = bits 4-13 appears at PICF2+1 for exactly this).

Measured during the storm: PICMASK stuck at 100562 (bits 9-13 = the internal
detects LEFT ENABLED) and never rewritten - the PLINT loop cycles
01133-01142 (PLINT/PLVO+1/PLVO+2) taking the `COND,F=0 F,RETURN` early path
and never reaches PICFM/PICF2 (01163-01171). The 21 successful TAIIC entries
during startup prove the flow works in other conditions.

## ROOT CAUSE FOUND: SBIT (status register bit) mis-wiring - schematic p.87

The DELILAH interrupt system is a close copy of the **Am2914** Vectored
Priority Interrupt Controller (Ronny, 13-JUL; confirmed against the 1978
Am2900 Family Data Book). The Am2914 rule that RUN depends on:

> "The Read Vector microinstruction ... **also automatically loads the value
> 'vector plus one' into the Status Register**." (Am2900 Family Data Book)

The Status Register is the fence that stops the interrupt just taken from
being re-dispatched. Our `CGA_INTR_CNTLR_VECGEN_STAT` implements it as six
`SBIT` cells (schematic p.87), whose D input is:

```
D = (SIN & DCDG & DCDF & GPE)      <- load S-bus data   (LDSTAT)
  | (DCDG & DCDFN & STS)           <- hold
  | (VINN & DCDF & DCDGN)          <- load vector+1     (RDVECT)
```

TWO transcription bugs, both now schematic-verified with Ronny (13-JUL):

1. **Cell** (`..._STAT_SBIT.v` GATES_3): the vector-load NAND's middle input
   was `GPE`; the sheet's SBIT detail box shows **`DCDF`**. With `GPE` there
   the vector+1 load could not fire.
2. **Instances** (`..._STAT.v`, all six): the six SBIT blocks on the sheet
   are drawn WITHOUT pin names (only the detail box names them), so the
   original transcription had to guess the pin order - and four pins were
   rotated. Verified pin reads (Ronny, top SBIT = HISTAT2, pins from top):
   pin2 = the XNOR increment output (**VINN** = the vector+1 bit),
   pin3 = **HIF** (the group F strobe, also on HISTAT1/HISTAT0),
   pin6 = **G_N** (same on all six SBITs).
   Correct wiring: `VINN`=XNOR chain, `DCDF`/`DCDFN`=HIF/HIFN (LOF/LOFN),
   `DCDG`/`DCDGN`=G_N/G, `GPE`=HIF (LOF), `SIN`=S-bus.
   As previously wired (`GPE`=HIF **with** `DCDG`=HIF_n) the S-bus load term
   was self-contradictory (`HIF & HIF_n`), and `VINN` was tied to a uniform
   strobe instead of the per-bit increment - which is why the status
   registers only ever read all-zeros or all-ones (LOSTAT = 0 or 7,
   HISTAT = 0) in every probe.

Net effect: **the Am2914 status fence never worked anywhere in this
machine.** Nothing but RUN exercises it (all 13 other INSTRUCTION-B areas
pass with the fence dead), so it went unnoticed until the IOX-error stress
storm - where the missing fence lets EXT14 re-dispatch at every macro
boundary, starving the level-14 handler before it can reach its `TRA IIC`
dismissal.

REGENERATION HAZARD: the Logisim CGA_INTR sheet needs the same corrections
(cell GATES_3 input + the six instance pin maps) or regenerating
`CGA_INTR_CNTLR_VECGEN_STAT*.v` reintroduces both bugs.

## 13-JUL: status-fence fix - the livelock is gone

With the corrected wiring (below) - now the RTL default; `ND120_INTR_STATUS_FENCE_OFF` restores the old dead fence:

| | fence dead (before) | fence live (now) |
|---|---|---|
| EXT14 re-dispatches in the storm window | **14 487** | **1** |
| TRA IIC reached (the handler's dismissal) | 21 (all pre-storm) | **22 - it runs** |
| HISTAT / LOSTAT | stuck 0 / {0,7} | real values (7,3,2,5...) |
| CPU self-test | passes | **passes** (no regression) |
| INSTRUCTION-B boots | yes | **yes** |

The level-14 livelock is FIXED. The final wiring (all four cases fall out of
the confirmed cell equation + the MDCD strobe polarities):

    DCDF/DCDFN = HIF / HIF_n     (group F strobe: RDVECT-of-this-group, LDSTAT)
    DCDG/DCDGN = G / G_N         (G is ACTIVE LOW: 1 idle, 0 on RDVECT/MCLR)
    VINN       = XNOR chain      (the vector+1 bits)
    GPE        = HIGE / LOGE     (group-enable, the FIDBO3/FIDBO4 buffers)
    SIN        = S-bus
      idle -> hold | LDSTAT -> load S-bus | RDVECT -> load vector+1 | MCLR -> clear

The earlier "self-test hangs with the fence on" was MY error, not a second RTL
bug: I had DCDG/DCDGN swapped because I read G as active-high. The comparator
(VECGEN_CMP/MAGCMP, p.88 - computes VGES = (V >= S), the correct Am2914 rule)
and IRGEL (p.90-95) were AUDITED and are CORRECT - no changes needed there.

## Verified NOT the cause

- MDCD HIK/LOK strobe gates: match the schematic (p.96) exactly - D0N/D1N/
  D4N with EPICN and the vector-clear-enable flops. A-OP 1 = CLRMPID and
  A-OP 4 = LCLRMPID are real PIC commands (Microprogrammer's Guide ND-06.031
  ch.3) missing from the ND110Compile token table, but the DELILAH microcode
  NEVER issues them - DELILAH dismisses internal detects via CLR14/MCLPID
  (data-path J clear, measured working).
- RQBIT latch semantics, IRSRC bit mapping, priority X-codes: all measured
  correct.
- Unanswered IDENTs: handled gracefully (INSTRUCTION-B's init sweeps all
  levels with no devices answering and proceeds fine).
- The C-model tape: answers and releases its level-12 IDENT correctly.

## HIVCE hold-term input: ruled R (scan illegible - decided by analysis)

The schematic scan (p.96) is unreadable at the HIVCE flop's hold input -
could be `P` or `R` (Ronny: leaning R, 13-JUL). RULED **R** by analysis:
(1) the HI/LO halves are mirror-symmetric everywhere else and LOVCE legibly
uses R; (2) R = the {MCLR,CLRMPID,LCLRMPID,RDVECT}&EPIC strobe, which gives
the flop exactly the "armed by RDVECT until the next clear-family command"
lifetime that LCLRMPID ("clear int for LAST vector read") requires; (3) the
only P-candidate (IRGEL PD) has no functional story here. Our
`CGA_INTR_CNTLR_MDCD.v` already uses the R-equivalent (`s_gates41_out`) for
both flops - **correct as-is, no change**. Functionally inert either way on
this machine (DELILAH microcode never issues LCLRMPID); re-verify only if
some future microcode uses the vector-read clear.

## 15-JUL: IIC architecture confirmed (nd100x + ND-120 uc-emulator) - the exact mapping

TRA IIC (nd100x cpu_instr.c:1888) returns calcIIC() = HIGHEST SET BIT of
(IID & IIE), then clears IID/IIC. IID is a SEPARATE register from the Am2914
IREQ. IID bit -> IIC code (console prints code in OCTAL):
  bit5=Z bit6=PI bit7=IOX bit8=PTY(10o) bit9=MOR(11o) bit10=POW(12o)

ND-120 uc-emulator note (Ronny): the two internal sources use DIFFERENT
conventions in the model:
  IOX -> SetInterruptDetectbits(1<<10)   = Am2914 IREQ bit 10 (hivec 2)
  MOR -> InternalInterruptLvl14(1<<9,..) = IID bit 9 directly

Reconciled mapping for our DELILAH hardware (IRSRC IREQ bits -> IIC):
  IOX IREQ10(hivec2) -> IID/IIC bit 7  (IIC 7)
  PAR IREQ11(hivec3) -> IID/IIC bit 8  (IIC 10o)
  MOR IREQ12(hivec4) -> IID/IIC bit 9  (IIC 11o)
  POW IREQ13(hivec5) -> IID/IIC bit 10 (IIC 12o)
  => IIC_bit = IREQ_bit - 3  (= hivec + 5)

## 15-JUL: ROOT CAUSE FOUND + FIXED - FIDBO[1]<->[2] swap

THE BUG: CGA_INTR_CNTLR.v:109-111 swapped FIDBO bits 1 and 2 on the
status-fence write path (s_fidbo_2_0 -> VECGEN.FIDBO_2_0 -> HISIN/LOSIN, the
value the microcode LDSTAT writes into the Am2914 status register):
    s_fidbo_2_0[1] = s_fidbo_15_0[2];   // WRONG (swapped)
    s_fidbo_2_0[2] = s_fidbo_15_0[1];   // WRONG (swapped)
The swap maps 2<->4 and 3<->5 (values where bit1!=bit2); 0,1,6,7 unchanged.

WHY IT MISDECODES IOX AS MOR: the AIIC (TRA IIC) microcode scans the status
fence: writes fence=Q, checks IRQ = (hivec >= status). The hardware stored
histat = swap(Q&7) but the comparator used the UNSWAPPED hivec. For IOX
(hivec 2): hivges passes only when swap(Q&7) <= 2, i.e. Q&7 in {0,1,4};
highest = 4. So the microcode brackets IOX at ITS fence value 4 and computes
the IIC for vector 4 = MOR = IIC 11 octal, instead of vector 2 = IOX = IIC 7.

WHY ONLY RUN FAILED: only the LDSTAT (microcode-written status) path goes
through this swap. The normal interrupt fence uses the hardware RDVECT
vector+1 auto-load (VINN), which does NOT go through s_fidbo_2_0. So self-
test, RTC (level 13), and all 13 instruction areas - which use RDVECT-based
fencing - passed, and only RUN's internal-interrupt TRA IIC scan (LDSTAT-
based, and the only test exercising vectors 2/3 through it) failed.

RED HERRINGS RULED OUT along the way (all measured):
- The IIE&37760 mask DOES work: LMSK sets PICMASK[14]=1, hivec drops 6->2.
  (The C# LLM's "bit 14 leaks / mask missing" hypothesis was wrong for us.)
- MOR wiring not firing (MOR-off run byte-identical).
- Encoder (PTYENC), VHR, comparator (MAGCMP), OSMUX all verified correct.
- The swap initially looked ruled-out because post-swap histat=2 read as
  "found vec 2" - but that was swap(4); the microcode's fence was 4.

FIX: `CGA_INTR_CNTLR.v` now assigns `s_fidbo_2_0[2:0]` straight through
from `s_fidbo_15_0[2:0]` - one version, no ifdef and no escape hatch. The
`CGA_INTR_CNTLR_tb.v` testbench carries dedicated FIDBO no-swap assertions.
VALIDATED 15-JUL: self-test 0 STERR, unit suite 49/49, all 13
instruction-verify areas unchanged, and RUN handles IOX-ERROR and reaches
LEVEL 13 / ARGUMENT == END OF TEST == (the reference RUN-console-ND120.log
sequence). That is one area's end inside RUN's level loop, not the end of
RUN: RUN as a whole is still NOT proven and not gated (see
`tests/instruction-verify/CAMPAIGN-STATUS.md`).

C# behavior (TRA IIC clears IOX/MOR sources, keeps level-14 bit 14) is
CORRECT - matches nd100x (gIID=0 clears sources, gPID bit14 separate). Not
a bug.
