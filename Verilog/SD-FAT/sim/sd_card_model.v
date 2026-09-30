/****************************************************************************
** Behavioral SD card model (native 1-bit mode) for the SD-FAT test        **
**                                                                         **
** Serves sectors from a raw filesystem image file ($fread at time 0).     **
** SD bus is split _i/_o/_oe (no tristates) - the TB muxes. See the port   **
** block. Runs under BOTH iverilog and Verilator.                          **
** Implements what the SD-FAT library needs:                               **
**   CMD0 (no response), CMD8 (R7), CMD55+ACMD41 (R1/R3, reports SDHC),    **
**   CMD2 (R2/CID), CMD3 (R6, RCA=0x0001), CMD7 (R1), CMD16 (R1),          **
**   CMD17 (R1 + 512-byte read block on DAT0, CRC16 appended),             **
**   CMD24 (R1 + receive a 512-byte write block on DAT0, CRC16 checked,    **
**          CRC status token + busy; the sector lands in the image),       **
**   CMD18 (R1 + blocks streamed back-to-back until the host sends CMD12), **
**   CMD25 (R1 + write blocks accepted until CMD12; each block is checked  **
**          and committed exactly like a CMD24, with the CRC status token  **
**          and an inter-block busy period; CMD12 answers R1b: R1 plus a   **
**          final busy on DAT0),                                           **
**   CMD55+ACMD6 (R1; arg 2 switches the DAT bus to 4-bit: data blocks     **
**          both ways then move as 1024 nibbles on DAT3..DAT0 with a       **
**          CRC16 PER LINE, while the CRC status token and all busy        **
**          signalling stay on DAT0 alone; CMD0 resets to 1-bit),          **
**   CMD55+ACMD23 (R1; the pre-erase count is recorded in acmd23_count;    **
**          CMD23 WITHOUT a valid CMD55 gets NO response - that is how a   **
**          wrong RCA in CMD55 shows up, since CMD55 with an RCA other     **
**          than 0x0000/0x0001 is ignored like a real card would),         **
**   CMD12 (R1, counted in cmd12_count for testbench assertions)           **
** Anything else gets no response (the host times out and retries).        **
**                                                                         **
** Timing contract with the host cores: the host drives CMD on the falling **
** edge of sd_clk and samples on the rising edge; this model does the      **
** mirror image (samples on rising, drives on falling). Response starts    **
** NCR = 4 clocks after the command end (host timeout is 250 clocks).      **
**                                                                         **
** The model checks the CRC7 of received commands and counts mismatches    **
** in crc_errors (testbench should require it to stay 0).                  **
**                                                                         **
** Error injection (hierarchically-settable registers, default OFF so     **
** behavior is identical to the original model):                           **
**   fail_next_writes - while nonzero, each written block (CMD24 or a     **
**     CMD25 burst block) is answered with the CRC status token "101"     **
**     (rejected), the data is NOT committed to the image and the counter **
**     decrements.                                                         **
**   fail_sector - one-shot: a write targeting exactly this sector        **
**     (CMD24 or a CMD25 burst block) is rejected the same way, then the  **
**     register self-clears to the all-ones sentinel (disabled).           **
**   fail_next_reads - while nonzero, that many upcoming READ data blocks **
**     are not sent at all: the command is answered, then the card goes    **
**     silent, and the host's read watchdog must catch it. See the long    **
**     note at the register for why a corrupted read CRC16 would NOT work  **
**     (sd_writer.v does not check the read data CRC).                     **
**   corrupt_line - one-shot, 4-bit mode only: 0..3 makes the card-side   **
**     CRC16 of that DAT line mismatch for the next received write block  **
**     (a simulated wire error on one line): the block is rejected with   **
**     "101" and NOT committed; self-clears to 7 (disabled).              **
**                                                                         **
** Reserved-region write detector for RAW (non-FAT) images: parameter     **
** LEGAL_MIN_SECTOR (default 0 = disabled); when nonzero, any write       **
** below it (CMD24 or any block of a CMD25 burst) increments              **
** illegal_writes (testbench should require it to stay 0). Mirrors the    **
** reserved-region check of the C++ card model in                         **
** fpga/tang-nano-20k/sd-fat-test/sim/test_sd_fat.cpp.                    **
**                                                                         **
** Simulation only - never synthesize.                                     **
**                                                                         **
** Last reviewed: 11-JUL-2026                                              **
** Ronny Hansen                                                            **
*****************************************************************************/
`timescale 1ns / 1ps

module sd_card_model #(
    parameter IMAGE            = "fat16.img",
    parameter MAX_BYTES        = 8 * 1024 * 1024,
    parameter LEGAL_MIN_SECTOR = 0   // nonzero: writes below this count illegal
) (
    input  sd_clk,
    // SD bus, SPLIT _i/_o/_oe - NO TRISTATES, NO PULLUP (14-JUL-2026).
    // Rationale: `z` is iverilog-only in practice and the repo bans it inside
    // the FPGA (see nd_storage.v header). The testbench resolves
    // each line with a MUX - host output-enable wins, then the card, then the
    // bus pullup (1) - exactly as nd_storage_vtop.v:92 already does. This is
    // what lets the SAME Verilog card model run under BOTH iverilog and
    // the Verilator flow, so the Verilog gets validated in both. (Do NOT start
    // a comment with the word "verilator" - it is lexed as a metacomment and
    // is a hard error. Yes, that is how this line got written.)
    input  sd_cmd_i,   //! resolved CMD line in
    output sd_cmd_o,   //! CMD value this card drives
    output sd_cmd_oe,  //! 1 = this card is driving CMD
    input  sd_dat0_i,  //! resolved DAT0 line in (bidir since CMD24)
    output sd_dat0_o,
    output sd_dat0_oe,
    input  sd_dat1_i,  //! 4-bit bus mode (ACMD6); tie 1 when unused
    output sd_dat1_o,
    output sd_dat1_oe,
    input  sd_dat2_i,
    output sd_dat2_o,
    output sd_dat2_oe,
    input  sd_dat3_i,
    output sd_dat3_o,
    output sd_dat3_oe
);

  reg [7:0] mem[0:MAX_BYTES-1];
  integer img_bytes;

  integer crc_errors;
  initial crc_errors = 0;

  // error injection hooks (testbench-settable, default off = stock behavior)
  reg [31:0] fail_next_writes;  // reject this many upcoming write blocks ("101")
  reg [31:0] fail_sector;       // one-shot: reject a write to this sector
  // READ-side injection, added 09-AUG-2026. There was write injection but
  // no read injection, so "the card failed a read" - the single most
  // common real storage fault - could not be tested at all.
  //
  // WHAT IT DOES: while nonzero, this many upcoming read data blocks are
  // NOT SENT AT ALL. The card answers the command normally and then goes
  // quiet, which is what a card that stops mid-transfer looks like on the
  // wire; the host's read watchdog in sd_writer.v fires and raises its err
  // output, and nd_storage_engine.v reports that as NDS_ERR_CARDIO.
  //
  // WHY NOT A BAD CRC16 (measured 09-AUG-2026, not assumed): sd_writer.v's
  // R_DATA state SKIPS the read data CRC16 entirely - the comment at the
  // bitcnt == s_rx_end branch says "CRC skipped, end bit", and no compare
  // against the received CRC exists anywhere in that file. So a corrupted
  // read CRC is invisible to this stack and could never have failed a test.
  // Withholding the block is the injection the host can actually detect.
  // (That the read CRC is unchecked at all is a real gap in sd_writer.v,
  // separate from this model - a silently corrupted sector currently reads
  // back as success.)
  reg [31:0] fail_next_reads;
  initial fail_next_writes = 32'd0;
  initial fail_sector = 32'hFFFF_FFFF;
  initial fail_next_reads = 32'd0;

  // reserved-region write detector (RAW images; see header)
  integer illegal_writes;
  initial illegal_writes = 0;

  // multi-block bookkeeping for testbench assertions
  integer cmd12_count;   // STOP_TRANSMISSION commands received
  reg [22:0] acmd23_count;  // last ACMD23 pre-erase block count
  reg        rca_published; // CMD3 has run: RCA 0 is no longer accepted
  initial cmd12_count = 0;
  initial acmd23_count = 23'd0;
  initial rca_published = 1'b0;

  initial begin : load_image
    integer fd;
    fd = $fopen(IMAGE, "rb");
    if (fd == 0) begin
      $display("sd_card_model: FATAL cannot open image %s", IMAGE);
      $finish;
    end
    img_bytes = $fread(mem, fd);
    $fclose(fd);
    $display("sd_card_model: loaded %0d bytes from %s", img_bytes, IMAGE);
  end

  // ------------------------------------------------------------- CMD pin
  reg cmd_drive;
  reg cmd_out;
  initial {cmd_drive, cmd_out} = 2'b01;
  assign sd_cmd_o  = cmd_out;
  assign sd_cmd_oe = cmd_drive;

  // ------------------------------------------------------------- DAT0 pin
  // driven only while the card sources data (read block, CRC status, busy)
  reg dat_out, dat_oe;
  initial {dat_out, dat_oe} = 2'b10;
  assign sd_dat0_o  = dat_out;
  assign sd_dat0_oe = dat_oe;

  // ------------------------------------------------------------- DAT1-3
  // driven ONLY during a 4-bit read data block; the CRC status token and
  // all busy signalling stay on DAT0 alone (SD Physical Layer spec)
  reg d1_out, d2_out, d3_out, datx_oe;
  initial {d1_out, d2_out, d3_out, datx_oe} = 4'b1110;
  assign sd_dat1_o  = d1_out;
  assign sd_dat1_oe = datx_oe;
  assign sd_dat2_o  = d2_out;
  assign sd_dat2_oe = datx_oe;
  assign sd_dat3_o  = d3_out;
  assign sd_dat3_oe = datx_oe;

  // bus width state: ACMD6 arg[1:0] = 2'b10 selects 4-bit, CMD0 resets it
  reg bus4;
  initial bus4 = 1'b0;

  // 4-bit write CRC-error injection: 0..3 corrupts the card-side CRC16 of
  // that DAT line for the NEXT received write block (one-shot) - the block
  // is rejected with the "101" status token and NOT committed, exactly as
  // a real card answers a wire error on a single line. >3 = disabled.
  reg [2:0] corrupt_line;
  initial corrupt_line = 3'd7;

  // CMD18 inter-block gap in SD clocks between a block's end bit and the
  // next start bit (default MINIMAL, near the spec's N_AC minimum of 2 -
  // real cards stream back-to-back); rgap_rand = 1 randomizes 0..16 per
  // block (testbench-settable)
  reg [7:0] rgap;
  reg       rgap_rand;
  initial rgap = 8'd3;
  initial rgap_rand = 1'b0;

  // ------------------------------------------------------------- CRC helpers
  function [6:0] crc7_step(input [6:0] crc, input b);
    crc7_step = {crc[5:0], 1'b0} ^ (7'h09 & {7{crc[6] ^ b}});
  endfunction

  function [15:0] crc16_step(input [15:0] crc, input b);
    crc16_step = {crc[14:0], 1'b0} ^ (16'h1021 & {16{crc[15] ^ b}});
  endfunction

  // CRC7 over an arbitrary-length MSB-first bit vector (up to 40 bits used)
  function [6:0] crc7_of40(input [39:0] bits);
    integer k;
    reg [6:0] c;
    begin
      c = 7'd0;
      for (k = 39; k >= 0; k = k - 1) c = crc7_step(c, bits[k]);
      crc7_of40 = c;
    end
  endfunction

  // ------------------------------------------------------------- engine
  reg [47:0] req;
  reg [5:0] cmd;
  reg [31:0] arg;
  reg app_cmd;
  initial app_cmd = 1'b0;

  reg [135:0] resp;
  integer resp_len;
  reg do_data, do_write, do_data18, do_write25, wr_reject;
  reg [31:0] data_base;
  initial wr_reject = 1'b0;

  // send one 512-byte sector + CRC16, MSB first; 1-bit: serial on DAT0,
  // 4-bit: 1024 nibbles on DAT3..DAT0 with a CRC16 PER LINE (each over the
  // serial bit stream that line carried), end nibble F
  task send_block(input [31:0] base);
    integer i, b;
    reg [15:0] crc, crc1, crc2, crc3;
    reg bitv;
    reg [7:0] byt;
    reg [3:0] nib;
    begin
      repeat (8) @(negedge sd_clk);
      if (bus4) begin
        @(negedge sd_clk) begin
          dat_oe  <= 1'b1;
          dat_out <= 1'b0;  // start nibble 0x0 on all four lines
          datx_oe <= 1'b1;
          d1_out  <= 1'b0;
          d2_out  <= 1'b0;
          d3_out  <= 1'b0;
        end
        crc  = 16'd0;
        crc1 = 16'd0;
        crc2 = 16'd0;
        crc3 = 16'd0;
        for (i = 0; i < 1024; i = i + 1) begin
          byt = (base + (i / 2) < MAX_BYTES) ? mem[base+(i/2)] : 8'hFF;
          nib = i[0] ? byt[3:0] : byt[7:4];  // MSB nibble first
          @(negedge sd_clk) begin
            d3_out  <= nib[3];
            d2_out  <= nib[2];
            d1_out  <= nib[1];
            dat_out <= nib[0];
          end
          crc3 = crc16_step(crc3, nib[3]);
          crc2 = crc16_step(crc2, nib[2]);
          crc1 = crc16_step(crc1, nib[1]);
          crc  = crc16_step(crc, nib[0]);
        end
        for (i = 15; i >= 0; i = i - 1)
          @(negedge sd_clk) begin
            d3_out  <= crc3[i];
            d2_out  <= crc2[i];
            d1_out  <= crc1[i];
            dat_out <= crc[i];
          end
        @(negedge sd_clk) begin  // end nibble 0xF
          d3_out  <= 1'b1;
          d2_out  <= 1'b1;
          d1_out  <= 1'b1;
          dat_out <= 1'b1;
        end
        @(negedge sd_clk) begin  // release all DAT lines
          dat_oe  <= 1'b0;
          datx_oe <= 1'b0;
        end
      end else begin
        @(negedge sd_clk) begin
          dat_oe  <= 1'b1;
          dat_out <= 1'b0;  // start bit
        end
        crc = 16'd0;
        for (i = 0; i < 512; i = i + 1) begin
          for (b = 7; b >= 0; b = b - 1) begin
            bitv = (base + i < MAX_BYTES) ? mem[base+i][b] : 1'b1;
            @(negedge sd_clk) dat_out <= bitv;
            crc  = crc16_step(crc, bitv);
          end
        end
        for (i = 15; i >= 0; i = i - 1) @(negedge sd_clk) dat_out <= crc[i];
        @(negedge sd_clk) dat_out <= 1'b1;  // end bit
        @(negedge sd_clk) dat_oe <= 1'b0;   // release DAT0
      end
    end
  endtask

  // receive one 512-byte write block on DAT0 (start bit already consumed),
  // answer the CRC status token and hold busy for a while; the data lands
  // in the image unless reject is set (injected failure: token "101",
  // nothing committed)
  integer wr_crc_errors;
  initial wr_crc_errors = 0;

  reg [7:0] blkbuf[0:511];  // 4-bit write staging (committed only if accepted)

  task recv_block_body(input [31:0] base, input reject);
    integer i, b;
    reg [15:0] crc, crc_host;
    reg [15:0] crc1, crc2, crc3, crch1, crch2, crch3;
    reg [7:0] byt;
    reg [3:0] nib;
    reg rej, inj;
    begin
      rej = reject;
      if (bus4) begin
        // 4-bit block: 1024 nibbles on DAT3..DAT0, then 16 CRC clocks with
        // one CRC16 PER LINE; data staged and committed only when accepted
        inj = (corrupt_line <= 3'd3);
        crc  = 16'd0;
        crc1 = 16'd0;
        crc2 = 16'd0;
        crc3 = 16'd0;
        byt  = 8'h00;
        for (i = 0; i < 1024; i = i + 1) begin
          @(posedge sd_clk);
          nib = {sd_dat3_i, sd_dat2_i, sd_dat1_i, sd_dat0_i};
          crc3 = crc16_step(crc3, nib[3]);
          crc2 = crc16_step(crc2, nib[2]);
          crc1 = crc16_step(crc1, nib[1]);
          crc  = crc16_step(crc, nib[0]);
          if (!i[0]) byt[7:4] = nib;
          else begin
            byt[3:0] = nib;
            blkbuf[i/2] = byt;
          end
        end
        if (inj) begin  // injected wire error on one line: card CRC differs
          case (corrupt_line)
            3'd0: crc = crc ^ 16'h0001;
            3'd1: crc1 = crc1 ^ 16'h0001;
            3'd2: crc2 = crc2 ^ 16'h0001;
            default: crc3 = crc3 ^ 16'h0001;
          endcase
          corrupt_line = 3'd7;  // one-shot
        end
        crc_host = 16'd0;
        crch1 = 16'd0;
        crch2 = 16'd0;
        crch3 = 16'd0;
        for (i = 15; i >= 0; i = i - 1) begin
          @(posedge sd_clk);
          crc_host[i] = sd_dat0_i;
          crch1[i] = sd_dat1_i;
          crch2[i] = sd_dat2_i;
          crch3[i] = sd_dat3_i;
        end
        if (crc_host !== crc || crch1 !== crc1 ||
            crch2 !== crc2 || crch3 !== crc3) begin
          if (!rej && !inj) begin
            wr_crc_errors = wr_crc_errors + 1;
            $display("sd_card_model: 4-bit write CRC16 mismatch at %0t", $time);
          end
          rej = 1'b1;  // a real card rejects the block ("101"), no commit
        end
        if (!rej) begin
          for (i = 0; i < 512; i = i + 1)
            if (base + i < MAX_BYTES) mem[base+i] = blkbuf[i];
        end
        @(posedge sd_clk);  // host end nibble
      end else begin
        crc = 16'd0;
        for (i = 0; i < 512; i = i + 1) begin
          byt = 8'h00;
          for (b = 7; b >= 0; b = b - 1) begin
            @(posedge sd_clk);
            byt[b] = sd_dat0_i;
            crc = crc16_step(crc, sd_dat0_i);
          end
          if (!reject && base + i < MAX_BYTES) mem[base+i] = byt;
        end
        crc_host = 16'd0;
        for (i = 15; i >= 0; i = i - 1) begin
          @(posedge sd_clk);
          crc_host[i] = sd_dat0_i;
        end
        if (!reject && crc_host !== crc) begin
          wr_crc_errors = wr_crc_errors + 1;
          $display("sd_card_model: write data CRC16 mismatch at %0t", $time);
        end
        @(posedge sd_clk);  // host end bit
      end

      // CRC status token + end bit: "010" = accepted (then busy for 64
      // clocks), "101" = rejected (no programming, so no busy phase);
      // the token and the busy stay on DAT0 in EVERY bus width
      repeat (2) @(negedge sd_clk);
      @(negedge sd_clk) begin dat_oe <= 1'b1; dat_out <= 1'b0; end  // start
      @(negedge sd_clk) dat_out <= rej ? 1'b1 : 1'b0;  // s2
      @(negedge sd_clk) dat_out <= rej ? 1'b0 : 1'b1;  // s1
      @(negedge sd_clk) dat_out <= rej ? 1'b1 : 1'b0;  // s0
      @(negedge sd_clk) dat_out <= 1'b1;  // token end bit
      if (!rej) begin
        @(negedge sd_clk) dat_out <= 1'b0;  // busy...
        repeat (63) @(negedge sd_clk);
        @(negedge sd_clk) dat_out <= 1'b1;  // ready
      end
      @(negedge sd_clk) dat_oe <= 1'b0;  // release DAT0
    end
  endtask

  // build a 48-bit response with a correct CRC7 (the host ignores it, but
  // an honest model catches host-side regressions)
  function [47:0] r48(input [5:0] rcmd, input [31:0] rarg);
    reg [39:0] head;
    begin
      head = {2'b00, rcmd, rarg};
      r48  = {head, crc7_of40(head), 1'b1};
    end
  endfunction

  // send a 48-bit response on CMD (NCR = 4 clocks, MSB first, falling edges)
  task send_resp48(input [47:0] r);
    integer i;
    begin
      repeat (4) @(negedge sd_clk);
      for (i = 47; i >= 0; i = i - 1) begin
        @(negedge sd_clk);
        cmd_drive <= 1'b1;
        cmd_out   <= r[i];
      end
      @(negedge sd_clk);
      cmd_drive <= 1'b0;
      cmd_out   <= 1'b1;
    end
  endtask

  // receive the remaining 47 bits of a host command whose start bit was
  // already sampled at a rising edge; verify the CRC7; a CMD12 is answered
  // with R1 (and counted), anything else is reported and ignored
  task recv_rest_cmd(output [5:0] rcmd);
    integer i;
    reg [47:0] q;
    reg [6:0] cc;
    begin
      q = 48'd0;
      for (i = 46; i >= 0; i = i - 1) begin
        @(posedge sd_clk);
        q[i] = sd_cmd_i;
      end
      cc = crc7_of40(q[47:8]);
      if ({cc, 1'b1} !== q[7:0]) begin
        crc_errors = crc_errors + 1;
        $display("sd_card_model: CMD%0d CRC7 MISMATCH (mid-transfer) at %0t", q[45:40], $time);
      end
      rcmd = q[45:40];
      if (q[45:40] == 6'd12) begin
        cmd12_count = cmd12_count + 1;
        send_resp48(r48(6'd12, 32'h00000900));
      end else begin
        $display("sd_card_model: unexpected CMD%0d during multi-block at %0t", q[45:40], $time);
      end
    end
  endtask

  // CMD18: stream consecutive blocks on DAT0 until the host sends CMD12;
  // the CMD line is watched at EVERY rising edge (block gaps and every
  // data bit) so the CMD12 start bit is never missed or misaligned
  task stream_blocks(input [31:0] base);
    integer blk, i, b, k, nb;
    reg [15:0] crc, crc1, crc2, crc3;
    reg bitv, abort;
    reg [5:0] rcmd;
    reg blkbits[0:4113];       // 1-bit: start + 4096 data + 16 CRC + end
    reg [3:0] blknibs[0:1041]; // 4-bit: start + 1024 nibbles + 16 CRC + end
    reg [7:0] byt;
    reg [3:0] nib;
    integer gap_now;
    begin
      abort = 1'b0;
      blk = 0;
      while (!abort) begin
        // inter-block gap, watching CMD for a command start bit. Real
        // cards stream back-to-back (spec N_AC minimum 2 clocks), so the
        // default is MINIMAL; rgap_rand randomizes it 0..16 per block so
        // a host whose start-bit hunt re-arms late fails here, not on
        // silicon.
        k = 0;
        gap_now = rgap_rand ? ({$random} % 17) : {24'd0, rgap};
        while (!abort && k < gap_now) begin
          @(posedge sd_clk);
          if (sd_cmd_i === 1'b0 && !cmd_drive) abort = 1'b1;
          else k = k + 1;
        end
        if (!abort && bus4) begin
          // assemble the framed 4-bit block (per-line CRC16), then drive it
          nb = 0;
          blknibs[nb] = 4'h0;  // start nibble on all four lines
          nb = nb + 1;
          crc  = 16'd0;
          crc1 = 16'd0;
          crc2 = 16'd0;
          crc3 = 16'd0;
          for (i = 0; i < 1024; i = i + 1) begin
            byt = (base + blk * 512 + (i / 2) < MAX_BYTES)
                  ? mem[base+blk*512+(i/2)] : 8'hFF;
            nib = i[0] ? byt[3:0] : byt[7:4];
            blknibs[nb] = nib;
            nb = nb + 1;
            crc3 = crc16_step(crc3, nib[3]);
            crc2 = crc16_step(crc2, nib[2]);
            crc1 = crc16_step(crc1, nib[1]);
            crc  = crc16_step(crc, nib[0]);
          end
          for (i = 15; i >= 0; i = i - 1) begin
            blknibs[nb] = {crc3[i], crc2[i], crc1[i], crc[i]};
            nb = nb + 1;
          end
          blknibs[nb] = 4'hF;  // end nibble
          nb = nb + 1;
          i = 0;
          while (!abort && i < nb) begin
            @(negedge sd_clk);
            dat_oe  <= 1'b1;
            datx_oe <= 1'b1;
            dat_out <= blknibs[i][0];
            d1_out  <= blknibs[i][1];
            d2_out  <= blknibs[i][2];
            d3_out  <= blknibs[i][3];
            i = i + 1;
            @(posedge sd_clk);
            if (sd_cmd_i === 1'b0 && !cmd_drive) abort = 1'b1;
          end
          @(negedge sd_clk) begin  // release the DAT lines between blocks
            dat_oe  <= 1'b0;
            datx_oe <= 1'b0;
          end
          if (!abort) blk = blk + 1;
        end else if (!abort) begin
          // assemble the framed block, then drive it bit by bit
          nb = 0;
          blkbits[nb] = 1'b0;  // start bit
          nb = nb + 1;
          crc = 16'd0;
          for (i = 0; i < 512; i = i + 1) begin
            for (b = 7; b >= 0; b = b - 1) begin
              bitv = (base + blk * 512 + i < MAX_BYTES) ? mem[base+blk*512+i][b] : 1'b1;
              blkbits[nb] = bitv;
              nb = nb + 1;
              crc = crc16_step(crc, bitv);
            end
          end
          for (i = 15; i >= 0; i = i - 1) begin
            blkbits[nb] = crc[i];
            nb = nb + 1;
          end
          blkbits[nb] = 1'b1;  // end bit
          nb = nb + 1;
          i = 0;
          while (!abort && i < nb) begin
            @(negedge sd_clk);
            dat_oe  <= 1'b1;
            dat_out <= blkbits[i];
            i = i + 1;
            @(posedge sd_clk);
            if (sd_cmd_i === 1'b0 && !cmd_drive) abort = 1'b1;
          end
          @(negedge sd_clk) dat_oe <= 1'b0;  // release DAT0 between blocks
          if (!abort) blk = blk + 1;
        end
      end
      recv_rest_cmd(rcmd);  // expect CMD12 -> R1
    end
  endtask

  // CMD25: accept write blocks on DAT0 until the host sends CMD12; every
  // block is validated and committed exactly like a CMD24 (injection and
  // reserved-region hooks included); CMD12 gets R1 plus the final busy
  task recv_blocks(input [31:0] base);
    integer blk;
    reg fin, rej;
    reg [31:0] cursec;
    reg [5:0] rcmd;
    begin
      blk = 0;
      fin = 1'b0;
      while (!fin) begin
        @(posedge sd_clk);
        if (sd_cmd_i === 1'b0 && !cmd_drive) begin
          recv_rest_cmd(rcmd);  // expect CMD12 -> R1
          // R1b: final busy while the last block finishes programming
          @(negedge sd_clk) begin
            dat_oe  <= 1'b1;
            dat_out <= 1'b0;
          end
          repeat (63) @(negedge sd_clk);
          @(negedge sd_clk) dat_out <= 1'b1;
          @(negedge sd_clk) dat_oe <= 1'b0;
          fin = 1'b1;
        end else if (sd_dat0_i === 1'b0 && !dat_oe) begin
          // data start bit: this burst block behaves exactly like a CMD24
          cursec = (base >> 9) + blk;
          rej = 1'b0;
          if (fail_next_writes != 32'd0) begin
            rej = 1'b1;
            fail_next_writes = fail_next_writes - 32'd1;
          end
          if (cursec == fail_sector) begin
            rej = 1'b1;
            fail_sector = 32'hFFFF_FFFF;  // one-shot
          end
          if (rej)
            $display("sd_card_model: CMD25 block sector %0d REJECTED (injected) at %0t",
                     cursec, $time);
          if (LEGAL_MIN_SECTOR != 0 && cursec < LEGAL_MIN_SECTOR) begin
            illegal_writes = illegal_writes + 1;
            $display("sd_card_model: ILLEGAL CMD25 write to reserved sector %0d at %0t",
                     cursec, $time);
          end
          recv_block_body(base + blk * 512, rej);
          blk = blk + 1;
        end
      end
    end
  endtask

  always begin : engine
    integer i;
    reg [6:0] crc_calc;
    // hunt for a command start bit on a rising edge
    @(posedge sd_clk);
    if (sd_cmd_i === 1'b0) begin
      req[47] = 1'b0;
      for (i = 46; i >= 0; i = i - 1) begin
        @(posedge sd_clk);
        req[i] = sd_cmd_i;
      end
      cmd = req[45:40];
      arg = req[39:8];

      // verify CRC7 over the first 40 bits
      crc_calc = crc7_of40(req[47:8]);
      if ({crc_calc, 1'b1} !== req[7:0]) begin
        crc_errors = crc_errors + 1;
        $display("sd_card_model: CMD%0d CRC7 MISMATCH (got %02x, want %02x) at %0t",
                 cmd, req[7:0], {crc_calc, 1'b1}, $time);
      end

      // decode
      resp_len   = 0;
      do_data    = 1'b0;
      do_write   = 1'b0;
      do_data18  = 1'b0;
      do_write25 = 1'b0;
      case (cmd)
        6'd0: begin  // GO_IDLE: no response; bus width resets to 1-bit and
          // the card leaves the addressed states, so its RCA is not assigned
          app_cmd       = 1'b0;
          bus4          = 1'b0;
          rca_published = 1'b0;
        end
        6'd6: begin  // ACMD6 -> R1: bus width (arg 2 = 4-bit); bare CMD6
          // (SWITCH_FUNC) is not modeled: no response, the host times out
          if (app_cmd) begin
            resp[135:88] = r48(6'd6, 32'h00000920);
            resp_len = 48;
            bus4 = (arg[3:0] == 4'd2);
            $display("sd_card_model: ACMD6 bus width -> %s at %0t",
                     bus4 ? "4-bit" : "1-bit", $time);
          end else begin
            $display("sd_card_model: CMD6 without CMD55 - no response at %0t",
                     $time);
          end
          app_cmd = 1'b0;
        end
        6'd8: begin  // SEND_IF_COND -> R7, echo the check pattern
          resp[135:88] = r48(6'd8, 32'h000001AA);
          resp_len = 48;
        end
        6'd55: begin  // APP_CMD -> R1, and ONLY when addressed to this card.
          // Before CMD3 the card has no address yet and RCA 0 is how the host
          // reaches it (that is the ACMD41 init path). AFTER CMD3 has
          // published 0x0001, RCA 0 is NOT this card's address - a real card
          // ignores it, and the ACMD that follows is taken as an ordinary
          // command. Modelling that is what catches a host which never picked
          // up the published RCA: it looks fine until it meets real silicon.
          if ((!rca_published && arg[31:16] == 16'h0000)
              || arg[31:16] == 16'h0001) begin
            resp[135:88] = r48(6'd55, 32'h00000120);
            resp_len = 48;
            app_cmd  = 1'b1;
          end else begin
            $display("sd_card_model: CMD55 with wrong RCA %04x ignored at %0t%s",
                     arg[31:16], $time,
                     (rca_published && arg[31:16] == 16'h0000)
                       ? " (RCA 0 after CMD3 - host never took the card's published RCA)"
                       : "");
            app_cmd = 1'b0;
          end
        end
        6'd41: begin  // ACMD41 -> R3: ready, CCS=1 (SDHC), reserved cmd field
          if (app_cmd) begin
            resp[135:88] = {2'b00, 6'b111111, 32'hC0FF8000, 7'b1111111, 1'b1};
            resp_len = 48;
          end
          app_cmd = 1'b0;
        end
        6'd23: begin  // ACMD23 -> R1 (pre-erase count); CMD23 alone: NO response
          if (app_cmd) begin
            resp[135:88] = r48(6'd23, 32'h00000900);
            resp_len = 48;
            acmd23_count = arg[22:0];
          end else begin
            $display("sd_card_model: CMD23 without CMD55 (wrong RCA?) - no response at %0t",
                     $time);
          end
          app_cmd = 1'b0;
        end
        6'd2: begin  // ALL_SEND_CID -> R2 (136 bits, reserved cmd field)
          resp = {2'b00, 6'b111111, 120'h4E44313230_53444D4F44454C_012345, 7'b1010101, 1'b1};
          resp_len = 136;
        end
        6'd3: begin  // SEND_RELATIVE_ADDR -> R6: RCA=0x0001, status 0x0500
          resp[135:88] = r48(6'd3, {16'h0001, 16'h0500});
          resp_len = 48;
          rca_published = 1'b1;
        end
        6'd9: begin  // SEND_CSD -> R2: CSD v2, capacity = the loaded image
          // frame = {00, 111111, CSD[127:1], end 1} so resp[k] = CSD[k]
          resp = {2'b00, 6'b111111, 120'd0, 7'b1010101, 1'b1};
          resp[127:120] = 8'h40;  // CSD_STRUCTURE = 1 (CSD version 2.0)
          resp[69:48] = img_bytes / 524288 - 1;  // C_SIZE (512 KB units - 1)
          resp_len = 136;
        end
        6'd7: begin  // SELECT_CARD -> R1
          resp[135:88] = r48(6'd7, 32'h00000700);
          resp_len = 48;
        end
        6'd12: begin  // STOP_TRANSMISSION while idle -> R1 (stray, counted)
          resp[135:88] = r48(6'd12, 32'h00000900);
          resp_len = 48;
          cmd12_count = cmd12_count + 1;
        end
        6'd16: begin  // SET_BLOCKLEN -> R1
          resp[135:88] = r48(6'd16, 32'h00000900);
          resp_len = 48;
        end
        6'd17: begin  // READ_SINGLE_BLOCK -> R1 + data block (SDHC: arg = sector)
          resp[135:88] = r48(6'd17, 32'h00000900);
          resp_len  = 48;
          do_data   = 1'b1;
          data_base = arg * 512;
        end
        6'd18: begin  // READ_MULTIPLE_BLOCK -> R1 + blocks until CMD12
          resp[135:88] = r48(6'd18, 32'h00000900);
          resp_len  = 48;
          do_data18 = 1'b1;
          data_base = arg * 512;
        end
        6'd24: begin  // WRITE_BLOCK -> R1 + receive a data block (SDHC: arg = sector)
          resp[135:88] = r48(6'd24, 32'h00000900);
          resp_len  = 48;
          do_write  = 1'b1;
          data_base = arg * 512;
          wr_reject = 1'b0;
          if (fail_next_writes != 32'd0) begin
            wr_reject = 1'b1;
            fail_next_writes = fail_next_writes - 32'd1;
          end
          if (arg == fail_sector) begin
            wr_reject = 1'b1;
            fail_sector = 32'hFFFF_FFFF;  // one-shot
          end
          if (wr_reject)
            $display("sd_card_model: CMD24 sector %0d REJECTED (injected) at %0t", arg, $time);
          if (LEGAL_MIN_SECTOR != 0 && arg < LEGAL_MIN_SECTOR) begin
            illegal_writes = illegal_writes + 1;
            $display("sd_card_model: ILLEGAL CMD24 to reserved sector %0d at %0t", arg, $time);
          end
        end
        6'd25: begin  // WRITE_MULTIPLE_BLOCK -> R1 + blocks until CMD12
          resp[135:88] = r48(6'd25, 32'h00000900);
          resp_len   = 48;
          do_write25 = 1'b1;
          data_base  = arg * 512;
        end
        default: ;  // no response -> host times out
      endcase

      // respond: NCR = 4 clocks, then MSB-first on falling edges
      if (resp_len > 0) begin
        repeat (4) @(negedge sd_clk);
        for (i = 0; i < resp_len; i = i + 1) begin
          @(negedge sd_clk);
          cmd_drive <= 1'b1;
          cmd_out   <= resp[135-i];
        end
        @(negedge sd_clk);
        cmd_drive <= 1'b0;
        cmd_out   <= 1'b1;
      end

      if (do_data) begin
        if (fail_next_reads != 32'd0) begin
          // injected read fault: answer the command, then send NOTHING.
          // The host's read watchdog is what must catch this.
          fail_next_reads = fail_next_reads - 32'd1;
        end else begin
          send_block(data_base);
        end
      end
      if (do_data18) stream_blocks(data_base);
      if (do_write) begin
        // wait for the host's data start bit (with a timeout), then receive
        begin : wr_wait
          integer guard;
          guard = 0;
          while (guard >= 0) begin
            @(posedge sd_clk);
            if (sd_dat0_i === 1'b0) guard = -1;  // start bit seen
            else if (guard > 5000) begin
              $display("sd_card_model: CMD24 data start-bit timeout at %0t", $time);
              guard = -2;
            end else guard = guard + 1;
          end
          if (guard == -1) recv_block_body(data_base, wr_reject);
        end
      end
      if (do_write25) recv_blocks(data_base);
    end
  end

endmodule
