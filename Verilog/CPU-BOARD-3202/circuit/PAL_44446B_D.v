/**************************************************************************
** PAL_44446B_D - sysclk-domain mirror of PAL_44446B (UBADEC)            **
** Same equations; the four registers sample on sysclk with a rising-    **
** edge ENABLE on the original CK (DBAPR) instead of using it as a       **
** clock net (routed-net-as-clock breaks the write phase on FPGA -       **
** see docs/nd120-dram-memory.md section 5). PAL file itself untouched.  **
** Pattern: CYC_CC_D / CYC_TERM_D.                                       **
** Last reviewed: 8-JUL-2026  Ronny Hansen                               **
***************************************************************************/
module PAL_44446B_D (
    input sysclk,    //! System clock (for the FF-mode _D PAL mirrors) (from MEM_ADEC_45.sysclk)
    input sys_rst_n,  //! System reset (from MEM_ADEC_45.sys_rst_n)
    input CK,        // DBAPR - used as an edge-detected ENABLE here
    input OE_n,      //! Bus Grant (from MEM_RAMC_50.BGNT_n)
    input DBAPR,     //! BUS Address Present (from MEM_43.DBAPR)
    input MOFF_n,    //! tied to 1 (in MEM_ADEC_45)
    input BINPUT_n,  //! Bus Input Enable (from MEM_43.IBINPUT_n)
    input BMEM_n,    //! BUS MEMORY Enable (from MEM_43.BMEM_n)
    input BD20_n,    //! Bus Data and Address (bits 23:19 negated) (from MEM_43.BD_23_19_n[1])
    input BD21_n,    //! Bus Data and Address (bits 23:19 negated) (from MEM_43.BD_23_19_n[2])
    input BD22_n,    //! Bus Data and Address (bits 23:19 negated) (from MEM_43.BD_23_19_n[3])
    input BD23_n,    //! Bus Data and Address (bits 23:19 negated) (from MEM_43.BD_23_19_n[4])
    output AOK,
    output DDBAPR,
    output MSIZE1_n,  //! I1 - MSIZE1_n (to PAL_44904B.MSIZE1_n)
    output BANK2,
    output BANK1,
    output BANK0,
    output MWRITE_n
);
  wire BD20 = ~BD20_n;
  wire BD21 = ~BD21_n;
  wire BD22 = ~BD22_n;
  wire BD23 = ~BD23_n;
  wire MOFF = ~MOFF_n;
  wire BINPUT = ~BINPUT_n;

  reg BANK0_n_reg, BANK1_n_reg, BANK2_n_reg, MWRITE_reg;
  reg ck_d;
  always @(posedge sysclk) begin
    if (!sys_rst_n) begin
      ck_d <= 0;
      BANK0_n_reg <= 1; BANK1_n_reg <= 1; BANK2_n_reg <= 1;
      MWRITE_reg <= 0;
    end else begin
      ck_d <= CK;
      if (CK && !ck_d) begin  // one capture per CK (DBAPR) rise
        BANK0_n_reg <= BD21 | BD20;
        BANK2_n_reg <= BD21 | BD20_n;
        BANK1_n_reg <= BD21_n | BD20;
        MWRITE_reg  <= BINPUT;
      end
    end
  end

  assign BANK2 = OE_n ? 1'b0 : ~BANK2_n_reg;
  assign BANK1 = OE_n ? 1'b0 : ~BANK1_n_reg;
  assign BANK0 = OE_n ? 1'b0 : ~BANK0_n_reg;
  assign MWRITE_n = OE_n ? 1'b0 : ~MWRITE_reg;

  // ND120_ONBOARD_2MB: the 2 MB variant of this board. DERIVED, NOT FROM A PAL
  // DUMP. Real 3202D boards were fitted with 2, 4 or 6 MB (the size display
  // described in MEM_ADEC_45.v: 100 = 2 MB, 200 = 4 MB, 300 = 6 MB); the
  // equations in this file are the 4 MB programming. The 2 MB form here keeps
  // only the first 2 MB block (address bit 20 = 0, BANK0), following the
  // original listing's own note that each address line in the decode covers
  // one block ("EACH LINE R...", "THE 4MB (2M..." in PAL_44445B). Above 2 MB
  // the board then does not answer and the CPU raises memory out of range, as
  // a 2 MB board would. Only the Azure build defines it
  // (Verilog/fpga/azure-x930613/docs/00-plan.md).
`ifdef ND120_ONBOARD_2MB
  assign AOK = ~(BMEM_n | BD23 | BD22 | BD21 | BD20 | MOFF);  // 2 MB (derived)
`else
  assign AOK = ~(BMEM_n | BD23 | BD22 | BD21 | MOFF);
`endif
  assign DDBAPR = DBAPR;
  assign MSIZE1_n = 1;
endmodule
