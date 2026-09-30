`timescale 1ns / 1ps
`default_nettype none

/**************************************************************************
** Testbench for ND_FLOPPY_PIO - IOX REGISTER MAP, STATUS BIT POSITIONS  **
** COMMAND DECODE and the COMPLETION / INTERRUPT / IDENT handshake.      **
**                                                                       **
** DUT: Verilog/ND-BUS-DEVICES/FLOPPY/                                   **
**        circuit/ND_FLOPPY_PIO.v                                        **
**                                                                       **
** WHY THIS BENCH EXISTS ALONGSIDE nd_floppy_pio_tb.v                    **
**   The existing bench in this same directory drives the controller     **
**   THROUGH ND_BUS_SLAVE with an image-backed disk model, and it tests  **
**   whole scenarios (boot-style sector read, seek, write-back). It      **
**   therefore only ever touches the register addresses those scenarios  **
**   happen to use. This bench does the opposite: it attaches DIRECTLY   **
**   to the device-bus port and attacks the WIRING -                     **
**     - EXHAUSTIVE sweep of all 65536 iox_addr values, proving that     **
**       exactly eight addresses respond and every other address reads   **
**       zero (the repo's OR-bus rule: a disabled output drives 0)       **
**     - which of those eight addresses reads which register, and that   **
**       the four odd (write-only) addresses read zero                   **
**     - the BIT POSITION of every status flag in RSR1 and RSR2          **
**     - EXHAUSTIVE 256-value sweep of the control-word high byte        **
**       against the "highest set bit wins" command decode               **
**     - which write address latches which field, with walking patterns  **
**       over the drive / format / sector / track-difference fields      **
**     - the completion delay, the level-11 interrupt condition, and     **
**       the IDENT answer + grant daisy-chain                            **
**                                                                       **
** WHERE THE REFERENCE MODEL COMES FROM                                  **
**   Read off the NETLIST of ND_FLOPPY_PIO.v, line by line - NOT from    **
**   the ND-11.012.01 register spec, NOT from the C models it names, and **
**   NOT from any floppy-controller datasheet. Where the RTL's behaviour **
**   looks questionable this bench CHARACTERISES it (records what the    **
**   RTL does today) and says so in the list below, rather than          **
**   inventing a specification. No RTL was changed.                      **
**                                                                       **
**   Key netlist facts the model is built on (file line numbers):        **
**     150  s_addressed = (iox_addr[15:3] == BASE_ADDR[15:3])            **
**          -> the decode ignores nothing else; exactly 8 addresses      **
**             respond, o1560..o1567 for the default BASE_ADDR           **
**     167-178 read mux: +0 buffer[bufptr], +2 RSR1, +4 RSR2, +6 const 0 **
**          and everything else 0; the whole mux is gated by iox_rd      **
**     113-117 RSR2 = {0,overrun,0,crc,missing,0,wprot,notready,8'd0}    **
**             RSR1 = {7'd0,timeout,seekc,rwc,deleted,rsr2_or,rft,busy,  **
**                     inten,1'b0}                                       **
**     186-194 cmd_decode: loops k=0..7 keeping the LAST set bit, i.e.   **
**             the HIGHEST set bit of iox_wdata[15:8], wins              **
**     154-164 pending = int_enabled & rft; ident answers only on        **
**             strobe & grant_in & level==INT_LEVEL & pending            **
**                                                                       **
** CHARACTERISED BEHAVIOUR (recorded, not asserted as correct - each of  **
** these is reported in the campaign notes as a suspected defect):       **
**   C1. Read address +6 ("read test data") returns CONSTANT 0 even in   **
**       test mode. Line 174 hard-codes 0 and the clocked block at       **
**       356-365 only shifts the test byte INTO the interface buffer.    **
**       The CPU can therefore never read the test byte back from +6.    **
**   C2. An error completion never restores "ready for transfer".        **
**       Lines 370-375: on disk_err_notrdy or disk_err_missing the DUT   **
**       clears s_busy but leaves s_rft at 0 and does NOT start the      **
**       completion delay - so no completion flag, and because           **
**       pending = int_enabled & rft, NO INTERRUPT IS EVER RAISED for a  **
**       failed operation. Contrast line 311, where the "sector out of   **
**       range" rejection DOES set s_rft back to 1, and line 314, where  **
**       the "no drive selected" rejection does NOT. This bench pins     **
**       all three so the inconsistency is visible in the log.           **
**   C3. Sector auto-increment can step one past the end of the track:   **
**       line 398 permits the increment while s_sector <= sectors/track, **
**       so the last sector advances to sectors/track + 1.               **
**   C4. Status bits deleted(RSR1 b5), timeout(RSR1 b8), write_prot      **
**       (RSR2 b9), crc(RSR2 b12) and overrun(RSR2 b14) are declared and **
**       placed but nothing in the RTL ever sets them. This bench checks **
**       they stay 0 through every stimulus it applies, which is a       **
**       characterisation of today's RTL, not an endorsement.            **
**   C5. Reading +0 increments the buffer pointer on every clock edge    **
**       for which iox_rd is high (line 239). It is the bus slave, not   **
**       the controller, that must guarantee a one-cycle iox_rd pulse.   **
**       This bench always pulses iox_rd for exactly one edge.           **
**                                                                       **
** BUILD MODES: ND_FLOPPY_PIO.v contains no `ifdef at all (no            **
** FPGA_FF_MODE, no VERILATOR_SIM), so one build covers every path. The  **
** registered make target still compiles and runs it a second time with  **
** -DFPGA_FF_MODE to prove the results are identical.                    **
**                                                                       **
** The DUT is instantiated with DELAY_TICKS=5 instead of the default     **
** 3000 purely to keep the run and the committed VCD short; the delay    **
** counter is exercised by count, not by wall time.                      **
**                                                                       **
** HOW TO RUN                                                            **
**   cd Verilog/ND-BUS-DEVICES/FLOPPY/sim && make test-floppy-ioxmap     **
**                                                                       **
** Ronny Hansen                                                          **
** 20-AUG-2026                                                           **
***************************************************************************/

module ND_FLOPPY_PIO_IOXMAP_tb;

  // Guard against a bench that silently stops checking. Set from the
  // enumerated plan above (sections A-I); if a future RTL change makes a
  // conditional branch run differently the count moves and this fires.
  localparam integer EXPECTED_CHECKS = 66281;

  localparam [15:0] BASE = 16'o001560;
  localparam integer DLY = 5;

  reg         sysclk = 1'b0;
  reg         sys_rst_n = 1'b0;

  reg  [15:0] iox_addr = 16'd0;
  reg         iox_wr = 1'b0;
  reg  [15:0] iox_wdata = 16'd0;
  reg         iox_rd = 1'b0;
  wire [15:0] iox_rdata;
  wire [3:0]  int_pending;
  reg         ident_strobe = 1'b0;
  reg  [3:0]  ident_level = 4'd0;
  reg         ident_grant_in = 1'b0;
  wire        ident_grant_out;
  wire        ident_hit;
  wire [15:0] ident_code;

  wire        disk_req;
  wire [2:0]  disk_op;
  wire [6:0]  disk_sector;
  wire [6:0]  disk_track;
  wire [1:0]  disk_format;
  wire [2:0]  disk_drive;
  wire [9:0]  disk_buf_start;
  wire [10:0] disk_wordcount;
  reg         disk_done = 1'b0;
  reg         disk_err_notrdy = 1'b0;
  reg         disk_err_missing = 1'b0;

  reg  [9:0]  dbuf_addr = 10'd0;
  reg  [15:0] dbuf_wdata = 16'd0;
  reg         dbuf_we = 1'b0;
  wire [15:0] dbuf_rdata;

  integer checks = 0;
  integer errors = 0;
  integer cycles = 0;

  reg [15:0] rv;

  ND_FLOPPY_PIO #(
      .BASE_ADDR  (BASE),
      .IDENT_CODE (16'o000021),
      .INT_LEVEL  (4'd11),
      .DELAY_TICKS(DLY[15:0])
  ) DUT (
      .sysclk         (sysclk),
      .sys_rst_n      (sys_rst_n),
      .iox_addr       (iox_addr),
      .iox_wr         (iox_wr),
      .iox_wdata      (iox_wdata),
      .iox_rd         (iox_rd),
      .iox_rdata      (iox_rdata),
      .int_pending    (int_pending),
      .ident_strobe   (ident_strobe),
      .ident_level    (ident_level),
      .ident_grant_in (ident_grant_in),
      .ident_grant_out(ident_grant_out),
      .ident_hit      (ident_hit),
      .ident_code     (ident_code),
      .disk_req       (disk_req),
      .disk_op        (disk_op),
      .disk_sector    (disk_sector),
      .disk_track     (disk_track),
      .disk_format    (disk_format),
      .disk_drive     (disk_drive),
      .disk_buf_start (disk_buf_start),
      .disk_wordcount (disk_wordcount),
      .disk_done      (disk_done),
      .disk_err_notrdy(disk_err_notrdy),
      .disk_err_missing(disk_err_missing),
      .dbuf_addr      (dbuf_addr),
      .dbuf_wdata     (dbuf_wdata),
      .dbuf_we        (dbuf_we),
      .dbuf_rdata     (dbuf_rdata)
  );

  initial begin
    $dumpfile("ND_FLOPPY_PIO_IOXMAP_tb.vcd");
    $dumpvars(0, ND_FLOPPY_PIO_IOXMAP_tb);
  end

  // ---- watchdog ---------------------------------------------------------
  // The DUT has a delay counter and a command engine; a build where the
  // engine never completes must fail, not hang.
  initial begin
    #4000000;
    $display("FAIL WATCHDOG: not finished after 4000000 ns (%0d clocks)", cycles);
    $display(" checks run : %0d", checks);
    $display(" failures   : %0d", errors + 1);
    $display("TB_RESULT: FAIL");
    $finish;
  end

  // ---- helpers ----------------------------------------------------------
  // The clock is stepped explicitly so the address sweep can be run with
  // the clock FROZEN - that keeps it purely combinational and free of
  // buffer-pointer side effects.
  task tick;
    begin
      #10 sysclk = 1'b1;
      #10 sysclk = 1'b0;
      cycles = cycles + 1;
    end
  endtask

  task ck;
    input [255:0] name;
    input [31:0]  got;
    input [31:0]  exp;
    begin
      checks = checks + 1;
      if (got !== exp) begin
        errors = errors + 1;
        if (errors < 40)
          $display("FAIL %0s at t=%0t: got %0h expected %0h", name, $time, got, exp);
      end
    end
  endtask

  // combinational peek - no clock edge, so no side effects at all
  task peek;
    input [15:0] a;
    begin
      iox_addr = a;
      iox_rd   = 1'b1;
      #1;
      rv = iox_rdata;
      iox_rd = 1'b0;
      #1;
    end
  endtask

  // real CPU read: one clock edge with iox_rd high
  task bus_read;
    input [15:0] a;
    begin
      iox_addr = a;
      iox_rd   = 1'b1;
      #1;
      rv = iox_rdata;
      tick;
      iox_rd = 1'b0;
      #1;
    end
  endtask

  task bus_write;
    input [15:0] a;
    input [15:0] d;
    begin
      iox_addr  = a;
      iox_wdata = d;
      iox_wr    = 1'b1;
      #1;
      tick;
      iox_wr = 1'b0;
      #1;
    end
  endtask

  task do_reset;
    begin
      sys_rst_n = 1'b0;
      iox_wr = 1'b0; iox_rd = 1'b0; iox_addr = 16'd0; iox_wdata = 16'd0;
      ident_strobe = 1'b0; ident_grant_in = 1'b0; ident_level = 4'd0;
      disk_done = 1'b0; disk_err_notrdy = 1'b0; disk_err_missing = 1'b0;
      dbuf_we = 1'b0;
      tick;
      sys_rst_n = 1'b1;
      tick;
    end
  endtask

  // load one word into the interface buffer over the BACKEND port
  task bram_poke;
    input [9:0]  a;
    input [15:0] d;
    begin
      dbuf_addr  = a;
      dbuf_wdata = d;
      dbuf_we    = 1'b1;
      tick;
      dbuf_we = 1'b0;
    end
  endtask

  task bram_read;
    input [9:0] a;
    begin
      dbuf_addr = a;
      #1;
      rv = dbuf_rdata;
    end
  endtask

  // expected RSR1 / RSR2 words, assembled from named flags
  function [15:0] mk_rsr1;
    input timeout, seekc, rwc, deleted, rsr2_or, rft, busy, inten;
    begin
      mk_rsr1 = {7'd0, timeout, seekc, rwc, deleted, rsr2_or, rft, busy, inten, 1'b0};
    end
  endfunction

  function [15:0] mk_rsr2;
    input overrun, crc, missing, wprot, notrdy;
    begin
      mk_rsr2 = {1'b0, overrun, 1'b0, crc, missing, 1'b0, wprot, notrdy, 8'd0};
    end
  endfunction

  integer i, j, k;
  integer exp_cmd;
  reg [15:0] rsr1_now, rsr2_now;
  reg [7:0]  hi;
  reg [6:0]  trk;

  initial begin
    $display("=====================================================");
    $display(" ND_FLOPPY_PIO - IOX map / status bits / command decode");
    $display("=====================================================");

    do_reset;

    // =================================================================
    // A. Reset state (netlist lines 200-229)
    // =================================================================
    peek(BASE + 16'd2); ck("A_RSR1_RESET", rv, mk_rsr1(0,0,0,0,0,1,0,0));  // rft only
    peek(BASE + 16'd4); ck("A_RSR2_RESET", rv, 16'd0);
    ck("A_INTPEND_RESET",  int_pending, 4'd0);
    ck("A_IDENTHIT_RESET", ident_hit,   1'b0);
    ck("A_IDENTCODE_RESET",ident_code,  16'd0);
    ck("A_DISKREQ_RESET",  disk_req,    1'b0);
    ck("A_SECTOR_RESET",   disk_sector, 7'd1);
    ck("A_TRACK_RESET",    disk_track,  7'd0);
    ck("A_FORMAT_RESET",   disk_format, 2'd0);
    ck("A_DRIVE_RESET",    disk_drive,  3'd0);
    // format 0 -> 26 sectors/track, 64 words/sector (lines 130-133)
    ck("A_WORDCOUNT_FMT0", disk_wordcount, 11'd64);

    // =================================================================
    // B. EXHAUSTIVE 16-bit address decode sweep, clock frozen.
    //    Preload buffer[0] with a marker so the +0 read is
    //    distinguishable from "not addressed".
    // =================================================================
    bram_poke(10'd0, 16'hBEEF);
    // put a non-zero pattern into RSR2 as well: a data command with no
    // drive selected sets not_ready (line 314). It also leaves rft=0,
    // which is characterisation point C2.
    bus_write(BASE + 16'd3, 16'h1000);          // read-data command, no drive
    peek(BASE + 16'd4);
    ck("B_SETUP_RSR2_NOTRDY", rv, mk_rsr2(0,0,0,0,1));
    peek(BASE + 16'd2);
    ck("B_SETUP_RSR1_NOTRDY", rv, mk_rsr1(0,0,0,0,1,0,0,0));  // rsr2_or, no rft
    rsr1_now = mk_rsr1(0,0,0,0,1,0,0,0);
    rsr2_now = mk_rsr2(0,0,0,0,1);

    for (i = 0; i < 65536; i = i + 1) begin
      iox_addr = i[15:0];
      iox_rd   = 1'b1;
      #1;
      if (i[15:3] == BASE[15:3]) begin
        case (i[2:0])
          3'd0: ck("B_MAP_R0_BUFFER", iox_rdata, 16'hBEEF);
          3'd2: ck("B_MAP_R2_RSR1",   iox_rdata, rsr1_now);
          3'd4: ck("B_MAP_R4_RSR2",   iox_rdata, rsr2_now);
          // +6 is documented "read test data" but the mux hard-codes 0
          // (characterisation C1); 1/3/5/7 are write-only.
          default: ck("B_MAP_ZERO_REG", iox_rdata, 16'd0);
        endcase
      end else begin
        ck("B_NOT_ADDRESSED_MUST_BE_ZERO", iox_rdata, 16'd0);
      end
      iox_rd = 1'b0;
    end
    #1;

    // C. read-enable low: every one of the 8 addresses must read 0
    for (i = 0; i < 8; i = i + 1) begin
      iox_addr = BASE + i[15:0];
      iox_rd   = 1'b0;
      #1;
      ck("C_RD_LOW_DRIVES_ZERO", iox_rdata, 16'd0);
    end

    // =================================================================
    // D. Status bit positions, one flag at a time.
    // =================================================================
    do_reset;

    // D1 int_enabled -> RSR1 bit 1 (control word bit 1, line 249)
    bus_write(BASE + 16'd3, 16'h0002);
    peek(BASE + 16'd2); ck("D1_INTEN_B1", rv, mk_rsr1(0,0,0,0,0,1,0,1));

    // D2 busy -> RSR1 bit 2, and rft cleared, on any command (267-271).
    //    Use SEEK (control bit 13 -> command 5) so nothing reaches the
    //    disk backend.
    bus_write(BASE + 16'd3, 16'h2002);
    peek(BASE + 16'd2); ck("D2_BUSY_B2_RFT_CLEARED", rv, mk_rsr1(0,0,0,0,0,0,1,1));
    ck("D2_NO_DISK_REQ_ON_SEEK", disk_req, 1'b0);
    ck("D2_PENDING_LOW_WHILE_BUSY", int_pending, 4'd0);

    // D3 completion delay: DLY+1 edges after the command (387-403)
    for (i = 0; i < DLY; i = i + 1) begin
      tick;
      peek(BASE + 16'd2);
      ck("D3_STILL_BUSY_DURING_DELAY", rv, mk_rsr1(0,0,0,0,0,0,1,1));
    end
    tick;
    peek(BASE + 16'd2);
    ck("D3_SEEKCOMPLETE_B7_RFT_B3", rv, mk_rsr1(0,1,0,0,0,1,0,1));
    ck("D3_INTPEND_LEVEL11_ONEHOT", int_pending, 4'b0010);

    // D4 rw_complete -> RSR1 bit 6, via READ ID (command 3, control bit
    //    11) which also completes through the delay path (297-306)
    do_reset;
    bus_write(BASE + 16'd3, 16'h0800);
    for (i = 0; i <= DLY; i = i + 1) tick;
    peek(BASE + 16'd2); ck("D4_RWCOMPLETE_B6", rv, mk_rsr1(0,0,1,0,0,1,0,0));
    // READ ID writes track/sector into buffer words 0 and 1 (300-301)
    bram_read(10'd0); ck("D4_READID_W0_TRACK",  rv, {1'b0, 7'd0, 8'd0});
    bram_read(10'd1); ck("D4_READID_W1_SECTOR", rv, {1'b0, 7'd1, 8'd0});

    // D5 missing -> RSR2 bit 11, and rsr2_or -> RSR1 bit 4.
    //    Sector out of range for format 0 (26 sectors) -> line 309-312.
    //    NOTE this path DOES set rft back to 1 (characterisation C2).
    do_reset;
    bus_write(BASE + 16'd7, 16'h1B00);          // sector 27, auto_incr=0
    ck("D5_SECTOR_LATCHED", disk_sector, 7'd27);
    bus_write(BASE + 16'd3, 16'h1000);          // read data
    peek(BASE + 16'd4); ck("D5_MISSING_B11", rv, mk_rsr2(0,0,1,0,0));
    peek(BASE + 16'd2); ck("D5_RSR2OR_B4_RFT_SET", rv, mk_rsr1(0,0,0,0,1,1,0,0));
    ck("D5_NO_DISK_REQ", disk_req, 1'b0);

    // D6 not_ready -> RSR2 bit 8, no drive selected (313-315).
    //    THIS path leaves rft at 0 - the inconsistency of C2.
    do_reset;
    bus_write(BASE + 16'd3, 16'h1000);
    peek(BASE + 16'd4); ck("D6_NOTREADY_B8", rv, mk_rsr2(0,0,0,0,1));
    peek(BASE + 16'd2); ck("D6_RFT_STAYS_CLEARED", rv, mk_rsr1(0,0,0,0,1,0,0,0));

    // =================================================================
    // E. Write-address map. Each address must latch ONLY its own field.
    // =================================================================
    do_reset;

    // E1 +5 with bit0=1: drive / drive-select / format (327-332).
    //    Walk every drive code and every format code.
    for (i = 0; i < 8; i = i + 1) begin
      for (j = 0; j < 4; j = j + 1) begin
        bus_write(BASE + 16'd5, {j[1:0], 2'b00, 1'b0, i[2:0], 8'h01});
        ck("E1_DRIVE_FIELD",  disk_drive,  i[2:0]);
        ck("E1_FORMAT_FIELD", disk_format, j[1:0]);
      end
    end
    // words/sector and sectors/track follow the format (130-133)
    bus_write(BASE + 16'd5, 16'h0001); ck("E1_WPS_FMT0", disk_wordcount, 11'd64);
    bus_write(BASE + 16'd5, 16'h4001); ck("E1_WPS_FMT1", disk_wordcount, 11'd64);
    bus_write(BASE + 16'd5, 16'h8001); ck("E1_WPS_FMT2", disk_wordcount, 11'd128);
    bus_write(BASE + 16'd5, 16'hC001); ck("E1_WPS_FMT3", disk_wordcount, 11'd256);
    // bit 11 DESELECTS: drive_sel = !wdata[11] (line 331). Observable
    // because a data command with no drive selected sets not_ready.
    do_reset;
    bus_write(BASE + 16'd5, 16'h0901);          // bit11 set -> deselect
    bus_write(BASE + 16'd3, 16'h1000);
    peek(BASE + 16'd4); ck("E1_BIT11_DESELECTS", rv, mk_rsr2(0,0,0,0,1));
    do_reset;
    bus_write(BASE + 16'd5, 16'h0101);          // bit11 clear -> select
    bus_write(BASE + 16'd3, 16'h1000);
    peek(BASE + 16'd4); ck("E1_BIT11_CLEAR_SELECTS", rv, 16'd0);
    ck("E1_SELECTED_ISSUES_DISK_OP", disk_op, 3'd4);

    // E2 +5 with bit0=0: track difference, walking magnitudes, clamped
    //    to 0..76 (334-341).
    do_reset;
    bus_write(BASE + 16'd5, 16'h8A00);          // b15=1 -> +10
    ck("E2_TRACK_PLUS10", disk_track, 7'd10);
    bus_write(BASE + 16'd5, 16'h0300);          // b15=0 -> -3
    ck("E2_TRACK_MINUS3", disk_track, 7'd7);
    bus_write(BASE + 16'd5, 16'h0F00);          // -15 from 7 -> clamp 0
    ck("E2_TRACK_CLAMP_LOW", disk_track, 7'd0);
    bus_write(BASE + 16'd5, 16'hFF00);          // +127 -> clamp 76
    ck("E2_TRACK_CLAMP_HIGH", disk_track, 7'd76);
    // walking-one over the difference field from a known base
    for (i = 0; i < 7; i = i + 1) begin
      bus_write(BASE + 16'd5, 16'h7F00);        // -127, floors at 0
      trk = ((7'd1 << i) > 7'd76) ? 7'd76 : (7'd1 << i);
      bus_write(BASE + 16'd5, {1'b1, (7'd1 << i), 8'h00});
      ck("E2_TRACK_WALKING_ONE", disk_track, trk);
    end

    // E3 +7: sector field bits 14:8, auto-increment bit 15 (346-352)
    do_reset;
    for (i = 0; i < 7; i = i + 1) begin
      bus_write(BASE + 16'd7, {1'b0, (7'd1 << i), 8'h00});
      ck("E3_SECTOR_WALKING_ONE", disk_sector, (7'd1 << i));
    end

    // E4 +1 writes the interface buffer and post-increments the pointer
    //    (242-245); +0/+2/+4/+6 writes must do NOTHING (no case for them).
    do_reset;
    bus_write(BASE + 16'd1, 16'h1111);
    bus_write(BASE + 16'd1, 16'h2222);
    bus_write(BASE + 16'd1, 16'h3333);
    bram_read(10'd0); ck("E4_BUF_W0", rv, 16'h1111);
    bram_read(10'd1); ck("E4_BUF_W1", rv, 16'h2222);
    bram_read(10'd2); ck("E4_BUF_W2", rv, 16'h3333);
    // pointer now 3 -> a CPU read of +0 must return buffer[3]
    bram_poke(10'd3, 16'h4444);
    bus_read(BASE + 16'd0); ck("E4_PTR_AT_3", rv, 16'h4444);
    // ...and that read post-incremented it to 4
    bram_poke(10'd4, 16'h5555);
    peek(BASE + 16'd0); ck("E4_PTR_AT_4_AFTER_READ", rv, 16'h5555);
    // writes to the read-only addresses change nothing
    bus_write(BASE + 16'd0, 16'hDEAD);
    bus_write(BASE + 16'd2, 16'hDEAD);
    bus_write(BASE + 16'd4, 16'hDEAD);
    bus_write(BASE + 16'd6, 16'hDEAD);
    peek(BASE + 16'd0); ck("E4_RO_WRITES_NO_PTR_MOVE", rv, 16'h5555);
    bram_read(10'd4);    ck("E4_RO_WRITES_NO_BUF_WRITE", rv, 16'h5555);
    peek(BASE + 16'd2);  ck("E4_RO_WRITES_NO_STATUS_CHANGE", rv, mk_rsr1(0,0,0,0,0,1,0,0));

    // E5 control word bit 5 clears the buffer pointer and sets rft (262)
    bus_write(BASE + 16'd3, 16'h0020);
    bram_poke(10'd0, 16'h6666);
    peek(BASE + 16'd0); ck("E5_CLEAR_BUF_ADDRESS", rv, 16'h6666);

    // E6 control word bit 4 = device clear (252-260): deselects the drive
    do_reset;
    bus_write(BASE + 16'd5, 16'h0101);          // select drive 1
    bus_write(BASE + 16'd3, 16'h0010);          // device clear
    bus_write(BASE + 16'd3, 16'h1000);          // read data
    peek(BASE + 16'd4); ck("E6_DEVCLEAR_DESELECTS", rv, mk_rsr2(0,0,0,0,1));

    // E7 test mode: control bit 3 redirects +7 to the test byte (346-352)
    do_reset;
    bus_write(BASE + 16'd7, 16'h0500);          // sector 5, normal mode
    bus_write(BASE + 16'd3, 16'h0008);          // test mode on
    bus_write(BASE + 16'd7, 16'hAA00);          // test byte, NOT sector
    ck("E7_TESTMODE_SECTOR_UNCHANGED", disk_sector, 7'd5);
    // C1: +6 still reads 0 in test mode
    peek(BASE + 16'd6); ck("E7_R6_ZERO_IN_TESTMODE", rv, 16'd0);
    // the test byte is shifted into the buffer instead (356-365)
    bram_poke(10'd0, 16'h0000);
    bus_read(BASE + 16'd6);
    bram_read(10'd0); ck("E7_TESTBYTE_HIGH_HALF", rv, 16'hAA00);
    bus_read(BASE + 16'd6);
    bram_read(10'd0); ck("E7_TESTBYTE_LOW_HALF", rv, 16'hAAAA);

    // =================================================================
    // F. EXHAUSTIVE control-word high-byte sweep vs "highest bit wins".
    //    Reference model written from the loop at lines 186-194, not
    //    from the command list in the header comment.
    // =================================================================
    for (i = 0; i < 256; i = i + 1) begin
      do_reset;
      bus_write(BASE + 16'd5, 16'h0101);        // select drive 1, format 0
      hi = i[7:0];
      exp_cmd = 0;
      for (k = 0; k < 8; k = k + 1) if (hi[k]) exp_cmd = k;

      bus_write(BASE + 16'd3, {hi, 8'h00});
      if (hi == 8'd0) begin
        ck("F_NO_COMMAND_NO_REQ", disk_req, 1'b0);
        peek(BASE + 16'd2);
        ck("F_NO_COMMAND_NOT_BUSY", rv, mk_rsr1(0,0,0,0,0,1,0,0));
      end else if (exp_cmd == 0 || exp_cmd == 1 || exp_cmd == 2 || exp_cmd == 4) begin
        // FORMAT / WRITE / WRITEDEL / READ reach the disk backend
        ck("F_BACKEND_REQ", disk_req, 1'b1);
        ck("F_BACKEND_OP",  disk_op,  exp_cmd[2:0]);
      end else begin
        // READID / SEEK / RECAL / CTLRESET are handled internally
        ck("F_INTERNAL_NO_REQ", disk_req, 1'b0);
        if (exp_cmd == 7) begin
          // CTLRESET: not busy again immediately (283-286)
          peek(BASE + 16'd2);
          ck("F_CTLRESET_NOT_BUSY", rv, mk_rsr1(0,0,0,0,0,0,0,0));
        end else begin
          peek(BASE + 16'd2);
          ck("F_INTERNAL_BUSY", rv, mk_rsr1(0,0,0,0,0,0,1,0));
        end
      end
    end

    // RECAL (command 6) homes the head and sector (287-291)
    do_reset;
    bus_write(BASE + 16'd5, 16'h8F00);          // track +15
    bus_write(BASE + 16'd7, 16'h0700);          // sector 7
    bus_write(BASE + 16'd3, 16'h4000);          // recalibrate
    ck("F_RECAL_TRACK_HOME",  disk_track,  7'd0);
    ck("F_RECAL_SECTOR_HOME", disk_sector, 7'd1);

    // =================================================================
    // G. Backend read operation and pointer advance (368-384)
    // =================================================================
    do_reset;
    bus_write(BASE + 16'd5, 16'hC101);          // drive 1, format 3
    bus_write(BASE + 16'd7, 16'h0200);          // sector 2
    bus_write(BASE + 16'd1, 16'h0BAD);          // one buffer write -> ptr=1
    bus_write(BASE + 16'd3, 16'h1000);          // read data
    ck("G_REQ",        disk_req,       1'b1);
    ck("G_OP",         disk_op,        3'd4);
    ck("G_SECTOR",     disk_sector,    7'd2);
    ck("G_DRIVE",      disk_drive,     3'd1);
    ck("G_FORMAT",     disk_format,    2'd3);
    ck("G_WORDCOUNT",  disk_wordcount, 11'd256);
    ck("G_BUF_START",  disk_buf_start, 10'd1);
    tick;
    ck("G_REQ_IS_ONE_CYCLE", disk_req, 1'b0);
    // backend fills the sector then reports done
    bram_poke(10'd257, 16'hC0DE);               // word at start+256
    disk_done = 1'b1; tick; disk_done = 1'b0;
    for (i = 0; i <= DLY; i = i + 1) tick;
    peek(BASE + 16'd2); ck("G_RWCOMPLETE", rv, mk_rsr1(0,0,1,0,0,1,0,0));
    peek(BASE + 16'd0); ck("G_PTR_ADVANCED_BY_SECTOR", rv, 16'hC0DE);

    // G2 auto-increment of the sector on completion (398-400)
    do_reset;
    bus_write(BASE + 16'd5, 16'hC101);          // drive 1, format 3 (8 sec)
    bus_write(BASE + 16'd7, 16'h8200);          // sector 2, auto-increment
    bus_write(BASE + 16'd3, 16'h1000);
    disk_done = 1'b1; tick; disk_done = 1'b0;
    for (i = 0; i <= DLY; i = i + 1) tick;
    ck("G2_SECTOR_AUTOINCREMENT", disk_sector, 7'd3);
    // C3: at the last sector it steps one PAST the end of the track
    do_reset;
    bus_write(BASE + 16'd5, 16'hC101);
    bus_write(BASE + 16'd7, 16'h8800);          // sector 8 = last, auto-inc
    bus_write(BASE + 16'd3, 16'h1000);
    disk_done = 1'b1; tick; disk_done = 1'b0;
    for (i = 0; i <= DLY; i = i + 1) tick;
    ck("G2_AUTOINC_PAST_LAST_SECTOR_C3", disk_sector, 7'd9);

    // G3 error completions (370-375) - characterisation C2
    do_reset;
    bus_write(BASE + 16'd5, 16'hC101);
    bus_write(BASE + 16'd3, 16'h0002);          // enable interrupt
    bus_write(BASE + 16'd3, 16'h1002);          // read data + int enable
    disk_done = 1'b1; disk_err_notrdy = 1'b1; tick;
    disk_done = 1'b0; disk_err_notrdy = 1'b0;
    for (i = 0; i <= DLY + 2; i = i + 1) tick;
    peek(BASE + 16'd4); ck("G3_NOTRDY_SET", rv, mk_rsr2(0,0,0,0,1));
    peek(BASE + 16'd2);
    ck("G3_NO_RFT_NO_COMPLETION_C2", rv, mk_rsr1(0,0,0,0,1,0,0,1));
    ck("G3_NO_INTERRUPT_ON_ERROR_C2", int_pending, 4'd0);

    do_reset;
    bus_write(BASE + 16'd5, 16'hC101);
    bus_write(BASE + 16'd3, 16'h1002);
    disk_done = 1'b1; disk_err_missing = 1'b1; tick;
    disk_done = 1'b0; disk_err_missing = 1'b0;
    for (i = 0; i <= DLY + 2; i = i + 1) tick;
    peek(BASE + 16'd4); ck("G3_MISSING_SET", rv, mk_rsr2(0,0,1,0,0));
    ck("G3_MISSING_NO_INTERRUPT_C2", int_pending, 4'd0);

    // =================================================================
    // H. Interrupt condition and IDENT handshake (154-164, 406-408)
    // =================================================================
    do_reset;
    // pending = int_enabled & rft. After reset rft=1, int_enabled=0.
    ck("H_NO_PENDING_WITHOUT_ENABLE", int_pending, 4'd0);
    bus_write(BASE + 16'd3, 16'h0002);
    ck("H_PENDING_LEVEL11_ONLY", int_pending, 4'b0010);

    // IDENT with the wrong level never answers
    ident_grant_in = 1'b1;
    ident_strobe   = 1'b1;
    for (i = 0; i < 16; i = i + 1) begin
      ident_level = i[3:0];
      #1;
      if (i == 11) begin
        ck("H_IDENT_HIT_L11",   ident_hit,       1'b1);
        ck("H_IDENT_CODE_L11",  ident_code,      16'o000021);
        ck("H_IDENT_GRANT_OUT", ident_grant_out, 1'b0);
      end else begin
        ck("H_IDENT_NO_HIT",       ident_hit,       1'b0);
        ck("H_IDENT_CODE_ZERO",    ident_code,      16'd0);
        ck("H_IDENT_GRANT_PASSES", ident_grant_out, 1'b1);
      end
    end

    // grant_in low: no answer, and the chain output stays low
    ident_level = 4'd11; ident_grant_in = 1'b0; #1;
    ck("H_NO_GRANT_NO_HIT",       ident_hit,       1'b0);
    ck("H_NO_GRANT_CODE_ZERO",    ident_code,      16'd0);
    ck("H_NO_GRANT_OUT_LOW",      ident_grant_out, 1'b0);

    // strobe low: no answer even with grant and the right level
    ident_grant_in = 1'b1; ident_strobe = 1'b0; #1;
    ck("H_NO_STROBE_NO_HIT", ident_hit, 1'b0);

    // answering IDENT clears the enable, so pending drops
    ident_strobe = 1'b1; #1;
    ck("H_IDENT_HIT_BEFORE_CLOCK", ident_hit, 1'b1);
    tick;
    ident_strobe = 1'b0; ident_grant_in = 1'b0; #1;
    ck("H_IDENT_CLEARS_ENABLE", int_pending, 4'd0);
    peek(BASE + 16'd2); ck("H_INTEN_BIT_CLEARED", rv, mk_rsr1(0,0,0,0,0,1,0,0));

    // no interrupt while busy (rft=0) even with the enable set
    bus_write(BASE + 16'd3, 16'h2002);          // seek + enable
    ck("H_NO_PENDING_WHILE_BUSY", int_pending, 4'd0);
    ident_strobe = 1'b1; ident_grant_in = 1'b1; ident_level = 4'd11; #1;
    ck("H_NO_IDENT_WHILE_BUSY", ident_hit, 1'b0);
    ck("H_GRANT_PASSES_WHILE_BUSY", ident_grant_out, 1'b1);
    ident_strobe = 1'b0; ident_grant_in = 1'b0; #1;

    // =================================================================
    // I. C4 - the five flags nothing ever sets are still 0 after all of
    //    the above stimulus.
    // =================================================================
    peek(BASE + 16'd2);
    ck("I_C4_DELETED_B5_NEVER_SET", rv[5], 1'b0);
    ck("I_C4_TIMEOUT_B8_NEVER_SET", rv[8], 1'b0);
    ck("I_C4_RSR1_HIGH_BITS_ZERO",  rv[15:9], 7'd0);
    peek(BASE + 16'd4);
    ck("I_C4_WPROT_B9_NEVER_SET",   rv[9],  1'b0);
    ck("I_C4_CRC_B12_NEVER_SET",    rv[12], 1'b0);
    ck("I_C4_OVERRUN_B14_NEVER_SET",rv[14], 1'b0);
    ck("I_RSR2_LOW_BYTE_ZERO",      rv[7:0], 8'd0);
    ck("I_RSR2_B15_ZERO",           rv[15], 1'b0);
    ck("I_RSR2_B13_ZERO",           rv[13], 1'b0);
    ck("I_RSR2_B10_ZERO",           rv[10], 1'b0);

    if (checks !== EXPECTED_CHECKS) begin
      errors = errors + 1;
      $display("FAIL CHECK_COUNT: ran %0d checks, expected %0d", checks, EXPECTED_CHECKS);
    end

    $display("-----------------------------------------------------");
    $display(" clock edges : %0d", cycles);
    $display(" checks run  : %0d", checks);
    $display(" failures    : %0d", errors);
    if (errors == 0) $display("TB_RESULT: PASS");
    else             $display("TB_RESULT: FAIL");
    $display("=====================================================");
    $finish;
  end

endmodule

`default_nettype wire
