/**************************************************************************
** ND120 CPU, MM&M                                                       **
** CPU/MMU/CSR                                                           **
** CACHE STATUS REGISER                                                  **
** SHEET 26 of 50                                                        **
**                                                                       **
** Last reviewed: 29-JAN-2025                                            **
** Ronny Hansen                                                          **
***************************************************************************/
module CPU_MMU_CSR_26 (
    input STP,    //! Stop signal (from CPU_MMU_24.STP)
    input EMPID_n,  //! Interrupt disable (from CPU_MMU_24.EMPID_n)
    input EDO_n,  //! Enable data output (from CPU_MMU_24.EDO_n)
    input LCS_n,  //! Load Control Store
    input PD2,    //! Power Down 2

    input CUP,    //! Cache Updated (CUP) goes to IDB0 when ECSR_n is low 
    input CON,    //! Cache ON (CON) goes to IDB1 when ECSR_n is low. CON_n goes to IDB2
    input ECSR_n, //! Enable Cache Status Reg

    // IF PD2 goes active to 1, then all B-signals goes to high-impediance aka 0)
    output BSTP,      //! Buffered STP 
    output BEMPID_n,  //! Buffered EMPID_n
    output BEDO_n,    //! Buffered EDO_n
    output BLCS_n,    //! Buffered LCS_n

    output [3:0] IDB_3_0  // Bit 0=CUP, Bit 1=CON, Bit 2= CON_n, Bit 3=1 (FIN-Cache Clear finished. Not currently enabled)
);



  // This code replaces one 74244 (CHIP 27H)
  // 74LS244 (NONE negated outputs)
  // Octal Buffers and Line Drivers With 3-State Outputs


  assign BSTP = PD2 ? 1'b0 : STP;
  assign BEMPID_n = PD2 ? 1'b0 : EMPID_n;
  assign BEDO_n = PD2 ? 1'b0 : EDO_n;
  assign BLCS_n = PD2 ? 1'b0 : LCS_n;

  wire [3:0] idb = {1'b1, ~CON, CON, CUP};

  assign IDB_3_0 = ECSR_n ? 4'b0 : idb;

endmodule
