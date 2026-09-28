/****************************************************************************************
** ND120 - COMMITTED ACCESS TO A ZERO PAGE-TABLE ENTRY MUST DISPATCH A PAGE-FAULT TRAP  **
**                                                                                     **
** THE QUESTION (H1, PLAN-zero-read-nonresident-page.md, git 043c460): when a committed **
** MMU-translated access (VACC=1) reads a page-table entry whose permit bits are all    **
** zero (a non-resident page), does the RTL raise the page-fault trap and divert the    **
** microsequencer to trap vector 1 - or does the access complete and the CPU carry on?  **
** Measured on the Tang: the CPU executed ZEROS fetched at 064540..064547 where the     **
** oracle takes a FETCH page fault (PTe=0), pages the page in, and re-executes.         **
**                                                                                     **
** WHAT IS WIRED (all real modules, no mocks):                                          **
**   PAL_44601B (UCYCFSM) + PAL_44307C (UCYCLK)   - the real cycle machine, producing   **
**                                                  TERM/CC/UCLK/MACLK/ETRAP_n          **
**   TMM2018D_25                                  - the real PT status RAM model        **
**                                                  (CHIP_24G equivalent, sync read)    **
**   CGA_TRAP_BRKDET                              - PGF/BRK/TRAPN generation            **
**   CGA_TRAP_TVGEN (+_P2)                        - trap vector, TCLK(=UCLK)-registered **
**   CGA_MIC_IPOS                                 - the microaddress mux that a trap    **
**                                                  must force to MA = {9'b0, TVEC}     **
** Feedback is the real board feedback: BRKDET.BRKN -> the FSM's BRK_n input, and       **
** BRKDET.TRAPN -> PAL_44307C's TRAP_n input and IPOS's TRAPN input. TCLK = UCLK        **
** (CPU_PROC_CGA_33.v:269 wires XTCLK to UCLK).                                        **
**                                                                                     **
** WHAT IT ASSERTS. The PT address is applied at the START of the access cycle, so the  **
** sync RAM read is comfortably early - this is the WELL-TIMED case on purpose. (The    **
** address-changes-late stale case is PT_stale_read_tvec_tb.v's subject.) For each of   **
** FETCH / READ / WRITE to the zero entry:                                              **
**   1. TRAPN goes low while the fault condition stands, and                            **
**   2. at the microaddress-consuming edge (MACLK, which asserts in the TERM state)     **
**      IPOS outputs MA = 0001 octal = trap vector 1 (DELILAH page-fault vector),       **
**      not the normal next address.                                                    **
** A control access to a MAPPED entry (WPM|RPM|FPM set) must NOT trap and must leave    **
** MA = the normal next address.                                                        **
**                                                                                     **
** FAIL here = H1 confirmed at unit level (the chain cannot trap even when driven       **
** cleanly). PASS = the chain works when driven cleanly, and the boot-time fault is in  **
** what reaches it (map-RAM contents, VACC qualification, or arrival timing).           **
**                                                                                     **
** Build both ways (see Makefile targets test-pgf-committed / -ff):                     **
**   default          = latch-mode timing model                                        **
**   -DFPGA_FF_MODE   = the FPGA build's clock-enable capture in TVGEN_P2               **
**                                                                                     **
** Verdict: TB_RESULT: PASS / TB_RESULT: FAIL                                          **
**                                                                                     **
** Ronny Hansen                                                                        **
*****************************************************************************************/
`timescale 1ns / 1ps

module PGF_COMMITTED_ACCESS_tb;

  integer errors = 0;
  integer checks = 0;

  task ck;
    input          cond;
    input [1023:0] what;
    begin
      checks = checks + 1;
      // (cond !== 1'b1): an X comparison must FAIL loudly, not slip through
      // as pass - the first version of this bench measured exactly that.
      if (cond !== 1'b1) begin
        $display("FAIL: %0s", what);
        errors = errors + 1;
      end else begin
        $display("[ ok ] %0s", what);
      end
    end
  endtask

  // ------------------------------------------------------------------
  // Clocks (same scheme as CPU_CYCLE_TIMELINE_tb.v: sysclk fast, one
  // cycle state per OSC period)
  // ------------------------------------------------------------------
  reg sysclk = 1'b0;
  always #1 sysclk = ~sysclk;

  reg sys_rst_n = 1'b0;
  reg osc       = 1'b0;

  // ------------------------------------------------------------------
  // Cycle-machine inputs held at idle (no RWCS/LCS/FORM paths here)
  // ------------------------------------------------------------------
  reg rwcs_n     = 1'b1;
  reg form_n     = 1'b1;
  reg vex        = 1'b0;
  reg short_n    = 1'b1;
  reg slow_n     = 1'b1;
  reg dly0_n     = 1'b1;
  reg dly1_n     = 1'b1;
  reg csdelay0   = 1'b0;
  reg wait1      = 1'b0;
  reg wait2      = 1'b0;
  reg cgntcact_n = 1'b1;
  reg hit        = 1'b0;

  // ------------------------------------------------------------------
  // The access under test (what the CGA decode would drive)
  // ------------------------------------------------------------------
  reg        vacc   = 1'b0;  // committed MMU-translated reference
  reg        ifetch = 1'b0;
  reg        iwrite = 1'b0;
  reg        iind   = 1'b0;
  reg  [1:0] ipcr   = 2'b00; // ring 0, so only PGF (no ring-down/ring-violation terms)
  reg        poni   = 1'b1;  // paging on
  reg [10:0] pt_la  = 11'd0; // PT index driven at the RAM

  // ------------------------------------------------------------------
  // The real cycle-control hardware
  // ------------------------------------------------------------------
  wire cx_n, term_n, cc0_n, cc1_n, cc2_n, cc3_n;
  wire brk_n_from_cga;   // BRKDET.BRKN feeds the FSM, as on the board
  wire trapn_from_cga;   // BRKDET.TRAPN feeds PAL_44307C and IPOS

  PAL_44601B UCYCFSM (
      .CK        (osc),
      .OE_n      (1'b0),
      .DLY1_n    (dly1_n),
      .DLY0_n    (dly0_n),
      .CSDELAY0  (csdelay0),
      .WAIT1     (wait1),
      .WAIT2     (wait2),
      .CGNTCACT_n(cgntcact_n),
      .HIT       (hit),
      .BRK_n     (brk_n_from_cga),
      .SLOW_n    (slow_n),
      .SHORT_n   (short_n),
      .CX_n      (cx_n),
      .TERM_n    (term_n),
      .CC0_n     (cc0_n),
      .CC1_n     (cc1_n),
      .CC2_n     (cc2_n),
      .CC3_n     (cc3_n)
  );

  wire mclk_n, maclk_n, wrfstb, cyd, eorf_n, uclk, etrap_n, map_n;

  PAL_44307C UCYCLK (
      .TERM_n (term_n),
      .CC0_n  (cc0_n),
      .CC1_n  (cc1_n),
      .CC2_n  (cc2_n),
      .CC3_n  (cc3_n),
      .FORM_n (form_n),
      .BRK_n  (brk_n_from_cga),
      .RWCS_n (rwcs_n),
      .TRAP_n (trapn_from_cga),
      .VEX    (vex),
      .MCLK_n (mclk_n),
      .MACLK_n(maclk_n),
      .WRFSTB (wrfstb),
      .CYD    (cyd),
      .EORF_n (eorf_n),
      .UCLK   (uclk),
      .ETRAP_n(etrap_n),
      .MAP_n  (map_n)
  );

  // Exactly how CYC_36.v combines them (CYC_36.v:173-176 of the timeline tb)
  wire maclk = ~(term_n & maclk_n);

  // ------------------------------------------------------------------
  // PT status RAM (CHIP_24G equivalent): D_OUT[7:1] = PT bits 15..9
  // ------------------------------------------------------------------
  reg        pt_cs_n = 1'b0;
  reg        pt_w_n  = 1'b1;
  reg  [7:0] pt_wdata = 8'h00;
  wire [7:0] pt_dout;

  TMM2018D_25 #(.INSTANCE_NAME("CHIP_24G")) CHIP_24G (
      .clk(sysclk), .reset_n(sys_rst_n),
      .ADDRESS(pt_la), .CS_n(pt_cs_n), .D(pt_wdata), .D_OUT(pt_dout),
      .OE_n(1'b0), .W_n(pt_w_n)
  );

  wire [6:0] ipt = pt_dout[7:1];   // PT15..PT9

  // ------------------------------------------------------------------
  // Trap request (BRKDET) - the real PGF/BRK/TRAPN terms
  // ------------------------------------------------------------------
  CGA_TRAP_BRKDET BRKDET (
      .CBRKN(1'b1),
      .ETRAPN(etrap_n),
      .FTRAPN(1'b1),
      .IFETCH(ifetch), .IFETCHN(~ifetch),
      .IINDN(~iind),
      .INTRQ(1'b0),
      .IPCR_1_0(ipcr), .IPCR_1_0_N(~ipcr),
      .IPT_15_9(ipt), .IPT_15_9_N(~ipt),
      .IWRITE(iwrite), .IWRITEN(~iwrite),
      .VACC(vacc),
      .VTRAPN(1'b1),
      .BRKN(brk_n_from_cga),
      .TRAPN(trapn_from_cga)
  );

  // ------------------------------------------------------------------
  // Trap vector generator; TCLK = UCLK (CPU_PROC_CGA_33.v:269)
  // ------------------------------------------------------------------
  reg  uclk_d = 1'b0;
  always @(posedge sysclk) uclk_d <= uclk;
  wire tclk_en = uclk & ~uclk_d;   // 1-sysclk pulse on the UCLK rise (FF mode)

  wire       pviol, restr;
  wire [3:0] tvec;

  CGA_TRAP_TVGEN TVGEN (
      .sysclk(sysclk), .TCLK_EN(tclk_en),
      .DSTOPN(1'b1), .FTRAPN(1'b1),
      .IFETCH(ifetch), .IFETCHN(~ifetch),
      .IIND(iind), .IINDN(~iind),
      .INTRQ(1'b0),
      .IPCR_1_0(ipcr), .IPCR_1_0_N(~ipcr),
      .IPT_15_9(ipt), .IPT_15_9_N(~ipt),
      .IWRITE(iwrite), .IWRITEN(~iwrite),
      .PAN(1'b1), .PONI(poni),
      .TCLK(uclk), .VACC(vacc), .VTRAPN(1'b1),
      .PVIOL(pviol), .RESTR(restr), .TVEC_3_0(tvec)
  );

  // ------------------------------------------------------------------
  // The microaddress mux a trap must capture
  // ------------------------------------------------------------------
  localparam [12:0] W_NEXT = 13'o1234;  // the "normal next" microaddress

  wire [12:0] ma;

  CGA_MIC_IPOS IPOS (
      .CD_15_0(16'd0),
      .EWCAN(1'b1),
      .MAPN(1'b1),
      .TRAPN(trapn_from_cga),
      .TVEC_3_0(tvec),
      .WCA_12_0(13'd0),
      .W_12_0(W_NEXT),
      .MA_12_0(ma)
  );

  // ------------------------------------------------------------------
  // Observation - two sampling points, matching the measured mechanism:
  //
  //  * The TRAP consumption is the MID-CYCLE MACLK strobe. It cannot be
  //    the TERM state, because ETRAP_n = ~(TERM_n & VEX_n & CC!=0)
  //    (PAL_44307C.v) disables traps whenever TERM is asserted - this
  //    bench MEASURED TRAPN back high and MA back to the normal address
  //    by the TERM state of a faulting cycle. So the fault verdict is
  //    taken at a posedge of MACLK that occurs while TRAPN is low.
  //
  //  * The NORMAL next-address verdict is taken in the TERM state,
  //    where maclk = ~(term_n & maclk_n) is high by construction.
  // ------------------------------------------------------------------
  reg [12:0] ma_at_trap;      // MA at a MACLK strobe with TRAPN low
  reg [3:0]  tvec_at_trap;
  reg        trap_maclk_seen; // such a strobe occurred
  reg [12:0] ma_at_term;      // MA sampled in the TERM state

  // Level-sampled on sysclk, not on the MACLK posedge event: MACLK and
  // ETRAP_n are outputs of the SAME PAL and move in the same simulation
  // delta, so "TRAPN at the posedge instant" is a delta-ordering race
  // (measured: the edge-conditioned sampler never fired at all). MACLK
  // stays high for several sysclks, so a level sample is race-free.
  always @(posedge sysclk) begin
    if (maclk && !trapn_from_cga) begin
      ma_at_trap      <= ma;
      tvec_at_trap    <= tvec;
      trap_maclk_seen <= 1'b1;
    end
  end

  reg trapn_seen_low;
  always @(negedge trapn_from_cga) trapn_seen_low <= 1'b1;

  // ------------------------------------------------------------------
  // Cycle-machine helpers (same as CPU_CYCLE_TIMELINE_tb.v)
  // ------------------------------------------------------------------
  task osc_tick;
    begin
      osc = 1'b0; #4;
      osc = 1'b1; #4;
    end
  endtask

  task cyc_init;
    begin
      force UCYCFSM.TERM_reg = 1'b0;
      force UCYCFSM.CC0_reg  = 1'b0;
      force UCYCFSM.CC1_reg  = 1'b0;
      force UCYCFSM.CC2_reg  = 1'b0;
      force UCYCFSM.CC3_reg  = 1'b0;
      osc_tick;
      release UCYCFSM.TERM_reg;
      release UCYCFSM.CC0_reg;
      release UCYCFSM.CC1_reg;
      release UCYCFSM.CC2_reg;
      release UCYCFSM.CC3_reg;
    end
  endtask

  task run_to_term;
    integer guard;
    begin
      guard = 0;
      while (term_n && guard < 64) begin
        osc_tick;
        guard = guard + 1;
      end
    end
  endtask

  // Walk one full microcycle (to and through its TERM state), sampling the
  // microaddress consumption in the TERM state (see Observation note above).
  task walk_one_cycle;
    integer guard;
    reg     done;
    begin
      done = 1'b0;
      if (!term_n) osc_tick;   // consume the standing TERM edge
      for (guard = 0; guard < 64 && !done; guard = guard + 1) begin
        osc_tick;
        if (!term_n) begin
          done       = 1'b1;
          ma_at_term = ma;
        end
      end
    end
  endtask

  // ------------------------------------------------------------------
  // PT entries used
  // ------------------------------------------------------------------
  localparam [10:0] LA_FAULT  = 11'o0032;      // the zero (non-resident) entry
                                               // - explicitly WRITTEN as zero:
                                               // an unwritten TMM2018D address
                                               // reads X in iverilog (no BRAM
                                               // init), and the X poisoned
                                               // BRK_n and the whole cycle FSM
                                               // in the first runs of this tb
  localparam [10:0] LA_MAPPED = 11'o0033;      // fully resident entry, ring 0
  // D[7:1] = PT15..PT9 = WPM,RPM,FPM,WIP,PGU,ring1,ring0. WIP and PGU must be
  // SET on the control entry: BRKDET's A02_2 fires the PGU bookkeeping break
  // on any committed access to a page with PGU=0 (first run of this bench
  // measured exactly that on a WPM|RPM|FPM-only entry), and A02_1 fires the
  // WIP break on a write with WIP=0.
  localparam [7:0]  E_MAPPED  = 8'b1111_1000;

  // One access scenario: present the access at a cycle boundary, walk the
  // cycle, judge at its MACLK edge.
  task access;
    input [10:0]   la;
    input          a_fetch, a_write;
    input          expect_trap;
    input [1023:0] label;
    begin
      run_to_term;
      // present the PT index FIRST and let the sync RAM read settle before
      // raising VACC. First run of this bench proved why: raising VACC in the
      // same instant as the address change let the RAM's one-clock-stale
      // D_OUT (still holding the PREVIOUS entry) meet VACC=1, and a MAPPED
      // control access fired a spurious PGF for that one clock. That ordering
      // sensitivity is the real machine's stale-read hazard showing up in the
      // bench; the WELL-TIMED contract this bench tests is data-before-VACC.
      pt_la          = la;
      @(posedge sysclk); @(posedge sysclk); @(posedge sysclk);
      ifetch          = a_fetch;
      iwrite          = a_write;
      vacc            = 1'b1;
      trapn_seen_low  = 1'b0;
      trap_maclk_seen = 1'b0;
      walk_one_cycle;
      if (expect_trap) begin
        ck(trapn_seen_low, {label, " : TRAPN asserted during the access"});
        ck(trap_maclk_seen, {label, " : a MACLK strobe fired while TRAPN was low"});
        ck(tvec_at_trap == 4'd1, {label, " : TVEC=1 (page fault) at that strobe"});
        ck(ma_at_trap == 13'o0001, {label, " : MA forced to trap vector 0001 at that strobe"});
      end else begin
        ck(!trapn_seen_low, {label, " : no trap asserted"});
        ck(ma_at_term == W_NEXT, {label, " : MA = normal next address at TERM"});
      end
      // withdraw the access
      vacc   = 1'b0;
      ifetch = 1'b0;
      iwrite = 1'b0;
      walk_one_cycle;
    end
  endtask

  integer k;

  initial begin
    sys_rst_n = 1'b0;
    for (k = 0; k < 8; k = k + 1) @(posedge sysclk);
    sys_rst_n = 1'b1;
    for (k = 0; k < 8; k = k + 1) @(posedge sysclk);

    // write the mapped control entry into the PT RAM
    pt_la = LA_MAPPED; pt_wdata = E_MAPPED; pt_w_n = 1'b0;
    @(posedge sysclk); @(posedge sysclk);
    pt_w_n = 1'b1;
    @(posedge sysclk);
    // and write the non-resident entry as an explicit ZERO
    pt_la = LA_FAULT; pt_wdata = 8'h00; pt_w_n = 1'b0;
    @(posedge sysclk); @(posedge sysclk);
    pt_w_n = 1'b1;
    @(posedge sysclk);

    cyc_init;
    for (k = 0; k < 6; k = k + 1) osc_tick;

`ifdef FPGA_FF_MODE
    $display("== committed access to a zero PT entry (FPGA_FF_MODE) ==");
`else
    $display("== committed access to a zero PT entry (latch mode) ==");
`endif

    // control first: a mapped page must not trap
    access(LA_MAPPED, 1'b1, 1'b0, 1'b0, "CONTROL mapped FETCH");

    // the three access classes against the zero entry - all must trap
    access(LA_FAULT, 1'b1, 1'b0, 1'b1, "FETCH  PTe=0");
    access(LA_FAULT, 1'b0, 1'b0, 1'b1, "READ   PTe=0");
    access(LA_FAULT, 1'b0, 1'b1, 1'b1, "WRITE  PTe=0");

    // and the control again, to prove the trap state does not stick
    access(LA_MAPPED, 1'b1, 1'b0, 1'b0, "CONTROL mapped FETCH (after faults)");

    $display("");
    if (errors == 0) $display("TB_RESULT: PASS (%0d checks)", checks);
    else             $display("TB_RESULT: FAIL (%0d checks, %0d errors)", checks, errors);
    $finish;
  end

endmodule
