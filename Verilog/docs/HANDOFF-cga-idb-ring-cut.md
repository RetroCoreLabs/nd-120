# HANDOFF: cutting the CGA IDB combinational ring

**Full path:** `Verilog/docs/HANDOFF-cga-idb-ring-cut.md`
**Written:** 04-SEP-2026
**Status:** ANALYSIS. One RTL cut (A9, section 4) was made and REVERTED on
06-SEP-2026; the ring is still in the RTL. This document says what the ring is,
why the attempts failed, what would actually work, and what must be proven
before anyone commits a fix.

---

> **OUTCOME, added 04-SEP-2026 after the analysis was written:** the QMTECH
> XC7A35T was built and **its CPU domain closes with +5.255 ns and zero
> failing endpoints at 20 MHz, with the ring present**. The ring does not
> block the SINTRAN-capable board. It remains worth cutting, but as quality
> work rather than to unblock anything. Full numbers in section 8, and read
> section 2 before touching any RTL - the ring is not where `CGA.v` says.

## 1. Why this is worth doing now

The ring stopped being a warning count and started failing a build.

The Cmod A7 (`xc7a35t`) was built for the first time on 04-SEP-2026. It fits
the part easily - 11,493 of 20,800 LUTs - and then **misses timing by
89.814 ns at 27 MHz**, 5133 of 18465 endpoints failing. From the routed
checkpoint, **all 200 worst paths share one start and one end**:
`CPU/CS/WCS/CHIP_21C` to `CPU/PROC/CGA/DELILAH/MAC/MAC_LA1025/R_LA_L`, 234
logic levels, 126.5 ns, through the ALU, never touching main memory.

That number is a property of the netlist, not of the machine. The same RTL
gives the same path:

| netlist | logic levels | delay | verified? |
|---|---|---|---|
| Nexys 4 DDR at 45.45 MHz | **31** | - | **YES** - `fpga/nexys4ddr/timing-analysis/run_clk45/setup_paths_post_route.rpt:24` |
| QMTECH at 20 MHz | **49** | 45.4 ns | **YES** - `fpga/qmtech-a35t/timing.rpt:431` |
| MEGA65 R6 | 58 | 34 ns | NO - prose only |
| MEGA65 R3 | 93 | 57 ns | NO - prose only |
| Cmod A7 | **234** | 126.5 ns | **YES** - `fpga/cmod-a7-35t/top5_paths.rpt` |

**The row that used to sit at the top of this table said "Nexys 4 DDR at
33.9 MHz | 7 | 6.8 ns". It was WRONG** - see section 3a. The Nexys report says
31 levels. Everything written on top of that 7, here and elsewhere, has been
re-checked and corrected.

and it boots SINTRAN on the Tang, whose toolchain has no loop check at all.
The MEGA65 R3 already paid for this: its CPU runs at 13.333 MHz because the
period was made to fit the ring rather than untime the bus.

**Lowering a clock is not a fix.** 126.5 ns would need the CPU under 7.9 MHz.

---

## 2. What the ring is - AND WHY THE COMMENT IN CGA.v IS NOW WRONG

> **READ THIS BEFORE ANYTHING ELSE.** The ring described in
> `DELILAH-CPU/CGA/circuit/CGA.v:707-745` **no longer exists**. That comment
> describes the design as it was before the 21/22-AUG-2026 cuts, and it will
> send anyone who trusts it to the wrong module. Verified against the working
> tree 04-SEP-2026.

### The ring the comment describes (call it B) is CUT

`FIDBO -> MAC/INTR -> PCR / PGS / PICMASK -> SEL6 -> FIDBO`.

**Every one of those five SEL6 data sources is now behind a register:**

| source | where the register is | file:line |
|---|---|---|
| PCR | the `L8`/`L4` stored taps `QA_R..QH_R`, bypassing the transparent mux | `Shared/ndlib/L8.v:64-66,104-115`; `CGA_MAC_SEGPT_PCR.v:116-123,149-152`; routed at `CGA.v:876` |
| PGS | `SCAN_FF_EN` throughout | `CGA_IDBCTL_PGSREG.v:82,93,104,115,126,137,148,...` |
| PICMASK | `D_FLIPFLOP_EN` on MCLK | `CGA_INTR_CNTLR_IRQ_MASK_MASKBIT.v:112` |
| PICS / PICV | clocked FF outputs | `CGA_INTR_CNTLR_VECGEN_STAT_SBIT.v` (SBIT spot-checked; the VHR/OSMUX chain NOT exhaustively traced) |

All five SEL6 enables are DCD flip-flop outputs with no FIDBO dependency
(`CGA_DCD.v:1350-1453`). All fourteen OUTMUX enables are register outputs
(`CGA_ALU_OUTMUX_IDBS.v:260-319`).

Also corrected: `s_FIDBO_15_0` is no longer an OR with the IDBCTL output.
`CGA.v:746` is now `assign s_FIDBO_15_0 = s_alu_IDB_15_0_OUT;`. And the FIDBO
fanout assigns the comment calls "CGA.v:614-615" are at **`CGA.v:695-696`**
today; 614-615 are two unrelated interrupt assigns.

### The ring that actually exists (call it A) LEAVES THE CHIP

```
FIDBI ──► ALU_OUTMUX SI[5] (EFIDB, the pass-through default)
       ──► D_15_0[n] ──► G_15_0[n] ──► ~G ──► FIDBO
       ──► BusDriver16 ──► XFIDB_15_0_OUT            [leaves the CGA]
       ──► TTL_74245 CHIP_32F/33F  (B ──► A_OUT when DIR==0)
       ──► board IDB (BIF / DPATH / MMU cache / ERF SRAM)
       ──► TTL_74245               (A ──► B_OUT when DIR==1)
       ──► XFIDB_15_0_IN
       ──► BusDriver16  A_15_0_OUT = IO_15_0_IN   ◄── UNCONDITIONAL, no enable
       ──► XFIDBI ──► CGA_IDBCTL_SEL6 .D  (gated by ED)
       ──► FIDBI    [closes]
```

Key file:line: `CGA_ALU_OUTMUX.v:379-513` (SI[5] wiring), `:825-920` (DMUX),
`:678-820` (GMUX), `CGA_ALU.v:216` (the inverter), `CGA.v:746`, `:760-765`,
**`Shared/ndlib/BusDriver16.v:49`** (`assign A_15_0_OUT = IO_15_0_IN;`),
`TTL_74245.v:43,46`, `CPU_PROC_32.v:280-287,285,521`,
`CGA_IDBCTL_SEL6.v:87,94`, `CGA_IDBCTL.v:100,115`, `CGA.v:886,702,705,793`.

**Inside the CGA there is now exactly ONE combinational return into `D_15_0`:
`SI[5] = FIDBI`.** Everything else feeding the OUTMUX is behind a flop.

### The second live arc - this is the one the Cmod measurement hit

```
FIDBO ──► MAC ──► PCR / SEG / XPT  (L8/L4 TRANSPARENT latches)
      ──► MAC_LASEL / MAC_LA1025 ──► LA_23_10
```

`Shared/ndlib/L8.v:79-86` models a transparent latch as `L ? D : reg` even in
FPGA mode, and `CGA_MAC_SEGPT_SEG.v:82` / `CGA_MAC_SEGPT_XPT.v:103`
**deliberately leave `QA_R` unconnected and use the transparent output**
(`:114-115`, `:126-127`), feeding LASEL/LA1025 at `CGA_MAC.v:260,291`.

**This is why every one of the Cmod's 200 worst paths ended at
`MAC/MAC_LA1025/R_LA_L`.** The 21-AUG `PCR_RB` fix cut the PCR *readback* leg;
it did not touch this *outbound* leg.

### The loop still cannot happen in hardware

Reading the IDB as an ALU operand while driving the ALU result onto it would
be two drivers on one bus. Both pass-through terms are proper defaults:
`EFIDB` is the else-branch of the OUTMUX decode
(`CGA_ALU_OUTMUX_IDBS.v:167-179`) and `ED` is the explicit complement of the
five internal enables (`CGA_IDBCTL.v:115`). The bus direction is additionally
controlled by the `TTL_74245` `DIR` pin, whose two branches are complementary
within one module (`TTL_74245.v:43,46`) - but the outbound and return legs go
through **CHIP_32F and CHIP_33F**, two different instances, so that exclusivity
is again split across a boundary the tool cannot cross.

### Independent confirmation from the QMTECH build, 04-SEP-2026

The first build of a board that had never been synthesized reported its loops
with the cell lists below, and they trace ring A and the MAC arc exactly, on a
netlist nobody had tuned:

```
loop 1 (10 cells):
  ALU/ALU_OUTMUX/OUTMUX_IDBS/IDBS_R1/D_15_0[8]_INST_0
  ALU/ALU_OUTMUX/OUTMUX_IDBS/IDBS_R1/G_15_0[8]_INST_0      <- A2a
  ALU/ALU_RALU/RN_R_MUX/MUXQ3/s_f_15_0_inferred_i_5         <- A2b
  ALU/ALU_STS/STS_REG_MID/ZN_i_1__3
  MAC/MAC_LASEL/ALU_i_320, ALU_i_72, CS_i_45                <- the MAC arc
  DELILAH/g_sync.tmm_memory_array_reg_i_16
  IO/g_async.tmm_memory_array_reg_0_255_0_0_i_3             <- the board SRAM

loop 2 (11 cells):
  CPU/MMU/CACHE/CHIP_21F/g_sync.tmm_memory_array_reg_i_14__0
  ALU/ALU_OUTMUX/OUTMUX_IDBS/IDBS_R1/D_15_0[10] + G_15_0[10]
  ALU/ALU_RALU/RN_R_MUX/MUXQ3/s_f_15_0_inferred_i_3
  ALU/ALU_STS/STS_REG_MID/s_f_15_0_inferred_i_14
  MAC/MAC_LA1025/R_LA_H/ALU_i_314, ALU_i_70, CS_i_41        <- the MAC arc
  IO/CS_i_40
```

Both close through `tmm_memory_array` cells - the board-side SRAM in the
return path - which is the off-chip half of ring A, and both pass through
`MAC_LASEL` / `MAC_LA1025`, which is the transparent-latch arc. Neither
touches PCR, PGS or PICMASK readback. **That is ring B being dead and ring A
being alive, measured rather than argued.**

### Bit coverage

**All 16 bits carry ring A** - `.D` (XFIDBI) is wired on every SEL6 instance
(`CGA_IDBCTL.v:126..291`) and `SI[5]` on every DMUX
(`CGA_ALU_OUTMUX.v:379..513`), with no bit tied to a constant. The latest DRC
in the tree (`fpga/mega65/build/r3/timing-analysis/run_4/drc.rpt`, Vivado
2026.1, 04-SEP-2026) names bits **0 through 13** plus two in
`BIF/DPATH/PESPEA/CHIP_9A`. Bits 14 and 15 appeared in the older R6 report and
not in R3; nothing in the RTL distinguishes them, so this is most likely LUT
packing, **NOT VERIFIED**.

Per-bit differences do exist in the *internal* source population (bits 13,12
have no PGS; bits 6..3 have no PCR; PICS/PICV only on bits 2..0 -
`CGA_IDBCTL.v:125-299`), but those belong to ring B, which is cut, so they do
not explain the reported bit set.

---

## 3. The one-hot property is REAL, and structural

This was the load-bearing question: if exclusivity held only because of what
the microcode happens to contain, no RTL restructuring could ever prove it and
the whole effort would be pointless. It does not.

- `CSIDBS_4_0` is **`CSBITS[41:37]`**, a 5-bit **binary-encoded** field of the
  64-bit microword. Established from three independent files:
  `CPU-BOARD-3202/circuit/CPU_PROC_CGA_33.v:160-162`, `CPU_PROC_32.v:203`,
  `ND3202D.v:536`.
- A binary field always has exactly one value, so "can two sources be selected
  at once" is not a meaningful question. **No microcode scan is needed and
  none can change the answer.**
- `CGA_DCD.v` decodes **full 5-bit minterms**, one per enable:
  `EPGSN`=19 (`CGA_DCD.v:1338-1348`), `EPCRN`=21 (`:1368-1379`),
  `EPICVN`=25 (`:1399-1410`), `EPICSN`=13 (`:1430-1441`), `ERFN`=5
  (`:1456-1465`). Five distinct minterms of one field are provably exclusive
  from the RTL alone.
- The ALU output mux uses **two 3-to-8 decoders with complementary enables**
  (`CGA_ALU_OUTMUX_IDBS.v:216-222, 197-203, 229, 244`). `ND38GLP`
  (`Shared/ndlib/ND38GLP.v`) structurally cannot assert two outputs. `EFIDB`,
  the pass-through that closes the ring, is an explicit **default term**
  (`CGA_ALU_OUTMUX_IDBS.v:167-179`) - a `case` with `default`, in gate form.

### So why can the tool not see it

**Because the decoded enables are registered before use, and then cross two
module boundaries.**

- OUTMUX enables are latched in `IDBS_R1`/`IDBS_R2`
  (`CGA_ALU_OUTMUX_IDBS.v:260, 291`, on ALUCLK).
- DCD enables are latched in five `D_FLIPFLOP_EN` instances
  (`CGA_DCD.v:1350-1489`, on MCLK).
- What finally meets the data is `CGA_ALU_OUTMUX_SEL8.v:50-126` instantiated
  16 times (`CGA_ALU_OUTMUX.v:825-920`), fed bit-by-bit from
  `CGA_ALU_OUTMUX.v:234-368`.

The cone Vivado sees is **eight unrelated flip-flop outputs, eight data bits,
one OR**. Nothing in it says the enables are one-hot. Vivado's loop analysis
is purely combinational and cannot relate the Q outputs of several registers.

### The shape that already works, in this same tree

`CGA_IDBCTL.v:115` writes the pass-through enable as the explicit complement
of all the others, in one module, combinationally:

```verilog
assign s_epins[5] = (s_epicmask_n & s_epicv_n & s_epics_n & s_epcr_n & s_epgs_n);
```

**Vivado resolves that one and does not complain about it.** It is the model
for the fix.

### One genuine exception, carried as an open item

`EPICMASKN` is **not** CSIDBS-derived. It comes from `CGA_INTR_CNTLR_MDCD.v:248-253`
via `EPIC`, a decode of a different microword field, `CSCOMM`
(`CGA_DCD.v:1180-1190`). Exclusivity between `EPICMASK` and the four CSIDBS
enables is therefore **convention, not construction, and is NOT VERIFIED**.

It does not affect the loop argument, because `ED` is off whenever any of the
five is on. To settle it: extract `CSBITS[41:37]` and `CSBITS[36:32]` for every
microword and check no word has CSIDBS in {13,19,21,25} while CSCOMM == 9 with
a matching LAA.

---

## 3a. LOGIC-LEVEL FIGURES: what is measured and what is not

**Corrected 07-SEP-2026 after a reader challenged the numbers, and they were
right to.** The per-board logic-level counts quoted around this project were a
mix of report readings and prose repeated until it looked like data. What each
one actually rests on:

| board | levels | source | verified |
|---|---|---|---|
| Nexys 4 DDR @ 45.45 MHz | **31** | `fpga/nexys4ddr/timing-analysis/run_clk45/setup_paths_post_route.rpt:24` | **YES** |
| QMTECH @ 20 MHz | **49** | `fpga/qmtech-a35t/timing.rpt:431` | **YES** |
| Cmod A7 @ 27 MHz | **234** | `fpga/cmod-a7-35t/top5_paths.rpt` (5 paths agree) | **YES** |
| MEGA65 R6 | 58 | prose only - NOT in `fpga/mega65/docs/00-plan.md` | **NO** |
| MEGA65 R3 | 93 | prose only - NOT in `fpga/mega65/docs/00-plan.md` | **NO** |

**A figure of "7 levels on the Nexys" was written into three files on
04-SEP-2026. It is WRONG.** The Nexys report says 31. The 7 came from a
sentence, not a report, and was then quoted back as though measured.

Why this matters beyond tidiness: the argument "the ring constraint takes the
path from hundreds of levels to single digits, so the unconstrained boards are
sitting on huge headroom" was built on that 7. With the real number, the
constrained Nexys (31) and the unconstrained QMTECH (49) are much closer, and
the gap is equally explainable by the different part (`xc7a100t` vs
`xc7a35t`), different memory and different build config. **The claim that the
QMTECH has large headroom is NOT supported by this data.**

What survives: the Cmod's 234 is verified and is roughly 5x every other board,
and the QMTECH and Cmod genuinely carry no ring constraint while the Nexys
does (`fpga/nexys4ddr/nd120_timing.xdc:67-70`). Whether adding it helps is an
open question that one build would settle.

The 93-level figure is load-bearing in sections 7 and 9 below. Treat those
passages as resting on an unverified number until someone reads it off a real
MEGA65 R3 report.

---

## 4. What has already been tried - do not repeat these

| # | Change | Loops | WNS | Verdict | Recorded |
|---|---|---|---|---|---|
| A1 | Gate the IDBCTL term into FIDBO | 46->42; 12 LUTLP unchanged | -12.6 -> -23.6 | REVERTED | `CGA.v:709-717` |
| A2 | New `SRC_15_0_OUT` output, drive FIDBO from it | 46 -> **47** | +1.460 -> -12.289 | REMOVED | `CGA.v:722-723` |
| A3 | Leave `SRC_15_0_OUT` in place but unused | - | - | synth sat **>2 h** in Timing Optimization (normally ~30 s) | `CGA.v:727-732` |
| A4 | `b3ee391`: FIDBO = OUTMUX only + registered PCR tap | unmeasured at commit | unmeasured | SHIPPED, in tree | commit |
| A5 | Rely on Vivado's auto-cuts | 2 to 32, unstable | +? / -10.4 / -50.7 | ABANDONED | `fpga/nexys4ddr/nd120_timing.xdc:27-45` |
| A6 | Explicit ordered false path in XDC | 19 auto-cuts remain | **+0.261** on the real build | SHIPPED, **Nexys only** | `268c61d`, `df8357d` |
| A7 | `SKIP_WCS_LOAD` (Cmod) | n/a | -95.488 -> -89.814 | **not the cause**, 5.7 ns of 95 | `fpga/cmod-a7-35t/README.md` |
| A8 | Lower the clock | n/a | needs <7.9 MHz | rejected as artifact-fitting | `TODO.md` |
| A9 | **Cut it properly: a second output network FIDBI never enters** | n/a (Gowin) | Tang `fast20` CPU domain **0 -> 1064 failing endpoints**, Fmax **22.849 -> 18.994 MHz** | **REVERTED 06-SEP-2026** | below |

### A9 - the cut that works in simulation and loses on the board

The one restructuring that actually removes the cycle, built and measured, and
then reverted because it costs too much. **Do not spend a second week
rediscovering it.**

What it was. FIDBI reaches the outgoing bus driver through `SI[5]` of the ALU
output mux. Rewriting that mux as a `case` does NOT help - Vivado's and
Gowin's loop checks are STRUCTURAL, they flag any combinational cycle and
never look at enables, so the wire path is what matters and it was unchanged.
Nor does gating FIDBO at the far end (`FIDBO_EXT = EFIDB ? 0 : FIDBO`): the
gate's input cone still contains FIDBI.

What does remove it is a SECOND copy of the output network that FIDBI never
enters - same enables, same seven other sources, `SI[5]` tied low - with its
result the only net wired to the outgoing driver. 16 `SEL8`/`SEL7` plus 16
`MUX31LP`. The internal FIDBO keeps the pass-through, so MAC, INTR and MIC
are untouched.

It is exactly equivalent, and that is checkable without a golden model:

    G_EXT(FIDBI = anything)  ===  G(FIDBI = 0)

A bench on that spec passed **6368 checks, 0 errors, both build modes**, with
4242 of them in the cycles where old and new genuinely differ. Every existing
ALU bench passed unchanged (`test-alu-outmux` 101,236 checks), and the whole
CPU still reached the OPCOM `#` prompt in Verilator.

**Then the Tang killed it.** A/B on the same tree, same commit, one define
apart (an `-IdbRingKeep` escape hatch built for exactly this):

| Tang `fast20`, CPU clock `CLKOUTD` @ 20.25 MHz | ring CUT | ring KEPT |
|---|---|---|
| setup TNS | **-1819.731** | 0.000 |
| failing endpoints | **1064** | 0 |
| Fmax | **18.994 MHz** | 22.849 MHz |
| logic levels on the critical path | 34 | 38 |

The control reproduces the recorded baseline (22.849 against the 22.932 MHz
of 31-AUG), so this is the change and not a week of drift.

**The cause is NOT established.** Two candidates, neither confirmed:

  - the 32 extra instances cost congestion on a part that is already nearly
    full (20,736 LUT4), or
  - the cut makes the analysis HONEST: with the ring present the tool must
    break the loop to run STA, and the paths it disables to do that stop
    being reported. On that reading the pre-cut "TNS 0.000" was partly
    fiction and the -1819 ns was always there, unseen.

The evidence is genuinely ambiguous and the report does not settle it: the
cut build's own top-25 setup paths are ALL POSITIVE (worst +7.908 ns) while
its summary claims -1819 ns over 1064 endpoints, and its report file is 58%
larger than the control's. Fewer logic levels AND a lower Fmax is not what
simply-more-logic looks like.

**If anyone picks this up again, that ambiguity is the thing to resolve
first, and it is worth resolving** - because if the second reading is right,
every "timing-clean" number this project has recorded on a build containing
the ring is an overstatement, on every board. Compare the count of analysed
endpoints between the two builds before touching the RTL again.

### What `b3ee391` actually did

It removed **two edges**, not the ring, and its own commit message says so:
*"Remaining rings run through the board segment (IO_37/MMU readback); loop
count to be measured in the next synth."* That measurement was never taken.

The two edges: `s_FIDBO_15_0` stopped being an OR with the IDBCTL output
(now `CGA.v:746`), and the SEL6 PCR readback moved onto a new registered tap
(`Shared/ndlib/L8.v`, `CGA_MAC_SEGPT_PCR.v:31-36`, `CGA.v:873-876`).

### A claim in the tree that is FALSE

`fpga/nexys4ddr/build.tcl:496` says current builds report **zero** LUTLP-1
errors and exactly **two** auto-inserted false paths. The actual DRC reports
from two days later say **six** (`timing-analysis/run_clk16/drc.rpt`,
`run_clk45`, `run_clk50_1`, all 26-AUG) and **five** (`run_clk16_6`, 28-AUG).
`build.tcl:523` in the same file says "12 known CGA IDB loops".
`fpga/mega65/build.tcl:450` says the deployed Nexys build has **16**.
`timing.md:115-118` says six.

**The "zero/two" line is not supported by any artifact in the tree.** Loop and
auto-cut counts are netlist properties and have been measured at 2, 3, 4, 5,
12, 16, 19, 23 and 32 across builds of the same source. Never use "the loop
count went down" on one board as evidence that a fix worked.

---

## 5. THE IMMEDIATE PRACTICAL FINDING

**The Nexys does not tolerate the ring. It cuts it with an explicit
constraint, and the Cmod and QMTECH do not have that constraint.**

`fpga/nexys4ddr/nd120_timing.xdc:67-70`:

```tcl
set_false_path \
  -through [get_pins -hier -filter {NAME =~ *DELILAH/ALU/FIDBI_15_0[*]}] \
  -through [get_pins -hier -filter {NAME =~ *DELILAH/ALU/ALU_OUTMUX/OUTMUX_IDBS/IDBS_R*/F_15_0[*]}] \
  -through [get_pins -hier -filter {NAME =~ *DELILAH/ALU/FIDBO_15_0_OUT[*]}]
```

Measured when it was added (29-AUG-2026): two failed routed checkpoints went
**-10.4 -> +0.044 ns** and **-50.7 -> -0.19 ns**; the first real build with it
closed at **WNS +0.261 ns with the CPU worst path down from 208 logic levels
to 40**.

`fpga/cmod-a7-35t/nd120_timing.xdc` and `fpga/qmtech-a35t/nd120_timing.xdc`
contain **clock groups only**. Both boards are running the A5 regime that the
Nexys abandoned - the one measured to produce 208-level, -50.7 ns netlists.

It is ordered deliberately: it cuts only the ALU-result branch, so the
legitimate path `external IDB -> FIDBI -> OUTMUX EFIDB -> FIDBO -> MAC/INTR
register loads` stays timed (`nd120_timing.xdc:46-49`).

**Trap:** if `[Vivado 12-4739]` appears after synthesis, a `-through` pattern
was dropped and the -50 ns path is back. Grep every build log for it.

---

## 6. The fix that the evidence points to

Not clever, and mechanical: **register the 5-bit select, not the eight signals
decoded from it, and put the decode and the multiplex in one module as a single
selection over that field, with the pass-through as the `default` branch.**

The decoders are already the right structure. They are on the wrong side of the
flip-flops.

Concretely, two shapes, either of which gives the tool one cone it can
discharge:

1. One `case (rcs_4_0)` inside `CGA_ALU_OUTMUX` selecting among the eight
   sources, `FIDBI` as `default`. The tool then sees "select == default implies
   FIDBI, select == 3 implies EDBR" as one decode.
2. More minimally: move the `IDBS_R1`/`IDBS_R2` flops from **after** the
   `ND38GLP` decoders to **before** them, onto the 5-bit field, and do decode
   plus mux inside `CGA_ALU_OUTMUX`.

Whether that retiming is behaviourally neutral is **NOT VERIFIED**. Two
testbenches exist specifically for that seam:
`CGA_ALU/sim/CGA_ALU_OUTMUX_IDBS_tb.v` and `CGA_ALU_OUTMUX_tb.v:44,361-374`.

### Rules any attempt must obey, each from a measurement

1. **Do not gate the IDBCTL term into FIDBO** - costs 11 ns, removes 0 of 12
   LUTLP (A1). Moot anyway: the term no longer exists.
2. **Do not create a second, differently-derived IDBCTL output** - it *adds* a
   loop and costs ~13.7 ns, because the tool can no longer share one cone (A2).
3. **Never leave a dead cone attached to the ring** - >2 hours in Timing
   Optimization (A3).
4. **Attack the internal ring, not the external XFIDBI path.** XFIDBI was
   never part of the ring that matters (`CGA.v:719-722`).
5. **Preserve the ASIC structure: FIDBO driven ONLY by the ALU OUTMUX.**
   Drawing sheet 5 of 8, the `&BD4TU` XFIDB pad ring: FIDBO and XFIDBI are
   separate one-way buses that meet only at the pad. Any second FIDBO driver
   re-creates the arc `b3ee391` removed.
6. **Keep the legitimate path timed** - see section 5.
7. **Preserve latch-mode equivalence.** The `L8`/`L4` `*_R` taps were added on
   the explicit promise that in latch mode the tap equals the transparent
   value. Any further tap use needs the same argument.
8. **One build's WNS proves nothing.** Changing only a console baud divider
   moved a Nexys 50 MHz build from +0.007 to -0.210 ns.
9. **There is a SECOND, non-CGA loop family** in `CPU/MMU/PT/CHIP_22G` (nets
   `tmm_memory_array_reg_1/2`), plus board-segment `IO_37`/MMU readback rings.
   A CGA-only fix will not take the loop count to zero.

---

## 7. Verification - and the blind spot that matters most

### THE BLIND SPOT

**The PGS readback leg is never exercised by any simulation gate in this
repository.**

All four `IDBS,PGS` microwords are SINTRAN-III paging traps, at control-store
addresses 0003 (RING-DOWN), 0004 (PGU TRAP), 0005 (WIP TRAP) and 0027.
INSTRUCTION-B runs unpaged, and **there is no target in `runSim/Makefile` that
boots SINTRAN in Verilator** - `run`, `run-c`, `run-config`, `run-fs`,
`run-floppy`, `run-tpe`, `run-rtc`, none of them is SINTRAN. SINTRAN runs only
on silicon.

Proof it is never reached: in `sim/golden/trace_ff_golden.csv` the WCS loader
walks every control-store address exactly once, which produces exactly **68
rows** at the sample rate. Addresses 0003, 0004, 0005 and 0027 have **68 rows**
- the loader pass and nothing else. Confirmed against addresses that are
certainly never executed.

**So every simulation gate in this repo can pass with the PGS leg of the ring
completely broken, and the first thing that tells you is a board that
ERRFATALs after a real page fault.**

Module-level benches (`test-trap-pgs-paging`, `test-pgf-committed`,
`test-idbctl-pgsreg`) prove PGS is *formed* correctly. None of them drives the
CGA ring. **Only a SINTRAN boot on hardware covers this.**

### What IS covered

- **PICV / PICS**: control store 0017 (`% MACRO INTERRUPT`) runs **5233**
  sample-rows in the golden trace, and the runSim golden console shows real
  IDENT level-11/12/13 dispatches. Genuine coverage.
- **PCR**: `IDBS,PCR` appears **zero** times in the microcode listing. PCR is
  only ever written. The PCR leg may be structurally dead; it can only be
  defended by `test-idbctl-sel6`.

### Two gate-integrity defects found on the way

1. **`tests/instruction-verify/run_area_test.sh:23-27` prints
   `TB_RESULT: PASS (skipped - no golden)` and exits 0** when the golden is
   missing, and `make test-instr-%` greps for `TB_RESULT: PASS`. The goldens
   live **outside the repo**, at
   `$ND_REPOS/ND110Compile/traces/`. They are present today (16
   files, verified 04-SEP-2026), so the gate is live on this machine - but on
   any machine without that directory the entire instruction campaign reports
   green while doing nothing. **Verified by reading the script.**
2. **`make -C sim compare` cannot fail.** Its diff sits in a
   `|| (echo ...)` that succeeds. The real gate is the two `cmp`s against
   `sim/golden/trace_ff_golden.csv` and `trace_latch_golden.csv`, which
   `test-full` does and a bare `make compare` does not.

### Minimum bar before believing a fix works

1. `make -C DELILAH-CPU/CGA_IDBCTL/sim test-idbctl-sel6 test-idbctl test-idbctl-pgsreg`
2. `make -C DELILAH-CPU/CGA_DCD/sim test-dcd-idbs-enables`
3. `make -C DELILAH-CPU/CGA/sim test-busdriver16-full` and
   `make -C DELILAH-CPU/CGA_ALU/sim test-alu-outmux-idbs`
4. `make -C tests test-no-latches`
5. `make -C fpga/tang-nano-20k check` - inferred-latch census on a real netlist
6. `make -C sim compare` **followed by both `cmp`s against the goldens**. CSA
   is the control-store address, so any value the microcode branches on that
   goes wrong diverges the trace permanently, usually within a few cycles.
7. The runSim golden console `cmp` (`Verilog/Makefile:95-97`, exact flags -
   `-DDEBUG_INTERRUPT` yes, `-DDEBUG_BIF=1` no, `VERILOG_TAPE=0`)
8. `make test-instr-ARGUMENT` - **check the log for `SKIP`**
9. **Tang: build, program, `20500&` at the OPCOM prompt, banner within ~30 s.**
   NON-NEGOTIABLE. It is the only step that executes an `IDBS,PGS` microword.

Skipping step 9 leaves the PGS leg entirely unverified.

### Full bar for a commit

Add: `make test` (~34 min, require the `ALL n TESTS PASSED` banner, not merely
absence of errors - it is fail-fast); the STERR probe built with
`-DND120_COUNT_STERR` requiring **0 execution-phase STERR visits**;
`make test-full`; `make test-instr` (~1.5 h, all 13 areas, cross-checked
against `tests/instruction-verify/CAMPAIGN-STATUS.md`); Nexys at 45.45 MHz and
MiSTer at 20 MHz both booting SINTRAN; a MEGA65 R3 build, which is the
project's most sensitive ring measurement (93 levels / 57 ns) and should drop
sharply if the fix works; and the 4-hour soak recipe of 27-AUG-2026 (ESC console probes every 30 min, 8 over 4 h; see HISTORY.md 27-AUG; plan in git at c4896a4).

**Record the `[DRC LUTLP-1]` count and the `Synth 8-326` list before and
after.** That number is the change's stated purpose, and every prior attempt
failed on exactly it. Note that no `make` target measures it - it must be read
out of a vendor build log by hand.

---

## 8. MEASURED 04-SEP-2026: the ring does NOT block the SINTRAN target

The QMTECH XC7A35T was built for the first time, and it settles the question
this document was written to answer.

| clock domain | worst slack at 20 MHz | failing endpoints |
|---|---|---|
| `clk_cpu_pre` (CPU, bus, devices) | **+5.255 ns** | **0 of 27,698** |
| `clk_stor_pre` (SD/FAT stack) | +11.475 ns | 0 of 11,113 |
| `clk2x_pre` (SDRAM bridge) | +10.949 ns | 0 of 351 |
| `clk_cpu` <-> `clk2x` (related pair) | +4.105 ns | 0 of 255 |

**The CPU domain closes with 5.255 ns to spare and not one failing endpoint.**
The same netlist reports 16 `LUTLP-1` warnings and 10 auto-inserted
`Synth 8-326` cuts - the ring is present and Vivado is breaking it, and on
this part it happens to break it somewhere harmless. Utilization is 13,170 of
20,800 LUTs, 22 of 50 block RAM tiles.

The build still reported WNS -2.137 ns, from exactly **two** paths, both
`clk_stor -> clk_cpu` inside the storage stack
(`u_mount/r_size_reg[1][18] -> u_engine/g_fe[1].r_size_reg[18]` and
`u_engine/g_fe[1].r_wrdata_reg[7] -> u_engine/s_staging_reg`), with a
**required time of 1.000 ns**. That is not the ring and not logic depth: it is
two unrelated clocks being timed as synchronous, because the board's clock
constraint never took effect (see section 9).

### What this means

- **The ring is not what stops a SINTRAN-capable Artix board.** It stopped the
  Cmod; it does not stop this one, on the same die family, with a bigger
  design on it.
- **The RTL fix is therefore a quality improvement, not a blocker.** It can be
  done properly, with the full verification bar of section 7 and the hardware
  step that covers the PGS blind spot, rather than in a hurry to unblock a
  board.
- **What the ring still costs** is honesty: while it exists, every Artix
  board's WNS is a floor rather than a guarantee, and a netlist can land
  anywhere between 31 and 234 logic levels on the same source (measured: Nexys 31, QMTECH 49, Cmod 234 - section 3a; the "7" was never measured). The Cmod is the
  proof that "anywhere" includes unusable.

## 9. A constraint trap this project keeps falling into

Worth its own section because it has now cost three boards.

**Generated clocks do not exist when an XDC is read before synthesis.** The
QMTECH's `nd120_timing.xdc` guarded its `set_clock_groups` with
`get_clocks -quiet`; the guard found nothing, the else-branch ran, and no
clock relationship was applied at all. Every domain was internally clean and
the build still failed, on two paths given a 1.000 ns requirement.

The Nexys avoids this by applying clock relationships **in Tcl after
`synth_design`** (`fpga/nexys4ddr/build.tcl:439` onwards). The QMTECH now does
the same; its `nd120_timing.xdc` is deliberately almost empty and says why.

**And do not reach for `set_clock_groups -asynchronous` to fix it.** The Nexys
learned on 22-AUG-2026 that it leaves the `nds_sync` toggle-handshake PAYLOAD
buses completely untimed - the payload raced its toggle, FILSYS floppy reads
failed intermittently with status 020032 and finally hung. It also outranks
`set_max_delay`, so it cannot be softened afterwards. Use pairwise
`set_max_delay -datapath_only` bounded at one destination period.

Same family of error, opposite direction, on the Tang: a `.sdc` that was one
`create_clock` line described no crossing at all, its storage buses were timed
against a 0.000 ns requirement, and they were 24 of the 25 worst setup paths
in the build. Two lines took it from -260.076 ns over 398 endpoints to
-6.489 ns over 24.

## 10. Recommended order of work

1. **The RTL fix is no longer urgent.** The board that matters closes without
   it. Do it when it can be done to the section-7 bar, including the hardware
   step - nothing in simulation covers the PGS leg.
2. **Before any RTL work, try the section-5 false path on the Cmod.** It is
   measured and shipped on the Nexys, and it costs one build. It tells you
   whether the Cmod's -89.8 ns is the ring being cut badly or something else.
3. **If the RTL fix is done**, follow section 6, one change at a time,
   measured on at least three netlists (Nexys, MEGA65 R3 which is the most
   sensitive at 93 levels, and one small Artix part), and never judged by a
   single build's WNS. Note that section 2 means the target is **not** where
   `CGA.v` says it is.
4. **Fix the two gate-integrity defects in section 7 regardless.** They are
   independent of the ring and they weaken every future measurement.
5. **Correct the stale comment in `CGA.v:707-745`** and the false "zero
   LUTLP-1 / two false paths" claim in `fpga/nexys4ddr/build.tcl:496`. Both
   actively mislead.
