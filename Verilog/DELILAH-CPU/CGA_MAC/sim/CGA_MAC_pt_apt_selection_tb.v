/***************************************************************************************************
** ND120 CGA - CGA_MAC - PAGE-TABLE SELECTION: PT vs APT, SEXI vs REDUCED, ALL PIL, ALL MODES      **
**                                                                                                **
** WHY. SINTRAN III halts in ERRFATAL on a page fault at Perror 064544 (virtual page 0o32) at      **
** PIL 1, with NPIT/APIT = 012/007 - TWO DIFFERENT page tables. The trap machinery is proven       **
** correct (CGA_TRAP_TVGEN exhaustive, 524288 states) and the page-table STORAGE is proven correct **
** (CPU_MMU_24_allentries_tb, all 2048 entries written, read back and translated, 8198 checks).    **
** What is NOT covered anywhere is the layer between them: WHICH page table a given access         **
** selects. If an access takes the primary table where it should take the alternate - or the       **
** reverse - it reads an unmapped entry and faults, with every lower layer looking perfect.        **
**                                                                                                **
** WHAT IS CHECKED, as a swept matrix:                                                             **
**   * PCR round-trip: load via FIDBO+LLDPCR, read PCR_15_0 back.                                  **
**   * PT request  (CSCOMM 0o24) must form the table number from PCR[14:11] - the PRIMARY field.   **
**   * APT request (CSCOMM 0o34, CSMIS=1) must form it from PCR[10:7] - the ALTERNATE field.       **
**   * Both swept over ALL 16 PIL values in PCR[6:3], with PT != APT so a wrong pick is visible.   **
**   * Both swept in EXTENDED mode (DOUBLE=1, SEXI) and REDUCED mode (DOUBLE=0, REX).              **
**   * Both swept with PTM=0 and PTM=1, and with PONI on.                                          **
**                                                                                                **
** COMMAND ENCODINGS were enumerated from CGA_MAC_DECODE itself, not assumed (sweep of all 128     **
** CSCOMM x CSMIS combinations, 17-AUG-2026): SPT asserts for CSCOMM 0o24-0o27; SAPT asserts for   **
** 0o34/0o35 with CSMIS=1 (and for 0o30/0o32 CSMIS=1,2,3 and 0o31/0o33 CSMIS=0,1). That matches    **
** the note at CGA_MAC_DECODE.v:252-253 naming 0o34/0o35 CSMIS=1 as RDRQ,APT / WRRQ,APT.           **
**                                                                                                **
** FIELD LAYOUT, read off the address gates (CGA_MAC_LA1025.v:221-337):                            **
**   PT  (primary)   = PCR[14:11] -> LA19..LA16                                                    **
**   APT (alternate) = PCR[10:7]  -> LA19..LA16                                                    **
**   PCR[15] and PCR[6:0] are UNUSED by the LA gates - stated at CGA_MAC_LA1025.v:160. So the PIL  **
**   field takes NO part in address formation, and this bench asserts that: changing PIL alone     **
**   must not change the selected table. That is faithful - the per-level PCR copies are kept by   **
**   MICROCODE, which reloads the single latch with COMM,LDPCR on a level switch (see 00062/00065  **
**   in $ND_REPOS/nd120uc/source/nd-120-delilah.uc).                                               **
**                                                                                                **
** Runs in both build modes (plain and -DFPGA_FF_MODE), as the CGA_MAC directory requires.         **
**                                                                                                **
** Run: make iv-CGA_MAC_pt_apt_selection   (DELILAH-CPU/CGA_MAC/sim)                               **
**                                                                                                **
** 17-AUG-2026                                                                                    **
***************************************************************************************************/
`timescale 1ns / 1ps

module CGA_MAC_pt_apt_selection_tb;

  reg sysclk = 0;
  always #5 sysclk = ~sysclk;

  reg         MCLK, MCLK_EN;
  reg         CSMREQ, DOUBLE, ILCSN, PONI, PTM, WR3, WR7;
  reg  [ 1:0] CMIS_1_0;
  reg  [ 4:0] CSCOMM_4_0;
  reg  [15:0] RB_15_0, CD_15_0, FIDBO_15_0, PR_15_0, BR_15_0, XR_15_0;

  wire        ECCR, LSHADOW, VEX;
  wire [13:0] LA_23_10;
  wire [ 9:0] MCA_9_0;
  wire [15:0] NLCA_15_0, PCR_15_0;

  reg sys_rst_n;

  CGA_MAC DUT (
      .sysclk(sysclk), .sys_rst_n(sys_rst_n),
      .MCLK_EN(MCLK_EN), .CSMREQ(CSMREQ), .DOUBLE(DOUBLE), .ILCSN(ILCSN),
      .MCLK(MCLK), .PONI(PONI), .PTM(PTM), .WR3(WR3), .WR7(WR7),
      .CMIS_1_0(CMIS_1_0), .CSCOMM_4_0(CSCOMM_4_0),
      .RB_15_0(RB_15_0), .CD_15_0(CD_15_0), .FIDBO_15_0(FIDBO_15_0),
      .PR_15_0(PR_15_0), .BR_15_0(BR_15_0), .XR_15_0(XR_15_0),
      .ECCR(ECCR), .LA_23_10(LA_23_10), .LSHADOW(LSHADOW), .MCA_9_0(MCA_9_0),
      .NLCA_15_0(NLCA_15_0), .PCR_15_0(PCR_15_0), .VEX(VEX)
  );

  // The page-table number presented to the MMU is LA_20_10[10:6] =
  // {LA20, LA19..LA16}. LA20 comes from SEG[4] only (CGA_MAC_LA1025.v:209-215),
  // which is 0 in this bench, so the 4-bit field under test is LA_23_10[9:6].
  wire [3:0] la_table = LA_23_10[9:6];

  integer errors, checks, printed;
  localparam integer MAX_PRINT = 30;

  task chk(input [15:0] got, input [15:0] exp, input [(8*78):1] msg);
    begin
      checks = checks + 1;
      if (got !== exp) begin
        errors = errors + 1;
        if (printed < MAX_PRINT) begin
          printed = printed + 1;
          $display("FAIL %0s: got %0o expected %0o", msg, got, exp);
        end
      end
    end
  endtask

  // One MCLK cycle. In FPGA_FF_MODE the registers capture on posedge sysclk
  // gated by MCLK_EN aligned to the MCLK rise; otherwise they clock on MCLK.
  task mclk_cycle;
    begin
      @(negedge sysclk); MCLK_EN = 1;
      @(negedge sysclk); MCLK = 1; MCLK_EN = 0;
      @(negedge sysclk);
      @(negedge sysclk); MCLK = 0;
      @(negedge sysclk);
    end
  endtask

  // Load PCR. The LLDPCR encoding was MEASURED by sweeping all
  // CSCOMM x CSMIS x LCSN x WR3 x WR7 through CGA_MAC_DECODE (17-AUG-2026):
  // LLDPCR asserts ONLY at CSCOMM=0o06, CSMIS=3, LCSN=1 (WR3/WR7 immaterial).
  // Do not "correct" this to 0o31/CSMIS=00 - that encoding never asserts it,
  // and a bench that uses it silently leaves PCR unloaded (X) and every
  // downstream check meaningless.
  //
  // LLDPCR is MCLK-registered; the PCR latch is transparent while
  // L = ~MCLK & LLDPCR (CGA_MAC_SEGPT_PCR.v:63-69 with L8). So the register
  // must capture on an MCLK rise and the data must still be present when MCLK
  // falls - two cycles cover that ordering safely.
  task load_pcr(input [15:0] v);
    begin
      @(negedge sysclk);
      CSCOMM_4_0 = 5'o06; CMIS_1_0 = 2'b11; ILCSN = 1'b1; FIDBO_15_0 = v;
      mclk_cycle;
      mclk_cycle;
      @(negedge sysclk);
      CSCOMM_4_0 = 5'o00; CMIS_1_0 = 2'b00;
    end
  endtask

  // Issue an access and capture the resulting latched logical address.
  task issue(input [4:0] cmd, input [1:0] mis);
    begin
      @(negedge sysclk);
      CSCOMM_4_0 = cmd; CMIS_1_0 = mis; CSMREQ = 1'b1;
      mclk_cycle;
      @(negedge sysclk); CSMREQ = 1'b0;
    end
  endtask

  // PCR assembly: PT in 14:11, APT in 10:7, PIL in 6:3, MMS2 bit 2, ring 1:0.
  function [15:0] mk_pcr(input [3:0] pt, input [3:0] apt, input [3:0] pil);
    begin
      mk_pcr = {1'b0, pt, apt, pil, 1'b1, 2'b10};
    end
  endfunction

  integer pil, dbl, ptm_i, k;
  reg [3:0] ptf, aptf;
  reg [15:0] pcr;

  initial begin
`ifdef FPGA_FF_MODE
    $display("CGA_MAC_pt_apt_selection_tb: FPGA_FF_MODE (sysclk+MCLK_EN capture)");
`else
    $display("CGA_MAC_pt_apt_selection_tb: latch/CP mode (posedge MCLK capture)");
`endif
    errors = 0; checks = 0; printed = 0;
    MCLK = 0; MCLK_EN = 0; CSMREQ = 0; DOUBLE = 0; ILCSN = 1; PONI = 1;
    PTM = 1; WR3 = 0; WR7 = 0; CMIS_1_0 = 0; CSCOMM_4_0 = 0;
    RB_15_0 = 16'h0000; CD_15_0 = 16'h1234; FIDBO_15_0 = 0;
    PR_15_0 = 16'h0000; BR_15_0 = 16'h0000; XR_15_0 = 16'h0000;
    sys_rst_n = 0;
    repeat (4) @(posedge sysclk);
    sys_rst_n = 1;
    repeat (2) @(posedge sysclk);

    // PT != APT everywhere, so picking the wrong field is always visible.
    ptf = 4'ha; aptf = 4'h5;

    for (dbl = 0; dbl < 2; dbl = dbl + 1) begin           // REX / SEXI
      for (ptm_i = 0; ptm_i < 2; ptm_i = ptm_i + 1) begin // PTM 0 / 1
        for (pil = 0; pil < 16; pil = pil + 1) begin      // ALL PIL values
          @(negedge sysclk);
          DOUBLE = dbl[0];
          PTM    = ptm_i[0];

          pcr = mk_pcr(ptf, aptf, pil[3:0]);
          load_pcr(pcr);

          // 1. PCR must hold what was written in the fields the LA gates use.
          //    PCR[6:3] (PIL) is hardwired to 0 by CGA_MAC_SEGPT_PCR.v:53-54,
          //    so only the PT/APT fields are asserted here.
          chk({8'b0, PCR_15_0[14:11], 4'b0}, {8'b0, ptf, 4'b0},
              "PCR round-trip: PT field");
          chk({8'b0, PCR_15_0[10:7], 4'b0}, {8'b0, aptf, 4'b0},
              "PCR round-trip: APT field");

          // 2. A PT request must form the table from the PRIMARY field.
          issue(5'o24, 2'b00);
          chk({12'b0, la_table}, {12'b0, ptf},
              "PT request selects PCR[14:11] (primary table)");

          // 3. An APT request must form it from the ALTERNATE field.
          issue(5'o34, 2'b01);
          chk({12'b0, la_table}, {12'b0, aptf},
              "APT request selects PCR[10:7] (alternate table)");
        end
      end
    end

    // 4. PIL must NOT influence the selected table: same PT/APT, two different
    //    PIL values, identical result. PCR[6:0] is unused by the LA gates
    //    (CGA_MAC_LA1025.v:160) and the per-level copies live in microcode.
    DOUBLE = 0; PTM = 1;
    load_pcr(mk_pcr(4'h3, 4'hc, 4'd1));
    issue(5'o24, 2'b00);
    chk({12'b0, la_table}, {12'b0, 4'h3}, "PIL 1: PT request still primary");
    load_pcr(mk_pcr(4'h3, 4'hc, 4'd14));
    issue(5'o24, 2'b00);
    chk({12'b0, la_table}, {12'b0, 4'h3}, "PIL 14: same table as PIL 1");
    issue(5'o34, 2'b01);
    chk({12'b0, la_table}, {12'b0, 4'hc}, "PIL 14: APT request still alternate");

    $display("");
    if (errors == 0) $display("TB_RESULT: PASS (%0d checks)", checks);
    else             $display("TB_RESULT: FAIL (%0d checks, %0d errors)", checks, errors);
    $finish;
  end

  initial begin
    #50000000;
    $display("TB_RESULT: TIMEOUT");
    $finish;
  end

endmodule
