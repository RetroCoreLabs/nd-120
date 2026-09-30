`timescale 1ns / 1ps
`default_nettype none

/**************************************************************************
** Testbench for DECODE_DGA - the DGA TOP LEVEL (sheets 1-6).            **
** Verilog/DECODE-GateArray/DGA/circuit/                                 **
**   DECODE_DGA.v                                                        **
**                                                                       **
** SCOPE - READ THIS FIRST                                               **
**   DECODE_DGA.v is a WIRING sheet: apart from four assign-level        **
**   multiplexers it does nothing but connect its 60-odd pins to three   **
**   sub-sheets (DECODE_DGA_POW, DECODE_DGA_IDBS, DECODE_DGA_COMM), a    **
**   FIFO_8BIT and one F091 constant cell. Each sub-sheet already has    **
**   its own bench in this directory (test-dga-pow, test-dga-idbs,       **
**   test-dga-comm), so re-testing their internals here would add        **
**   nothing. What NO existing bench covers is whether the TOP LEVEL     **
**   connects them to the right pins - and a single crossed pin here is  **
**   exactly the class of fault that has produced every CPU bug found in **
**   this project so far.                                                **
**                                                                       **
**   This bench therefore deliberately tests ONE decode field end to     **
**   end, with everything else parked, plus the four muxes:              **
**                                                                       **
**   1. THE IDB-SOURCE DECODE FIELD XID_4_0, EXHAUSTIVELY. All 32 codes  **
**      x XLCN in {1,0}, checked at the TEN top-level pins the IDBS      **
**      sheet drives. This proves the XID_4_0 bus reaches IDBS.CSIDBS    **
**      unswapped AND that all ten enables leave through the right pins. **
**      The pin map being proved, read off DECODE_DGA.v:433-457:         **
**          IDBS.ECSRN   -> XCSN      IDBS.EDON    -> XDON               **
**          IDBS.EIORN   -> XION      IDBS.EPANN   -> XEPN               **
**          IDBS.EPANSN  -> XPSN      IDBS.EPEAN   -> XPAN               **
**          IDBS.EPESN   -> XPEN      IDBS.RINRN   -> XRIN               **
**          IDBS.RUARTN  -> XRUN      IDBS.TRAALDN -> XTRN               **
**      XPAN/XPEN and XRIN/XRUN are adjacent in that list and mean       **
**      completely different things (parity-error ADDRESS vs parity-     **
**      error STATUS; installation number vs UART) - a swap there is     **
**      invisible to every sub-sheet bench.                              **
**                                                                       **
**   2. XIDB_3_0_OUT, the panel nibble mux (DECODE_DGA.v:266).           **
**          XIDB_3_0_OUT = !XEPN ? {POW idb3..idb0} : XIDB_7_0_IN[3:0]   **
**      Swept over all 256 values of XIDB_7_0_IN in the pass-through     **
**      state, which also proves the UPPER nibble never leaks into the   **
**      lower one, and checked for independence from XIDB_7_0_IN[3:0]    **
**      in the panel state.                                              **
**                                                                       **
**   3. XA_7_0, the FIFO output port (DECODE_DGA.v:263):                 **
**          XA_7_0 = XRMN ? 8'b0 : s_ad_7_0                              **
**      The repo rule is that a disabled bus output drives ZERO, never   **
**      z, because these buses are OR-ed together. With XRMN parked      **
**      high the port is checked to be exactly 8'h00 at every step of    **
**      the decode sweep, so a change that let the FIFO leak onto the    **
**      A bus while disabled fails here.                                 **
**                                                                       **
** WHERE THE REFERENCE MODEL COMES FROM                                  **
**   The pin map above is read off the netlist DECODE_DGA.v. The DECODE  **
**   VALUES are the octal code sets from the independently derived model **
**   in DECODE_DGA_IDBS_tb.v (that bench states they were re-derived     **
**   from schematic intent, not transliterated from the NAND gates), and **
**   they are restated here as an independent copy:                      **
**       ECSRN <= o24   EIORN <= o16   EPESN <= o13   EPEAN <= o12       **
**       RUARTN<= o37   RINRN <= o35   EPANN <= o27   TRAALDN<= o26      **
**       EDON  <= {o00,o01,o02,o03,o04,o06,o10,o11,o14,o15,              **
**                 o22,o23,o25,o31,o36}                                  **
**       EPANSN = COMBINATIONAL ~((code==o20 | code==o21) & XLCN)        **
**   Every one of these products is gated by XLCN, so XLCN=0 deasserts   **
**   all ten. All except EPANSN are REGISTERED on XCLK.                  **
**                                                                       **
** WHAT IS NOT TESTED HERE, AND WHY                                      **
**   The POW sheet (power-up, master clear, RTC, bus timeout) and the    **
**   COMM sheet (microcode command decode) drive the other ~35 output    **
**   pins. Their behaviour is covered by test-dga-pow and the COMM       **
**   bench; driving them from the top level would need the whole         **
**   microcode command environment and would duplicate those benches     **
**   rather than test the wiring. The top-level pin map for those two    **
**   sheets is therefore NOT covered by this bench - that is a stated    **
**   gap, not an oversight.                                              **
**                                                                       **
** BUILD MODES                                                           **
**   DECODE_DGA.v selects the FIFO clocking with `ifdef FPGA_FF_MODE     **
**   (:355-365) and the IDBS/COMM sheets switch their capture the same   **
**   way. The bench drives XCLK directly in the default build and the    **
**   XCLK_EN clock-enable pulse in FPGA_FF_MODE, and the make target     **
**   runs BOTH; the results must be identical.                           **
**                                                                       **
** HOW TO RUN                                                            **
**   cd Verilog/DECODE-GateArray/DGA/sim && make test-dga-top            **
**                                                                       **
** Ronny Hansen                                                          **
** 20-AUG-2026                                                           **
***************************************************************************/

module DECODE_DGA_tb;

  localparam integer EXPECTED_CHECKS = 64*12 + 257 + 17 + 4;

  reg sysclk = 1'b0;
  reg sys_rst_n = 1'b0;
  reg XCLK_EN = 1'b0;
  reg XCLK_FALL_EN = 1'b0;

  // --- inputs, all parked except the ones this bench drives ------------
  reg       XBDN = 1'b1;
  reg       XBRN = 1'b1;
  reg       XCLK = 1'b0;
  reg       XCLO = 1'b0;
  reg       XCON = 1'b1;
  reg [4:0] XCO_4_0 = 5'o37;     // a COMM command that decodes nothing here
  reg       XDAN = 1'b1;
  reg       XEFN = 1'b1;
  reg       XEON = 1'b1;
  reg       XHIN = 1'b1;
  reg [4:0] XID_4_0 = 5'o17;     // the field under test; o17 decodes nothing
  reg       XLCN = 1'b1;
  reg       XLON = 1'b1;
  reg       XLSH = 1'b0;
  reg [1:0] XMI_1_0 = 2'b00;
  reg       XPOI = 1'b0;
  reg       XPOW = 1'b1;
  reg       XPWC = 1'b1;
  reg       XRMN = 1'b1;         // FIFO read disabled -> XA_7_0 must be 0
  reg       XRTO = 1'b0;
  reg       XS5N = 1'b1;
  reg [1:0] XST_4_3 = 2'b00;
  reg       XTES = 1'b0;
  reg       XTON = 1'b1;
  reg       XUCK = 1'b0;
  reg [7:0] XIDB_7_0_IN = 8'h00;

  wire [3:0] XIDB_3_0_OUT;
  wire [7:0] XA_7_0;
  wire XC10, XCLN, XCRN, XCSN, XDON, XDTN, XDVN, XECR, XEMN, XEPN;
  wire XESN, XEUN, XFEC, XFMI, XFON, XFUN, XION, XLHN, XMCL, XMRN;
  wire XOCN, XPAN, XPEN, XPFN, XPIN, XPNN, XPSC, XPSN, XRFN, XRIN;
  wire XRQN, XRTN, XRUN, XRWN, XSCN, XSHN, XSSN, XSTP, XSWN, XTEO;
  wire XTOT, XTRN, XVAL, XWHN, XWRI;

  integer checks = 0;
  integer errors = 0;

  DECODE_DGA DUT (
      .sysclk      (sysclk),
      .sys_rst_n   (sys_rst_n),
      .XCLK_EN     (XCLK_EN),
      .XCLK_FALL_EN(XCLK_FALL_EN),
      .XBDN        (XBDN),
      .XBRN        (XBRN),
      .XCLK        (XCLK),
      .XCLO        (XCLO),
      .XCON        (XCON),
      .XCO_4_0     (XCO_4_0),
      .XDAN        (XDAN),
      .XEFN        (XEFN),
      .XEON        (XEON),
      .XHIN        (XHIN),
      .XID_4_0     (XID_4_0),
      .XLCN        (XLCN),
      .XLON        (XLON),
      .XLSH        (XLSH),
      .XMI_1_0     (XMI_1_0),
      .XPOI        (XPOI),
      .XPOW        (XPOW),
      .XPWC        (XPWC),
      .XRMN        (XRMN),
      .XRTO        (XRTO),
      .XS5N        (XS5N),
      .XST_4_3     (XST_4_3),
      .XTES        (XTES),
      .XTON        (XTON),
      .XUCK        (XUCK),
      .XIDB_7_0_IN (XIDB_7_0_IN),
      .XIDB_3_0_OUT(XIDB_3_0_OUT),
      .XA_7_0      (XA_7_0),
      .XC10        (XC10),
      .XCLN        (XCLN),
      .XCRN        (XCRN),
      .XCSN        (XCSN),
      .XDON        (XDON),
      .XDTN        (XDTN),
      .XDVN        (XDVN),
      .XECR        (XECR),
      .XEMN        (XEMN),
      .XEPN        (XEPN),
      .XESN        (XESN),
      .XEUN        (XEUN),
      .XFEC        (XFEC),
      .XFMI        (XFMI),
      .XFON        (XFON),
      .XFUN        (XFUN),
      .XION        (XION),
      .XLHN        (XLHN),
      .XMCL        (XMCL),
      .XMRN        (XMRN),
      .XOCN        (XOCN),
      .XPAN        (XPAN),
      .XPEN        (XPEN),
      .XPFN        (XPFN),
      .XPIN        (XPIN),
      .XPNN        (XPNN),
      .XPSC        (XPSC),
      .XPSN        (XPSN),
      .XRFN        (XRFN),
      .XRIN        (XRIN),
      .XRQN        (XRQN),
      .XRTN        (XRTN),
      .XRUN        (XRUN),
      .XRWN        (XRWN),
      .XSCN        (XSCN),
      .XSHN        (XSHN),
      .XSSN        (XSSN),
      .XSTP        (XSTP),
      .XSWN        (XSWN),
      .XTEO        (XTEO),
      .XTOT        (XTOT),
      .XTRN        (XTRN),
      .XVAL        (XVAL),
      .XWHN        (XWHN),
      .XWRI        (XWRI)
  );

  initial begin
    $dumpfile("DECODE_DGA_tb.vcd");
    $dumpvars(0, DECODE_DGA_tb);
  end

  always #5 sysclk = ~sysclk;

  initial begin
    #200000;
    $display("FAIL WATCHDOG: not finished after 200000 ns");
    $display(" checks run : %0d", checks);
    $display(" failures   : %0d", errors + 1);
    $display("TB_RESULT: FAIL");
    $finish;
  end

  task ck;
    input [255:0] name;
    input [31:0]  got;
    input [31:0]  exp;
    begin
      checks = checks + 1;
      if (got !== exp) begin
        errors = errors + 1;
        if (errors < 30)
          $display("FAIL %0s at t=%0t: got %0h expected %0h", name, $time, got, exp);
      end
    end
  endtask

  // One IDB-source capture. In the default build the IDBS registers clock
  // on the routed XCLK net; in FPGA_FF_MODE they capture on sysclk gated
  // by XCLK_EN (DECODE_DGA.v:355-365 and the IDBS sheet).
  task xclk_capture;
    begin
`ifdef FPGA_FF_MODE
      @(negedge sysclk);
      XCLK_EN = 1'b1;
      XCLK    = 1'b1;
      @(negedge sysclk);
      XCLK_EN = 1'b0;
      XCLK    = 1'b0;
      #1;
`else
      @(negedge sysclk);
      XCLK = 1'b0;
      #1;
      XCLK = 1'b1;
      #1;
      @(negedge sysclk);
      #1;
`endif
    end
  endtask

  // ---- independent decode model --------------------------------------
  function edo_hit;
    input [4:0] c;
    input       lcs;
    begin
      case (c)
        5'o00, 5'o01, 5'o02, 5'o03, 5'o04, 5'o06,
        5'o10, 5'o11, 5'o14, 5'o15,
        5'o22, 5'o23, 5'o25, 5'o31, 5'o36: edo_hit = lcs;
        default: edo_hit = 1'b0;
      endcase
    end
  endfunction

  integer ic, il;
  reg [4:0] code;
  reg        prev_pans_reg;   // registered o21 (MAPANS) XPSN term from the previous step
  reg lcs;
  reg [3:0] panel_nibble;
  reg [3:0] first_nibble;

  initial begin
    $display("=====================================================");
    $display(" DECODE_DGA top level - IDB source decode field, muxes");
    $display("=====================================================");

    sys_rst_n = 1'b0;
    repeat (4) @(negedge sysclk);
    sys_rst_n = 1'b1;
    repeat (2) @(negedge sysclk);

    // settle the IDBS panel FSM on a code that decodes nothing
    XID_4_0 = 5'o17; XLCN = 1'b1;
    xclk_capture;
    xclk_capture;
    prev_pans_reg = 1'b0;   // o17 decodes nothing -> registered o21 term idle

    // =================================================================
    // A. EXHAUSTIVE XID_4_0 sweep x XLCN, at the top-level pins.
    // =================================================================
    for (il = 1; il >= 0; il = il - 1) begin
      for (ic = 0; ic < 32; ic = ic + 1) begin
        code = ic[4:0];
        lcs  = il[0];
        XID_4_0 = code;
        XLCN    = lcs;
        #1;

        // XPSN (28-AUG-2026): comb o20 term (MIPANS, the 20 ms COND,F15
        // check) AND the CLK0-registered o21 term (MAPANS, the macro TRA
        // PANS read). Before the clock the registered half still holds the
        // PREVIOUS code's decode.
        ck("A_XPSN_COMB_BEFORE_CLOCK", XPSN,
           !(lcs && (code == 5'o20)) && !prev_pans_reg);

        xclk_capture;

        ck("A_XCSN_ECSR_o24",   XCSN, !(lcs && (code == 5'o24)));
        ck("A_XION_EIOR_o16",   XION, !(lcs && (code == 5'o16)));
        ck("A_XPEN_EPES_o13",   XPEN, !(lcs && (code == 5'o13)));
        ck("A_XPAN_EPEA_o12",   XPAN, !(lcs && (code == 5'o12)));
        ck("A_XRUN_RUART_o37",  XRUN, !(lcs && (code == 5'o37)));
        ck("A_XRIN_RINR_o35",   XRIN, !(lcs && (code == 5'o35)));
        ck("A_XEPN_EPAN_o27",   XEPN, !(lcs && (code == 5'o27)));
        ck("A_XTRN_TRAALD_o26", XTRN, !(lcs && (code == 5'o26)));
        ck("A_XDON_EDO_SET",    XDON, !edo_hit(code, lcs));
        ck("A_XPSN_COMB_AFTER_CLOCK", XPSN,
           !(lcs && ((code == 5'o20) || (code == 5'o21))));
        prev_pans_reg = (lcs && (code == 5'o21));

        // the FIFO output port stays at ZERO the whole time, because
        // XRMN is parked high (disabled bus outputs drive 0, never z)
        ck("A_XA_7_0_ZERO_WHEN_DISABLED", XA_7_0, 8'h00);
      end
    end

    // =================================================================
    // B. XIDB_3_0_OUT pass-through: XEPN high (code o17 decodes nothing)
    //    means the low nibble of the input bus comes straight out, and
    //    the HIGH nibble must not reach it.
    // =================================================================
    XID_4_0 = 5'o17; XLCN = 1'b1;
    xclk_capture;
    ck("B_XEPN_DEASSERTED", XEPN, 1'b1);
    for (ic = 0; ic < 256; ic = ic + 1) begin
      XIDB_7_0_IN = ic[7:0];
      #1;
      ck("B_PASSTHROUGH_LOW_NIBBLE", XIDB_3_0_OUT, ic[3:0]);
    end
    XIDB_7_0_IN = 8'h00;

    // =================================================================
    // C. XIDB_3_0_OUT in the panel state: code o27 asserts XEPN low, and
    //    the output must then be the POW nibble, completely independent
    //    of XIDB_7_0_IN[3:0].
    // =================================================================
    XID_4_0 = 5'o27; XLCN = 1'b1;
    xclk_capture;
    ck("C_XEPN_ASSERTED", XEPN, 1'b0);
    XIDB_7_0_IN = 8'h00;
    #1;
    first_nibble = XIDB_3_0_OUT;
    for (ic = 0; ic < 16; ic = ic + 1) begin
      XIDB_7_0_IN = {4'h0, ic[3:0]};
      #1;
      panel_nibble = XIDB_3_0_OUT;
      checks = checks + 1;
      if (panel_nibble !== first_nibble) begin
        errors = errors + 1;
        if (errors < 30)
          $display("FAIL C_PANEL_NIBBLE_NOT_INDEPENDENT at t=%0t: in=%1h out=%1h, was %1h",
                   $time, ic[3:0], panel_nibble, first_nibble);
      end
    end
    XIDB_7_0_IN = 8'h00;

    // =================================================================
    // D. XA_7_0 disabled-output rule, restated as named checks after the
    //    FIFO has been written to (LDPANCN comes from COMM; whatever the
    //    FIFO holds, the port must read 0 while XRMN is high).
    // =================================================================
    #1;
    ck("D_XA_ZERO_XRMN_HIGH_1", XA_7_0, 8'h00);
    XIDB_7_0_IN = 8'hFF;
    #1;
    ck("D_XA_ZERO_XRMN_HIGH_2", XA_7_0, 8'h00);
    xclk_capture;
    ck("D_XA_ZERO_XRMN_HIGH_3", XA_7_0, 8'h00);
    XIDB_7_0_IN = 8'h00;
    #1;
    ck("D_XA_ZERO_XRMN_HIGH_4", XA_7_0, 8'h00);

    if (checks !== EXPECTED_CHECKS) begin
      errors = errors + 1;
      $display("FAIL CHECK_COUNT: ran %0d checks, expected %0d", checks, EXPECTED_CHECKS);
    end

    $display("-----------------------------------------------------");
    $display(" checks run : %0d", checks);
    $display(" failures   : %0d", errors);
    if (errors == 0) $display("TB_RESULT: PASS");
    else             $display("TB_RESULT: FAIL");
    $display("=====================================================");
    $finish;
  end

endmodule

`default_nettype wire
