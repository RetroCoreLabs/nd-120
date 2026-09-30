/**************************************************************************
** ND120 CPU, MM&M                                                       **
** IO/DCD                                                                **
** IO DECODING                                                           **
** SHEET 38 of 50                                                        **
**                                                                       **
** Last reviewed: 14-DEC-2024                                            **
** Ronny Hansen                                                          **
***************************************************************************/

module IO_DCD_38 (
    input sysclk,    // System clock in FPGA
    input sys_rst_n, // System reset in FPGA
    input CLK_EN,      // CLK rise clock-enable pulse (FPGA_FF_MODE, else 0)
    input CLK_FALL_EN, // CLK fall clock-enable pulse (FPGA_FF_MODE, else 0)

    input       BDRY50_n,  //! Bus Data Ready (Delayed 50ns) (from BIF_5.BDRY50_n)
    input       BRK_n,  //! CPU Break Signal (from CPU_15.BRK_n)
    input       CLK,  //! Main system clock (same net as CPU_15.CLK)
    input [4:0] CSCOMM_4_0,  //! Control Store Command (5 bits) (from IO_37.CSCOMM_4_0)
    input [4:0] CSIDBS_4_0,  //! Control Store IDB Source (5 bits) (from IO_37.CSIDBS_4_0)
    input [1:0] CSMIS_1_0,  //! Control Store MIS signal (2 bits) (from IO_37.CSMIS_1_0)
    input       DAP_n,  //! Data Present (from BIF_5.DAP_n)
    input       EORF_n,  //! Enable output register file (same net as CPU_15.EORF_n)
    input       HIT,  //! Cache hit (from CPU_15.HIT)
    input       ICONTIN_n,  //! Input signal from "C PLUG", signal B15 - CONTINUE_n (from ND3202D.CONTINUE_n)

    input       ILOAD_n,  //! Input signal from "C PLUG", signal B12 - LOAD_n (from ND3202D.LOAD_n)
    input       ISTOP_n,  //! Input signal from "C PLUG", signal B16 - STOP_n (from ND3202D.STOP_n)
    input       LCS_n,  //! Load control store (same net as CPU_15.LCS_n)
    input       LSHADOW,  //! Latch Shadow signal (from CPU_15.LSHADOW)
    input [1:0] OC_1_0,  //! Input signal from "A PLUG", signal C6 (OC0) and A6 (OC1)       => (TO IO OC_1_0) (from ND3202D.OC_1_0)
    input       OPCLCS,  //! COMMAND 36.2 LCS - Load control store from PROM and perform a Master Clear (from CPU_15.OPCLCS)
    input       OSCCL_n,  //! Input signal from "A PLUG", signal B3 - OSCCL_n                => (TO IO OSCCL_n) (from ND3202D.OSCCL_n)
    input       PONI,   //! Memory Protection ON, PONI=1
    input       POWSENSE_n,  //! Power Sense (from ND120_CORE.POWSENSE_n)
    input       REF_n,
    input       RMM_n,
    input       SEL5MS_n,  //! SEL5MS if active will trigger RTC after 5 ms, not 20ms) (from ND3202D.SEL5MS_n)
    input [1:0] STAT_4_3,  //! Status bits 4 and 3 from PANEL/CALENDAR CPU 68705
    input       SWMCL_n,  //! tied to 1 (in IO_37)
    input       UCLK,  //! Microcode clock (same net as CPU_15.UCLK)
    input       XTAL1,  //! XTAL1 = 39.3216MHZ (from ND3202D.CLOCK_1)
    input       XTAL2,  //! CPU + bus + device domain (ND3202D sysclk/CLOCK_1/CLOCK_2) (from ND120_CORE.clk_cpu)

    input  [7:0] IDB_7_0_IN,  //! Internal Data Bus 7:0 IN (same net as IO_UART_42.IDB_7_0_IN)
    output [7:0] IDB_7_0_OUT,


    output CA10,     //! Cache address bit 10 (to CPU_15.CA10)
    output CCLR_n,   //! Cache clear (to CPU_15.CCLR_n)
    output CEUART_n,  //! Chip Enable UART (to IO_UART_42.CEUART_n)
    output CLEAR_n,
    output DT_n,     //! Data transfer (to CPU_15.DT_n)
    output DVACC_n,   //! DGA access qualifier (DECODE_DGA_COMM A227, arrives as XDVN) - not the CGA's VACC
    output ECREQ,
    output ECSR_n,   //! Enable control store read (to CPU_15.ECSR_n)
    output EDO_n,    //! Enable data out (to CPU_15.EDO_n)
    output EIOR_n,   //! Enable I/O Read (to IO_UART_42.EIOR_n)
    output EMPID_n,  //! Enable memory parity interrupt disable (to CPU_15.EMPID_n)
    output EMP_n,
    output EPANS_n,
    output ESTOF_n,  //! Enable store overflow (to CPU_15.ESTOF_n)
    output FETCH,
    output FMISS,    //! Cache fetch miss (to CPU_15.FMISS)
    output FORM_n,   //! Format instruction (to CPU_15.FORM_n)
    output FUL_n,
    output IORQ_n,
    output LHIT,
    output MCL,
    output MREQ_n,   //! Memory request (to CPU_15.MREQ_n)
    output OSC,
    output PANOSC,
    output PAN_n,    //! Panel interrupt request, active low (from the DGA, DECODE_DGA_POW.PANN)
    output [7:0] PA_7_0,  //! Data from FIFO in DGA (to IO_PANCAL_40.PA_7_0)
    output PA_n,
    output POWFAIL_n,  //! Power failure detected (to CPU_15.POWFAIL_n)
    output PPOSC,    //! Panel Oscillator (to IO_UART_42.PPOSC)
    output PS_n,
    output REFRQ_n,
    output RINR_n,
    output RT_n,     //! Reset trap (to CPU_15.RT_n)
    output RUART_n,  //! Read UART (HIGH=Write UART) (to IO_UART_42.RUART_n)
    output RWCS_n,  // (NOT CONNECTED IN SHEET 39) - find signal from one of the PAL's ??
    output SHORT_n,
    output SIOC_n,
    output SLOW_n,
    output SSEMA_n,
    output STOC_n,   //! Store overflow check (to CPU_15.STOC_n)
    output STP,      //! Output-signal to "C PLUG", signal B14 RUN~ (driven by Stop flip-flop: low while CPU is running) (to ND3202D.RUN_n)
    output TOUT,
    output TRAALD_n,
    output VAL,
    output WCHIM_n,  //! Write cache hit memory (to CPU_15.WCHIM_n)
    output WRITE,    //! Write cycle active (to CPU_15.WRITE)
    output EPAN_n  // Signal on the DGA chip (not connected in sheet 39). Maybe replaced by a PAL?
);


  // DCD  BUS signal group documented in ND doc

  // DCDPANCALI (input) = RMM_n, STAT_4_3
  // DCDPANCALO (output) = EMP_n, EPANS_n, FUL_n, LHIT, PANOSC, PA[7:0], VAL

  // DCDCNTLI (input) = BDRY50_n, BRK_n, DAP_n, HIT, LCS_n, LSHADOW, OPCLCS, PONI, REF_n
  // DCDCNTLO (output) = CA10, CCLR_n, CLEAR_n, DT_n, DCACC_n, ECREQ, ECSR_n, EDO_n,  EMPID_n, ESTOF_n, FETCH, FMISS, FORM_n, IORQ_n, MCL, MREQ_n, PA_n, PS_n, REFRQ_n
  //                     RT_n, RWCS_n, SHORT_n, SLOW_n, SSEMA_n, STOC_n, STP, TOUT, WCHIM_n, WRITE

  /*******************************************************************************
   ** The wires are defined here                                                 **
   *******************************************************************************/
  wire [1:0] s_csmis_1_0;
  wire [1:0] s_oc_1_0;
  wire [1:0] s_stat_4_3;
  wire [3:0] s_dga_idb_3_0_out;
  wire [4:0] s_cscomm_4_0;
  wire [4:0] s_csidbs_4_0;
  wire [7:0] s_IDB_7_0_in;
  wire [7:0] s_IDB_7_0_out;
  wire [7:0] s_pa_7_0;

  wire       s_bdry50_n;
  wire       s_brk_n;
  wire       s_ca10;
  wire       s_cclr_n;
  wire       s_ceuart_n;
  wire       s_clear_n;
  wire       s_clk;  // bus IOTIM B
  wire       s_closc;
  wire       s_dap_n;
  wire       s_div_16;
  wire       s_dt_n;
  wire       s_dvacc_n;
  wire       s_ecreq;
  wire       s_ecsr_n;
  wire       s_edo_n;
  wire       s_eior_n;
  wire       s_emp_n;
  wire       s_empid_n;
  wire       s_eorf_n;
  wire       s_epan_n;
  wire       s_epans_n;
  wire       s_estof_n;
  wire       s_fetch;
  wire       s_fmiss;
  wire       s_form_n;
  wire       s_ful_n;
  wire       s_gated_swmcl_n;
  wire       s_hit;
  wire       s_icontin_n;
  wire       s_iload_n;
  wire       s_ioreq_n;
  wire       s_istop_n;
  wire       s_lcs_n;
  wire       s_lhit;
  wire       s_lshadow;
  wire       s_mcl;
  wire       s_mreq_n;
  wire       s_oc0_n;
  wire       s_oc0;
  wire       s_oc1_and_xtal2_n;
  wire       s_oc1;
  wire       s_opclcs;
  wire       s_osc_inp1;
  wire       s_osc_inp2;
  wire       s_osc;
  wire       s_oscccl_n;
  wire       s_pa_n;
  wire       s_pan_n;
  wire       s_panosc;
  wire       s_poni;
  wire       s_power_on_zener;
  wire       s_powfail_n;
  wire       s_powsense_n;
  wire       s_powsense;
  wire       s_pposc;
  wire       s_ps_n;
  wire       s_pwcl;
  wire       s_ref_n;
  wire       s_refrq_n;
  wire       s_rinr_n;
  wire       s_rmm_n;
  wire       s_rt_n;
  wire       s_ruart_n;
  wire       s_rwcs_n;
  wire       s_sel5ms_n;
  wire       s_short_n;
  wire       s_sioc_n;
  wire       s_slow_n;
  wire       s_ssema_n;
  wire       s_stoc_n;
  wire       s_stp;
  wire       s_swmcl_n;
  wire       s_tout;
  wire       s_traald_n;
  wire       s_uclk;
  wire       s_val;
  wire       s_wchim_n;
  wire       s_write;
  wire       s_XRTOSC;
  wire       s_XTAL1;
  wire       s_XTAL2;



  /*******************************************************************************
   ** Here all input connections are defined                                     **
   *******************************************************************************/

  // BUS signals
  assign s_csmis_1_0[1:0]   = CSMIS_1_0;
  assign s_stat_4_3[1:0]    = STAT_4_3;
  assign s_csidbs_4_0[4:0]  = CSIDBS_4_0;
  assign s_cscomm_4_0[4:0]  = CSCOMM_4_0;
  assign s_oc_1_0[1:0]      = OC_1_0;
  assign s_IDB_7_0_in[7:0]  = IDB_7_0_IN[7:0];

  // Signals
  assign s_bdry50_n         = BDRY50_n;
  assign s_brk_n            = BRK_n;
  assign s_clk              = CLK;
  assign s_dap_n            = DAP_n;
  assign s_eorf_n           = EORF_n;
  assign s_hit              = HIT;
  assign s_icontin_n        = ICONTIN_n;
  assign s_iload_n          = ILOAD_n;
  assign s_istop_n          = ISTOP_n;
  assign s_lcs_n            = LCS_n;
  assign s_lshadow          = LSHADOW;
  assign s_opclcs           = OPCLCS;
  assign s_oscccl_n         = OSCCL_n;
  assign s_poni             = PONI;
  assign s_powsense_n       = POWSENSE_n;
  assign s_ref_n            = REF_n;
  assign s_rmm_n            = RMM_n;
  assign s_sel5ms_n         = SEL5MS_n;
  assign s_swmcl_n          = SWMCL_n;  // Software Master Clear (MCL) negated
  assign s_uclk             = UCLK;
  assign s_XTAL1            = XTAL1;
  assign s_XTAL2            = XTAL2;

  /*******************************************************************************
   ** Here all output connections are defined                                    **
   *******************************************************************************/
  assign CA10               = s_ca10;
  assign CCLR_n             = s_cclr_n;
  assign CEUART_n           = s_ceuart_n;
  assign CLEAR_n            = s_clear_n;
  assign DT_n               = s_dt_n;
  assign DVACC_n            = s_dvacc_n;
  assign ECREQ              = s_ecreq;
  assign ECSR_n             = s_ecsr_n;
  assign EDO_n              = s_edo_n;
  assign EIOR_n             = s_eior_n;
  assign EMP_n              = s_emp_n;
  assign EMPID_n            = s_empid_n;
  assign EPAN_n             = s_epan_n;
  assign EPANS_n            = s_epans_n;
  assign ESTOF_n            = s_estof_n;
  assign FETCH              = s_fetch;
  assign FMISS              = s_fmiss;
  assign FORM_n             = s_form_n;
  assign FUL_n              = s_ful_n;
  assign IORQ_n             = s_ioreq_n;
  assign LHIT               = s_lhit;
  assign MCL                = s_mcl;
  assign MREQ_n             = s_mreq_n;
  assign OSC                = s_osc;
  assign PA_7_0             = s_pa_7_0[7:0];
  assign PA_n               = s_pa_n;
  assign PAN_n              = s_pan_n;
  assign PANOSC             = s_panosc;
  assign POWFAIL_n          = s_powfail_n;
  assign PPOSC              = s_pposc;
  assign PS_n               = s_ps_n;
  assign REFRQ_n            = s_refrq_n;
  assign RINR_n             = s_rinr_n;
  assign RT_n               = s_rt_n;
  assign RUART_n            = s_ruart_n;
  assign RWCS_n             = s_rwcs_n;
  assign SHORT_n            = s_short_n;
  assign SIOC_n             = s_sioc_n;
  assign SLOW_n             = s_slow_n;
  assign SSEMA_n            = s_ssema_n;
  assign STOC_n             = s_stoc_n;
  assign STP                = s_stp;
  assign TOUT               = s_tout;
  assign TRAALD_n           = s_traald_n;
  assign VAL                = s_val;
  assign WCHIM_n            = s_wchim_n;
  assign WRITE              = s_write;


  // IDB[7:0] out = IDB[7:0] in (Except if EPAN_n is low, then IDB out is the IDB 3-0 from the DGA chip)

  // Assign the upper 4 bits directly from the input to the output
  // WRONG! assign s_IDB_7_0_out[7:4] = s_IDB_7_0_in[7:4];

  // Assign to 0 as its not output
  assign s_IDB_7_0_out[7:4] = 4'b0; 

  // Conditionally assign the lower 4 bits based on the state of EPAN_n
  assign s_IDB_7_0_out[3:0] = s_epan_n ? 4'b0 : s_dga_idb_3_0_out[3:0];

  // Connect the intermediate signal to the final output
  assign IDB_7_0_OUT        = s_IDB_7_0_out;


  /*******************************************************************************
   ** Here all in-lined components are defined                                   **
   *******************************************************************************/

  // Power-on-zener  (schematic shows a zener diode circuit, that after anlysis needs 14 uSec to go from logic high to low - based on the 10nF capacitor and 1k resistor)
  // At 40Mhz that is 567 clock cycles

   // Power On Clear - 10ms delay
   reg regPowerOnClear;
   reg [10:0] regPowerOnDelay;

   assign s_power_on_zener   = regPowerOnClear;


  // NOT Gate
  assign s_powsense         = ~s_powsense_n;

  // OC 0 and 1
  assign s_oc0              = s_oc_1_0[0];
  assign s_oc0_n            = ~s_oc0;
  assign s_oc1              = s_oc_1_0[1];



  always @(posedge sysclk) begin
    if (sys_rst_n == 1'b0) begin
      regPowerOnClear <= 0;  // Start with 1, and then set to 0 after 14us delay
      regPowerOnDelay <= 0;
    end else begin
      if (regPowerOnClear == 0) begin
        if (regPowerOnDelay > 10) begin  //its 1418 clock cycles if we have 100MHZ- 575?. Make it easy for debugging cnt = 10
          regPowerOnClear <= 1;
        end else begin
          regPowerOnDelay <= regPowerOnDelay + 1;
        end
      end
    end
  end


  // Test signals
  wire TESTE;
  assign TESTE = 1'b0;  // Tied to GND on production PCB (TESTE=1 = factory test mode, runs timers 64x faster)

  //wire XTESTO;



  /***************
   ** Components **
  ****************/

  // Calculate OSC signal
  assign s_osc_inp1 = ~(s_XTAL1 & s_oc1 & s_oc0);  // Chip 10F
  assign s_osc_inp2 = ~(s_oc0_n & s_oc1_and_xtal2_n);
// ND120_FORCE_FPGA_OSC (01-SEP-2026): take the FPGA branch even in a Verilator
// build. The two branches are NOT equivalent - one is a combinational decode of
// XTAL/oc0/oc1, the other a clean clock net - and OSC clocks the AM29C821 delay
// chain and PAL_44403C (DLY0/DLY1). So a simulator run is NOT a like-for-like
// reference for anything that depends on OSC phase, which includes cycle
// timing. Needed to tell a genuine MiSTer fault from a sim-vs-FPGA difference
// that every board shares (Nexys and Tang boot on the FPGA branch).
`ifdef ND120_FORCE_FPGA_OSC
  assign s_osc = s_XTAL1;
`elsif VERILATOR_SIM
  assign s_osc = ~(s_osc_inp1 & s_osc_inp2);
`else
  // FPGA: OSC must be a CLEAN clock net, not a combinational LUT decode. The
  // memory controller (PAL_44902A) clocks the whole DRAM state machine on OSC,
  // while the BRAM + address latches clock on the BUFG sysclk. A LUT-generated
  // OSC is phase-shifted from sysclk and can glitch on the oc0/oc1/XTAL edges ->
  // the state machine mis-clocks and every memory read returns a fixed value.
  // On the FPGA XTAL1 = XTAL2 = clk1 = clk_cpu (BUFG), so the clock select is
  // moot; drive OSC straight from that clean net so OSC == sysclk == clk_cpu.
  assign s_osc = s_XTAL1;
`endif

  // The AND is done in a 74321 chip (Positive NAND Schmitt Trigger)
  assign s_oc1_and_xtal2_n = ~(s_oc1 & s_XTAL2);

  // Calculate CLOSC signal (Clear Oscillator)
  assign s_closc = ~(s_oscccl_n & s_power_on_zener);

  // Calculate PWCL signal
  assign s_gated_swmcl_n = ~(s_power_on_zener & s_swmcl_n);
  assign s_pwcl = s_gated_swmcl_n | s_opclcs;



  /*******************************************************************************
   ** Here all sub-circuits are defined                                          **
   *******************************************************************************/

  // PPOSC baud-rate reference always derived from sysclk (100MHz/8 = 12.5MHz),
  // NOT from XTAL1/clk1, so the UART speed is unaffected by SW2 clock divider.
`ifdef FPGA_FF_MODE
  // P3 (docs/plan-fix-unconstrained-clocks.md): the two ripple 74393s made
  // s_div_16 / s_XRTOSC register-driven clock roots. One synchronous 8-bit
  // counter is bit-exact to the cascade (the second counter incremented on
  // the s_div_16 fall = bits[3:0] wrap = bit 4 of a plain binary counter),
  // only shifted from negedge to posedge sysclk.
  reg [7:0] r_rt_cnt;
  always @(posedge sysclk) begin
    if (s_closc) r_rt_cnt <= 8'd0;
    else r_rt_cnt <= r_rt_cnt + 8'd1;
  end
  assign s_pposc  = r_rt_cnt[2];  // period 8 sysclk (12.5MHz at 100MHz, for UART)
  assign s_div_16 = r_rt_cnt[3];
  assign s_XRTOSC = r_rt_cnt[7];  // period 256 sysclk -> RTOSC to DGA
`else
  TTL_74393 CHIP_13C_1 (
      .CLK_n(sysclk),
      .RESET(s_closc),
      .QA(),
      .QB(),
      .QC(s_pposc),  // Signal PPOSC leaving DCD (100MHz/8 = 12.5MHz for UART)
      .QD(s_div_16)
  );

  TTL_74393 CHIP_13C_2 (
      .CLK_n(s_div_16),
      .RESET(s_closc),
      .QA(),
      .QB(),
      .QC(),
      .QD(s_XRTOSC)  // Signal RTOSC going to DGA (153.6Khz)
  );
`endif





  DECODE_DGA DGA (
      .sysclk(sysclk),
      .sys_rst_n(sys_rst_n),
      .XCLK_EN(CLK_EN),           // P2 clock-enable (CLK rise, FPGA_FF_MODE)
      .XCLK_FALL_EN(CLK_FALL_EN), // P2 clock-enable (CLK fall, FPGA_FF_MODE)
      /** INPUT **/

      .XBDN(s_bdry50_n),
      .XBRN(s_brk_n),
      .XCLK(s_clk),
      .XCLO(s_closc),
      .XCON(s_icontin_n),
      .XCO_4_0(s_cscomm_4_0),
      .XDAN(s_dap_n),
      .XEFN(s_ref_n),
      .XEON(s_eorf_n),
      .XHIN(~s_hit),  // XHIT_n (negated)
      .XID_4_0(s_csidbs_4_0),

      .XLCN(s_lcs_n),
      .XLON(s_iload_n),
      .XLSH(s_lshadow),
      .XMI_1_0(s_csmis_1_0),
      .XPOI(s_poni),
      .XPOW(s_powsense),
      .XPWC(s_pwcl),
      .XRMN(s_rmm_n),
      .XRTO(s_XRTOSC),  // XRTOSC
      .XS5N(s_sel5ms_n),
      .XST_4_3(s_stat_4_3),
      .XTES(TESTE),
      .XTON(s_istop_n),
      .XUCK(s_uclk),

      // IDB IN and OUT
      .XIDB_7_0_IN (s_IDB_7_0_in),
      .XIDB_3_0_OUT(s_dga_idb_3_0_out),

      /** OUTPUT **/
      .XA_7_0(s_pa_7_0),
      .XC10(s_ca10),
      .XCLN(s_clear_n),
      .XCRN(s_cclr_n),
      .XCSN(s_ecsr_n),
      .XDON(s_edo_n),
      .XDTN(s_dt_n), // Output from DGA_COMM when EXAMINE, DEPOSIT, AREAD, READ or WRITE
      .XDVN(s_dvacc_n),
      .XECR(s_ecreq),
      .XEMN(s_emp_n),
      .XEPN(s_epan_n),
      .XESN(s_estof_n),
      .XEUN(s_ceuart_n),
      .XFEC(s_fetch),
      .XFMI(s_fmiss),
      .XFON(s_form_n),
      .XFUN(s_ful_n),
      .XION(s_eior_n),
      //            .XI_3_0_C(),
      //            .XI_3_0_O(),
      .XLHN(s_lhit),
      .XMCL(s_mcl),
      .XMRN(s_mreq_n),
      .XOCN(s_sioc_n),
      .XPAN(s_pa_n),
      .XPEN(s_ps_n),
      .XPFN(s_powfail_n),
      .XPIN(s_empid_n),
      .XPNN(s_pan_n),
      .XPSC(s_panosc),
      .XPSN(s_epans_n),
      .XRFN(s_refrq_n),
      .XRIN(s_rinr_n),
      .XRQN(s_ioreq_n),
      .XRTN(s_rt_n),
      .XRUN(s_ruart_n),
      .XRWN(s_rwcs_n),  // (NOT CONNECTED IN SHEET 39)
      .XSCN(s_stoc_n),
      .XSHN(s_short_n),
      .XSSN(s_ssema_n),
      .XSTP(s_stp), // output (STP indicates the Stop flip-flop is set) (from DGA_POW)
      .XSWN(s_slow_n),
      //.XTEO(XTESTO),
      .XTEO(),  // TEST OUTPUT (NOT CONNECTED IN SHEET 39)
      .XTOT(s_tout),
      .XTRN(s_traald_n),
      .XVAL(s_val),
      .XWHN(s_wchim_n),
      .XWRI(s_write)

  );

endmodule
