/**************************************************************************
** ND120 CGA (CPU Gate Array / DELILAH)                                  **
** /CGA/TRAP/TVGEN                                                       **
** Trap Vector Generator (?)                                             **
**                                                                       **
** Page 104                                                              **
** SHEET 1 of 1                                                          **
**                                                                       **
** Last reviewed: 2-FEB-2024                                             **
** Ronny Hansen                                                          **
***************************************************************************/

module CGA_TRAP_TVGEN (
    input       sysclk,   //! FPGA system clock (P2: TCLK_EN capture)
    input       TCLK_EN,  //! TCLK clock-enable pulse (FPGA_FF_MODE, else 0)

    input       DSTOPN,   //! DSTOP negated (from CGA_DCD.DSTOPN)
    input       FTRAPN,   //! tied to 1 (in CGA_TRAP)
    input       IFETCH,
    input       IFETCHN,
    input       IIND,
    input       IINDN,
    input       INTRQ,
    input [1:0] IPCR_1_0,
    input [1:0] IPCR_1_0_N,
    input [6:0] IPT_15_9,
    input [6:0] IPT_15_9_N,
    input       IWRITE,
    input       IWRITEN,
    input       PAN,
    input       PONI,     //! Memory Protection ON, PONI=1 (same net as CGA.XPONI)
    input       TCLK,     //! User Clock (from CPU_PROC_CGA_33.UCLK)
    input       VACC,       //! MMU-translated memory reference this cycle - qualifies every trap-vector term below
    input       VTRAPN,   //! tied to 1 (in CGA_TRAP)

    output       PVIOL,
    output       RESTR,
    output [3:0] TVEC_3_0  //! Trap vector bits 3 to 0 (to CGA_MIC.TVEC_3_0)
);

  /*******************************************************************************
   ** The wires are defined here                                                 **
   *******************************************************************************/
  wire [6:0] s_ipt_15_9;
  wire [1:0] s_ipcr_1_0_n;
  wire [6:0] s_ipt_15_9_n;
  wire [3:0] s_tvec_3_0_out;
  wire [1:0] s_ipcr_1_0;
  wire       s_dstop_n;
  wire       s_fpvn_out;
  wire       s_ftrap_n;
  wire       s_gates1_out;
  wire       s_gates10_out;
  wire       s_gates3_out;
  wire       s_gates9_out;
  wire       s_ifetch_n;
  wire       s_ifetch;
  wire       s_iind_n;
  wire       s_iind;
  wire       s_intrq;
  wire       s_ipvn_out;
  wire       s_iwrite_n;
  wire       s_iwrite;
  wire       s_pan;
  wire       s_pgf_out;
  wire       s_pgfn_out;
  wire       s_pgu_out;
  wire       s_pgun_out;
  wire       s_poni;
  wire       s_pviol_out;
  wire       s_rd1n_out;
  wire       s_rd2n_out;
  wire       s_rd3n_out;
  wire       s_restr_out;
  wire       s_rpvn_out;
  wire       s_rv1n_out;
  wire       s_rv2n_out;
  wire       s_rv3n_out;
  wire       s_tclk;
  wire       s_vacc;
  wire       s_vtrap_n;
  wire       s_wip_out;
  wire       s_wipn_out;
  wire       s_wpvn_out;

  /*******************************************************************************
   ** The module functionality is described here                                 **
   *******************************************************************************/

  /*******************************************************************************
   ** Here all input connections are defined                                     **
   *******************************************************************************/
  assign s_dstop_n         = DSTOPN;
  assign s_ftrap_n         = FTRAPN;
  assign s_ifetch          = IFETCH;
  assign s_ifetch_n        = IFETCHN;
  assign s_iind            = IIND;
  assign s_iind_n          = IINDN;
  assign s_intrq           = INTRQ;
  assign s_ipcr_1_0_n[1:0] = IPCR_1_0_N;
  assign s_ipcr_1_0[1:0]   = IPCR_1_0;
  assign s_ipt_15_9_n[6:0] = IPT_15_9_N;
  assign s_ipt_15_9[6:0]   = IPT_15_9;
  assign s_iwrite          = IWRITE;
  assign s_iwrite_n        = IWRITEN;
  assign s_pan             = PAN;
  assign s_poni            = PONI;
  assign s_tclk            = TCLK;
  assign s_vacc            = VACC;
  assign s_vtrap_n         = VTRAPN;

  /*******************************************************************************
   ** Here all output connections are defined                                    **
   *******************************************************************************/
  assign PVIOL             = s_pviol_out;
  assign RESTR             = s_restr_out;
  assign TVEC_3_0          = s_tvec_3_0_out[3:0];

  /*******************************************************************************
   ** Here all in-lined components are defined                                   **
   *******************************************************************************/

  // NOT Gate
  assign s_pgf_out         = ~s_pgfn_out;
  assign s_pgu_out         = ~s_pgun_out;
  assign s_wip_out         = ~s_wipn_out;


  // Code to make LINTER not complaing about bits _not_ read in IPT 14,12:11
  (* keep = "true", DONT_TOUCH = "true" *) wire [2:0] unused_ipt_bits;
  assign unused_ipt_bits[2:0] = {s_ipt_15_9[5], s_ipt_15_9[3:2]};

  /*******************************************************************************
   ** Here all normal components are defined                                     **
   *******************************************************************************/
  OR_GATE_8_INPUTS #(
      .BubblesMask(8'hFF)
  ) GATES_1 (
      .input1(s_pgfn_out),
      .input2(s_wpvn_out),
      .input3(s_ipvn_out),
      .input4(s_fpvn_out),
      .input5(s_rpvn_out),
      .input6(s_rv1n_out),
      .input7(s_rv2n_out),
      .input8(s_rv3n_out),
      .result(s_gates1_out)
  );

  OR_GATE_5_INPUTS #(
      .BubblesMask({1'b1, 4'hF})
  ) GATES_2 (
      .input1(s_pgfn_out),
      .input2(s_wpvn_out),
      .input3(s_ipvn_out),
      .input4(s_fpvn_out),
      .input5(s_rpvn_out),
      .result(s_pviol_out)
  );

  OR_GATE_3_INPUTS #(
      .BubblesMask(3'b111)
  ) GATES_3 (
      .input1(s_rv3n_out),
      .input2(s_rv2n_out),
      .input3(s_rv1n_out),
      .result(s_gates3_out)
  );

  NAND_GATE_4_INPUTS #(
      .BubblesMask(4'h0)
  ) WIPN (
      .input1(s_vacc),
      .input2(s_iwrite),
      .input3(s_ipt_15_9[6]),
      .input4(s_ipt_15_9_n[3]),
      .result(s_wipn_out)
  );

  NAND_GATE #(
      .BubblesMask(2'b00)
  ) PGUN (
      .input1(s_vacc),
      .input2(s_ipt_15_9_n[2]),
      .result(s_pgun_out)
  );

  NAND_GATE_5_INPUTS #(
      .BubblesMask({1'b0, 4'h0})
  ) RD1N (
      .input1(s_vacc),
      .input2(s_ifetch),
      .input3(s_ipt_15_9[4]),
      .input4(s_ipt_15_9_n[1]),
      .input5(s_ipcr_1_0[1]),
      .result(s_rd1n_out)
  );

  NAND_GATE_6_INPUTS #(
      .BubblesMask({2'b00, 4'h0})
  ) RD2N (
      .input1(s_vacc),
      .input2(s_ifetch),
      .input3(s_ipt_15_9[4]),
      .input4(s_ipt_15_9_n[1]),
      .input5(s_ipt_15_9_n[0]),
      .input6(s_ipcr_1_0[0]),
      .result(s_rd2n_out)
  );

  NAND_GATE_6_INPUTS #(
      .BubblesMask({2'b00, 4'h0})
  ) RD3N (
      .input1(s_vacc),
      .input2(s_ifetch),
      .input3(s_ipt_15_9[4]),
      .input4(s_ipt_15_9_n[0]),
      .input5(s_ipcr_1_0[1]),
      .input6(s_ipcr_1_0[0]),
      .result(s_rd3n_out)
  );

  OR_GATE_5_INPUTS #(
      .BubblesMask({1'b1, 4'hF})
  ) GATES_9 (
      .input1(s_wipn_out),
      .input2(s_pgun_out),
      .input3(s_rd1n_out),
      .input4(s_rd2n_out),
      .input5(s_rd3n_out),
      .result(s_gates9_out)
  );

  OR_GATE_3_INPUTS #(
      .BubblesMask(3'b111)
  ) GATES_10 (
      .input1(s_rd3n_out),
      .input2(s_rd2n_out),
      .input3(s_rd1n_out),
      .result(s_gates10_out)
  );

  AND_GATE #(
      .BubblesMask(2'b00)
  ) GATES_11 (
      .input1(s_ipcr_1_0_n[1]),
      .input2(s_poni),
      .result(s_restr_out)
  );

  NAND_GATE_4_INPUTS #(
      .BubblesMask(4'h0)
  ) PGFN (
      .input1(s_vacc),
      .input2(s_ipt_15_9_n[6]),
      .input3(s_ipt_15_9_n[5]),
      .input4(s_ipt_15_9_n[4]),
      .result(s_pgfn_out)
  );

  NAND_GATE_5_INPUTS #(
      .BubblesMask({1'b0, 4'h0})
  ) WPVN (
      .input1(s_vacc),
      .input2(s_iwrite),
      .input3(s_iind_n),
      .input4(s_ifetch_n),
      .input5(s_ipt_15_9_n[6]),
      .result(s_wpvn_out)
  );

  NAND_GATE_6_INPUTS #(
      .BubblesMask({2'b00, 4'h0})
  ) IPVN (
      .input1(s_vacc),
      .input2(s_iwrite_n),
      .input3(s_iind),
      .input4(s_ifetch_n),
      .input5(s_ipt_15_9_n[5]),
      .input6(s_ipt_15_9_n[4]),
      .result(s_ipvn_out)
  );

  NAND_GATE_5_INPUTS #(
      .BubblesMask({1'b0, 4'h0})
  ) FPVN (
      .input1(s_vacc),
      .input2(s_iwrite_n),
      .input3(s_iind_n),
      .input4(s_ifetch),
      .input5(s_ipt_15_9_n[4]),
      .result(s_fpvn_out)
  );

  NAND_GATE_5_INPUTS #(
      .BubblesMask({1'b0, 4'h0})
  ) RPVN (
      .input1(s_vacc),
      .input2(s_iwrite_n),
      .input3(s_iind_n),
      .input4(s_ifetch_n),
      .input5(s_ipt_15_9_n[5]),
      .result(s_rpvn_out)
  );

  NAND_GATE_3_INPUTS #(
      .BubblesMask(3'b000)
  ) RV1N (
      .input1(s_vacc),
      .input2(s_ipt_15_9[1]),
      .input3(s_ipcr_1_0_n[1]),
      .result(s_rv1n_out)
  );

  NAND_GATE_4_INPUTS #(
      .BubblesMask(4'h0)
  ) RV2N (
      .input1(s_vacc),
      .input2(s_ipt_15_9[0]),
      .input3(s_ipcr_1_0_n[1]),
      .input4(s_ipcr_1_0_n[0]),
      .result(s_rv2n_out)
  );

  NAND_GATE_4_INPUTS #(
      .BubblesMask(4'h0)
  ) RV3N (
      .input1(s_vacc),
      .input2(s_ipt_15_9[1]),
      .input3(s_ipt_15_9[0]),
      .input4(s_ipcr_1_0_n[0]),
      .result(s_rv3n_out)
  );


  /*******************************************************************************
   ** Here all sub-circuits are defined                                          **
   *******************************************************************************/

  CGA_TRAP_TVGEN_P2 TRAP_TVGEN (
      .sysclk(sysclk),
      .TCLK_EN(TCLK_EN),
      .DSTOPN(s_dstop_n),
      .FTRAPN(s_ftrap_n),
      .IFETCH(s_ifetch),
      .INTRQ(s_intrq),
      .LEV1(s_gates1_out),
      .LEV2(s_gates9_out),
      .PAN(s_pan),
      .PGF(s_pgf_out),
      .PGU(s_pgu_out),
      .PGUN(s_pgun_out),
      .PVIOL(s_pviol_out),
      .RD(s_gates10_out),
      .RV(s_gates3_out),
      .TCLK(s_tclk),
      .TVEC_3_0(s_tvec_3_0_out[3:0]),
      .VACC(s_vacc),
      .VTRAPN(s_vtrap_n),
      .WIP(s_wip_out),
      .WIPN(s_wipn_out)
  );

endmodule
