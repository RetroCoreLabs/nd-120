/**************************************************************************
** TESTBENCH: ND_SMD - IOX register / status / control conformance (P1)   **
**  (SMD analogue of the floppy P1 IOX tb; CONFORMANCE-style unit test)   **
**                                                                       **
** Asserts the ND_SMD register / status / control-word MATRIX directly    **
** at the device IOX slave port. This is a UNIT test of ND_SMD in         **
** isolation: the DUT's iox_* port is driven directly (NOT through        **
** ND_BUS_SLAVE), and NO command is ever GO'd (control bit 2 stays 0), so  **
** the transfer engine never leaves E_IDLE and no DMA / disk backend is   **
** needed - the full DMA-stack behaviour is covered by nd_smd_tb.v.       **
**                                                                       **
** Register semantics under test (oracle NDBusDiscControllerSMD.cs, via   **
** the 15 MHz-card ND_SMD.v):                                            **
**   - boot mode is active from reset; +2 returns the boot status form    **
**     (RFT in b3) until the FIRST Load Control Word (+5)                 **
**   - after +5 selects a unit, the NORMAL register model is live: reads  **
**     return 0 while no unit is selected                                 **
**   - Status (+4, CWR=0): b15 CWR, b14 on-cylinder, b13 disk-not-ready,  **
**     b3 RFT, b2 active, b1 err-int-en, b0 int-en                        **
**   - Seek condition (+2, CWR=0): b12 = 1 ALWAYS (the 15 MHz card id     **
**     SINTRAN uses to tell it from the NORD-10), b0-7 seek-complete      **
**   - 15 MHz flip-flop: ONE flip-flop serves the 24-bit Core Address and **
**     the Word Counter (+1 / +7 writes, +0 reads). The first write of a  **
**     pair loads all 24 bits (bits 16-23 from A bits 0-7), the second    **
**     bits 0-15; reads return bits 0-15 then 16-23. Sections 8-13 check  **
**     one-write-loads-all, the mass-load word count (one +7 of 002000),  **
**     the shared toggle, no toggle on ECC control / +3 / +5, and the     **
**     status-read and device-clear resets                                **
**   - CWR (control b15) multiplexes Core Address vs Word Counter on +0   **
**   - interrupt is a latched level-11 line; a non-GO control word with   **
**     int-enable set raises it (RFT already true); IDENT answers code    **
**     017 (octal) and clears the enable + drops the line                 **
**   - device clear (+5 b4): RFT low, registers zeroed, per-unit          **
**     seek-complete set, errors cleared                                  **
**                                                                       **
** Verdict line: TB_RESULT: PASS / TB_RESULT: FAIL                       **
**                                                                       **
** Last reviewed: 25-JUL-2026                                            **
** Ronny Hansen                                                          **
***************************************************************************/

`timescale 1ns / 1ps

module nd_smd_iox_tb;

  localparam [15:0] BASE  = 16'o001540;
  localparam [15:0] IDENT = 16'o000017;   // octal 017 = 0x000F

  reg sysclk = 0;
  reg sys_rst_n = 0;
  always #10 sysclk = ~sysclk;

  // ---- DUT IOX slave side ----
  reg  [15:0] iox_addr  = 16'd0;
  reg         iox_wr    = 1'b0;
  reg  [15:0] iox_wdata = 16'd0;
  reg         iox_rd    = 1'b0;
  wire [15:0] iox_rdata;
  wire [3:0]  int_pending;
  reg         ident_strobe   = 1'b0;
  reg  [3:0]  ident_level    = 4'd0;
  reg         ident_grant_in = 1'b0;
  wire        ident_grant_out;
  wire        ident_hit;
  wire [15:0] ident_code;

  // ---- DMA + disk backend left idle (no GO is ever issued) ----
  wire        dma_req, dma_wr;
  wire [23:0] dma_addr;
  wire [15:0] dma_wdata;
  wire        disk_start, disk_req, disk_wr;
  wire [15:0] disk_blkaddr1, disk_blkaddr2;
  wire [2:0]  disk_unit;
  wire [10:0] disk_wordcount;
  wire [15:0] dbuf_rdata;

  // HAS_WC_FLIPFLOP(1): this conformance matrix exercises the 15 MHz two-write
  // HI/LO load + LO/HI readback, so it pins the flip-flop card (the module
  // default is the single-write ECC card).
  ND_SMD #(.HAS_WC_FLIPFLOP(1)) dut (
      .sysclk        (sysclk),
      .sys_rst_n     (sys_rst_n),
      .iox_addr      (iox_addr),
      .iox_wr        (iox_wr),
      .iox_wdata     (iox_wdata),
      .iox_rd        (iox_rd),
      .iox_rdata     (iox_rdata),
      .int_pending   (int_pending),
      .ident_strobe  (ident_strobe),
      .ident_level   (ident_level),
      .ident_grant_in(ident_grant_in),
      .ident_grant_out(ident_grant_out),
      .ident_hit     (ident_hit),
      .ident_code    (ident_code),
      .dma_req       (dma_req),
      .dma_wr        (dma_wr),
      .dma_addr      (dma_addr),
      .dma_wdata     (dma_wdata),
      .dma_rdata     (16'd0),
      .dma_ack       (1'b0),
      .dma_err       (1'b0),
      .dma_busy      (1'b0),
      .disk_start    (disk_start),
      .disk_req      (disk_req),
      .disk_wr       (disk_wr),
      .disk_blkaddr1 (disk_blkaddr1),
      .disk_blkaddr2 (disk_blkaddr2),
      .disk_unit     (disk_unit),
      .disk_wordcount(disk_wordcount),
      .disk_done     (1'b0),
      .disk_err_in   (1'b0),
      .dbuf_addr     (10'd0),
      .dbuf_wdata    (16'd0),
      .dbuf_we       (1'b0),
      .dbuf_rdata    (dbuf_rdata)
  );

  // ---- checking ----
  integer errors = 0;
  task check(input cond, input [1023:0] msg);
    begin
      if (!cond) begin
        errors = errors + 1;
        $display("  FAIL: %0s", msg);
      end
    end
  endtask

  // IOX read held HIGH across one posedge: the 15 MHz read flip-flops
  // (mar_ff / wcr_ff toggle, status-read clr_ff) fire on that edge. The
  // returned value is the combinational read mux BEFORE the toggle, so it
  // is sampled in the low phase; the edge then advances the flip-flop for
  // the next read.
  task iox_read(input [15:0] a, output [15:0] d);
    begin
      @(negedge sysclk);
      iox_addr = a;
      iox_rd   = 1'b1;
      #1 d = iox_rdata;      // low-phase sample (pre-toggle value)
      @(posedge sysclk);     // read side-effect / flip-flop toggle fires here
      @(negedge sysclk);
      iox_rd   = 1'b0;
    end
  endtask

  // clocked IOX write (one full cycle, like a real IOX store)
  task iox_write(input [15:0] a, input [15:0] data);
    begin
      @(negedge sysclk);
      iox_addr  = a;
      iox_wdata = data;
      iox_wr    = 1'b1;
      @(negedge sysclk);
      iox_wr    = 1'b0;
    end
  endtask

  // A non-GO Load Control Word (b2 = 0): leave boot mode, pick CWR + unit +
  // interrupt bits, no transfer. unit 0..3 (b9 = 0) selects a disk.
  task ctrl_word(input cwr, input inten, input errint, input devclr, input [2:0] unit);
    reg [15:0] cw;
    begin
      cw = 16'd0;
      cw[0]     = inten;
      cw[1]     = errint;
      cw[4]     = devclr;
      cw[9:7]   = unit;
      cw[15]    = cwr;
      iox_write(BASE + 16'd5, cw);
    end
  endtask

  reg [15:0] r, r2;

  initial begin
    sys_rst_n = 1'b0;
    repeat (4) @(negedge sysclk);
    sys_rst_n = 1'b1;
    repeat (2) @(negedge sysclk);

    // =================================================================
    // 1. Boot mode at reset: +2 returns the boot status form (RFT in b3).
    //    (+0 in boot mode consumes the stream, so it is left to the boot
    //    tb; here we only sample the non-consuming +2.)
    // =================================================================
    iox_read(BASE + 16'd2, r);
    check(r === 16'h0008, "boot: +2 status form must have RFT in b3 (0x0008)");

    // =================================================================
    // 2. First Load Control Word leaves boot mode + selects unit 0
    //    (CWR=0, no interrupts). Status is now the normal model.
    //      b14 on-cylinder=1 (selecting a unit puts it on cyl), b13 not
    //      ready=0, b3 RFT=1, b2 active=0 -> 0x4008.
    // =================================================================
    ctrl_word(1'b0, 1'b0, 1'b0, 1'b0, 3'd0);
    iox_read(BASE + 16'd4, r);
    check(r === 16'h4008, "select unit0: status must be 0x4008 (oncyl b14, rft b3)");
    check(r[15] === 1'b0, "status b15 CWR must mirror control b15 (=0)");

    // seek condition: b12 = 1 (15 MHz card id), seek-complete all 0 here
    iox_read(BASE + 16'd2, r);
    check(r === 16'h1000, "seek cond must be 0x1000 (b12 15MHz id, no seek-complete)");
    check(r[12] === 1'b1, "seek cond b12 must be 1 (SINTRAN 15MHz-card detect)");

    // =================================================================
    // 3. 24-bit Core Address: load HI (0xAB) then LO (0xCDEF) via +1,
    //    read back LO then HI via +0 (CWR=0). mar_ff starts 0 -> LO first.
    // =================================================================
    iox_write(BASE + 16'd1, 16'h00AB);   // first +1 write: all 24 bits, b16-23 = 0xAB
    iox_write(BASE + 16'd1, 16'hCDEF);   // second +1 write: bits 0-15 only
    iox_read (BASE + 16'd0, r);          // first +0 read = LO
    iox_read (BASE + 16'd0, r2);         // second +0 read = HI
    check(r  === 16'hCDEF, "core addr readback LO must be 0xCDEF");
    check(r2 === 16'h00AB, "core addr readback HI must be 0x00AB");

    // =================================================================
    // 4. 24-bit Word Counter: load HI (0x12) then LO (0x3456) via +7
    //    (CWR=0 is Load Word Counter), then switch CWR=1 and read back
    //    LO then HI via +0.
    // =================================================================
    iox_write(BASE + 16'd7, 16'h0012);   // first +7 write (CWR=0): all 24 bits, b16-23 = 0x12
    iox_write(BASE + 16'd7, 16'h3456);   // second +7 write: bits 0-15 only
    ctrl_word(1'b1, 1'b0, 1'b0, 1'b0, 3'd0);   // switch to CWR=1, unit0
    iox_read (BASE + 16'd0, r);          // +0 CWR=1 first read = WC LO
    iox_read (BASE + 16'd0, r2);         // +0 CWR=1 second read = WC HI
    check(r  === 16'h3456, "word count readback LO must be 0x3456 (CWR=1 mux)");
    check(r2 === 16'h0012, "word count readback HI must be 0x0012");

    // =================================================================
    // 5. Interrupt is level-sensitive: a non-GO control word with
    //    int-enable set raises the latched level-11 line (RFT already 1).
    //    status: b14 oncyl=1, b3 rft=1, b0 int-en=1 -> 0x4009.
    // =================================================================
    ctrl_word(1'b0, 1'b0, 1'b0, 1'b0, 3'd0); // CWR back to 0, unit0
    ctrl_word(1'b0, 1'b1, 1'b0, 1'b0, 3'd0); // int-enable
    @(negedge sysclk);
    iox_read(BASE + 16'd4, r);
    check(r === 16'h4009, "int-enable status must be 0x4009 (b0 set)");
    check(int_pending === 4'b0010, "int-enable+RFT must assert level-11 int_pending");

    // =================================================================
    // 6. IDENT answers level 11 with code 017 (octal) and clears enable.
    // =================================================================
    @(negedge sysclk);
    ident_level    = 4'd11;
    ident_grant_in = 1'b1;
    ident_strobe   = 1'b1;
    #1;
    check(ident_hit  === 1'b1,  "IDENT must hit on level 11 while pending");
    check(ident_code === IDENT, "IDENT code must be 017 (octal) = 0x000F");
    @(posedge sysclk);          // clock the enable-clear + line drop
    @(negedge sysclk);
    ident_strobe   = 1'b0;
    ident_grant_in = 1'b0;
    @(negedge sysclk);
    check(int_pending === 4'b0000, "IDENT must clear enable and drop the int line");

    // =================================================================
    // 7. Device clear (+5 b4): RFT low, registers zeroed, errors cleared.
    //    A clear raises NO seek-complete: ND-11.020.01 (seek condition) says
    //    that bit is only set once an initiate seek has been issued.
    //      status: b14 oncyl=1 (clear does not touch on-cyl), b3 rft=0,
    //      everything else 0 -> 0x4000.
    //      seek cond: seek-complete=0, b12=1 -> 0x1000.
    //      core address reads back 0 (LO then HI).
    // =================================================================
    ctrl_word(1'b0, 1'b0, 1'b0, 1'b1, 3'd0); // device clear, unit0, CWR=0
    iox_read(BASE + 16'd4, r);
    check(r === 16'h4000, "device clear status must be 0x4000 (rft=0, errors clear)");
    iox_read(BASE + 16'd2, r);
    check(r === 16'h1000, "device clear seek cond must be 0x1000 (b12 only: a clear raises no seek-complete)");
    iox_read(BASE + 16'd0, r);
    iox_read(BASE + 16'd0, r2);
    check(r  === 16'h0000, "device clear core addr LO must be 0");
    check(r2 === 16'h0000, "device clear core addr HI must be 0");

    // =================================================================
    // 8-13: the memory address / word count flip-flop of the 15 MHz card
    //    (ND_SMD.v s_ma_wc_ff; card 3044 sheet 3, simulated in
    //    Logisim/ND-BUS-DEVICES/SMD-3044). One flip-flop for +1 / +7 writes
    //    and +0 reads; the first write of a pair loads all 24 bits (bits
    //    16-23 from A bits 0-7), the second bits 0-15 only. Values octal.
    //    Every check starts from a device clear or a status read, which
    //    reset the flip-flop to "first access".
    // =================================================================

    // 8. One +1 write loads all 24 bits: 000401 -> bits 16-23 = 001,
    //    bits 0-15 = 000401.
    ctrl_word(1'b0, 1'b0, 1'b0, 1'b1, 3'd0);   // device clear, CWR=0
    iox_write(BASE + 16'd1, 16'o000401);
    iox_read(BASE + 16'd4, r);                 // status read -> first access
    iox_read(BASE + 16'd0, r);                 // bits 0-15
    iox_read(BASE + 16'd0, r2);                // bits 16-23
    check(r  === 16'o000401, "8: one +1 write of 000401: bits 0-15 must be 000401");
    check(r2 === 16'o000001, "8: one +1 write of 000401: bits 16-23 must be 001");

    // 9. One +7 write loads all 24 bits of the word count the same way.
    ctrl_word(1'b0, 1'b0, 1'b0, 1'b1, 3'd0);   // device clear, CWR=0
    iox_write(BASE + 16'd7, 16'o000401);       // +7, CWR=0 = Load Word Count
    iox_read(BASE + 16'd4, r);                 // status read -> first access
    ctrl_word(1'b1, 1'b0, 1'b0, 1'b0, 3'd0);   // CWR=1 (no toggle on +5)
    iox_read(BASE + 16'd0, r);                 // word count bits 0-15
    iox_read(BASE + 16'd0, r2);                // word count bits 16-23
    check(r  === 16'o000401, "9: one +7 write of 000401: WC bits 0-15 must be 000401");
    check(r2 === 16'o000001, "9: one +7 write of 000401: WC bits 16-23 must be 001");

    // 9b. The mass-storage load's word count: one +7 write of 002000 gives
    //     00 002000 = 1024 words (bits 16-23 = 002000 & 0377 = 0).
    ctrl_word(1'b0, 1'b0, 1'b0, 1'b1, 3'd0);   // device clear, CWR=0
    iox_write(BASE + 16'd7, 16'o002000);
    iox_read(BASE + 16'd4, r);                 // status read -> first access
    ctrl_word(1'b1, 1'b0, 1'b0, 1'b0, 3'd0);   // CWR=1
    iox_read(BASE + 16'd0, r);
    iox_read(BASE + 16'd0, r2);
    check(r  === 16'o002000, "9b: one +7 write of 002000: WC bits 0-15 must be 002000");
    check(r2 === 16'o000000, "9b: one +7 write of 002000: WC bits 16-23 must be 0");

    // 10. The flip-flop is SHARED by the memory address and the word count.
    //     Writes: +1 then +7 - the +7 is the SECOND access, so it loads WC
    //     bits 0-15 only and WC bits 16-23 stay 0 from the device clear.
    ctrl_word(1'b0, 1'b0, 1'b0, 1'b1, 3'd0);   // device clear, CWR=0
    iox_write(BASE + 16'd1, 16'o000003);       // first access
    iox_write(BASE + 16'd7, 16'o000005);       // second access
    ctrl_word(1'b1, 1'b0, 1'b0, 1'b0, 3'd0);   // CWR=1
    iox_read(BASE + 16'd4, r);                 // +4 with CWR=1 = ECC pattern: no reset
    iox_read(BASE + 16'd0, r);                 // flip-flop is at "first" again
    iox_read(BASE + 16'd0, r2);                // (two writes = two toggles)
    check(r  === 16'o000005, "10: +1 then +7: WC bits 0-15 must be 000005");
    check(r2 === 16'o000000, "10: +1 then +7: the +7 is a second access, WC bits 16-23 must stay 0");

    //     Reads: a memory address read then a word count read - the word
    //     count read is the SECOND access and returns bits 16-23.
    ctrl_word(1'b0, 1'b0, 1'b0, 1'b1, 3'd0);   // device clear, CWR=0
    iox_write(BASE + 16'd1, 16'o000012);       // MA: 012 000012
    iox_write(BASE + 16'd1, 16'o000345);       // MA bits 0-15 = 000345
    iox_write(BASE + 16'd7, 16'o000067);       // WC: 067 000067
    iox_write(BASE + 16'd7, 16'o001234);       // WC bits 0-15 = 001234
    iox_read(BASE + 16'd4, r);                 // status read -> first access
    iox_read(BASE + 16'd0, r);                 // CWR=0: MA bits 0-15
    ctrl_word(1'b1, 1'b0, 1'b0, 1'b0, 3'd0);   // CWR=1 (no toggle on +5)
    iox_read(BASE + 16'd0, r2);                // second access: WC bits 16-23
    check(r  === 16'o000345, "10: MA read (first access) must be bits 0-15 = 000345");
    check(r2 === 16'o000067, "10: WC read after an MA read is a second access, must be bits 16-23 = 067");

    // 11. The ECC control register (+7 with CWR=1) does NOT toggle the
    //     flip-flop: the +1 after it is still a first access.
    ctrl_word(1'b1, 1'b0, 1'b0, 1'b1, 3'd0);   // device clear, CWR=1
    iox_write(BASE + 16'd7, 16'o000000);       // +7 CWR=1 = ECC control
    ctrl_word(1'b0, 1'b0, 1'b0, 1'b0, 3'd0);   // CWR=0
    iox_write(BASE + 16'd1, 16'o000401);       // must be the first access
    iox_read(BASE + 16'd4, r);
    iox_read(BASE + 16'd0, r);
    iox_read(BASE + 16'd0, r2);
    check(r  === 16'o000401, "11: MA after an ECC control write: bits 0-15 must be 000401");
    check(r2 === 16'o000001, "11: ECC control write must not toggle: MA bits 16-23 must be 001");

    // 12. The block address (+3) and the control word (+5) do NOT toggle it:
    //     +1, +3, +1 is still a pair, and so is +1, +5, +1.
    ctrl_word(1'b0, 1'b0, 1'b0, 1'b1, 3'd0);   // device clear, CWR=0
    iox_write(BASE + 16'd1, 16'o000002);       // first: MA 002 000002
    iox_write(BASE + 16'd3, 16'o000000);       // block address I
    iox_write(BASE + 16'd1, 16'o000100);       // second: bits 0-15 only
    iox_read(BASE + 16'd4, r);
    iox_read(BASE + 16'd0, r);
    iox_read(BASE + 16'd0, r2);
    check(r  === 16'o000100, "12: +1 +3 +1: MA bits 0-15 must be 000100");
    check(r2 === 16'o000002, "12: +3 must not toggle: MA bits 16-23 must be 002");

    ctrl_word(1'b0, 1'b0, 1'b0, 1'b1, 3'd0);   // device clear, CWR=0
    iox_write(BASE + 16'd1, 16'o000002);       // first
    ctrl_word(1'b0, 1'b0, 1'b0, 1'b0, 3'd0);   // control word, no clear
    iox_write(BASE + 16'd1, 16'o000100);       // second
    iox_read(BASE + 16'd4, r);
    iox_read(BASE + 16'd0, r);
    iox_read(BASE + 16'd0, r2);
    check(r  === 16'o000100, "12: +1 +5 +1: MA bits 0-15 must be 000100");
    check(r2 === 16'o000002, "12: +5 must not toggle: MA bits 16-23 must be 002");

    // 13. A status read (+4, CWR=0) resets the flip-flop: +1, status, +1 -
    //     the second +1 is a FIRST access again and loads bits 16-23.
    ctrl_word(1'b0, 1'b0, 1'b0, 1'b1, 3'd0);   // device clear, CWR=0
    iox_write(BASE + 16'd1, 16'o000007);       // first
    iox_read(BASE + 16'd4, r);                 // status read -> reset
    iox_write(BASE + 16'd1, 16'o000011);       // first again
    iox_read(BASE + 16'd4, r);
    iox_read(BASE + 16'd0, r);
    iox_read(BASE + 16'd0, r2);
    check(r  === 16'o000011, "13: +1 status +1: MA bits 0-15 must be 000011");
    check(r2 === 16'o000011, "13: status read must reset: second +1 loads MA bits 16-23 = 011");

    //     A device clear resets it the same way.
    ctrl_word(1'b0, 1'b0, 1'b0, 1'b1, 3'd0);   // device clear, CWR=0
    iox_write(BASE + 16'd1, 16'o000007);       // first
    ctrl_word(1'b0, 1'b0, 1'b0, 1'b1, 3'd0);   // device clear -> reset
    iox_write(BASE + 16'd1, 16'o000011);       // first again
    iox_read(BASE + 16'd4, r);
    iox_read(BASE + 16'd0, r);
    iox_read(BASE + 16'd0, r2);
    check(r  === 16'o000011, "13: +1 clear +1: MA bits 0-15 must be 000011");
    check(r2 === 16'o000011, "13: device clear must reset: second +1 loads MA bits 16-23 = 011");

    // =================================================================
    // 14. C/H/S range check with the default 75 MB geometry (5 heads, 18
    //     sectors per track, 823 cylinders), each part on its own. Cylinder
    //     823 used to pass (the LBA test is "greater than") and heads 5.. were
    //     compared with the cylinder limit. A mismatch ends the command at
    //     once: b8 address mismatch, b12 abnormal completion (ND-11.020.01
    //     sec 3.7.2), b4 error OR, not active. A device clear drops them.
    // =================================================================
    ctrl_word(1'b0, 1'b0, 1'b0, 1'b1, 3'd0);      // device clear
    ctrl_word(1'b0, 1'b0, 1'b0, 1'b0, 3'd0);      // unit 0, CWR=0
    iox_write(BASE + 16'd3, 16'h0000);            // block address I: head 0, sector 0
    ctrl_word(1'b1, 1'b0, 1'b0, 1'b0, 3'd0);      // CWR=1
    iox_write(BASE + 16'd3, 16'd823);             // block address II: cylinder 823
    ctrl_word(1'b0, 1'b0, 1'b0, 1'b0, 3'd0);      // CWR=0
    iox_write(BASE + 16'd5, 16'h0004);            // GO, M0
    iox_read(BASE + 16'd4, r);
    check(r[8]  === 1'b1, "14: cylinder 823 must set address mismatch b8");
    check(r[12] === 1'b1, "14: address mismatch must set abnormal completion b12");
    check(r[4]  === 1'b1, "14: address mismatch must set the error OR b4");
    // On-cylinder is drive state: an address error does not move the heads, and
    // no control word forces it (nd100x; not stated in ND-11.020.01).
    check(r[14] === 1'b1, "14: address mismatch must leave on-cylinder b14 alone");
    check(r[2]  === 1'b0, "14: address mismatch must not leave the controller active");
    ctrl_word(1'b0, 1'b0, 1'b0, 1'b1, 3'd0);      // device clear
    iox_read(BASE + 16'd4, r);
    check(r[8] === 1'b0 && r[12] === 1'b0 && r[4] === 1'b0, "14: device clear must drop b8, b12, b4");
    ctrl_word(1'b0, 1'b0, 1'b0, 1'b0, 3'd0);
    iox_write(BASE + 16'd3, 16'h0500);            // head 5 of 0-4, sector 0
    ctrl_word(1'b1, 1'b0, 1'b0, 1'b0, 3'd0);
    iox_write(BASE + 16'd3, 16'd0);               // cylinder 0
    ctrl_word(1'b0, 1'b0, 1'b0, 1'b0, 3'd0);
    iox_write(BASE + 16'd5, 16'h0004);
    iox_read(BASE + 16'd4, r);
    check(r[8] === 1'b1, "14: head 5 must set address mismatch b8");
    ctrl_word(1'b0, 1'b0, 1'b0, 1'b1, 3'd0);      // device clear

    // ---- verdict ----
    if (errors == 0) $display("TB_RESULT: PASS");
    else begin
      $display("%0d errors", errors);
      $display("TB_RESULT: FAIL");
    end
    $finish;
  end

  // global watchdog
  initial begin
    #5000000;
    $display("TIMEOUT");
    $display("TB_RESULT: FAIL");
    $finish;
  end

endmodule
