# ND-120 CPU-BOARD-3202 — PAL Verilog transcription faults (audit 2026-07-21)

**Method.** Every Verilog PAL model in `Verilog/PAL/PAL_*.v` was diffed, equation-by-equation
and product-term-by-product-term, against its authoritative original PALASM source in
`DesignDocuments/PAL-Code/SRC/*.txt`. Each candidate was then **behaviourally verified** with an
exhaustive (combinational) or 40 000-cycle random (registered/latch) iverilog equivalence
testbench that instantiates the **real** module and compares it to a reference in which **only the
one flagged literal/term is corrected** to match the PALASM. A nonzero diff count proves the fault
changes real behaviour (i.e. it is not a redundant term or a De-Morgan-equivalent rewrite).

**PNG re-verification (2026-07-21).** Every flagged PAL was then cross-checked against the
**scanned PALASM listing** in `DesignDocuments/PAL-Code/IMG/*.png` (the true original — the `.txt`
SRC is OCR'd and has known garble). This CAUGHT ONE FALSE POSITIVE: **44601B CC0 is NOT a fault** —
the scan shows `/CGNTCACT` (slashed) in the "WAIT FOR BUS OR LOC" term; the Verilog `CGNTCACT_n` is
CORRECT; the `.txt` had dropped the slash via OCR. **44511A CUP is downgraded** (registered
PAL16R4 output-pin polarity is "solved differently" between PALASM and the `CUP_n_reg` model, and
the output is n.c. — not claimed). **Pin-polarity rule used:** a `/PIN` in the PALASM pin list =
active-low pin, so an unslashed literal `X` in an equation = active-high sense = Verilog
`wire X = ~X_n`; a slashed `/X` = the raw `X_n` port. All 8 remaining faults were re-derived under
this rule against the scan and hold.

**Status (checked 28-SEP-2026): ALL 8 confirmed faults below are FIXED in the RTL** - each fixed
equation carries a "PALASM ..." / "30-JUL audit" comment in its `Verilog/PAL/PAL_*.v`
(44306A EIPL, 44302B DSTB, 45001B SPES + SPEA, 44403C DLY0, 44310D BDRY, 45008B DISB + TST). The
"Verilog as-built (wrong)" column and line numbers below describe the code as it was at the audit.
`Verilog/PAL/PROVENANCE.md` describes the checks that guard the PALs now. `44801A` (arbiter) was
already fixed in earlier work and is not re-listed here.

**Fault classes found:** (A) inverted literal — a `/X` negation dropped or added on one literal of
a product term; (B) NAND-vs-NOR latch reset — two hold product-terms OR-combined as `(H1==0)|(H2==0)`
where the PALASM requires reset only when the whole hold sum is 0, `((H1|H2)==0)`; (C) wrong signal —
undelayed input used where the registered/delayed version was specified.

---

## Confirmed faults (verify each against the schematic pin named)

| PAL (cell) | Output | Class | PALASM source (correct) | Verilog as-built (wrong) | Verilog loc | Sim evidence |
|---|---|---|---|---|---|---|
| **44306A** (21G MMUCTL) | EIPL | A | `EIPL = … + LSHADOW * WRITE` (44306A.txt:28) | `… \| (DOUBLE & LSHADOW & WRITE)` — extra `DOUBLE` | PAL_44306A.v:67 | 64/1024 vectors differ (REX-mode shadow write) |
| **44302B** (11D LBC1) | DSTB | A×3 | `… + CACT * /BDRY50 * /BDRY25 * /IORQ` (44302B.txt:19) | `(CACT & BDRY50 & BDRY25 & IORQ)` — 3 literals lost negation | PAL_44302B.v:107 | 3 vectors differ |
| **45001B** (8D BPAR) | SPES | A | `/SPES = … + BLOCK25` (45001B.txt:13) | `\| ( BLOCK25_n )` | PAL_45001B.v:73 | 4 vectors differ |
| **45001B** (8D BPAR) | SPEA | A | `/SPEA = … + MR` (45001B.txt:23) | `\| (MR_n)` | PAL_45001B.v:80 | 16 vectors differ |
| **44403C** (15D CYIN0) | DLY0 | A×2 + C | `DLY0 = MDLY + …` (`.txt:10`); `… + LUA12 * /DMA12 + /LUA12 * DMA12` (XOR, `.txt:14-15`); `… + DMAP` (`.txt:16`) | `MDLY_n`; `(LUA12 & ~DMA12_n) \| (~LUA12 & DMA12_n)` (= XNOR); `MAP` (undelayed, not registered `DMAP`) | PAL_44403C.v:115,119-120,121 | 3134 cycles differ |
| **44310D** (3F LBDIF) | BDRY | B | reset only when `((/MR*BDAP50)+(/MR*BIOXE))==0` (44310D.txt:14-15) | `((MR_n&BDAP50)==0) \| ((MR_n&BIOXE)==0)` — NAND not NOR | PAL_44310D.v:99-100 | 2526 cycles differ |
| **45008B** (2F DATA) | DISB | B | reset only when `((/MR*/BIOXL)+(/MR*/ECCR))==0` (45008B.txt:20-21) | `((MR_n&BIOXL_n)==0) \| ((MR_n&ECCR_n)==0)` — NAND not NOR | PAL_45008B.v:114 | 1391 cycles differ |
| **45008B** (2F DATA) | TST | A + B | hold `/MR*TST*/BIOXL` ⇒ `MR_n & BIOXL_n` (45008B.txt:26), reset when sum==0 | `((MR_n & BIOXL)==0) \| …` — `BIOXL` should be `BIOXL_n`, AND NAND not NOR | PAL_45008B.v:119 | 2456 cycles differ |

## RETRACTED / not faults (caught by the PNG scan)

- **44601B (12D) CC0 — NOT A FAULT.** The scan (`IMG/44601B.png`) shows the CC0 "WAIT FOR BUS OR
  LOC" term as `+ /CC3*CC2*CC1*/CC0*/CGNTCACT*/TERM` — **`/CGNTCACT` (slashed)**. Verilog v236 uses
  `CGNTCACT_n`, which is exactly `/CGNTCACT`. **Correct.** The `.txt` SRC (44601B.txt:52) dropped
  the slash (OCR). CC2's `CGNTCACT` (unslashed) and CC0's "PREV WRITE" `CGNTCACT` also both match
  the Verilog. Module is clean.
- **44511A (26H) CUP — UNRESOLVED, not claimed.** PAL16R4 registered output; pin declared
  active-high `CUP` but the equation is `/CUP := …`, and the FF/output-buffer polarity is handled
  differently in the `CUP_n_reg` model. Needs a rigorous macrocell-polarity analysis to judge; and
  the output is **n.c.** in the 3202 (zero functional impact). Not asserted as a fault.

---

## Notes

- **44306A EIPL** is the MMU-control PAL under active investigation for the `STA→177777` symptom.
  Datapath: `EIPL_n` → `CPU_MMU_PPNX_28` CHIP 9B (74245 lower byte); a deasserted `EIPL_n` in
  REX/16-bit mode leaves `PPN[7:0]` not loaded from the IDB, corrupting 16-bit-mode page-table /
  shadow-PPN writes. (Not yet proven to be the exact cause of `STA→177777=0`; a symmetric MMU-off
  raw-data round-trip reads back correctly, so raw shadow data appears to bypass PPNX.)
- **44403C DLY0** MAP-vs-DMAP (class C): the registered `DMAP` (`DMAP := MAP`, one clock delayed)
  was replaced by the raw undelayed `MAP` — the design note in 45001B.txt explicitly calls out
  needing the delayed version in an analogous case.
- **NAND-vs-NOR (class B)** appears three times (44310D BDRY, 45008B DISB, 45008B TST). It is a
  systematic modelling error in how the PAL latch/register hold terms were reduced to Verilog
  `if/else if`. BDRY (bus data ready) is a live, timing-critical output — note the 44310D source's
  own history line about "BDRY CAN BE LOST".

## Clean (no divergence)

44303B, 44304E, 44305D, 44307C (batch 1); 44401B, 44402D, 44404C, 44407A, 44408B (batch 2);
44445B, 44446B, 44511A/LEV0+CWR (batch 3); 44803A, 44902A, 44904B, 45009B (batch 4);
**44601B (PNG-verified clean — see RETRACTED above)**. `44465B`/`44466B` have a PALASM source but
**no Verilog model** (not implemented).

**Final tally: 8 confirmed faults across 6 PALs** (44306A, 44302B, 45001B×2, 44403C, 44310D,
45008B×2). 1 retracted (44601B), 1 unresolved+inert (44511A CUP, n.c.).

## Testbenches (scratchpad, iverilog)

**Full per-PAL equivalence suite (24 PALs, one `tb_<NAME>.v` each).** Each instantiates the real
`PAL_<NAME>` and compares every output, over all inputs (exhaustive for combinational, 40 000
random clocked cycles for registered), against a reference transcribed **independently from the
PNG scan** (never from the `.v`). Run all with `run_pal_tbs.sh`.

Verified result (24/24 run, 2026-07-21): **FAIL** = 44302B, 44306A, 44310D, 44403C, 45001B, 45008B
(the 6 confirmed-fault PALs). **PASS** = the other 18 (44303B, 44304E, 44305D, 44307C, 44401B,
44402D, 44404C, 44407A, 44408B, 44445B, 44446B, 44511A[LEV0+CWR], 44601B, 44801A, 44803A, 44902A,
44904B, 45009B). 44511A CUP is excluded from the tb (unresolved registered-pin polarity, n.c.);
44404C `DLSHADOW` excluded (44404D-era output, no 44404C equation); 45001B BLOCK/RERR and stateful
c-print `TEST=1` modes not swept (both known faults are combinational and were caught).

Earlier focused tbs also retained: `tb_44306a_eipl.v`, `tb_comb_pals.v`, `tb_seq_pals.v`.
