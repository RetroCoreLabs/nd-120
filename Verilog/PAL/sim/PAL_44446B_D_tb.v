/**************************************************************************
** ND120 PAL unit test                                                   **
** PAL_44446B (UBADEC, 6G, PAL16R4) + PAL_44446B_D sysclk mirror         **
**                                                                       **
** DMA ADDRESS DECODE FOR 4MB MEMORY (sheet 45). Both implementations    **
** run side by side against ONE golden model re-derived INDEPENDENTLY    **
** from the PALASM equations in the PAL_44446B.v header comments         **
** (PAL16R4: Q0-Q3 registered on CK, inverting, OE_n tri-state gated;    **
** B outputs combinational). On the board CK is WIRED TO DBAPR ("PAL     **
** input signal DBAPR is connected to PAL CK pin (AND I0)"), and this    **
** tb keeps that tie:                                                    **
**   registered on CK (=DBAPR) rise, one-hot from BD21:20 (active-low    **
**   pins, so BDx = ~BDx_n):                                             **
**     00 -> BANK0, 01 -> BANK2, 10 -> BANK1, 11 -> none                 **
**     (BANK1/BANK2 swapped - the 060687 JLB PALASM note, matching       **
**     PAL_44445B's PPN decode)                                          **
**     MWRITE <= BINPUT (= ~BINPUT_n; the 2/1-86 "BOTH SIDES OF MWRITE   **
**     EQUATION INVERTED" note)                                          **
**   AOK    = ~(BMEM_n | BD23 | BD22 | BD21 | MOFF)   (4 MB limit; BD20  **
**            is NOT an AOK literal - checked exhaustively)              **
**   DDBAPR = DBAPR (combinational pass-through)                         **
**   MSIZE1_n = 1 constant (MSIZE1 tied low)                             **
** AUDIT RESULT: gates match the PALASM comments - no transcription      **
** error found in PAL_44446B.v or PAL_44446B_D.v.                        **
**                                                                       **
** PINNED (gate behavior, flagged):                                      **
**  PIN-1 OE_n=1 drives ALL Q outputs 0 INCLUDING MWRITE_n=0, unlike     **
**        the sibling PAL_44445B which drives MWRITE_n=1 when disabled.  **
**        The asymmetry is masked by the grant gating in MEM_ADEC_45.    **
**  PIN-2 PAL_44446B_D only: sys_rst_n forces BANK*_n_reg=1/MWRITE=0     **
**        (enabled outputs BANK=000, MWRITE_n=1) and holds until the     **
**        next CK rise; the base PAL has no reset and holds its state.   **
**        The tb tracks the two register sets separately across resets.  **
**                                                                       **
** _D contract (MEM_ADEC_45 usage): CK is generated in the sysclk        **
** domain, at least one sysclk wide; observation is two negedges after   **
** any change. Resets are only applied while CK is LOW (releasing under  **
** a held-high CK would make the _D re-capture - never exercised by the  **
** parent).                                                              **
**                                                                       **
** Run: make test-44446b-d (PAL/sim)                                     **
**                                                                       **
** Last reviewed: 01-AUG-2026                                            **
** Ronny Hansen                                                          **
***************************************************************************/
`timescale 1ns / 1ps

module PAL_44446B_D_tb;

  parameter EXPECTED_CHECKS = 61495;

  reg sysclk = 0;
  always #10 sysclk = ~sysclk;

  reg sys_rst_n = 0;

  // Shared stimulus: CKE drives BOTH the CK pin and the DBAPR input (the
  // board tie). The remaining inputs are free.
  reg CKE = 0;
  reg OE_n = 0;
  reg MOFF_n = 1;
  reg BINPUT_n = 1;
  reg BMEM_n = 1;
  reg BD20_n = 1;
  reg BD21_n = 1;
  reg BD22_n = 1;
  reg BD23_n = 1;

  // Base PAL outputs
  wire b_AOK, b_DDBAPR, b_MSIZE1_n, b_BANK2, b_BANK1, b_BANK0, b_MWRITE_n;
  // _D mirror outputs
  wire d_AOK, d_DDBAPR, d_MSIZE1_n, d_BANK2, d_BANK1, d_BANK0, d_MWRITE_n;

  PAL_44446B base (
      .CK(CKE),
      .OE_n(OE_n),
      .DBAPR(CKE),
      .MOFF_n(MOFF_n),
      .BINPUT_n(BINPUT_n),
      .BMEM_n(BMEM_n),
      .BD20_n(BD20_n),
      .BD21_n(BD21_n),
      .BD22_n(BD22_n),
      .BD23_n(BD23_n),
      .AOK(b_AOK),
      .DDBAPR(b_DDBAPR),
      .MSIZE1_n(b_MSIZE1_n),
      .BANK2(b_BANK2),
      .BANK1(b_BANK1),
      .BANK0(b_BANK0),
      .MWRITE_n(b_MWRITE_n)
  );

  PAL_44446B_D mirror (
      .sysclk(sysclk),
      .sys_rst_n(sys_rst_n),
      .CK(CKE),
      .OE_n(OE_n),
      .DBAPR(CKE),
      .MOFF_n(MOFF_n),
      .BINPUT_n(BINPUT_n),
      .BMEM_n(BMEM_n),
      .BD20_n(BD20_n),
      .BD21_n(BD21_n),
      .BD22_n(BD22_n),
      .BD23_n(BD23_n),
      .AOK(d_AOK),
      .DDBAPR(d_DDBAPR),
      .MSIZE1_n(d_MSIZE1_n),
      .BANK2(d_BANK2),
      .BANK1(d_BANK1),
      .BANK0(d_BANK0),
      .MWRITE_n(d_MWRITE_n)
  );

  /*************************************************************************
   ** Golden model - two register sets (PIN-2: only the _D resets)        **
   *************************************************************************/
  reg [2:0] gb_bank = 3'b000;  // base registers, one-hot {BANK2,BANK1,BANK0}
  reg       gb_mwrite = 1'b0;
  reg [2:0] gd_bank = 3'b000;  // _D registers
  reg       gd_mwrite = 1'b0;

  function [2:0] bank_decode(input b21, input b20);
    case ({b21, b20})
      2'b00:   bank_decode = 3'b001;
      2'b01:   bank_decode = 3'b100;
      2'b10:   bank_decode = 3'b010;
      default: bank_decode = 3'b000;
    endcase
  endfunction

  integer checks = 0;
  integer errors = 0;

  task cmp(input got, input exp, input [127:0] what);
    begin
      checks = checks + 1;
      if (got !== exp) begin
        errors = errors + 1;
        if (errors <= 30)
          $display("FAIL t=%0t %0s got=%b exp=%b", $time, what, got, exp);
      end
    end
  endtask

  task settle;
    begin
      @(negedge sysclk);
      @(negedge sysclk);
    end
  endtask

  // Compare BOTH DUTs against the golden model (14 checks per call)
  task check_all;
    reg exp_aok;
    begin
`ifdef ND120_ONBOARD_2MB
      // 2 MB board (derived equations, see PAL_44446B.v): BD20 joins the
      // limit, so the upper 2 MB is not answered
      exp_aok = ~(BMEM_n | ~BD23_n | ~BD22_n | ~BD21_n | ~BD20_n | ~MOFF_n);
`else
      exp_aok = ~(BMEM_n | ~BD23_n | ~BD22_n | ~BD21_n | ~MOFF_n);
`endif

      cmp(b_AOK, exp_aok, "b.AOK");
      cmp(b_DDBAPR, CKE, "b.DDBAPR");
      cmp(b_MSIZE1_n, 1'b1, "b.MSIZE1_n");
      cmp(b_BANK2, OE_n ? 1'b0 : gb_bank[2], "b.BANK2");
      cmp(b_BANK1, OE_n ? 1'b0 : gb_bank[1], "b.BANK1");
      cmp(b_BANK0, OE_n ? 1'b0 : gb_bank[0], "b.BANK0");
      cmp(b_MWRITE_n, OE_n ? 1'b0 : ~gb_mwrite, "b.MWRITE_n");  // PIN-1

      cmp(d_AOK, exp_aok, "d.AOK");
      cmp(d_DDBAPR, CKE, "d.DDBAPR");
      cmp(d_MSIZE1_n, 1'b1, "d.MSIZE1_n");
      cmp(d_BANK2, OE_n ? 1'b0 : gd_bank[2], "d.BANK2");
      cmp(d_BANK1, OE_n ? 1'b0 : gd_bank[1], "d.BANK1");
      cmp(d_BANK0, OE_n ? 1'b0 : gd_bank[0], "d.BANK0");
      cmp(d_MWRITE_n, OE_n ? 1'b0 : ~gd_mwrite, "d.MWRITE_n");
    end
  endtask

  task raise_ck;  // DBAPR rise = capture event for both register sets
    begin
      @(negedge sysclk);
      CKE = 1;
      settle;
      gb_bank   = bank_decode(~BD21_n, ~BD20_n);
      gb_mwrite = ~BINPUT_n;
      gd_bank   = gb_bank;
      gd_mwrite = gb_mwrite;
    end
  endtask

  task drop_ck;
    begin
      @(negedge sysclk);
      CKE = 0;
      settle;
    end
  endtask

  // _D-only reset (CK held LOW - see the contract note in the header)
  task pulse_reset;
    begin
      if (CKE) drop_ck;
      @(negedge sysclk);
      sys_rst_n = 0;
      settle;
      gd_bank   = 3'b000;  // PIN-2 reset state (enabled outputs)
      gd_mwrite = 1'b0;
      @(negedge sysclk);
      sys_rst_n = 1;
      settle;
    end
  endtask

  reg [31:0] prng = 32'h446B0001;
  task prng_next;
    begin
      prng = prng ^ (prng << 13);
      prng = prng ^ (prng >> 17);
      prng = prng ^ (prng << 5);
    end
  endtask

  integer i;

  initial begin
    /*********************************************************************
     ** Reset + priming capture (defines the base PAL's X registers)     **
     *********************************************************************/
    repeat (4) @(negedge sysclk);
    sys_rst_n = 1;
    settle;
    // Before the first CK rise the base regs are X - check the _D reset
    // state alone (7 checks), then prime both with a capture.
    cmp(d_AOK, 1'b0, "d.AOK(rst)");         // BMEM_n=1 blocks
    cmp(d_DDBAPR, 1'b0, "d.DDBAPR(rst)");
    cmp(d_MSIZE1_n, 1'b1, "d.MSIZE1_n(rst)");
    cmp(d_BANK2, 1'b0, "d.BANK2(rst)");
    cmp(d_BANK1, 1'b0, "d.BANK1(rst)");
    cmp(d_BANK0, 1'b0, "d.BANK0(rst)");
    cmp(d_MWRITE_n, 1'b1, "d.MWRITE_n(rst)");
    raise_ck;
    drop_ck;
    check_all;

    /*********************************************************************
     ** 1. EXHAUSTIVE sweep: all 128 input combos x {CK low, CK rise,    **
     **    OE disabled} - every AOK literal asserted and deasserted      **
     **    (incl. BD20 NOT blocking), every bank code, MWRITE both ways  **
     *********************************************************************/
    for (i = 0; i < 128; i = i + 1) begin
      @(negedge sysclk);
      {BD23_n, BD22_n, BD21_n, BD20_n, BMEM_n, MOFF_n, BINPUT_n} = i[6:0];
      OE_n = 0;
      settle;
      check_all;      // comb with CK low + held registers
      raise_ck;
      check_all;      // fresh capture (+ DDBAPR pass-through high)
      @(negedge sysclk);
      OE_n = 1;
      settle;
      check_all;      // PIN-1 disabled values (CK still high)
      @(negedge sysclk);
      OE_n = 0;
      settle;
      drop_ck;
    end

    /*********************************************************************
     ** 2. Edge-not-level: data churn under a HELD-high CK               **
     *********************************************************************/
    @(negedge sysclk);
    {BD23_n, BD22_n, BD21_n, BD20_n, BMEM_n, MOFF_n, BINPUT_n} = 7'b1111011;
    settle;
    raise_ck;
    check_all;
    @(negedge sysclk) BD20_n = 0; BD21_n = 0; BINPUT_n = 0; settle;
    check_all;        // registers must NOT re-capture
    @(negedge sysclk) BD20_n = 1; BD21_n = 1; BINPUT_n = 1; settle;
    check_all;
    drop_ck;
    check_all;

    /*********************************************************************
     ** 3. PIN-2 mid-run reset: _D clears, base holds                    **
     *********************************************************************/
    @(negedge sysclk);
    {BD21_n, BD20_n} = 2'b01;  // BD21 active -> BANK1 one-hot
    BINPUT_n = 0;
    settle;
    raise_ck;
    drop_ck;
    check_all;
    pulse_reset;
    check_all;        // gd = reset state, gb = held BANK1/MWRITE
    raise_ck;         // re-converge
    drop_ck;
    check_all;

    /*********************************************************************
     ** 4. Fixed-seed soak: 4000 single-change steps                     **
     *********************************************************************/
    for (i = 0; i < 4000; i = i + 1) begin
      prng_next;
      case (prng[3:0] % 5)
        0: begin
          if (CKE) drop_ck;
          else raise_ck;
        end
        1: begin
          @(negedge sysclk);
          {BD23_n, BD22_n, BD21_n, BD20_n} = prng[19:16];
          settle;
        end
        2: begin
          @(negedge sysclk);
          {BMEM_n, MOFF_n, BINPUT_n} = prng[18:16];
          settle;
        end
        3: begin
          @(negedge sysclk);
          OE_n = prng[16];
          settle;
        end
        4: begin
          if (prng[17:16] == 2'b00) pulse_reset;  // occasional _D reset
          else begin
            @(negedge sysclk);
            {BD21_n, BD20_n, BMEM_n} = prng[18:16];
            settle;
          end
        end
      endcase
      check_all;
    end

    /*********************************************************************
     ** Verdict                                                          **
     *********************************************************************/
    $display("checks=%0d errors=%0d", checks, errors);
    if (checks != EXPECTED_CHECKS) begin
      $display("TB_RESULT: FAIL (check count %0d != expected %0d)", checks,
               EXPECTED_CHECKS);
    end else if (errors == 0) begin
      $display("TB_RESULT: PASS (%0d checks)", checks);
    end else begin
      $display("TB_RESULT: FAIL (%0d errors)", errors);
    end
    $finish;
  end

endmodule
