/*****************************************************************************
 *  nd120_sterr_catch.v - catch the self-test failure and report its number    *
 *                                                                            *
 *  WHY (01-SEP-2026, Ronny's call)                                            *
 *  -------------------------------                                            *
 *  The MiSTer board reaches no OPCOM prompt. Sampling the microcode address   *
 *  once a second was a dead end - it ALIASES against a tight loop and reports *
 *  arbitrary points inside it. The direct question is instead: did the        *
 *  microcode take the self-test failure branch, and if so with what error?    *
 *                                                                            *
 *  The DELILAH microcode answers it at address 002156:                        *
 *                                                                            *
 *      % DISPLAY ERROR NO. R2                                                 *
 *      STERR:  B,R2   ALUF,PASSB  ALUD,Q                                      *
 *              IDBS,ALU           T,JMP  T,PUSH DYTP2;                        *
 *              ALUF,PASSQ ALUD,NONE  % LOOP ON ERROR                          *
 *              IDBS,ALU   COMM,LDPIL  T,RETURN T,HOLD;                        *
 *                                                                            *
 *  So STERR selects R2 onto the register file's B port. This module watches   *
 *  for CSA == 002156 and latches that port. The value it captures IS R2, by   *
 *  construction - no need to know which of the sixteen register slots the     *
 *  microcode assembler's name "R2" decodes to. The captured LBA field reports *
 *  that slot as a by-product, which settles the question for good.            *
 *                                                                            *
 *  CAREFUL - not every visit counts. The WCS loader walks PAST the STERR      *
 *  address once while loading microcode (noted in runSim/Run120.cpp); only    *
 *  execution-phase visits mean a real self-test failure. This module          *
 *  therefore reports a COUNT as well as the value, and keeps BOTH the first   *
 *  and the most recent capture, so a single spurious walk-past is visible as  *
 *  count==1 rather than being mistaken for a failure.                         *
 *                                                                            *
 *  DIAGNOSTIC SCAFFOLDING, built only under ND120_DIAG_PRINT.                 *
 *****************************************************************************/

`default_nettype none

module nd120_sterr_catch #(
    parameter [12:0] STERR_ADDR = 13'o02156  //! microcode address of STERR
) (
    input  wire        clk_cpu,
    input  wire        cpu_rst_n,
    input  wire [12:0] csa,           //! live microcode address
    input  wire [19:0] wrfb,          //! {LBA_3_0, B_15_0} from the register file

    output reg         hit,           //! sticky: STERR was reached at least once
    output reg  [7:0]  hit_count,     //! visits, saturating - 1 may be the loader
    output reg  [19:0] first_capture, //! {LBA, R2} at the FIRST visit
    output reg  [19:0] last_capture   //! {LBA, R2} at the most recent visit
);

  reg r_at_sterr;   //! previous cycle was already at STERR - count ENTRIES only

  wire s_at = (csa == STERR_ADDR);

  always @(posedge clk_cpu) begin
    if (!cpu_rst_n) begin
      hit           <= 1'b0;
      hit_count     <= 8'd0;
      first_capture <= 20'd0;
      last_capture  <= 20'd0;
      r_at_sterr    <= 1'b0;
    end else begin
      r_at_sterr <= s_at;
      // Count ENTRIES into STERR, not clocks spent there: the microinstruction
      // is held for several cycles, and counting clocks would turn one visit
      // into a meaningless large number.
      if (s_at && !r_at_sterr) begin
        last_capture <= wrfb;
        if (!hit) begin
          hit           <= 1'b1;
          first_capture <= wrfb;
        end
        if (hit_count != 8'hFF) hit_count <= hit_count + 8'd1;
      end
    end
  end

endmodule

`default_nettype wire
