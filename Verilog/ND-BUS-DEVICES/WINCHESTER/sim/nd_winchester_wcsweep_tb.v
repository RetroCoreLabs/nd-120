/**************************************************************************
** TESTBENCH: ND_WINCHESTER - word-count sweep                            **
**                                                                       **
** Ronny 18-AUG-2026: "maybe the problem is the word count (4608) that    **
** its not an even 512 or 1024 or 2048?"                                  **
**                                                                       **
** 4608 = 4 x 1024 + 512, so the last chunk is a HALF sector. The chunk   **
** arithmetic also truncates a 24-bit counter to 11 bits                  **
**   s_chunk_q <= ((s_words_left-1) > BUF_WORDS) ? BUF_WORDS              **
**                                              : (s_words_left[10:0]-1)  **
** so a remaining count of 1025 truncates to 1 and asks for a ZERO-word   **
** chunk. This sweeps counts around every 1024 boundary with a backend    **
** that always completes, so any count that fails to finish is the        **
** controller's own arithmetic and nothing else.                          **
***************************************************************************/
`timescale 1ns / 1ps

module nd_winchester_wcsweep_tb;

  localparam [15:0] BASE = 16'o000500;
  localparam SB_FINISHED = 3;
  localparam SB_ACTIVE   = 2;

  reg sysclk = 0;
  reg sys_rst_n = 0;
  always #10 sysclk = ~sysclk;

  reg  [15:0] iox_addr = 0; reg iox_wr = 0; reg [15:0] iox_wdata = 0;
  reg         iox_rd = 0;   wire [15:0] iox_rdata; wire iox_sel;
  wire [3:0]  int_pending;
  wire        dma_req, dma_wr; wire [23:0] dma_addr; wire [15:0] dma_wdata;
  wire        disk_start, disk_req, disk_wr;
  wire [15:0] disk_blkaddr1, disk_blkaddr2;
  wire [2:0]  disk_unit; wire [10:0] disk_wordcount; wire [15:0] dbuf_rdata;

  reg dma_ack = 0;
  always @(posedge sysclk) dma_ack <= dma_req;

  reg  [3:0] disk_dly = 0;
  reg        disk_done = 0;
  integer    disk_reqs = 0, disk_words = 0;
  always @(posedge sysclk) begin
    disk_done <= 1'b0;
    if (disk_req && disk_dly == 0) begin
      disk_dly <= 4; disk_reqs <= disk_reqs + 1;
      disk_words <= disk_words + disk_wordcount;
      if (disk_wordcount == 11'd0)
        $display("      !! controller asked for a ZERO-word chunk");
    end else if (disk_dly != 0) begin
      disk_dly <= disk_dly - 1;
      if (disk_dly == 1) disk_done <= 1'b1;
    end
  end

  ND_WINCHESTER #(.DELAY_TICKS(32'd20)) dut (
      .sysclk(sysclk), .sys_rst_n(sys_rst_n),
      .iox_addr(iox_addr), .iox_wr(iox_wr), .iox_wdata(iox_wdata),
      .iox_rd(iox_rd), .iox_rdata(iox_rdata), .iox_sel(iox_sel),
      .int_pending(int_pending),
      .ident_strobe(1'b0), .ident_level(4'd0), .ident_grant_in(1'b0),
      .ident_grant_out(), .ident_hit(), .ident_code(),
      .dma_req(dma_req), .dma_wr(dma_wr), .dma_addr(dma_addr),
      .dma_wdata(dma_wdata), .dma_rdata(16'd0), .dma_ack(dma_ack),
      .dma_err(1'b0), .dma_busy(1'b0),
      .disk_start(disk_start), .disk_req(disk_req), .disk_wr(disk_wr),
      .disk_blkaddr1(disk_blkaddr1), .disk_blkaddr2(disk_blkaddr2),
      .disk_unit(disk_unit), .disk_wordcount(disk_wordcount),
      .disk_done(disk_done), .disk_err_in(1'b0), .disk_err_code(4'd0),
      .dbuf_addr(10'd0), .dbuf_wdata(16'd0), .dbuf_we(1'b0),
      .dbuf_rdata(dbuf_rdata)
  );

  integer errors = 0;

  task iox_write(input [15:0] a, input [15:0] d);
    begin @(negedge sysclk); iox_addr=a; iox_wdata=d; iox_wr=1;
          @(negedge sysclk); iox_wr=0; end
  endtask
  task iox_read(input [15:0] a, output [15:0] d);
    begin @(negedge sysclk); iox_addr=a; iox_rd=1; #1 d=iox_rdata;
          @(posedge sysclk); @(negedge sysclk); iox_rd=0; end
  endtask

  task try_wc(input [15:0] wc);
    reg [15:0] st; integer polls; integer r0, w0;
    begin
      r0 = disk_reqs; w0 = disk_words;
      iox_write(BASE+5, 16'o000020); iox_write(BASE+5, 16'o000020);
      iox_write(BASE+7, 16'd0);
      iox_write(BASE+3, 16'o000200);
      iox_write(BASE+1, 16'd0); iox_write(BASE+1, 16'o040000);
      iox_write(BASE+7, wc);
      iox_write(BASE+5, 16'o000005);
      polls = 0; st = 16'hFFFF;
      while (polls < 60000 && st[SB_ACTIVE] !== 1'b0) begin
        iox_read(BASE+4, st); polls = polls + 1;
      end
      if (st[SB_ACTIVE] !== 1'b0) begin
        $display("  wc=%-6d (%06o) FAIL - never finished, status=%06o, chunks=%0d words=%0d",
                 wc, wc, st, disk_reqs-r0, disk_words-w0);
        errors = errors + 1;
      end else if (disk_words-w0 != wc) begin
        $display("  wc=%-6d (%06o) FAIL - finished but moved %0d words, chunks=%0d",
                 wc, wc, disk_words-w0, disk_reqs-r0);
        errors = errors + 1;
      end else
        $display("  wc=%-6d (%06o) ok   chunks=%0d words=%0d status=%06o",
                 wc, wc, disk_reqs-r0, disk_words-w0, st);
    end
  endtask

  initial begin
    sys_rst_n = 0; repeat (5) @(negedge sysclk);
    sys_rst_n = 1; repeat (5) @(negedge sysclk);
    $display("== ND_WINCHESTER word-count sweep (backend always completes) ==");
    // Every transfer below reads block address 000200 = cylinder 4. The arm
    // must be on that cylinder first (sec 2.2: "The software driver must do a
    // seek to the correct cylinder prior to a read or write operation"), so
    // step it out 4 cylinders once; a device clear does not move the arm.
    begin : seek_to_4
      reg [15:0] sst; integer sp;
      iox_write(BASE+7, 16'd4);
      iox_write(BASE+5, 16'o060004);          // activate, M4, direction out
      sp = 0; sst = 16'hFFFF;
      while (sp < 60000 && sst[SB_ACTIVE] !== 1'b0) begin
        iox_read(BASE+4, sst); sp = sp + 1;
      end
      if (dut.s_cyl_pos[0] != 16'd4) begin
        $display("  FAIL - the seek to cylinder 4 did not get there (arm at %0d)",
                 dut.s_cyl_pos[0]);
        errors = errors + 1;
      end
    end
    try_wc(16'd512);   try_wc(16'd1023);  try_wc(16'd1024);
    try_wc(16'd1025);  try_wc(16'd1026);  try_wc(16'd2047);
    try_wc(16'd2048);  try_wc(16'd2049);  try_wc(16'd3072);
    try_wc(16'd4095);  try_wc(16'd4096);  try_wc(16'd4097);
    try_wc(16'd4608);  try_wc(16'd4609);  try_wc(16'd5120);
    $display("\nTB_RESULT: %0s  (%0d failures)", (errors==0)?"PASS":"FAIL", errors);
    $finish;
  end

  initial begin #200_000_000; $display("TB_RESULT: FAIL - global timeout"); $finish; end
endmodule
