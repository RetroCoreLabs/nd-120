/****************************************************************************
** Behavioral model of the MEGA65 R4/R5/R6 board SDRAM as the ND-120 uses **
** it: a 16-bit SDR part driven by the Tang/MiSTer sheet-49 bridge         **
** (fpga/tang-nano-20k/sdram-bridge/sdram18.v) in ND_SDRAM_PACK16 +         **
** ND_SDRAM_DQ16 mode.                                                      **
**                                                                         **
** Full path: Verilog/fpga/mega65/sim/sdram16_model.v                      **
**                                                                         **
** Derived from the Tang's 32-bit model (fpga/tang-nano-20k/sdram-test/    **
** sim/sdram_model.v): the same protocol subset - BankActivate, Read/Write **
** with auto-precharge (A10 ignored), byte masking via DQM, AutoRefresh /  **
** ModeReg / Precharge accepted and ignored, CL=2 - at the width and       **
** geometry the bridge drives on this board: 16 data bits, 2 DQM bits,     **
** 4 banks x 2K rows x 256 columns (the bridge's ROW_WIDTH 11 / COL_WIDTH  **
** 8; nd120_mega65_machine.v pads the board's A[12:11] with zeros), i.e.   **
** 2M x 16 = the machine's 4 MB map. The real chip is bigger (32M x 16);   **
** the part of it the bridge can address is all that is modelled.          **
**                                                                         **
** Contents start as X on purpose: a read of a location never written      **
** returns X, so a CPU that fetches from unwritten memory shows it.        **
*****************************************************************************/
`timescale 1ns / 1ps

module sdram16_model (
    input clk,   // SDRAM clock pin (180 degrees from the bridge's clock)
    input cke,
    input cs_n,
    input ras_n,
    input cas_n,
    input we_n,
    input [10:0] a,
    input [1:0] ba,
    input [1:0] dqm,
    inout [15:0] dq
);

  // {RAS#, CAS#, WE#}
  localparam CMD_MRS = 3'b000;
  localparam CMD_REF = 3'b001;
  localparam CMD_PRE = 3'b010;
  localparam CMD_ACT = 3'b011;
  localparam CMD_WR  = 3'b100;
  localparam CMD_RD  = 3'b101;

  reg [15:0] mem[0:2097151];  // 2M x 16 = 4 MB
  reg [10:0] row[0:3];

  wire [2:0] cmd = {ras_n, cas_n, we_n};
  wire [20:0] idx = {ba, row[ba], a[7:0]};

  // CL=2 read pipeline: data driven between the 2nd and 3rd clock edge
  // after the READ command, exactly one clock wide (as the Tang model).
  reg pipe0, pipe1, drv;
  reg [15:0] pdata, ddata;
  assign dq = drv ? ddata : 16'hzzzz;

  integer i;
  initial begin
    for (i = 0; i < 2097152; i = i + 1) mem[i] = 16'hXXXX;
    pipe0 = 0;
    pipe1 = 0;
    drv   = 0;
  end

  always @(posedge clk) begin
    pipe0 <= 1'b0;
    pipe1 <= pipe0;
    drv   <= pipe1;
    if (pipe1) ddata <= pdata;

    if (!cs_n && cke) begin
      case (cmd)
        CMD_ACT: row[ba] <= a;
        CMD_WR: begin
          if (!dqm[0]) mem[idx][7:0]  <= dq[7:0];
          if (!dqm[1]) mem[idx][15:8] <= dq[15:8];
        end
        CMD_RD: begin
          pipe0 <= 1'b1;
          pdata <= mem[idx];
        end
        default: ;  // MRS / REF / PRE: accepted, nothing to model
      endcase
    end
  end

endmodule
