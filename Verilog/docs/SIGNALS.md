# ND-120 signal dictionary

What each control signal actually is, who drives it, who consumes it — and
**how that was established**.

## Why this file exists

Port comments in this tree were written as confident names before anyone had
traced the signal. `MACLK` was documented as "Memory Access Clock" for over a
year; it has nothing to do with memory. `MCLK` was "Main Clock". Both names
were guesses, and during the TRA CS investigation in August 2026 they sent the
search in the wrong direction for the better part of a day, because a wrong
name written without a hedge is indistinguishable from a measurement.

So every row here carries an **Evidence** column. Three values, and only three:

| Value | Means |
|---|---|
| `measured` | Observed in simulation or on silicon. The command or testbench that shows it is named. |
| `drawing` | Read off a schematic or PALASM listing. The sheet or file is named. |
| `unknown` | Nobody has checked. **This is a valid entry.** |

An `unknown` row is more useful than a plausible guess, because it can be
resolved. A guess just gets believed.

**Rule: no `?` in a port comment.** If the function is not known, the comment
says `UNKNOWN` and points here.

---

## Cycle control

The cycle machine is `PAL_44601B` (CYCFSM) walking the CC3..CC0 state counter;
`PAL_44307C` (CYCLK) derives clocks and strobes from those states; `CYC_36.v`
combines the PAL outputs with `TERM` to make the board-level clocks.

Fast way to see any of this: `cd Verilog/CPU-BOARD-3202/circuit/sim &&
make test-cycle-timeline` prints every signal below, per cycle state, for nine
cycle kinds, in about a second.

| Signal | What it is | Driven by | Consumed by | Evidence |
|---|---|---|---|---|
| `TERM` | Ends the microcycle. One assertion per microinstruction. | `PAL_44601B` | everything; gates most CYCLK outputs | drawing — `PAL_44601B.v` equations |
| `CC3..CC0` | Cycle state counter. Walks a fixed sequence per cycle kind. | `PAL_44601B` | `PAL_44307C`, `PAL_44305D` | measured — `test-cycle-timeline` |
| `MCLK` | **Microcycle clock.** Not "Main Clock". Its PAL equation has *only* RWCS terms, so outside a RWCS cycle `MCLK = ~(TERM_n & MCLK_n)` collapses to plain TERM — one pulse per microinstruction. The RWCS terms stretch it so the gate array sees one long cycle while MA is used twice. | `PAL_44307C` + `CYC_36.v` | CGA | drawing — `PAL_44307C.v`; measured — `test-cycle-timeline` |
| `MACLK` | **Micro-address latch strobe.** Not "Memory Access Clock" — nothing to do with memory cycles. Its only consumer on the whole board is the control-store address latches. All three product terms do the same job from different sources: latch whatever is on MA. Latches are transparent while it is high, so the **falling edge** is the capture. | `PAL_44307C` + `CYC_36.v` | `CPU_CS_ACAL_17` (CHIP_30H 74373 pin C, CHIP_31F AM29841 pin LE), via `CPU_15` → `CPU_CS_16` | drawing — `DesignDocuments/PAL-Code/SRC/44307C.txt`; consumer confirmed against the schematic by Ronny, 08-AUG-2026 |
| `ALUCLK` | Writes the CGA working register file. `= ~(TERM_n \| LCS)` — fires **only** at TERM. | `CYC_36.v:365` | `CGA_WRF` | drawing — `CYC_36.v`; measured — `test-cycle-timeline` |
| `WRFSTB` | UNKNOWN. Named "Write Strobe" in the port comment with a question mark; never traced. Fires in state `0001` of most cycle kinds. | `PAL_44307C` | unknown | measured (timing only) — `test-cycle-timeline` |
| `CYD` | UNKNOWN function. The PAL comment says "WRITE PULSE USED IN WMAP AND WCA", i.e. the memory map and the microinstruction cache. Wired to `CPU_MMU_24` / `CPU_MMU_CACHE_25`. Ruled out as a control-store holding strobe. | `PAL_44307C` | `CPU_MMU_24`, `CPU_MMU_CACHE_25` | drawing — `PAL_44307C.v` comment + wiring; function itself unverified |
| `EORF` | UNKNOWN. PAL comment: "MISC WRITE PULSE", on state `d` only. | `PAL_44307C` | unknown | measured (timing only) — `test-cycle-timeline` |
| `UCLK` | UNKNOWN. PAL comment: "ON ALL MEMORY REQUESTS. USED TO UPDATE USED BITS". | `PAL_44307C` | unknown | drawing — `PAL_44307C.v` comment only |
| `ETRAP` | Enables traps. Deliberately off during states `t`/`a` and during VEX, because a trap there "can destroy MA". | `PAL_44307C` | trap logic | drawing — `PAL_44307C.v` comment |
| `MAP` | Qualifies the first MACLK term. Gated by `FORM & BRK_n & CC2 & TERM_n`. | `PAL_44307C` | `PAL_44307C` MACLK term | drawing — `PAL_44307C.v` |

## Control store

| Signal | What it is | Driven by | Consumed by | Evidence |
|---|---|---|---|---|
| `ECSL` | Enable Control Store Lower — opens the control-store read window onto the IDB. One term is commented "HOLD OVERLAP WITH EWCA_n". | `PAL_44305D` | `CPU_CS_16` | drawing — `PAL_44305D.v`; measured — `test-cs-rwcs`, `test-cycle-timeline` |
| `EWCA` | Enables the WCA register in the MIC onto MA — i.e. presents the ADCS-latched control-store address. | `PAL_44305D` | `CGA_MIC_IPOS` | drawing — `PAL_44305D.v` port comment |
| `EUPP` / `ELOW` | Select the upper / lower control-store bank. | `PAL_44305D` | `CPU_CS_WCS_21_22` | drawing — `PAL_44305D.v` |
| `WCSTB` | Write pulse to the writable control store; also the write pulse during microcode load. Observed in states `1010`/`1011` of an LCS cycle. | `PAL_44305D` | `CPU_CS_WCS_21_22` | drawing + measured — `test-cycle-timeline` |
| `WICA` | Write pulse to the microinstruction cache. | `PAL_44305D` | `CPU_MMU_CACHE_25` | drawing — `PAL_44305D.v` |
| `LUA` | Control-store **read address**, output of the ACAL latches. Feeds the control-store combinationally, so it must track `CSA` with zero latency while MACLK is high — a one-cycle lag here corrupts CSBITS on a microcode jump and was the Tang Nano 20K boot hang (fixed 19-JUL-2026). | `CPU_CS_ACAL_17` | `CPU_CS_WCS_21_22` | measured — `CPU_CS_ACAL_17_tb.v`, and on silicon |
| `IDBS,RCS` (CSIDBS 030) | "Read control store" IDB-source code - deliberately **not** decoded as an IDB source. The word reaches the IDB only through command `COMM,RWCS` (36,1). The DGA has no gate for 030 (nor for 031 PICV, same rule). Used by `TRA CS` (routine `ACS`, microwords 000746 `COMM,ADCS` then 000747 `IDBS,RCS COMM,RWCS`). | - | - | drawing — Microprogrammer's Guide ND-06.031.1 IDB source table, DELILAH Hardware Introduction |
| control-store read capture | The '245/latch pair on the control-store read path acts as an **edge-triggered capture on the falling edge of ECSL~**, then holds the word on the IDB while ECSL~ stays low. During RWCS, ECSL asserts at state 0101 while EWCA still holds the ADCS address; EWCA drops at 1100 and LUA moves on, so without this capture the word is lost (`TRA CS` returned 000000 until 08-AUG-2026). | `CPU_CS_TCV_20.v` | IDB | measured — `test-cs-rwcs`, `test-cs-rwcs-cycle`; reasoning in the `CPU_CS_TCV_20.v` header |
| `MA` | The micro-address bus. A **combinational** mux over `WCA_12_0` / `W_12_0` / `TVEC_3_0` / `CD_15_0`, selected by EWCA, MAP_n, TRAP_n — so it switches the instant EWCA drops. | `CGA_MIC_IPOS.v` | `CPU_CS_ACAL_17` | drawing — `CGA_MIC_IPOS.v` (page 22) |

## Known-wrong names that were corrected

Kept so the old names are recognisable if they resurface in an old document or
an old comment.

| Was called | Actually is | Corrected |
|---|---|---|
| `MACLK` = "Memory Access Clock" | micro-address latch strobe | 08-AUG-2026 |
| `MCLK` = "Main Clock" / "Master Clock" / "Memory Clock" | microcycle clock | 08-AUG-2026 |

## Adding a row

State the evidence or state `unknown`. Do not infer a function from a signal's
name — that is exactly how `MACLK` acquired the wrong one.
