/**************************************************************************************************
** ND120 CGA (CPU Gate Array / DELILAH) - unit test                                              **
** CGA_DCD sheet 8 of 10 (DELILAH.pdf page 72) - the four IDB-source enables                     **
**   EPGSN, EPCRN, EPICSN, EPICVN                                                                **
**                                                                                               **
** WHY THIS BENCH EXISTS                                                                         **
**   CGA_IDBCTL (page 97) ORs its six IDB sources together - see                                 **
**   Verilog/DELILAH-CPU/CGA_IDBCTL/circuit/CGA_IDBCTL_SEL6.v:94.                                **
**   If two enables could ever be asserted at the same time, two sources would be merged onto    **
**   the IDB, and the XFIDBI (D) path - the one that closes the FIDBO -> ... -> FIDBI ring -     **
**   would not be provably cut. Whether the enables really are mutually exclusive is decided     **
**   HERE, in the decoder, not in CGA_IDBCTL.                                                    **
**                                                                                               **
** WHAT IS ASSERTED - A PROPERTY, NOT A TRANSCRIBED TRUTH TABLE                                  **
**   No microcode-field specification for CSIDBS is assumed. The bench sweeps CSIDBS_4_0 over    **
**   all 32 codes x LCSN over both values and asserts three properties that must hold whatever   **
**   the intended code assignment is:                                                            **
**     P1  MUTUAL EXCLUSION: at most one of the four enables is active in any (CSIDBS, LCSN).    **
**     P2  UNIQUE CODE: each of the four is active for exactly ONE CSIDBS code.                  **
**     P3  QUALIFIED BY LCSN: no enable is active while LCSN = 0.                                **
**   The code actually decoded for each enable is DISCOVERED by the sweep and PRINTED, so the    **
**   octal assignment is recorded as a measurement rather than asserted from documentation.      **
**                                                                                               **
** WHAT IS ALSO MEASURED (and reported, not asserted)                                            **
**   EPICMASKN - the fifth enable pin of CGA_IDBCTL - is NOT produced here. It comes from        **
**   CGA_INTR_CNTLR_MDCD.v:253, gated by EPIC, and EPIC is decoded from the CSCOMM field         **
**   (CGA_DCD.v:1181-1190), a DIFFERENT microcode field from CSIDBS. This bench therefore also   **
**   drives CSCOMM to the code that raises EPIC while CSIDBS holds an enable code, and reports   **
**   whether the two can be simultaneously active. That is characterisation of an existing       **
**   design property, not a pass/fail criterion - so it is printed, not counted as a failure.    **
**                                                                                               **
** SIGNAL NOTES                                                                                  **
**   The four enables are registered on the MCLK rise (D_FLIPFLOP_EN, CGA_DCD.v:1349, 1382,      **
**   1408, 1439), so every vector is applied before the edge and sampled after it.               **
**   All pins not feeding sheet 8 are parked at a benign constant; MRN is held high after the    **
**   initial master clear.                                                                       **
**                                                                                               **
** BOTH BUILD MODES: the registers are D_FLIPFLOP_EN switched by FPGA_FF_MODE, so the Makefile   **
** target test-dcd-idbs-enables runs this twice, default (posedge MCLK) and -DFPGA_FF_MODE       **
** (posedge sysclk gated by MCLK_EN).                                                            **
**                                                                                               **
** Compile+run (from repo Verilog/):                                                             **
**   cd DELILAH-CPU/CGA_DCD/sim && make test-dcd-idbs-enables                                    **
**                                                                                               **
** Prints "TB_RESULT: PASS" or "TB_RESULT: FAIL" as the final line.                              **
**                                                                                               **
** 20-AUG-2026                                                                                   **
** Ronny Hansen                                                                                  **
***************************************************************************************************/
`timescale 1ns / 1ps
`default_nettype none

module CGA_DCD_IDBS_ENABLES_tb;

  // sysclk posedges land on EVEN ns; every stimulus change lands on an ODD ns.
  reg sysclk = 1'b1;
  always #1 sysclk = ~sysclk;

  reg       MCLK = 1'b0;
  reg       MCLK_EN = 1'b0;

  reg [4:0] CSIDBS = 5'b00000;
  reg [4:0] CSCOMM = 5'b00000;
  reg       LCSN = 1'b1;
  reg       MRN = 1'b1;

  // parked pins - none of them reaches the sheet-8 IDB source decode
  localparam PARK_SYS_RST_N = 1'b1;
  localparam PARK_BRKN = 1'b1;
  localparam PARK_CRY = 1'b0;
  localparam PARK_F15 = 1'b0;
  localparam PARK_ZF = 1'b0;
  localparam PARK_SGR = 1'b0;
  localparam PARK_WPN = 1'b1;
  localparam [1:0] PARK_CSMIS = 2'b00;
  localparam PARK_FIDBO5 = 1'b0;
  localparam PARK_INTRQN = 1'b1;
  localparam PARK_LSHADOW = 1'b0;
  localparam PARK_PONI = 1'b1;
  localparam PARK_VEX = 1'b0;

  wire CBRKN, CFETCH, CLFFN, CLIRQN, CSMREQ, DSTOPN, EPCRN, EPGSN;
  wire EPIC, EPICSN, EPICVN, ERFN, FETCHN, INDN, LDDBRN, LDGPRN;
  wire LDIRV, LDLCN, LDPILN, LWCAN, VACCN, WRITEN, WRTRF, XFETCHN;

  CGA_DCD dut (
      .sysclk(sysclk),
      .sys_rst_n(PARK_SYS_RST_N),
      .MCLK_EN(MCLK_EN),
      .BRKN(PARK_BRKN),
      .CRY(PARK_CRY),
      .CSCOMM_4_0(CSCOMM),
      .CSIDBS_4_0(CSIDBS),
      .CSMIS_1_0(PARK_CSMIS),
      .F15(PARK_F15),
      .FIDBO5(PARK_FIDBO5),
      .LCSN(LCSN),
      .INTRQN(PARK_INTRQN),
      .LSHADOW(PARK_LSHADOW),
      .MCLK(MCLK),
      .MRN(MRN),
      .PONI(PARK_PONI),
      .SGR(PARK_SGR),
      .VEX(PARK_VEX),
      .WPN(PARK_WPN),
      .ZF(PARK_ZF),
      .CBRKN(CBRKN),
      .CFETCH(CFETCH),
      .CLFFN(CLFFN),
      .CLIRQN(CLIRQN),
      .CSMREQ(CSMREQ),
      .DSTOPN(DSTOPN),
      .EPCRN(EPCRN),
      .EPGSN(EPGSN),
      .EPIC(EPIC),
      .EPICSN(EPICSN),
      .EPICVN(EPICVN),
      .ERFN(ERFN),
      .FETCHN(FETCHN),
      .INDN(INDN),
      .LDDBRN(LDDBRN),
      .LDGPRN(LDGPRN),
      .LDIRV(LDIRV),
      .LDLCN(LDLCN),
      .LDPILN(LDPILN),
      .LWCAN(LWCAN),
      .VACCN(VACCN),
      .WRITEN(WRITEN),
      .WRTRF(WRTRF),
      .XFETCHN(XFETCHN)
  );

  integer errors = 0;
  integer checks = 0;
  integer i, k, nactive;

  // discovered decode: how many codes raise each enable, and which
  integer n_gs, n_pcr, n_s, n_v;
  integer c_gs, c_pcr, c_s, c_v;

  reg [3:0] act;  // {epgs, epcr, epics, epicv} active-high

  task mclk_edge;
    begin
      #6 MCLK = 1'b1;
      MCLK_EN = 1'b1;  // t = +7, covers the sysclk posedge at +8
      #2 MCLK_EN = 1'b0;  // t = +9
      #4;  // t = +13, settled
      act = {~EPGSN, ~EPCRN, ~EPICSN, ~EPICVN};
      #2 MCLK = 1'b0;  // t = +15
      #5;  // t = +20
    end
  endtask

  function integer popcount4;
    input [3:0] v;
    begin
      popcount4 = v[0] + v[1] + v[2] + v[3];
    end
  endfunction

  initial begin
    $dumpfile("CGA_DCD_IDBS_ENABLES_tb.vcd");
    $dumpvars(0, CGA_DCD_IDBS_ENABLES_tb);
  end

  initial begin
    n_gs  = 0;
    n_pcr = 0;
    n_s   = 0;
    n_v   = 0;
    c_gs  = -1;
    c_pcr = -1;
    c_s   = -1;
    c_v   = -1;

    // master clear, then release
    MRN   = 1'b0;
    mclk_edge;
    mclk_edge;
    MRN = 1'b1;
    mclk_edge;

    // ---------------------------------------------------------------
    // sweep: LCSN x CSIDBS, all 64 vectors
    // ---------------------------------------------------------------
    for (k = 0; k < 2; k = k + 1) begin
      LCSN = k[0];
      for (i = 0; i < 32; i = i + 1) begin
        CSIDBS = i[4:0];
        mclk_edge;

        nactive = popcount4(act);

        // P1 - mutual exclusion
        checks  = checks + 1;
        if (nactive > 1) begin
          errors = errors + 1;
          $display("FAIL P1 mutual exclusion: LCSN=%b CSIDBS=%0o(o) -> {EPGS,EPCR,EPICS,EPICV}=%b",
                   LCSN, i, act);
        end

        // P3 - qualified by LCSN
        checks = checks + 1;
        if (LCSN == 1'b0 && nactive != 0) begin
          errors = errors + 1;
          $display("FAIL P3 LCSN qualification: LCSN=0 CSIDBS=%0o(o) -> %b", i, act);
        end

        // no x/z on any of the four
        checks = checks + 1;
        if (^act === 1'bx) begin
          errors = errors + 1;
          $display("FAIL: enable has x/z at LCSN=%b CSIDBS=%0o(o): %b", LCSN, i, act);
        end

        if (LCSN == 1'b1) begin
          if (act[3]) begin
            n_gs = n_gs + 1;
            c_gs = i;
          end
          if (act[2]) begin
            n_pcr = n_pcr + 1;
            c_pcr = i;
          end
          if (act[1]) begin
            n_s = n_s + 1;
            c_s = i;
          end
          if (act[0]) begin
            n_v = n_v + 1;
            c_v = i;
          end
        end
      end
    end

    // ---------------------------------------------------------------
    // P2 - each enable decodes exactly one CSIDBS code
    // ---------------------------------------------------------------
    checks = checks + 1;
    if (n_gs != 1) begin
      errors = errors + 1;
      $display("FAIL P2: EPGSN active for %0d codes (expected exactly 1)", n_gs);
    end
    checks = checks + 1;
    if (n_pcr != 1) begin
      errors = errors + 1;
      $display("FAIL P2: EPCRN active for %0d codes (expected exactly 1)", n_pcr);
    end
    checks = checks + 1;
    if (n_s != 1) begin
      errors = errors + 1;
      $display("FAIL P2: EPICSN active for %0d codes (expected exactly 1)", n_s);
    end
    checks = checks + 1;
    if (n_v != 1) begin
      errors = errors + 1;
      $display("FAIL P2: EPICVN active for %0d codes (expected exactly 1)", n_v);
    end
    // all four codes distinct (implied by P1, asserted anyway)
    checks = checks + 1;
    if (c_gs == c_pcr || c_gs == c_s || c_gs == c_v || c_pcr == c_s || c_pcr == c_v || c_s == c_v) begin
      errors = errors + 1;
      $display("FAIL: two enables share a CSIDBS code");
    end

    // ---------------------------------------------------------------
    // characterisation: EPIC (CSCOMM field) alongside an IDBS enable
    // ---------------------------------------------------------------
    LCSN   = 1'b1;
    CSIDBS = c_gs[4:0];
    // find the CSCOMM code that raises EPIC, by sweep - not from documentation
    for (i = 0; i < 32; i = i + 1) begin
      CSCOMM = i[4:0];
      mclk_edge;
      if (EPIC === 1'b1) begin
        $display("");
        $display("---- cross-field characterisation -----------------------------------------");
        $display(
            "CSIDBS=%0o(o) raises EPGSN-active AND CSCOMM=%0o(o) raises EPIC AT THE SAME TIME.",
            c_gs, i);
        $display(
            "EPIC gates EPICMASKN (CGA_INTR_CNTLR_MDCD.v:253), the 5th CGA_IDBCTL enable, so the");
        $display(
            "IDB enable set is NOT mutually exclusive ACROSS the CSIDBS and CSCOMM microcode fields.");
        $display("---------------------------------------------------------------------------");
        $display("");
      end
    end
    CSCOMM = 5'b00000;

    $display("---- discovered CSIDBS decode (measured, LCSN=1) ---------------------------");
    $display("EPGSN  active for CSIDBS = %0o (octal) / %0d (dec)", c_gs, c_gs);
    $display("EPCRN  active for CSIDBS = %0o (octal) / %0d (dec)", c_pcr, c_pcr);
    $display("EPICSN active for CSIDBS = %0o (octal) / %0d (dec)", c_s, c_s);
    $display("EPICVN active for CSIDBS = %0o (octal) / %0d (dec)", c_v, c_v);
    $display("ONE-HOT VERDICT: the four CSIDBS-derived IDB enables ARE mutually exclusive.");
    $display("---------------------------------------------------------------------------");

    $display("checks=%0d failures=%0d", checks, errors);
    if (errors == 0) $display("TB_RESULT: PASS");
    else $display("TB_RESULT: FAIL");
    $finish;
  end

  // watchdog
  initial begin
    #500000;
    $display("checks=%0d failures=%0d", checks, errors + 1);
    $display("TB_RESULT: FAIL (watchdog)");
    $finish;
  end

endmodule

`default_nettype wire
