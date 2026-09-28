# Multicycle proof: LAA_REG/LBA_REG -> WCS address pins (Nexys, FF mode)

Written 30-AUG-2026, from static reading of the RTL only. No sim was run for
this document; the one thing that still wants a sim check is listed at the
end. All file references are the evidence; read them before doubting a step.

## The question

Build 10 (clk=45, 22 ns) failed with the worst path

```
From: CORE/CPU_BOARD/CPU/PROC/CGA/DELILAH/MIC/LAA_REG/gen_enable.q_r_reg[2]_replica_5/C
To:   CORE/CPU_BOARD/CPU/CS/WCS/CHIP_26D/idt_memory_array_reg/ADDRARDADDR[11]
27.986 ns, 36 logic levels, route 72%
```

How many clk_cpu cycles does the machine really give this path?

## The clocking model (FF mode, what the FPGA builds)

Everything below runs on one clock. OSC == sysclk == clk_cpu on the FPGA -
stated and enforced in
Verilog/CPU-BOARD-3202/circuit/IO_DCD_38.v:367-373
("drive OSC straight from that clean net so OSC == sysclk == clk_cpu"), and
Verilog/ND120_TOP.v:404 (assign clk1 = clk_cpu).

The microcycle is sequenced by PAL_44601B (the CC0-CC3 FSM), clocked on OSC
(Verilog/CPU-BOARD-3202/circuit/CYC_36.v:382-408).
Its TERM register is set for EXACTLY ONE clk_cpu cycle per microcycle and
then self-clears
(Verilog/PAL/PAL_44601B.v:113-127: the whole
TERM equation is guarded by "if (s_term_n_int) ... else TERM_reg <= 1'b0").
Cycle length varies ONLY in the number of states BEFORE the TERM pulse:

| cycle type              | states before TERM (CC values)     | total clk_cpu |
|-------------------------|------------------------------------|---------------|
| SHORT "50 ns"           | 0000                               | 2             |
| "75 ns" (SHORT/HIT)     | 0000, 0001                         | 3             |
| "100 ns"                | 0000, 0001, 0011                   | 4             |
| SLOW / FE               | ... through CC2 states             | 7+            |
| BRK (>200 ns)           | ... through 0111                   | 8+            |
| UART / LCS / RWCS       | ... through CC3 states             | 8+            |

(state sequence and TERM product terms: PAL_44601B.v:113-127, with the
original listing comments naming each cycle length.)

The derived clocks (all from CYC_36.v):

- MCLK = ~(TERM_n & MCLK_n), and MCLK_n has ONLY RWCS product terms
  (Verilog/PAL/PAL_44307C.v:96-99 and the naming
  comment at :46-53). So outside a RWCS cycle, MCLK == TERM: ONE rise per
  microcycle, entering the TERM pulse. During RWCS, MCLK is stretched high
  through the CC3_n/CC2 states and its single rise is at the start of the
  RWCS microcycle, in state a (0000).
- MACLK = ~(TERM_n & MACLK_n); MACLK_n asserts extra windows only for
  MAP (states e+f), TRAP (d+e) and RWCS (CC3_n states)
  (PAL_44307C.v:127-132). Plain cycles: MACLK == TERM, one 1-clk window.
- In FF mode these are phase-accurate registered levels plus one-clk enables
  (CYC_36.v:191-321); MCLK_EN is high during exactly the cycle whose
  closing posedge is the MCLK rise.

## The three events

**(1) Launch.** LAA_REG (and its twin LBA_REG) are R41P_EN registers
with EN = MCLK_EN
(Verilog/DELILAH-CPU/CGA_MIC/circuit/CGA_MIC.v:1038,1102;
FF implementation
Verilog/Shared/ndlib/R41P_EN.v:40-49, which is
where the "gen_enable.q_r_reg" name in the timing report comes from). They
capture ONLY on the MCLK rise. Call that posedge t. From the clock model
above, the cycle [t, t+1) is either the TERM pulse (all non-RWCS cycles) or
state a=0000 (the RWCS stretch, whose rise is in state a).

**(2) Capture.** The WCS is 32 BRAMs
(Verilog/CPU-BOARD-3202/circuit/CPU_CS_WCS_21_22.v,
chips CHIP_16C..31D, model
Verilog/Shared/support/IDT6168A_20.v:104-127):
the address pin is sampled at EVERY posedge, data out one cycle later. But
the address only MOVES while the ACAL latches are transparent, and they are
transparent only while MACLK is high
(Verilog/CPU-BOARD-3202/circuit/CPU_CS_ACAL_17.v:150-170:
hold-FF plus pass-through mux on s_maclk). So the address captures that
can ever carry NEW data are the posedges that close a MACLK-high cycle:

- end of the TERM pulse (every cycle type) = t+1,
- ends of states d/e (TRAP window) and e/f (MAP window) = t+5 .. t+7,
- every edge inside the RWCS stretch = t+1, t+2, ...

**(3) Consumption.** The BRAM output register IS the microinstruction
register - CSBITS fans out combinationally into the CGA with no register in
between
(Verilog/CPU-BOARD-3202/circuit/CPU_PROC_CGA_33.v:126
onward is pure assigns). Whatever the address pins sample gets executed. So
the constraint question is purely: which address captures at t+1 can depend
on data launched at t?

## Why every 1-cycle capture is masked

The address the BRAMs sample is MA_12_0 from the IPOS mux
(Verilog/DELILAH-CPU/CGA_MIC/circuit/CGA_MIC_IPOS.v:96-141),
a 4-way mux per bit:

| sel | source   | reaches it from LAA/LBA_REG? |
|-----|----------|------------------------------|
| 0   | W_12_0   | no - regW passes regREP (a plain sysclk register, CGA_MIC_MASEL.v:141-143) or regIW (MCLK_EN register, :174-181). Both registered; neither is in the -from set. |
| 1   | WCA_12_0 | no - WCAREG is MCLK_EN-registered (CGA_MIC_WCAREG.v:47-53). |
| 2   | CD_15_0  | possibly (memory/IDB data) - selected only when MAPN=0. |
| 3   | TVEC_3_0 | yes - THE failing route: LAA_REG -> WRF -> ALU -> TVGEN/BRKDET -> TVEC. Selected only when TRAPN=0. |

and the mux SELECTS are built from TRAPN, MAPN, EWCAN. The dangerous
data (TVEC) and the dangerous select influence (BRK_n -> MAP) are both
fenced off during exactly the two cycle states that can close a 1-cycle
capture:

- **Trap fence.** ETRAP_n = ~(TERM_n & VEX_n & (CC3|CC2|CC1|CC0))
  (PAL_44307C.v:134-139, original comment: "ENABLE TRAPS ONLY OUTSIDE t OR
  a - UNSTABLE TRAP IN THIS PERIOD CAN DESTROY MA !"). During the TERM pulse
  TERM_n=0, and in state a all CC bits are 0 - either way ETRAP_n=1.
  TRAPN = BRK_n | CBRK | ETRAP_n
  (Verilog/DELILAH-CPU/CGA_TRAP/circuit/CGA_TRAP_BRKDET.v:256-263,
  GATES_16, NAND with all-inverted inputs). ETRAP_n=1 forces TRAPN=1 no
  matter what the ALU is doing: TVEC deselected, the IPOS selector pinned.
  The 1988 designers built this fence for exactly this hazard; we are
  re-using their proof.
- **MAP fence.** MAP_n = ~(FORM & BRK_n & CC2 & TERM_n)
  (PAL_44307C.v:124). TERM_n=0 (TERM pulse) or CC2=0 (state a) forces
  MAP_n=1: the CD branch is deselected and the ALU-derived BRK_n cannot move
  the selector. (The listing comment "MUST NOT COME BEFORE ALL SHORT CYCLES"
  is the same statement from the other side: MAP dispatch waits for states
  that short cycles do not have.)
- **UUA side (CHIP_31G / CSCA route).** UUA[9:0] can also come from CSCA via
  the 31G latch, whose enable is CLK (=TERM level)
  (CPU_CS_ACAL_17.v:168-170) - so its captures are all end-of-TERM. CSCA
  is MCA from the MAC, and MCA is an L8 latch of ICA transparent only while
  MCLK is LOW
  (Verilog/DELILAH-CPU/CGA_MAC/circuit/CGA_MAC_APOS_CALCA.v:214
  onward, .L(s_mclk_n), header comment "MCA source is ICA, and is latched on
  posedge on MCLK"). During TERM, MCLK is high, the latch holds, and the
  live route from the datapath is closed at every 31G capture.

The fence signals themselves (TERM_reg, CC regs -> ETRAP_n/MAP_n ->
selector) are short single-cycle paths from the FSM registers and are NOT in
the -from set, so they stay fully timed.

**Captures at spacing 2 are real.** In an RWCS cycle MACLK is high through
the CC3_n states, and from state b (0001) onward the trap fence is open; a
capture at t+2 that depends on the t launch cannot be ruled out. So the
exception must not exceed 2.

## Derived N

**set_multicycle_path 2 (setup), 1 (hold), from {LAA_REG, LBA_REG} to the
control-store address endpoints.** Every capture at launch+1 is masked by
the machine's own trap/MAP fences; captures at launch+2 exist and are still
fully timed by the constraint. The matching -hold 1 moves the hold check
back to the launch edge (the default relationship), so hold closure is
unchanged.

Destinations covered (all on the LUA/UUA address side of the same route):

- WCS BRAM address pins (CHIP_* / idt_memory_array_reg* / ADDR*),
- PROM BRAM address pins (rom_lo / rom_hi in CPU_CS_PROM_19.v - same LUA
  address, only read during microcode load, same fences),
- the ACAL hold FFs fed from CSA (r_chip30h_hold, r_lua_9_0_hold,
  r_uua_32g_hold in CPU_CS_ACAL_17.v) - they capture on the same
  MACLK-window edges as the BRAM pins and would otherwise become the new
  worst endpoints. The CSCA-fed r_uua_31g_hold is NOT included (different
  source route).

Sources deliberately NOT included, and why:

- regREP / regW / regIW (MIC/MASEL): genuinely single-cycle. This is
  the microcode-JUMP route whose same-cycle transparency is load-bearing - a
  1-cycle lag here was the Tang o06000 boot hang (CPU_CS_ACAL_17.v history
  block). Relaxing it corrupts the machine.
- WRF register file outputs: REJECTED. WRF write strobes fire in state b
  (WRFSTB, PAL_44307C.v:102), so a WRF launch can be 1 clk before an
  open RWCS capture window with the trap fence already open - the +1 masking
  proof does not hold for them. If they surface as the next worst source
  they need their own analysis, not a copy of this exception.
- ALUCLK-domain registers (ALU Q/F/flags): their enable is TERM-aligned like
  MCLK, so the same proof likely holds, but I have not walked their extra
  routes (CSEL/SC5/SC6 feed regREP_comb every cycle). Left out; add only
  with the route walk done.

## Why this was never done before (timing.md lines 91-99)

Verilog/fpga/nexys4ddr/timing.md says a multicycle was "not done,
deliberately" because the old Tang "52 ns WCS->ACAL" idea had no RTL proof
and 45-50 MHz closed without it. Both halves were right: a blanket
WCS->ACAL or ACAL->WCS multicycle would be WRONG (the regREP jump route is
truly single-cycle - relaxing it re-creates the Tang o06000 hang class), and
the cache-off build did close 22 ns without any exception (WNS +0.020 with
physopt). Build 10 is a different netlist (the cache work); the added logic
pushed this one family to 27.986 ns. This document is the missing RTL proof,
and it is deliberately narrower than the Tang idea: source-scoped to the two
MCLK_EN operand-address registers.

## What this does NOT fix

Build 10 reports 4248 failing endpoints; only the subset from LAA/LBA_REG to
the CS address pins is relieved here. The OTHER known family
(WCS output -> CSIDBS decode -> ALU -> ALUCLK_EN -> WRF CE fanout,
timing.md lines 47-68) is genuinely single-cycle (the microword decides
within its own cycle whether the WRF clocks at its end) and gets no
exception from this work.

## Not established statically - how to settle it

1. **The one load-bearing claim without a sim measurement:** that every
   MCLK rise is immediately followed by a cycle in which the machine is in
   TERM or state a (equivalently: at every posedge that closes a MACLK-high
   cycle exactly 1 clk after MCLK_EN, TRAPN==1 and MAP_n==1). Derived from
   the PAL equations above; a cheap check is an assertion in a CYC_36
   testbench, or one run of the existing cycle-timeline tb
   (CPU-BOARD-3202/circuit/sim, make test-cycle-timeline) extended with
   that predicate over a full runSim boot. Not run here (no-sim rule for
   this task).
2. RWCS cycles under a simultaneous trap: I claim spacing-2 captures are
   possible there and sized N accordingly (the conservative direction). A
   trace of TRAPN during RWCS would show whether even those exist.
3. Whether LAA/LBA -> ICA -> MCA(L8) -> MAC endpoints (not constrained
   here) are anywhere near failing. They did not appear as the worst path;
   if they show up they are a separate family.
