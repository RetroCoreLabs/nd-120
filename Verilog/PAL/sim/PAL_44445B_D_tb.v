/**************************************************************************
** ND120 PAL unit test                                                   **
** PAL_44445B (UCADEC, 9G, PAL16R4) + PAL_44445B_D sysclk mirror         **
**                                                                       **
** CPU ADDRESS DECODER FOR 4MB MEMORY (sheet 45). Both implementations   **
** run side by side against ONE golden model re-derived INDEPENDENTLY    **
** from the PALASM equations in the PAL_44445B.v header comments         **
** (PAL16R4: Q0-Q3 registered on CK, inverting, OE_n tri-state gated;    **
** B outputs combinational):                                             **
**   registered on CK (=ECREQ) rise, one-hot from PPN21:20:              **
**     00 -> BANK0, 01 -> BANK2, 10 -> BANK1, 11 -> none                 **
**     (BANK1/BANK2 deliberately swapped - the 060687 JLB PALASM note)   **
**     MWRITE <= WRITE                                                   **
**   CLRQ_n = ~(ECREQ & IORQ_n & ~PPN23 & ~PPN22 & ~PPN21 & MOFF_n)      **
**     - the two PALASM product terms differ only in the PPN20 literal,  **
**       so PPN20 is a DON'T-CARE (checked exhaustively here)            **
**   CRQ_n  = ~(ECREQ & (IORQ | MOFF | PPN23 | PPN22 | PPN21))           **
**   MSIZE0_n = 0 constant ("MSIZE0 IS ALWAYS HIGH (VCC)")               **
** AUDIT RESULT: gates match the PALASM comments - no transcription      **
** error found in PAL_44445B.v or PAL_44445B_D.v.                        **
**                                                                       **
** PINNED (gate behavior, flagged):                                      **
**  PIN-1 OE_n=1 drives BANKx=0 but MWRITE_n=1 (FPGA no-Z convention;    **
**        the sibling PAL_44446B drives MWRITE_n=0 when disabled - the   **
**        asymmetry is masked by the grant gating in MEM_ADEC_45).       **
**  PIN-2 PAL_44445B_D only: sys_rst_n forces BANK*_n_reg=1/MWRITE=0     **
**        (enabled outputs BANK=000, MWRITE_n=1) and holds until the     **
**        next CK rise; the base PAL has no reset and holds its state.   **
**        The tb tracks the two register sets separately across resets.  **
**                                                                       **
** _D contract (MEM_ADEC_45 usage): CK is generated in the sysclk        **
** domain, at least one sysclk wide; observation is two negedges after   **
** any change (the _D capture lags the base capture by one sysclk).      **
** Resets are only applied while CK is LOW - releasing reset under a     **
** held-high CK would make the _D re-capture (ck_d cleared), a           **
** divergence the parent never exercises.                                **
**                                                                       **
** Run: make test-44445b-d (PAL/sim)                                     **
**                                                                       **
** Last reviewed: 01-AUG-2026                                            **
** Ronny Hansen                                                          **
***************************************************************************/
`timescale 1ns / 1ps

module PAL_44445B_D_tb;

  parameter EXPECTED_CHECKS = 61495;

  reg sysclk = 0;
  always #10 sysclk = ~sysclk;

  reg sys_rst_n = 0;

  // Shared stimulus
  reg CKE = 0;  // drives CK and the ECREQ input pin of both DUTs
  reg OE_n = 0;
  reg WRITE = 0;
  reg IORQ_n = 1;
  reg MOFF_n = 1;
  reg PPN20 = 0;
  reg PPN21 = 0;
  reg PPN22 = 0;
  reg PPN23 = 0;

  // Base PAL outputs
  wire b_MSIZE0_n, b_CLRQ_n, b_CRQ_n, b_BANK2, b_BANK1, b_BANK0, b_MWRITE_n;
  // _D mirror outputs
  wire d_MSIZE0_n, d_CLRQ_n, d_CRQ_n, d_BANK2, d_BANK1, d_BANK0, d_MWRITE_n;

  PAL_44445B base (
      .CK(CKE),
      .OE_n(OE_n),
      .WRITE(WRITE),
      .IORQ_n(IORQ_n),
      .MOFF_n(MOFF_n),
      .PPN20(PPN20),
      .PPN21(PPN21),
      .PPN22(PPN22),
      .PPN23(PPN23),
      .MSIZE0_n(b_MSIZE0_n),
      .CLRQ_n(b_CLRQ_n),
      .CRQ_n(b_CRQ_n),
      .ECREQ(CKE),
      .BANK2(b_BANK2),
      .BANK1(b_BANK1),
      .BANK0(b_BANK0),
      .MWRITE_n(b_MWRITE_n)
  );

  PAL_44445B_D mirror (
      .sysclk(sysclk),
      .sys_rst_n(sys_rst_n),
      .CK(CKE),
      .OE_n(OE_n),
      .WRITE(WRITE),
      .IORQ_n(IORQ_n),
      .MOFF_n(MOFF_n),
      .PPN20(PPN20),
      .PPN21(PPN21),
      .PPN22(PPN22),
      .PPN23(PPN23),
      .MSIZE0_n(d_MSIZE0_n),
      .CLRQ_n(d_CLRQ_n),
      .CRQ_n(d_CRQ_n),
      .ECREQ(CKE),
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
    reg exp_clrq_n;
    reg exp_crq_n;
    begin
`ifdef ND120_ONBOARD_2MB
      // 2 MB board (derived equations, see PAL_44445B.v): only the lower
      // 2 MB (PPN20 = 0) is local; the upper 2 MB goes to the bus
      exp_clrq_n = ~(CKE & IORQ_n & ~PPN23 & ~PPN22 & ~PPN21 & ~PPN20 & MOFF_n);
      exp_crq_n  = ~(CKE & (~IORQ_n | ~MOFF_n | PPN23 | PPN22 | PPN21 | PPN20));
`else
      exp_clrq_n = ~(CKE & IORQ_n & ~PPN23 & ~PPN22 & ~PPN21 & MOFF_n);
      exp_crq_n  = ~(CKE & (~IORQ_n | ~MOFF_n | PPN23 | PPN22 | PPN21));
`endif

      cmp(b_MSIZE0_n, 1'b0, "b.MSIZE0_n");
      cmp(b_CLRQ_n, exp_clrq_n, "b.CLRQ_n");
      cmp(b_CRQ_n, exp_crq_n, "b.CRQ_n");
      cmp(b_BANK2, OE_n ? 1'b0 : gb_bank[2], "b.BANK2");
      cmp(b_BANK1, OE_n ? 1'b0 : gb_bank[1], "b.BANK1");
      cmp(b_BANK0, OE_n ? 1'b0 : gb_bank[0], "b.BANK0");
      cmp(b_MWRITE_n, OE_n ? 1'b1 : ~gb_mwrite, "b.MWRITE_n");  // PIN-1

      cmp(d_MSIZE0_n, 1'b0, "d.MSIZE0_n");
      cmp(d_CLRQ_n, exp_clrq_n, "d.CLRQ_n");
      cmp(d_CRQ_n, exp_crq_n, "d.CRQ_n");
      cmp(d_BANK2, OE_n ? 1'b0 : gd_bank[2], "d.BANK2");
      cmp(d_BANK1, OE_n ? 1'b0 : gd_bank[1], "d.BANK1");
      cmp(d_BANK0, OE_n ? 1'b0 : gd_bank[0], "d.BANK0");
      cmp(d_MWRITE_n, OE_n ? 1'b1 : ~gd_mwrite, "d.MWRITE_n");
    end
  endtask

  task raise_ck;  // capture event for both register sets
    begin
      @(negedge sysclk);
      CKE = 1;
      settle;
      gb_bank   = bank_decode(PPN21, PPN20);
      gb_mwrite = WRITE;
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

  reg [31:0] prng = 32'h445B0001;
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
    cmp(d_MSIZE0_n, 1'b0, "d.MSIZE0_n(rst)");
    cmp(d_CLRQ_n, 1'b1, "d.CLRQ_n(rst)");
    cmp(d_CRQ_n, 1'b1, "d.CRQ_n(rst)");
    cmp(d_BANK2, 1'b0, "d.BANK2(rst)");
    cmp(d_BANK1, 1'b0, "d.BANK1(rst)");
    cmp(d_BANK0, 1'b0, "d.BANK0(rst)");
    cmp(d_MWRITE_n, 1'b1, "d.MWRITE_n(rst)");
    raise_ck;
    drop_ck;
    check_all;

    /*********************************************************************
     ** 1. EXHAUSTIVE sweep: all 128 input combos x {CK low, CK rise,    **
     **    OE disabled} - covers every product term asserted and         **
     **    deasserted, incl. the PPN20 don't-care in CLRQ                **
     *********************************************************************/
    for (i = 0; i < 128; i = i + 1) begin
      @(negedge sysclk);
      {PPN23, PPN22, PPN21, PPN20, MOFF_n, IORQ_n, WRITE} = i[6:0];
      OE_n = 0;
      settle;
      check_all;      // comb with CK low + held registers
      raise_ck;
      check_all;      // fresh capture
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
    {PPN23, PPN22, PPN21, PPN20, MOFF_n, IORQ_n, WRITE} = 7'b0001110;
    settle;
    raise_ck;
    check_all;
    @(negedge sysclk) PPN20 = 1; PPN21 = 1; WRITE = 1; settle;
    check_all;        // registers must NOT re-capture
    @(negedge sysclk) PPN20 = 0; PPN21 = 0; WRITE = 0; settle;
    check_all;
    drop_ck;
    check_all;

    /*********************************************************************
     ** 3. PIN-2 mid-run reset: _D clears, base holds                    **
     *********************************************************************/
    @(negedge sysclk);
    {PPN23, PPN22, PPN21, PPN20} = 4'b0010;  // BANK1 one-hot
    WRITE = 1;
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
          {PPN23, PPN22, PPN21, PPN20} = prng[19:16];
          settle;
        end
        2: begin
          @(negedge sysclk);
          {MOFF_n, IORQ_n, WRITE} = prng[18:16];
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
            {PPN21, PPN20, WRITE} = prng[18:16];
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
