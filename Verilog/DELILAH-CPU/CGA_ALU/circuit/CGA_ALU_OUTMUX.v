/**************************************************************************
** ND120 CGA (CPU Gate Array / DELILAH)                                  **
** /CGA/ALU/OUTMUX                                                       **
** OUT MUX                                                               **
**                                                                       **
** Page 55                                                               **
** SHEET 1 of 1                                                          **
**                                                                       **
** Last reviewed: 29-JAN-2025                                            **
** Ronny Hansen                                                          **
***************************************************************************/

module CGA_ALU_OUTMUX (
    // System input signals
    input sysclk,    // System clock in FPGA
    input sys_rst_n, // System reset in FPGA

    input        AARG0,
    input        ALUCLK_EN,  //! ALUCLK clock-enable pulse (FPGA_FF_MODE, else 0)
    input        ALUCLK,  //! ALU clock signal (from CPU_PROC_CGA_33.ALUCLK)
    input        ALUD2N,  //! ALU Data 2, active low signal (from CGA_CPU_ALU_CONTR.ALUD2N)
    input [15:0] ARG_15_0,
    input [15:0] A_15_0,  //! DATA output 16 bit A, from register selected by LAA_3_0 (from CGA_WRF.A_15_0)
    input [ 4:0] CSIDBS_4_0,  //! Control Store Bits (from CPU_PROC_CGA_33.CSBITS[41:37])
    input [15:0] DBR_15_0,
    input [15:0] EA_15_0,  //! Enable A (source) bits for read. 16 bits to select register. (from CGA_WRF.EA_15_0)
    input [15:0] FIDBI_15_0,
    input [15:0] F_15_0,  //! Function Result (15:0) (from CGA_CPU_ALU_RALU.F_15_0)
    input [15:0] GPR_15_0,
    input [ 2:0] LAA_3_1,  //! A Operand. CSBITS [15:12] (from CGA_ALU.LAA_3_0[3:1])
    input [ 2:0] LBA_2_0,  //! B Operand. CSBITS [19:16] (from CGA_ALU.LBA_3_0[2:0])
    input [15:0] STS_15_0,
    input [15:0] SW_15_0,

    output [15:0] D_15_0,
    output [15:0] G_15_0
);

  /*******************************************************************************
   ** The wires are defined here                                                 **
   *******************************************************************************/
  wire [ 2:0] s_laa_3_1;
  wire [ 2:0] s_lba_2_0;
  wire [ 4:0] s_csidbs_4_0;
  wire [ 6:0] s_e_dmux7;
  wire [ 6:0] s_si_dmux7;
  wire [ 7:0] s_e_dmux0;
  wire [ 7:0] s_e_dmux1;
  wire [ 7:0] s_e_dmux10;
  wire [ 7:0] s_e_dmux11;
  wire [ 7:0] s_e_dmux12;
  wire [ 7:0] s_e_dmux13;
  wire [ 7:0] s_e_dmux14;
  wire [ 7:0] s_e_dmux15;
  wire [ 7:0] s_e_dmux2;
  wire [ 7:0] s_e_dmux3;
  wire [ 7:0] s_e_dmux4;
  wire [ 7:0] s_e_dmux5;
  wire [ 7:0] s_e_dmux6;
  wire [ 7:0] s_e_dmux8;
  wire [ 7:0] s_e_dmux9;
  wire [ 7:0] s_si_dmux0;
  wire [ 7:0] s_si_dmux1;
  wire [ 7:0] s_si_dmux10;
  wire [ 7:0] s_si_dmux11;
  wire [ 7:0] s_si_dmux12;
  wire [ 7:0] s_si_dmux13;
  wire [ 7:0] s_si_dmux14;
  wire [ 7:0] s_si_dmux15;
  wire [ 7:0] s_si_dmux2;
  wire [ 7:0] s_si_dmux3;
  wire [ 7:0] s_si_dmux4;
  wire [ 7:0] s_si_dmux5;
  wire [ 7:0] s_si_dmux6;
  wire [ 7:0] s_si_dmux8;
  wire [ 7:0] s_si_dmux9;
  wire [15:0] s_a_15_0;
  wire [15:0] s_arg_15_0;
  wire [15:0] s_d_15_0_out;
  wire [15:0] s_dbr_15_0;
  wire [15:0] s_ea_15_0;
  wire [15:0] s_f_15_0;
  wire [15:0] s_fidbi_15_0;
  wire [15:0] s_g_15_0_out;
  wire [15:0] s_gpr_15_0;
  wire [15:0] s_sts_15_0;
  wire [15:0] s_sw_15_0;

  wire        s_aluclk;
  wire        s_alud2n;
  wire        s_arg_0;
  wire        s_arg_1;
  wire        s_arg_10;
  wire        s_arg_11;
  wire        s_arg_12;
  wire        s_arg_13;
  wire        s_arg_14;
  wire        s_arg_15;
  wire        s_arg_2;
  wire        s_arg_3;
  wire        s_arg_4;
  wire        s_arg_5;
  wire        s_arg_6;
  wire        s_arg_7;
  wire        s_arg_8;
  wire        s_arg_9;
  wire        s_dbr_0;
  wire        s_dbr_1;
  wire        s_dbr_10;
  wire        s_dbr_11;
  wire        s_dbr_12;
  wire        s_dbr_13;
  wire        s_dbr_14;
  wire        s_dbr_15;
  wire        s_dbr_2;
  wire        s_dbr_3;
  wire        s_dbr_4;
  wire        s_dbr_5;
  wire        s_dbr_6;
  wire        s_dbr_7;
  wire        s_dbr_8;
  wire        s_dbr_9;
  wire        s_ea_0;
  wire        s_ea_1;
  wire        s_ea_10;
  wire        s_ea_11;
  wire        s_ea_12;
  wire        s_ea_13;
  wire        s_ea_14;
  wire        s_ea_15;
  wire        s_ea_2;
  wire        s_ea_3;
  wire        s_ea_4;
  wire        s_ea_5;
  wire        s_ea_6;
  wire        s_ea_7;
  wire        s_ea_8;
  wire        s_ea_9;
  wire        s_ea;
  wire        s_eaarg;
  wire        s_eabarg;
  wire        s_earg;
  wire        s_ebarg;
  wire        s_ebmg;
  wire        s_edbr;
  wire        s_ef;
  wire        s_efidb;
  wire        s_egprh;
  wire        s_egprl;
  wire        s_egprs;
  wire        s_ests;
  wire        s_eswap;
  wire        s_fidbi_0;
  wire        s_fidbi_1;
  wire        s_fidbi_10;
  wire        s_fidbi_11;
  wire        s_fidbi_12;
  wire        s_fidbi_13;
  wire        s_fidbi_14;
  wire        s_fidbi_15;
  wire        s_fidbi_2;
  wire        s_fidbi_3;
  wire        s_fidbi_4;
  wire        s_fidbi_5;
  wire        s_fidbi_6;
  wire        s_fidbi_7;
  wire        s_fidbi_8;
  wire        s_fidbi_9;
  wire        s_gpr_0;
  wire        s_gpr_1;
  wire        s_gpr_10;
  wire        s_gpr_11;
  wire        s_gpr_12;
  wire        s_gpr_13;
  wire        s_gpr_14;
  wire        s_gpr_15;
  wire        s_gpr_2;
  wire        s_gpr_3;
  wire        s_gpr_4;
  wire        s_gpr_5;
  wire        s_gpr_6;
  wire        s_gpr_7;
  wire        s_gpr_8;
  wire        s_gpr_9;
  wire        s_laa_1;
  wire        s_laa_2;
  wire        s_laa_3;
  wire        s_lba_0;
  wire        s_lba_1;
  wire        s_lba_2;
  wire        s_sts_0;
  wire        s_sts_1;
  wire        s_sts_10;
  wire        s_sts_11;
  wire        s_sts_12;
  wire        s_sts_13;
  wire        s_sts_14;
  wire        s_sts_15;
  wire        s_sts_2;
  wire        s_sts_3;
  wire        s_sts_4;
  wire        s_sts_5;
  wire        s_sts_6;
  wire        s_sts_7;
  wire        s_sts_8;
  wire        s_sts_9;
  wire        s_sw_0;
  wire        s_sw_1;
  wire        s_sw_10;
  wire        s_sw_11;
  wire        s_sw_12;
  wire        s_sw_13;
  wire        s_sw_14;
  wire        s_sw_15;
  wire        s_sw_2;
  wire        s_sw_3;
  wire        s_sw_4;
  wire        s_sw_5;
  wire        s_sw_6;
  wire        s_sw_7;
  wire        s_sw_8;
  wire        s_sw_9;

  /*******************************************************************************
   ** Here all wiring is defined                                                 **
   *******************************************************************************/
  // Enable DMUX 0-15

  assign s_e_dmux0[0]       = s_ebmg;
  assign s_e_dmux0[1]       = s_edbr;
  assign s_e_dmux0[2]       = s_earg;
  assign s_e_dmux0[3]       = s_ests;
  assign s_e_dmux0[4]       = s_eswap;
  assign s_e_dmux0[5]       = s_efidb;
  assign s_e_dmux0[6]       = s_egprl;
  assign s_e_dmux0[7]       = s_ebarg;

  assign s_e_dmux1[0]       = s_ebmg;
  assign s_e_dmux1[1]       = s_edbr;
  assign s_e_dmux1[2]       = s_earg;
  assign s_e_dmux1[3]       = s_ests;
  assign s_e_dmux1[4]       = s_eswap;
  assign s_e_dmux1[5]       = s_efidb;
  assign s_e_dmux1[6]       = s_egprl;
  assign s_e_dmux1[7]       = s_ebarg;

  assign s_e_dmux2[0]       = s_ebmg;
  assign s_e_dmux2[1]       = s_edbr;
  assign s_e_dmux2[2]       = s_earg;
  assign s_e_dmux2[3]       = s_ests;
  assign s_e_dmux2[4]       = s_eswap;
  assign s_e_dmux2[5]       = s_efidb;
  assign s_e_dmux2[6]       = s_egprl;
  assign s_e_dmux2[7]       = s_ebarg;

  assign s_e_dmux3[0]       = s_ebmg;
  assign s_e_dmux3[1]       = s_edbr;
  assign s_e_dmux3[2]       = s_earg;
  assign s_e_dmux3[3]       = s_ests;
  assign s_e_dmux3[4]       = s_eswap;
  assign s_e_dmux3[5]       = s_efidb;
  assign s_e_dmux3[6]       = s_egprl;
  assign s_e_dmux3[7]       = s_eabarg;

  assign s_e_dmux4[0]       = s_ebmg;
  assign s_e_dmux4[1]       = s_edbr;
  assign s_e_dmux4[2]       = s_earg;
  assign s_e_dmux4[3]       = s_ests;
  assign s_e_dmux4[4]       = s_eswap;
  assign s_e_dmux4[5]       = s_efidb;
  assign s_e_dmux4[6]       = s_egprl;
  assign s_e_dmux4[7]       = s_eaarg;

  assign s_e_dmux5[0]       = s_ebmg;
  assign s_e_dmux5[1]       = s_edbr;
  assign s_e_dmux5[2]       = s_earg;
  assign s_e_dmux5[3]       = s_ests;
  assign s_e_dmux5[4]       = s_eswap;
  assign s_e_dmux5[5]       = s_efidb;
  assign s_e_dmux5[6]       = s_egprl;
  assign s_e_dmux5[7]       = s_eaarg;

  assign s_e_dmux6[0]       = s_ebmg;
  assign s_e_dmux6[1]       = s_edbr;
  assign s_e_dmux6[2]       = s_earg;
  assign s_e_dmux6[3]       = s_ests;
  assign s_e_dmux6[4]       = s_eswap;
  assign s_e_dmux6[5]       = s_efidb;
  assign s_e_dmux6[6]       = s_egprl;
  assign s_e_dmux6[7]       = s_eaarg;

  assign s_e_dmux7[0]       = s_ebmg;
  assign s_e_dmux7[1]       = s_edbr;
  assign s_e_dmux7[2]       = s_earg;
  assign s_e_dmux7[3]       = s_ests;
  assign s_e_dmux7[4]       = s_eswap;
  assign s_e_dmux7[5]       = s_efidb;
  assign s_e_dmux7[6]       = s_egprl;

  assign s_e_dmux8[0]       = s_ebmg;
  assign s_e_dmux8[1]       = s_edbr;
  assign s_e_dmux8[2]       = s_earg;
  assign s_e_dmux8[3]       = s_ests;
  assign s_e_dmux8[4]       = s_eswap;
  assign s_e_dmux8[5]       = s_efidb;
  assign s_e_dmux8[6]       = s_egprh;
  assign s_e_dmux8[7]       = s_egprs;

  assign s_e_dmux9[0]       = s_ebmg;
  assign s_e_dmux9[1]       = s_edbr;
  assign s_e_dmux9[2]       = s_earg;
  assign s_e_dmux9[3]       = s_ests;
  assign s_e_dmux9[4]       = s_eswap;
  assign s_e_dmux9[5]       = s_efidb;
  assign s_e_dmux9[6]       = s_egprh;
  assign s_e_dmux9[7]       = s_egprs;

  assign s_e_dmux10[0]      = s_ebmg;
  assign s_e_dmux10[1]      = s_edbr;
  assign s_e_dmux10[2]      = s_earg;
  assign s_e_dmux10[3]      = s_ests;
  assign s_e_dmux10[4]      = s_eswap;
  assign s_e_dmux10[5]      = s_efidb;
  assign s_e_dmux10[6]      = s_egprh;
  assign s_e_dmux10[7]      = s_egprs;

  assign s_e_dmux11[0]      = s_ebmg;
  assign s_e_dmux11[1]      = s_edbr;
  assign s_e_dmux11[2]      = s_earg;
  assign s_e_dmux11[3]      = s_ests;
  assign s_e_dmux11[4]      = s_eswap;
  assign s_e_dmux11[5]      = s_efidb;
  assign s_e_dmux11[6]      = s_egprh;
  assign s_e_dmux11[7]      = s_egprs;

  assign s_e_dmux12[0]      = s_ebmg;
  assign s_e_dmux12[1]      = s_edbr;
  assign s_e_dmux12[2]      = s_earg;
  assign s_e_dmux12[3]      = s_ests;
  assign s_e_dmux12[4]      = s_eswap;
  assign s_e_dmux12[5]      = s_efidb;
  assign s_e_dmux12[6]      = s_egprh;
  assign s_e_dmux12[7]      = s_egprs;

  assign s_e_dmux13[0]      = s_ebmg;
  assign s_e_dmux13[1]      = s_edbr;
  assign s_e_dmux13[2]      = s_earg;
  assign s_e_dmux13[3]      = s_ests;
  assign s_e_dmux13[4]      = s_eswap;
  assign s_e_dmux13[5]      = s_efidb;
  assign s_e_dmux13[6]      = s_egprh;
  assign s_e_dmux13[7]      = s_egprs;

  assign s_e_dmux14[0]      = s_ebmg;
  assign s_e_dmux14[1]      = s_edbr;
  assign s_e_dmux14[2]      = s_earg;
  assign s_e_dmux14[3]      = s_ests;
  assign s_e_dmux14[4]      = s_eswap;
  assign s_e_dmux14[5]      = s_efidb;
  assign s_e_dmux14[6]      = s_egprh;
  assign s_e_dmux14[7]      = s_egprs;

  assign s_e_dmux15[0]      = s_ebmg;
  assign s_e_dmux15[1]      = s_edbr;
  assign s_e_dmux15[2]      = s_earg;
  assign s_e_dmux15[3]      = s_ests;
  assign s_e_dmux15[4]      = s_eswap;
  assign s_e_dmux15[5]      = s_efidb;
  assign s_e_dmux15[6]      = s_egprh;
  assign s_e_dmux15[7]      = s_egprs;


  // SIGNAL DMUX 0-15
  assign s_si_dmux0[0]      = s_ea_0;
  assign s_si_dmux0[1]      = s_dbr_0;
  assign s_si_dmux0[2]      = s_arg_0;
  assign s_si_dmux0[3]      = s_sts_0;
  assign s_si_dmux0[4]      = s_sw_0;
  assign s_si_dmux0[5]      = s_fidbi_0;
  assign s_si_dmux0[6]      = s_gpr_0;
  assign s_si_dmux0[7]      = s_lba_0;

  assign s_si_dmux1[0]      = s_ea_1;
  assign s_si_dmux1[1]      = s_dbr_1;
  assign s_si_dmux1[2]      = s_arg_1;
  assign s_si_dmux1[3]      = s_sts_1;
  assign s_si_dmux1[4]      = s_sw_1;
  assign s_si_dmux1[5]      = s_fidbi_1;
  assign s_si_dmux1[6]      = s_gpr_1;
  assign s_si_dmux1[7]      = s_lba_1;

  assign s_si_dmux2[0]      = s_ea_2;
  assign s_si_dmux2[1]      = s_dbr_2;
  assign s_si_dmux2[2]      = s_arg_2;
  assign s_si_dmux2[3]      = s_sts_2;
  assign s_si_dmux2[4]      = s_sw_2;
  assign s_si_dmux2[5]      = s_fidbi_2;
  assign s_si_dmux2[6]      = s_gpr_2;
  assign s_si_dmux2[7]      = s_lba_2;

  assign s_si_dmux3[0]      = s_ea_3;
  assign s_si_dmux3[1]      = s_dbr_3;
  assign s_si_dmux3[2]      = s_arg_3;
  assign s_si_dmux3[3]      = s_sts_3;
  assign s_si_dmux3[4]      = s_sw_3;
  assign s_si_dmux3[5]      = s_fidbi_3;
  assign s_si_dmux3[6]      = s_gpr_3;
  assign s_si_dmux3[7]      = AARG0;

  assign s_si_dmux4[0]      = s_ea_4;
  assign s_si_dmux4[1]      = s_dbr_4;
  assign s_si_dmux4[2]      = s_arg_4;
  assign s_si_dmux4[3]      = s_sts_4;
  assign s_si_dmux4[4]      = s_sw_4;
  assign s_si_dmux4[5]      = s_fidbi_4;
  assign s_si_dmux4[6]      = s_gpr_4;
  assign s_si_dmux4[7]      = s_laa_1;

  assign s_si_dmux5[0]      = s_ea_5;
  assign s_si_dmux5[1]      = s_dbr_5;
  assign s_si_dmux5[2]      = s_arg_5;
  assign s_si_dmux5[3]      = s_sts_5;
  assign s_si_dmux5[4]      = s_sw_5;
  assign s_si_dmux5[5]      = s_fidbi_5;
  assign s_si_dmux5[6]      = s_gpr_5;
  assign s_si_dmux5[7]      = s_laa_2;

  assign s_si_dmux6[0]      = s_ea_6;
  assign s_si_dmux6[1]      = s_dbr_6;
  assign s_si_dmux6[2]      = s_arg_6;
  assign s_si_dmux6[3]      = s_sts_6;
  assign s_si_dmux6[4]      = s_sw_6;
  assign s_si_dmux6[5]      = s_fidbi_6;
  assign s_si_dmux6[6]      = s_gpr_6;
  assign s_si_dmux6[7]      = s_laa_3;

  assign s_si_dmux7[0]      = s_ea_7;
  assign s_si_dmux7[1]      = s_dbr_7;
  assign s_si_dmux7[2]      = s_arg_7;
  assign s_si_dmux7[3]      = s_sts_7;
  assign s_si_dmux7[4]      = s_sw_7;
  assign s_si_dmux7[5]      = s_fidbi_7;
  assign s_si_dmux7[6]      = s_gpr_7;

  assign s_si_dmux8[0]      = s_ea_8;
  assign s_si_dmux8[1]      = s_dbr_8;
  assign s_si_dmux8[2]      = s_arg_8;
  assign s_si_dmux8[3]      = s_sts_8;
  assign s_si_dmux8[4]      = s_sw_8;
  assign s_si_dmux8[5]      = s_fidbi_8;
  assign s_si_dmux8[6]      = s_gpr_8; // GPR
  assign s_si_dmux8[7]      = s_gpr_7; // GPR Sign extended

  assign s_si_dmux9[0]      = s_ea_9;
  assign s_si_dmux9[1]      = s_dbr_9;
  assign s_si_dmux9[2]      = s_arg_9;
  assign s_si_dmux9[3]      = s_sts_9;
  assign s_si_dmux9[4]      = s_sw_9;
  assign s_si_dmux9[5]      = s_fidbi_9;
  assign s_si_dmux9[6]      = s_gpr_9; // GPR
  assign s_si_dmux9[7]      = s_gpr_7; // GPR Sign extended

  assign s_si_dmux10[0]     = s_ea_10;
  assign s_si_dmux10[1]     = s_dbr_10;
  assign s_si_dmux10[2]     = s_arg_10;
  assign s_si_dmux10[3]     = s_sts_10;
  assign s_si_dmux10[4]     = s_sw_10;
  assign s_si_dmux10[5]     = s_fidbi_10;
  assign s_si_dmux10[6]     = s_gpr_10; // GPR
  assign s_si_dmux10[7]     = s_gpr_7;  // GPR Sign extended

  assign s_si_dmux11[0]     = s_ea_11;
  assign s_si_dmux11[1]     = s_dbr_11;
  assign s_si_dmux11[2]     = s_arg_11;
  assign s_si_dmux11[3]     = s_sts_11;
  assign s_si_dmux11[4]     = s_sw_11;
  assign s_si_dmux11[5]     = s_fidbi_11;
  assign s_si_dmux11[6]     = s_gpr_11;
  assign s_si_dmux11[7]     = s_gpr_7;   // GPR Sign extended

  assign s_si_dmux12[0]     = s_ea_12;
  assign s_si_dmux12[1]     = s_dbr_12;
  assign s_si_dmux12[2]     = s_arg_12;
  assign s_si_dmux12[3]     = s_sts_12;
  assign s_si_dmux12[4]     = s_sw_12;
  assign s_si_dmux12[5]     = s_fidbi_12;
  assign s_si_dmux12[6]     = s_gpr_12;
  assign s_si_dmux12[7]     = s_gpr_7;   // GPR Sign extended

  assign s_si_dmux13[0]     = s_ea_13;
  assign s_si_dmux13[1]     = s_dbr_13;
  assign s_si_dmux13[2]     = s_arg_13;
  assign s_si_dmux13[3]     = s_sts_13;
  assign s_si_dmux13[4]     = s_sw_13;
  assign s_si_dmux13[5]     = s_fidbi_13;
  assign s_si_dmux13[6]     = s_gpr_13;
  assign s_si_dmux13[7]     = s_gpr_7;  // GPR Sign extended

  assign s_si_dmux14[0]     = s_ea_14;
  assign s_si_dmux14[1]     = s_dbr_14;
  assign s_si_dmux14[2]     = s_arg_14;
  assign s_si_dmux14[3]     = s_sts_14;
  assign s_si_dmux14[4]     = s_sw_14;
  assign s_si_dmux14[5]     = s_fidbi_14;
  assign s_si_dmux14[6]     = s_gpr_14;
  assign s_si_dmux14[7]     = s_gpr_7;  // GPR Sign extended

  assign s_si_dmux15[0]     = s_ea_15;
  assign s_si_dmux15[1]     = s_dbr_15;
  assign s_si_dmux15[2]     = s_arg_15;
  assign s_si_dmux15[3]     = s_sts_15;
  assign s_si_dmux15[4]     = s_sw_15;
  assign s_si_dmux15[5]     = s_fidbi_15;
  assign s_si_dmux15[6]     = s_gpr_15;
  assign s_si_dmux15[7]     = s_gpr_7;  // GPR Sign extended

  
  assign s_arg_0            = s_arg_15_0[0];
  assign s_arg_1            = s_arg_15_0[1];
  assign s_arg_2            = s_arg_15_0[2];
  assign s_arg_3            = s_arg_15_0[3];
  assign s_arg_4            = s_arg_15_0[4];
  assign s_arg_5            = s_arg_15_0[5];
  assign s_arg_6            = s_arg_15_0[6];
  assign s_arg_7            = s_arg_15_0[7];
  assign s_arg_8            = s_arg_15_0[8];
  assign s_arg_9            = s_arg_15_0[9];
  assign s_arg_10           = s_arg_15_0[10];
  assign s_arg_11           = s_arg_15_0[11];
  assign s_arg_12           = s_arg_15_0[12];
  assign s_arg_13           = s_arg_15_0[13];
  assign s_arg_14           = s_arg_15_0[14];
  assign s_arg_15           = s_arg_15_0[15];

  assign s_dbr_0            = s_dbr_15_0[0];
  assign s_dbr_1            = s_dbr_15_0[1];
  assign s_dbr_2            = s_dbr_15_0[2];
  assign s_dbr_3            = s_dbr_15_0[3];
  assign s_dbr_4            = s_dbr_15_0[4];
  assign s_dbr_5            = s_dbr_15_0[5];
  assign s_dbr_6            = s_dbr_15_0[6];
  assign s_dbr_7            = s_dbr_15_0[7];
  assign s_dbr_8            = s_dbr_15_0[8];
  assign s_dbr_9            = s_dbr_15_0[9];
  assign s_dbr_10           = s_dbr_15_0[10];
  assign s_dbr_11           = s_dbr_15_0[11];
  assign s_dbr_12           = s_dbr_15_0[12];
  assign s_dbr_13           = s_dbr_15_0[13];
  assign s_dbr_14           = s_dbr_15_0[14];
  assign s_dbr_15           = s_dbr_15_0[15];


  assign s_ea_0             = s_ea_15_0[0];
  assign s_ea_1             = s_ea_15_0[1];
  assign s_ea_2             = s_ea_15_0[2];
  assign s_ea_3             = s_ea_15_0[3];
  assign s_ea_4             = s_ea_15_0[4];
  assign s_ea_5             = s_ea_15_0[5];
  assign s_ea_6             = s_ea_15_0[6];
  assign s_ea_7             = s_ea_15_0[7];
  assign s_ea_8             = s_ea_15_0[8];
  assign s_ea_9             = s_ea_15_0[9];
  assign s_ea_10            = s_ea_15_0[10];
  assign s_ea_11            = s_ea_15_0[11];
  assign s_ea_12            = s_ea_15_0[12];
  assign s_ea_13            = s_ea_15_0[13];
  assign s_ea_14            = s_ea_15_0[14];
  assign s_ea_15            = s_ea_15_0[15];


  assign s_fidbi_0          = s_fidbi_15_0[0];
  assign s_fidbi_1          = s_fidbi_15_0[1];
  assign s_fidbi_2          = s_fidbi_15_0[2];
  assign s_fidbi_3          = s_fidbi_15_0[3];
  assign s_fidbi_4          = s_fidbi_15_0[4];
  assign s_fidbi_5          = s_fidbi_15_0[5];
  assign s_fidbi_6          = s_fidbi_15_0[6];
  assign s_fidbi_7          = s_fidbi_15_0[7];
  assign s_fidbi_8          = s_fidbi_15_0[8];
  assign s_fidbi_9          = s_fidbi_15_0[9];
  assign s_fidbi_10         = s_fidbi_15_0[10];
  assign s_fidbi_11         = s_fidbi_15_0[11];
  assign s_fidbi_12         = s_fidbi_15_0[12];
  assign s_fidbi_13         = s_fidbi_15_0[13];
  assign s_fidbi_14         = s_fidbi_15_0[14];
  assign s_fidbi_15         = s_fidbi_15_0[15];


  assign s_gpr_0            = s_gpr_15_0[0];
  assign s_gpr_1            = s_gpr_15_0[1];
  assign s_gpr_2            = s_gpr_15_0[2];
  assign s_gpr_3            = s_gpr_15_0[3];
  assign s_gpr_4            = s_gpr_15_0[4];
  assign s_gpr_5            = s_gpr_15_0[5];
  assign s_gpr_6            = s_gpr_15_0[6];
  assign s_gpr_7            = s_gpr_15_0[7];
  assign s_gpr_8            = s_gpr_15_0[8];
  assign s_gpr_9            = s_gpr_15_0[9];
  assign s_gpr_10           = s_gpr_15_0[10];
  assign s_gpr_11           = s_gpr_15_0[11];
  assign s_gpr_12           = s_gpr_15_0[12];
  assign s_gpr_13           = s_gpr_15_0[13];
  assign s_gpr_14           = s_gpr_15_0[14];
  assign s_gpr_15           = s_gpr_15_0[15];


  assign s_laa_1            = s_laa_3_1[0];
  assign s_laa_2            = s_laa_3_1[1];
  assign s_laa_3            = s_laa_3_1[2];

  assign s_lba_0            = s_lba_2_0[0];
  assign s_lba_1            = s_lba_2_0[1];
  assign s_lba_2            = s_lba_2_0[2];

  assign s_sts_0            = s_sts_15_0[0];
  assign s_sts_1            = s_sts_15_0[1];
  assign s_sts_2            = s_sts_15_0[2];
  assign s_sts_3            = s_sts_15_0[3];
  assign s_sts_4            = s_sts_15_0[4];
  assign s_sts_5            = s_sts_15_0[5];
  assign s_sts_6            = s_sts_15_0[6];
  assign s_sts_7            = s_sts_15_0[7];
  assign s_sts_8            = s_sts_15_0[8];
  assign s_sts_9            = s_sts_15_0[9];
  assign s_sts_10           = s_sts_15_0[10];
  assign s_sts_11           = s_sts_15_0[11];
  assign s_sts_12           = s_sts_15_0[12];
  assign s_sts_13           = s_sts_15_0[13];
  assign s_sts_14           = s_sts_15_0[14];
  assign s_sts_15           = s_sts_15_0[15];


  assign s_sw_0             = s_sw_15_0[0];
  assign s_sw_1             = s_sw_15_0[1];
  assign s_sw_2             = s_sw_15_0[2];
  assign s_sw_3             = s_sw_15_0[3];
  assign s_sw_4             = s_sw_15_0[4];
  assign s_sw_5             = s_sw_15_0[5];
  assign s_sw_6             = s_sw_15_0[6];
  assign s_sw_7             = s_sw_15_0[7];
  assign s_sw_8             = s_sw_15_0[8];
  assign s_sw_9             = s_sw_15_0[9];
  assign s_sw_10            = s_sw_15_0[10];
  assign s_sw_11            = s_sw_15_0[11];
  assign s_sw_12            = s_sw_15_0[12];
  assign s_sw_13            = s_sw_15_0[13];
  assign s_sw_14            = s_sw_15_0[14];
  assign s_sw_15            = s_sw_15_0[15];

  /*******************************************************************************
   ** Here all input connections are defined                                     **
   *******************************************************************************/
  assign s_gpr_15_0[15:0]   = GPR_15_0;
  assign s_f_15_0[15:0]     = F_15_0;
  assign s_a_15_0[15:0]     = A_15_0;
  assign s_ea_15_0[15:0]    = EA_15_0;
  assign s_dbr_15_0[15:0]   = DBR_15_0;
  assign s_arg_15_0[15:0]   = ARG_15_0;
  assign s_lba_2_0[2:0]     = LBA_2_0;
  assign s_sw_15_0[15:0]    = SW_15_0;
  assign s_laa_3_1[2:0]     = LAA_3_1;
  assign s_sts_15_0[15:0]   = STS_15_0;
  assign s_fidbi_15_0[15:0] = FIDBI_15_0;
  assign s_csidbs_4_0[4:0]  = CSIDBS_4_0;
  assign s_aluclk           = ALUCLK;
  assign s_alud2n           = ALUD2N;

  /*******************************************************************************
   ** Here all output connections are defined                                    **
   *******************************************************************************/
  assign D_15_0             = s_d_15_0_out[15:0];
  assign G_15_0             = s_g_15_0_out[15:0];

  /*******************************************************************************
   ** Here all sub-circuits are defined                                          **
   *******************************************************************************/

  MUX31LP GMUX15 (
      .A (s_ea),
      .B (s_ef),
      .D0(s_d_15_0_out[15]),
      .D1(s_a_15_0[15]),
      .D2(s_f_15_0[15]),
      .ZN(s_g_15_0_out[15])
  );

  MUX31LP GMUX14 (
      .A (s_ea),
      .B (s_ef),
      .D0(s_d_15_0_out[14]),
      .D1(s_a_15_0[14]),
      .D2(s_f_15_0[14]),
      .ZN(s_g_15_0_out[14])
  );

  MUX31LP GMUX13 (
      .A (s_ea),
      .B (s_ef),
      .D0(s_d_15_0_out[13]),
      .D1(s_a_15_0[13]),
      .D2(s_f_15_0[13]),
      .ZN(s_g_15_0_out[13])
  );

  MUX31LP GMUX12 (
      .A (s_ea),
      .B (s_ef),
      .D0(s_d_15_0_out[12]),
      .D1(s_a_15_0[12]),
      .D2(s_f_15_0[12]),
      .ZN(s_g_15_0_out[12])
  );

  MUX31LP GMUX11 (
      .A (s_ea),
      .B (s_ef),
      .D0(s_d_15_0_out[11]),
      .D1(s_a_15_0[11]),
      .D2(s_f_15_0[11]),
      .ZN(s_g_15_0_out[11])
  );

  MUX31LP GMUX10 (
      .A (s_ea),
      .B (s_ef),
      .D0(s_d_15_0_out[10]),
      .D1(s_a_15_0[10]),
      .D2(s_f_15_0[10]),
      .ZN(s_g_15_0_out[10])
  );

  MUX31LP GMUX9 (
      .A (s_ea),
      .B (s_ef),
      .D0(s_d_15_0_out[9]),
      .D1(s_a_15_0[9]),
      .D2(s_f_15_0[9]),
      .ZN(s_g_15_0_out[9])
  );

  MUX31LP GMUX8 (
      .A (s_ea),
      .B (s_ef),
      .D0(s_d_15_0_out[8]),
      .D1(s_a_15_0[8]),
      .D2(s_f_15_0[8]),
      .ZN(s_g_15_0_out[8])
  );

  MUX31LP GMUX7 (
      .A (s_ea),
      .B (s_ef),
      .D0(s_d_15_0_out[7]),
      .D1(s_a_15_0[7]),
      .D2(s_f_15_0[7]),
      .ZN(s_g_15_0_out[7])
  );

  MUX31LP GMUX6 (
      .A (s_ea),
      .B (s_ef),
      .D0(s_d_15_0_out[6]),
      .D1(s_a_15_0[6]),
      .D2(s_f_15_0[6]),
      .ZN(s_g_15_0_out[6])
  );

  MUX31LP GMUX5 (
      .A (s_ea),
      .B (s_ef),
      .D0(s_d_15_0_out[5]),
      .D1(s_a_15_0[5]),
      .D2(s_f_15_0[5]),
      .ZN(s_g_15_0_out[5])
  );

  MUX31LP GMUX4 (
      .A (s_ea),
      .B (s_ef),
      .D0(s_d_15_0_out[4]),
      .D1(s_a_15_0[4]),
      .D2(s_f_15_0[4]),
      .ZN(s_g_15_0_out[4])
  );

  MUX31LP GMUX3 (
      .A (s_ea),
      .B (s_ef),
      .D0(s_d_15_0_out[3]),
      .D1(s_a_15_0[3]),
      .D2(s_f_15_0[3]),
      .ZN(s_g_15_0_out[3])
  );

  MUX31LP GMUX2 (
      .A (s_ea),
      .B (s_ef),
      .D0(s_d_15_0_out[2]),
      .D1(s_a_15_0[2]),
      .D2(s_f_15_0[2]),
      .ZN(s_g_15_0_out[2])
  );

  MUX31LP GMUX1 (
      .A (s_ea),
      .B (s_ef),
      .D0(s_d_15_0_out[1]),
      .D1(s_a_15_0[1]),
      .D2(s_f_15_0[1]),
      .ZN(s_g_15_0_out[1])
  );

  MUX31LP GMUX0 (
      .A (s_ea),
      .B (s_ef),
      .D0(s_d_15_0_out[0]),
      .D1(s_a_15_0[0]),
      .D2(s_f_15_0[0]),
      .ZN(s_g_15_0_out[0])
  );




  CGA_ALU_OUTMUX_SEL8 DMUX15 (
      .D(s_d_15_0_out[15]),
      .E_7_0(s_e_dmux15[7:0]),
      .SI_7_0(s_si_dmux15[7:0])
  );


  CGA_ALU_OUTMUX_SEL8 DMUX14 (
      .D(s_d_15_0_out[14]),
      .E_7_0(s_e_dmux14[7:0]),
      .SI_7_0(s_si_dmux14[7:0])
  );

  CGA_ALU_OUTMUX_SEL8 DMUX13 (
      .D(s_d_15_0_out[13]),
      .E_7_0(s_e_dmux13[7:0]),
      .SI_7_0(s_si_dmux13[7:0])
  );

  CGA_ALU_OUTMUX_SEL8 DMUX12 (
      .D(s_d_15_0_out[12]),
      .E_7_0(s_e_dmux12[7:0]),
      .SI_7_0(s_si_dmux12[7:0])
  );

  CGA_ALU_OUTMUX_SEL8 DMUX11 (
      .D(s_d_15_0_out[11]),
      .E_7_0(s_e_dmux11[7:0]),
      .SI_7_0(s_si_dmux11[7:0])
  );

  CGA_ALU_OUTMUX_SEL8 DMUX10 (
      .D(s_d_15_0_out[10]),
      .E_7_0(s_e_dmux10[7:0]),
      .SI_7_0(s_si_dmux10[7:0])
  );

  CGA_ALU_OUTMUX_SEL8 DMUX9 (
      .D(s_d_15_0_out[9]),
      .E_7_0(s_e_dmux9[7:0]),
      .SI_7_0(s_si_dmux9[7:0])
  );

  CGA_ALU_OUTMUX_SEL8 DMUX8 (
      .D(s_d_15_0_out[8]),
      .E_7_0(s_e_dmux8[7:0]),
      .SI_7_0(s_si_dmux8[7:0])
  );

  CGA_CPU_ALU_OUTMUX_SEL7 DMUX7 (
      .D(s_d_15_0_out[7]),
      .E_6_0(s_e_dmux7[6:0]),
      .SI_6_0(s_si_dmux7[6:0])
  );

  CGA_ALU_OUTMUX_SEL8 DMUX6 (
      .D(s_d_15_0_out[6]),
      .E_7_0(s_e_dmux6[7:0]),
      .SI_7_0(s_si_dmux6[7:0])
  );

  CGA_ALU_OUTMUX_SEL8 DMUX5 (
      .D(s_d_15_0_out[5]),
      .E_7_0(s_e_dmux5[7:0]),
      .SI_7_0(s_si_dmux5[7:0])
  );

  CGA_ALU_OUTMUX_SEL8 DMUX4 (
      .D(s_d_15_0_out[4]),
      .E_7_0(s_e_dmux4[7:0]),
      .SI_7_0(s_si_dmux4[7:0])
  );

  CGA_ALU_OUTMUX_SEL8 DMUX3 (
      .D(s_d_15_0_out[3]),
      .E_7_0(s_e_dmux3[7:0]),
      .SI_7_0(s_si_dmux3[7:0])
  );

  CGA_ALU_OUTMUX_SEL8 DMUX2 (
      .D(s_d_15_0_out[2]),
      .E_7_0(s_e_dmux2[7:0]),
      .SI_7_0(s_si_dmux2[7:0])
  );

  CGA_ALU_OUTMUX_SEL8 DMUX1 (
      .D(s_d_15_0_out[1]),
      .E_7_0(s_e_dmux1[7:0]),
      .SI_7_0(s_si_dmux1[7:0])
  );

  CGA_ALU_OUTMUX_SEL8 DMUX0 (
      .D(s_d_15_0_out[0]),
      .E_7_0(s_e_dmux0[7:0]),
      .SI_7_0(s_si_dmux0[7:0])
  );

  CGA_ALU_OUTMUX_IDBS OUTMUX_IDBS
  (
      .sysclk(sysclk),
      .ALUCLK_EN(ALUCLK_EN),
      .ALUCLK(s_aluclk),
      .ALUD2N(s_alud2n),
      .CSIDBS_4_0(s_csidbs_4_0[4:0]),
      .EA(s_ea),
      .EAARG(s_eaarg),
      .EBARG(s_ebarg),
      .EABARG(s_eabarg),
      .EARG(s_earg),
      .EBMG(s_ebmg),
      .EDBR(s_edbr),
      .EF(s_ef),
      .EFIDB(s_efidb),
      .EGPRH(s_egprh),
      .EGPRL(s_egprl),
      .EGPRS(s_egprs),
      .ESTS(s_ests),
      .ESWAP(s_eswap)
  );

endmodule
