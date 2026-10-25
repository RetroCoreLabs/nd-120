/**************************************************************************
** TESTBENCH: ND_SMD - SMD disk controller full DMA stack                **
**                                                                       **
** Same harness family as the floppy-DMA tb: scripted CPU IOX ->        **
** ND_BUS_SLAVE -> ND_SMD -> ND_DMA_MASTER -> BCU + ND-memory model,     **
** plus a linear disk-image model addressed from the block address       **
** registers (tb mapping: word offset = blkaddrII * 2048 + blkaddrI *    **
** 64; the backend owns the geometry, as in nd100x).                     **
**                                                                       **
** Updated 23-JUL-2026 for the oracle-faithful ND_SMD rewrite:           **
**  - Core Address and Word Count are 24-bit and loaded by TWO IOX        **
**    writes each via the 15 MHz card's one shared flip-flop (first      **
**    write loads all 24 bits, second bits 0-15); read back LO then HI.  **
**  - 9b: the MASS STORAGE LOAD sequence (one +7 write of 002000).       **
**  - New status layout: b4 inclusive-OR, b5 illegal load, b8 address     **
**    mismatch, b13 disk-unit-not-ready, b14 on-cylinder.               **
**  - Seek condition: b0-7 per-unit seek-complete, b12 = 1 (15 MHz id).  **
**  - On an ERROR the oracle leaves ready-for-transfer LOW and marks the  **
**    unit not-ready; error interrupts fire from HandleError. Tests use   **
**    wait_idle (poll not-active) on the error paths.                    **
**  - The DUT is instanced with a large GEO_MAX_CYL so the tb's linear    **
**    block map is never rejected by the CHS bound; address-mismatch is   **
**    exercised with an out-of-range SECTOR instead.                     **
**                                                                       **
** Covered: reset status, '1540&' boot byte-server, M0 read (1500 words, **
** crosses the 1K chunk), 24-bit register readback, M1 write (800 words), **
** M3 compare (one memory read per word, b10 on mismatch), M2 read       **
** parity (words counted, no memory cycle, media fault ends it,          **
** M4 seek (on-cyl + seek-complete + 15 MHz id), interrupt + IDENT 017,   **
** address mismatch, error interrupt, ECC pattern register, real 75 MB    **
** image windows, and a DMA bus fault -> disk-not-ready + recovery.       **
**                                                                       **
** Verdict line: TB_RESULT: PASS / TB_RESULT: FAIL                       **
**                                                                       **
** Ronny Hansen                                                          **
***************************************************************************/

`timescale 1ns / 1ps

module nd_smd_tb;

  reg sysclk = 0;
  reg sys_rst_n = 0;
  always #10 sysclk = ~sysclk;

  // ---- CPU-side bus ----
  reg  [23:0] bd_out = 24'hFFFFFF;
  wire [23:0] bd_in;
  reg  bapr_n = 1, bioxe_n = 1, binack_n = 1, outident_n = 1;
  wire binput_n, bdap_n, bdry_n;
  wire bint10_n, bint11_n, bint12_n, bint13_n;

  wire [15:0] iox_addr, iox_wdata, iox_rdata;
  wire iox_wr, iox_rd;
  wire ident_strobe;
  wire [3:0] ident_level;
  wire [3:0] intp;
  wire ident_hit;
  wire [15:0] ident_code;

  ND_BUS_SLAVE u_slave (
      .sysclk(sysclk), .sys_rst_n(sys_rst_n),
      .BD_23_0_n_OUT(bd_out), .BD_23_0_n_IN(bd_in),
      .BAPR_n(bapr_n), .BIOXE_n(bioxe_n), .BINACK_n(binack_n),
      .OUTIDENT_n(outident_n),
      .BINPUT_n(binput_n), .BDAP_n(bdap_n), .BDRY_n(bdry_n),
      .BINT10_n(bint10_n), .BINT11_n(bint11_n),
      .BINT12_n(bint12_n), .BINT13_n(bint13_n),
      .iox_addr(iox_addr), .iox_wr(iox_wr), .iox_wdata(iox_wdata),
      .iox_rd(iox_rd), .iox_rdata(iox_rdata), .iox_hit(1'b1),
      .int_pending(intp),
      .ident_strobe(ident_strobe), .ident_level(ident_level),
      .ident_hit(ident_hit), .ident_code(ident_code)
  );

  // ---- DMA master ----
  wire        c_dma_req, c_dma_wr;
  wire [23:0] c_dma_addr;
  wire [15:0] c_dma_wdata, c_dma_rdata;
  wire        c_dma_ack, c_dma_err, c_dma_busy;

  wire        m_breq_n;
  reg         bmem_n = 1;
  reg         grant_head_n = 1;
  wire [23:0] m_bd_out_n;
  reg  [23:0] mem_bd_n = 24'hFFFFFF;
  wire [23:0] mbd_bus_n = m_bd_out_n & mem_bd_n;
  wire        m_bapr_n, m_binput_n, m_bdap_n;
  reg         m_bdry_n = 1;

  ND_DMA_MASTER #(.TIMEOUT_TICKS(16'd500), .MIN_GAP_TICKS(8'd4)) u_dma (
      .sysclk(sysclk), .sys_rst_n(sys_rst_n),
      .dma_req(c_dma_req), .dma_wr(c_dma_wr), .dma_addr(c_dma_addr),
      .dma_wdata(c_dma_wdata), .dma_rdata(c_dma_rdata),
      .dma_ack(c_dma_ack), .dma_err(c_dma_err), .dma_busy(c_dma_busy),
      .BREQ_n(m_breq_n),
      .INGRANT_n(grant_head_n), .OUTGRANT_n(),
      .BMEM_n(bmem_n),
      .BD_23_0_n_OUT(m_bd_out_n), .BD_23_0_n_IN(mbd_bus_n),
      .BAPR_n(m_bapr_n), .BINPUT_n(m_binput_n), .BDAP_n(m_bdap_n),
      .BDRY_n(m_bdry_n)
  );

  // ---- SMD controller under test ----
  // GEO_MAX_CYL is set high so the tb's linear block-address map (blkaddrII
  // used as a large "cylinder") is never rejected by the CHS bound; the
  // address-mismatch feature is exercised through an out-of-range SECTOR.
  wire        disk_start, disk_req, disk_wr;
  wire [15:0] disk_blkaddr1, disk_blkaddr2;
  wire [2:0]  disk_unit;
  wire [10:0] disk_wordcount;
  reg         disk_done = 0, disk_err_in = 0;
  // WHY the backend failed (SD-FAT/circuit/nd_storage_status.vh); see the
  // note in nd_floppy_dma_tb.v.
  reg [3:0]   disk_err_code = 4'd0;
  reg  [9:0]  dbuf_addr = 0;
  reg  [15:0] dbuf_wdata = 0;
  reg         dbuf_we = 0;
  wire [15:0] dbuf_rdata;

  // HAS_WC_FLIPFLOP(1): this tb exercises the 15 MHz two-write HI/LO register
  // load + LO/HI readback, so it pins the flip-flop card (the module default is
  // the single-write ECC card).
  ND_SMD #(.DELAY_TICKS(16'd10), .GEO_MAX_CYL(65535), .HAS_WC_FLIPFLOP(1)) u_smd (
      .sysclk(sysclk), .sys_rst_n(sys_rst_n),
      .iox_addr(iox_addr), .iox_wr(iox_wr), .iox_wdata(iox_wdata),
      .iox_rd(iox_rd), .iox_rdata(iox_rdata),
      .int_pending(intp),
      .ident_strobe(ident_strobe), .ident_level(ident_level),
      .ident_grant_in(1'b1), .ident_grant_out(),
      .ident_hit(ident_hit), .ident_code(ident_code),
      .dma_req(c_dma_req), .dma_wr(c_dma_wr), .dma_addr(c_dma_addr),
      .dma_wdata(c_dma_wdata), .dma_rdata(c_dma_rdata),
      .dma_ack(c_dma_ack), .dma_err(c_dma_err), .dma_busy(c_dma_busy),
      .disk_start(disk_start), .disk_req(disk_req), .disk_wr(disk_wr),
      .disk_blkaddr1(disk_blkaddr1), .disk_blkaddr2(disk_blkaddr2),
      .disk_unit(disk_unit), .disk_wordcount(disk_wordcount),
      .disk_done(disk_done), .disk_err_in(disk_err_in),
      .disk_err_code(disk_err_code),
      .dbuf_addr(dbuf_addr), .dbuf_wdata(dbuf_wdata), .dbuf_we(dbuf_we),
      .dbuf_rdata(dbuf_rdata)
  );

  // ---- BCU + ND memory model ----
  reg [15:0] memory [0:65535];
  reg [23:0] m_addr;
  reg        m_write;
  reg [3:0]  m_state = 0;
  reg [3:0]  m_cnt = 0;
  reg        mem_stall = 1'b0;  // when set, the memory never grants the bus
                                // -> the DMA master times out (dma_err)

  always @(posedge sysclk) begin
    case (m_state)
      4'd0: if (!mem_stall && m_breq_n == 1'b0) begin m_cnt <= 4'd2; m_state <= 4'd1; end
      4'd1: begin
        if (m_cnt != 0) m_cnt <= m_cnt - 4'd1;
        else begin bmem_n <= 1'b0; grant_head_n <= 1'b0; m_state <= 4'd2; end
      end
      4'd2: if (m_bapr_n == 1'b0) begin
        m_addr  <= ~mbd_bus_n;
        m_write <= (m_binput_n == 1'b0);
        m_state <= 4'd3;
      end
      4'd3: if (m_bdap_n == 1'b0) begin
        if (m_write) memory[m_addr[15:0]] <= ~mbd_bus_n[15:0];
        else mem_bd_n <= ~{8'd0, memory[m_addr[15:0]]};
        m_bdry_n     <= 1'b0;
        grant_head_n <= 1'b1;
        m_state      <= 4'd4;
      end
      4'd4: if (m_bdap_n == 1'b1) begin
        m_bdry_n <= 1'b1;
        mem_bd_n <= 24'hFFFFFF;
        bmem_n   <= 1'b1;
        m_state  <= 4'd5;
      end
      4'd5: m_state <= 4'd0;
      default: m_state <= 4'd0;
    endcase
  end

  // ---- disk model: linear word array, position from block address ----
  // The array doubles as a WINDOW into the 75 MB real SMD image
  // (BIGDISK0-L2-100.IMG, gitignored - see testdata/README.md):
  // window_base is subtracted from the computed position, and the
  // real-image phase loads 1M-word windows with $fseek + $fread.
  localparam WIN_WORDS = 1048576;
  reg [15:0] image[0:WIN_WORDS - 1];
  integer window_base;  // in words
  integer disk_pos;     // advances across chunks within one transfer
  integer ii, w;
  initial begin
    window_base = 0;
    // Must cover the highest synthetic-phase position. With the real CHS
    // geometry a cylinder is 5*18*512 = 46080 words, so cylinder 3 alone is
    // already word 138240 - the old 16384 only sufficed for the linear map.
    for (ii = 0; ii < 200000; ii = ii + 1)
      image[ii] = 16'h7000 + ii[15:0];
  end

  reg img_avail;
  initial img_avail = 0;

  // How many memory cycles the controller asked for and how many disk
  // requests it made - the M2 test needs both, because "no data goes to
  // memory" is a statement about the DMA request line, not only the memory.
  integer dma_reqs  = 0;
  integer disk_reqs = 0;
  always @(posedge sysclk) begin
    if (c_dma_req) dma_reqs  = dma_reqs  + 1;
    if (disk_req)  disk_reqs = disk_reqs + 1;
  end

  // When set, every disk request fails (media fault) instead of moving data.
  reg inject_fault = 1'b0;
  // Fail the Nth disk request counted from now (0 = off): a fault in the
  // middle of a multi-chunk transfer, after the first chunk already moved.
  integer req_seq      = 0;
  integer fault_at_seq = 0;

  task load_window(input integer word_base);
    integer fd, n;
    begin
      fd = $fopen("../../testdata/BIGDISK0-L2-100.IMG", "rb");
      if (fd == 0) begin
        img_avail = 0;
      end else begin
        img_avail = 1;
        n = $fseek(fd, word_base * 2, 0);
        n = $fread(image, fd);
        $fclose(fd);
        window_base = word_base;
        $display("[tb] SMD image window @word %0d: %0d bytes, first words %06o %06o",
                 word_base, n, image[0], image[1]);
      end
    end
  endtask

  always @(posedge sysclk) begin
    disk_done   <= 1'b0;
    disk_err_in <= 1'b0;
    dbuf_we     <= 1'b0;
    if (disk_start) begin
      // CHS -> LBA -> words, the same sum as ND_SMD / nd_storage_disc_adapter
      // and process_verilog_smd(): 5 heads, 18 sectors/track, 512 words per
      // 1024-byte sector. head = blkaddr1[15:8], sector = blkaddr1[7:0].
      disk_pos = (((disk_blkaddr2 * 5) + ((disk_blkaddr1 >> 8) & 8'hFF)) * 18
                  + (disk_blkaddr1 & 8'hFF)) * 512 - window_base;
    end
    if (disk_req) begin
      req_seq = req_seq + 1;
      if (inject_fault || (fault_at_seq != 0 && req_seq == fault_at_seq)) begin
        @(posedge sysclk);
        disk_err_in <= 1'b1;
        disk_done   <= 1'b1;
      end else if (!disk_wr) begin
        for (w = 0; w < disk_wordcount; w = w + 1) begin
          @(posedge sysclk);
          dbuf_addr  <= w[9:0];
          dbuf_wdata <= image[disk_pos + w];
          dbuf_we    <= 1'b1;
        end
        @(posedge sysclk);
        dbuf_we   <= 1'b0;
        disk_pos  = disk_pos + disk_wordcount;
        disk_done <= 1'b1;
      end else begin
        for (w = 0; w < disk_wordcount; w = w + 1) begin
          dbuf_addr <= w[9:0];
          @(posedge sysclk);
          @(posedge sysclk);
          image[disk_pos + w] = dbuf_rdata;
        end
        disk_pos  = disk_pos + disk_wordcount;
        disk_done <= 1'b1;
      end
    end
  end

  integer errors = 0;

  task check(input cond, input [255:0] what);
    begin
      if (!cond) begin
        errors = errors + 1;
        $display("FAIL: %0s (time %0t)", what, $time);
      end
    end
  endtask

  // ---- IOX tasks ----

  task bus_apr(input [15:0] addr);
    begin
      @(negedge sysclk);
      bd_out = ~{8'd0, addr};
      bapr_n = 0;
      @(negedge sysclk);
      @(negedge sysclk);
      bapr_n = 1;
      bd_out = 24'hFFFFFF;
      @(negedge sysclk);
    end
  endtask

  task iox_write(input [15:0] addr, input [15:0] data);
    integer guard;
    begin
      bus_apr(addr | 16'd1);
      bd_out  = ~{8'd0, data};
      bioxe_n = 0;
      guard = 0;
      while (bdry_n !== 1'b0 && guard < 50) begin
        @(negedge sysclk); guard = guard + 1;
      end
      check(bdry_n === 1'b0, "iox_write: BDRY_n never asserted");
      @(negedge sysclk);
      bioxe_n = 1;
      bd_out  = 24'hFFFFFF;
      @(negedge sysclk);
      @(negedge sysclk);
    end
  endtask

  task iox_read(input [15:0] addr, output [15:0] data);
    integer guard;
    begin
      bus_apr(addr & 16'hFFFE);
      bioxe_n = 0;
      guard = 0;
      while (binput_n !== 1'b0 && guard < 50) begin
        @(negedge sysclk); guard = guard + 1;
      end
      check(binput_n === 1'b0, "iox_read: BINPUT_n never asserted");
      binack_n = 0;
      guard = 0;
      while (bdry_n !== 1'b0 && guard < 50) begin
        @(negedge sysclk); guard = guard + 1;
      end
      check(bdry_n === 1'b0, "iox_read: BDRY_n never asserted");
      data = ~bd_in[15:0];
      binack_n = 1;
      bioxe_n  = 1;
      @(negedge sysclk);
      @(negedge sysclk);
    end
  endtask

  task ident(input [15:0] levelcode, output hit, output [15:0] code);
    integer guard;
    begin
      bus_apr(levelcode);
      outident_n = 0;
      guard = 0;
      while (binput_n !== 1'b0 && guard < 10) begin
        @(negedge sysclk); guard = guard + 1;
      end
      if (binput_n === 1'b0) begin
        hit = 1;
        binack_n = 0;
        guard = 0;
        while (bdry_n !== 1'b0 && guard < 50) begin
          @(negedge sysclk); guard = guard + 1;
        end
        code = ~bd_in[15:0];
        binack_n = 1;
      end else begin
        hit  = 0;
        code = 0;
      end
      outident_n = 1;
      @(negedge sysclk);
      @(negedge sysclk);
    end
  endtask

  // Poll status +4 (CWR=0) until ready-for-transfer (b3) - normal completion.
  task wait_ready;
    integer guard;
    reg [15:0] st;
    begin
      guard = 0;
      st = 0;
      while (!(st & 16'h0008) && guard < 30000) begin
        iox_read(16'o001544, st);
        guard = guard + 1;
      end
      check((st & 16'h0008) !== 0, "controller never became ready");
    end
  endtask

  // Poll status +4 (CWR=0) until NOT active (b2 clear) - used on error paths,
  // where the oracle leaves ready-for-transfer low.
  task wait_idle;
    integer guard;
    reg [15:0] st;
    begin
      guard = 0;
      st = 16'h0004;
      while ((st & 16'h0004) && guard < 30000) begin
        iox_read(16'o001544, st);
        guard = guard + 1;
      end
      check((st & 16'h0004) === 0, "controller never left active");
    end
  endtask

  // Core Address (24-bit): two writes (s_ma_wc_ff): the first loads all 24
  // bits (bits 16-23 from A bits 0-7), the second bits 0-15.
  task load_core(input [23:0] a);
    begin
      iox_write(16'o001541, {8'd0, a[23:16]});
      iox_write(16'o001541, a[15:0]);
    end
  endtask

  // Word Counter (24-bit): two writes, same flip-flop and load as above.
  task load_wcnt(input [23:0] c);
    begin
      iox_write(16'o001547, {8'd0, c[23:16]});
      iox_write(16'o001547, c[15:0]);
    end
  endtask

  // Block Address I (CWR=0) then II (CWR=1), via control-word CWR toggles.
  task load_block(input [15:0] bi, input [15:0] bii);
    begin
      iox_write(16'o001545, 16'h0000);  // control: unit 0, CWR=0, no GO
      iox_write(16'o001543, bi);        // block address I  (head b8-15, sector b0-7)
      iox_write(16'o001545, 16'h8000);  // control: CWR=1
      iox_write(16'o001543, bii);       // block address II (cylinder)
      iox_write(16'o001545, 16'h0000);  // control: CWR=0
    end
  endtask

  reg [15:0] rdata;
  reg        ihit;
  reg [15:0] icode;
  integer    i, dpos, nzcount;

  initial begin
`ifdef DUMPFILE
    $dumpfile("nd_smd_tb.vcd");
    $dumpvars(0, nd_smd_tb);
`endif
    for (i = 0; i < 65536; i = i + 1) memory[i] = 16'hDEAD;

    repeat (5) @(negedge sysclk);
    sys_rst_n = 1;
    repeat (5) @(negedge sysclk);

    // 1: reset status: no unit is selected yet, so ALL reads return 0
    //    (oracle SMD_Read: `if (!data->regs.selectedDisk) return 0`,
    //    nd100x deviceSMD.c). In boot mode +4 is not served either.
    iox_read(16'o001544, rdata);
    check(rdata === 16'd0, "status not 0 before any unit selected");

    // 1b: BOOT MODE (the '1540&' handshake, BPUN byte-server): per word
    //     activate via +3 bit 2, poll +2 for ready, read the stream word
    //     from +0; cross the 1024-word chunk boundary
    begin : bootstream
      integer guard, k;
      reg [15:0] st, bw;
      for (k = 0; k < 1030; k = k + 1) begin
        iox_write(16'o001543, 16'o004005);
        guard = 0; st = 0;
        while (!(st & 16'h0008) && guard < 30000) begin
          iox_read(16'o001542, st);
          guard = guard + 1;
        end
        check((st & 16'h0008) !== 0, "boot stream never ready on +2");
        check((st & 16'h0010) === 0, "boot stream flagged error");
        iox_read(16'o001540, bw);
        if (bw !== image[k])
          check(1'b0, "boot stream word wrong");
      end
    end

    // Leave boot mode with a device clear (control word bit 4): selects unit
    // 0, clears the registers and resets the flip-flops. The oracle leaves
    // ready-for-transfer low after a device clear; we only assert not-active.
    iox_write(16'o001545, 16'h0010);
    iox_read(16'o001544, rdata);
    check((rdata & 16'h0004) === 0, "active after device clear");

    // 2: M0 READ 1500 words (crosses the 1K buffer chunk) from
    //    blkaddrII=1, blkaddrI=2 (tb map: word 2176) to core 0x4000
    load_core(24'h004000);
    load_block(16'd2, 16'd1);          // I=2 (head 0, sector 2), II=1 (cyl 1)
    load_wcnt(24'd1500);
    iox_write(16'o001545, 16'h0004);   // GO: ACTIVE, op M0
    wait_ready();
    dpos = ((1 * 5 + 0) * 18 + 2) * 512;   // cyl 1, head 0, sector 2
    for (i = 0; i < 1500; i = i + 1)
      if (memory[16'h4000 + i] !== (16'h7000 + dpos[15:0] + i[15:0]))
        check(1'b0, "M0 read data wrong in ND memory");
    check(memory[16'h4000 + 1500] === 16'hDEAD, "M0 overran its count");
    // core address readback (CWR=0, LO) and word counter (CWR=1, LO)
    iox_read(16'o001540, rdata);
    check(rdata === (16'h4000 + 16'd1500), "core address readback wrong");
    // The core address read left the shared memory address / word count
    // flip-flop at "second access"; a status read resets it so the word
    // counter read below returns bits 0-15.
    iox_read(16'o001544, rdata);
    iox_write(16'o001545, 16'h8000);   // CWR=1
    iox_read(16'o001540, rdata);
    check(rdata === 16'd0, "word counter not 0 after transfer");
    iox_write(16'o001545, 16'h0000);   // CWR back to 0
    iox_read(16'o001544, rdata);       // status read: flip-flop back to "first"

    // 3: M1 WRITE 800 words from core 0x5000 to blkaddrII=3, blkaddrI=0
    for (i = 0; i < 800; i = i + 1) memory[16'h5000 + i] = 16'hC000 + i[15:0];
    load_core(24'h005000);
    load_block(16'd0, 16'd3);
    load_wcnt(24'd800);
    iox_write(16'o001545, 16'h0804);   // GO: ACTIVE (b2), op M1 (b11)
    wait_ready();
    dpos = ((3 * 5 + 0) * 18 + 0) * 512;   // cyl 3, head 0, sector 0
    for (i = 0; i < 800; i = i + 1)
      if (image[dpos + i] !== (16'hC000 + i[15:0]))
        check(1'b0, "M1 written image data wrong");
    check(image[dpos + 800] === (16'h7000 + dpos[15:0] + 16'd800),
          "M1 overran the image");

    // 3b: M2 READ PARITY, 1500 words (crosses the 1K chunk) from cyl 1, head 0,
    //     sector 2 to core 0xA000. ND-11.020.01 "M2: Read parity transfer":
    //     "No data transfer to the computer memory is performed". The card
    //     ends an M2 on word count zero (sec 3.7.2), so the words are counted;
    //     the address and word counters are one Am2942 chain stepped by the
    //     same ENABLE COUNTERS clock (card 3044 sheet 3), so the address ends
    //     at start + 1500 exactly as after an M0.
    for (i = 0; i < 1600; i = i + 1) memory[16'hA000 + i] = 16'hBEEF;
    load_core(24'h00A000);
    load_block(16'd2, 16'd1);
    load_wcnt(24'd1500);
    nzcount = dma_reqs;                // memory cycles so far
    dpos    = disk_reqs;               // disk requests so far
    iox_write(16'o001545, 16'h1004);   // GO: ACTIVE (b2), op M2 (b12)
    wait_ready();
    iox_read(16'o001544, rdata);
    check((rdata & 16'h0004) === 0, "M2 still active after ready");
    check((rdata & 16'h0010) === 0, "M2 flagged an error on good data");
    check(dma_reqs === nzcount, "M2 made a memory cycle");
    check(disk_reqs === dpos + 2, "M2 disk reads != 2 chunks");
    for (i = 0; i < 1600; i = i + 1)
      if (memory[16'hA000 + i] !== 16'hBEEF)
        check(1'b0, "M2 wrote to ND memory");
    // address counter stepped with the word counter: 0xA000 + 1500
    iox_read(16'o001540, rdata);       // core address LO (CWR=0)
    check(rdata === (16'hA000 + 16'd1500), "M2 core address != start+words");
    iox_read(16'o001540, rdata);       // second read: bits 16-23
    check((rdata & 16'h00FF) === 16'd0, "M2 core address HI not 0");
    iox_read(16'o001544, rdata);       // status read: flip-flop back to "first"
    iox_write(16'o001545, 16'h8000);   // CWR=1
    iox_read(16'o001540, rdata);
    check(rdata === 16'd0, "M2 word counter not 0 at the end");
    iox_read(16'o001540, rdata);
    check((rdata & 16'h00FF) === 16'd0, "M2 word counter HI not 0");
    iox_write(16'o001545, 16'h0000);   // CWR back to 0
    iox_read(16'o001544, rdata);       // status read: flip-flop back to "first"

    // 3c: M2 with a MEDIA FAULT still ends through the error path: the unit
    //     goes not-ready (b13) and the command stops active, with no memory
    //     cycle. A fresh M2 afterwards recovers.
    inject_fault = 1'b1;
    load_core(24'h00A000);
    load_block(16'd2, 16'd1);
    load_wcnt(24'd100);
    nzcount = dma_reqs;
    iox_write(16'o001545, 16'h1004);
    wait_idle();
    iox_read(16'o001544, rdata);
    check((rdata & 16'h2000) !== 0, "M2 fault: not-ready b13 not set");
    check((rdata & 16'h0004) === 0, "M2 fault: still active");
    check((rdata & 16'h0010) !== 0, "M2 fault: error OR b4 not set");
    check(dma_reqs === nzcount, "M2 fault: made a memory cycle");
    inject_fault = 1'b0;
    load_core(24'h00A000);
    load_block(16'd2, 16'd1);
    load_wcnt(24'd100);
    iox_write(16'o001545, 16'h1004);
    wait_ready();
    iox_read(16'o001544, rdata);
    check((rdata & 16'h2000) === 0, "M2 not-ready stuck after retry");
    for (i = 0; i < 1600; i = i + 1)
      if (memory[16'hA000 + i] !== 16'hBEEF)
        check(1'b0, "M2 after fault wrote to memory");

    // 3d: M3 COMPARE TRANSFER, 1500 words (crosses the 1K chunk) from cyl 1,
    //     head 0, sector 2 against core 0xA000. ND-11.020.01 "M3: Compare
    //     transfer": the disk data and the memory data are compared bit by
    //     bit, "a mismatch causes compare error to be set" (status b10). One
    //     memory READ per word, nothing written to memory, the address and
    //     word counters step as in M0/M2. SINTRAN's driver sends an M3 after
    //     its first read and treats a command that does not step the counters
    //     as a failed compare (the start-up TRANSFER ERROR).
    // device clear first: the media-fault test above leaves b4/b10 set
    iox_write(16'o001545, 16'h0010);
    dpos = ((1 * 5 + 0) * 18 + 2) * 512 - window_base;   // image index of that block
    for (i = 0; i < 1500; i = i + 1) memory[16'hA000 + i] = image[dpos + i];
    load_core(24'h00A000);
    load_block(16'd2, 16'd1);
    load_wcnt(24'd1500);
    nzcount = dma_reqs;
    iox_write(16'o001545, 16'h1804);   // GO: ACTIVE (b2), op M3 (b11-12)
    wait_ready();
    iox_read(16'o001544, rdata);
    check((rdata & 16'h0004) === 0, "M3 still active after ready");
    check((rdata & 16'h0400) === 0, "M3 compare error on equal data");
    check((rdata & 16'h0010) === 0, "M3 flagged an error on equal data");
    check(dma_reqs === nzcount + 1500, "M3 memory cycles != one per word");
    for (i = 0; i < 1500; i = i + 1)
      if (memory[16'hA000 + i] !== image[dpos + i])
        check(1'b0, "M3 wrote to ND memory");
    iox_read(16'o001540, rdata);       // core address LO
    check(rdata === (16'hA000 + 16'd1500), "M3 core address != start+words");
    iox_read(16'o001540, rdata);       // bits 16-23
    iox_read(16'o001544, rdata);       // status read: flip-flop back to "first"
    iox_write(16'o001545, 16'h8000);   // CWR=1
    iox_read(16'o001540, rdata);
    check(rdata === 16'd0, "M3 word counter not 0 at the end");
    iox_read(16'o001540, rdata);
    iox_write(16'o001545, 16'h0000);   // CWR back to 0
    iox_read(16'o001544, rdata);
    // one wrong bit in the second chunk -> compare error, command still ends
    memory[16'hA000 + 1200] = image[dpos + 1200] ^ 16'h0100;
    load_core(24'h00A000);
    load_block(16'd2, 16'd1);
    load_wcnt(24'd1500);
    iox_write(16'o001545, 16'h1804);
    wait_ready();
    iox_read(16'o001544, rdata);
    check((rdata & 16'h0400) !== 0, "M3 mismatch: compare error b10 not set");
    check((rdata & 16'h0010) !== 0, "M3 mismatch: error OR b4 not set");
    check((rdata & 16'h0004) === 0, "M3 mismatch: still active");

    // 3f: a media fault in the SECOND chunk of an M0. The first 1024 words
    //     already reached memory, and the address and word counters are one
    //     chain that steps with every word moved, so a driver reading them
    //     after the failed command sees how far it got: address = start +
    //     1024, word counter = 1500 - 1024 = 476. They used to keep the values
    //     loaded before the GO. The error also sets abnormal completion (b12,
    //     ND-11.020.01 sec 3.7.2) and not-ready (b13).
    iox_write(16'o001545, 16'h0010);   // device clear
    load_core(24'h00A000);
    load_block(16'd2, 16'd1);
    load_wcnt(24'd1500);
    fault_at_seq = req_seq + 2;
    iox_write(16'o001545, 16'h0004);   // GO: M0
    wait_idle();
    fault_at_seq = 0;
    iox_read(16'o001544, rdata);
    check((rdata & 16'h2000) !== 0, "chunk-2 fault: not-ready b13 not set");
    check((rdata & 16'h1000) !== 0, "chunk-2 fault: abnormal completion b12 not set");
    iox_read(16'o001540, rdata);       // core address LO
    check(rdata === (16'hA000 + 16'd1024), "chunk-2 fault: core address != start+1024");
    iox_read(16'o001544, rdata);       // status read: flip-flop back to "first"
    iox_write(16'o001545, 16'h8000);   // CWR=1
    iox_read(16'o001540, rdata);
    check(rdata === 16'd476, "chunk-2 fault: word counter != 476");
    iox_write(16'o001545, 16'h0000);   // CWR back to 0
    iox_read(16'o001544, rdata);
    iox_write(16'o001545, 16'h0010);   // device clear: b12 and the rest drop
    iox_read(16'o001544, rdata);
    check((rdata & 16'h1000) === 0, "device clear left abnormal completion b12 set");

    // 4: M4 seek -> on-cylinder (status b14), per-unit seek-complete
    //    (seek condition b0) and the 15 MHz card id (seek condition b12)
    load_block(16'd0, 16'd2);
    iox_write(16'o001545, 16'h2004);   // GO: ACTIVE, op M4 (0100)
    // M4 completes as soon as the drive accepts it (ND-11.020.01 "M4:
    // Initiate seek"), with no completion delay: the FIRST status read after
    // the GO must already show active (b2) clear and ready (b3) set. SINTRAN
    // polls only ~17,000 cycles before its next control word.
    iox_read(16'o001544, rdata);
    check((rdata & 16'h0004) === 0, "M4 still active on first read");
    check((rdata & 16'h0008) !== 0, "M4 not ready on first read");
    wait_ready();
    iox_read(16'o001544, rdata);
    check((rdata & 16'h4000) !== 0, "onCylinder (status b14) not set after seek");
    iox_read(16'o001542, rdata);       // seek condition (CWR=0)
    check((rdata & 16'h0001) !== 0, "unit-0 seek-complete (seek cond b0) missing");
    check((rdata & 16'h1000) !== 0, "SMD-15MHz id (seek cond b12) not set");

    // 4b: only a SEEK raises seek-complete. ND-11.020.01 (seek condition,
    //     bits 0-3): "only set if an initiate seek command for that unit has
    //     first been issued ... The condition will last until a transfer
    //     command is given." So an M0 ends it, and a device clear does not
    //     raise it. (M4 above left unit 0's bit set.)
    load_core(24'h006000);
    load_block(16'd0, 16'd0);
    load_wcnt(24'd16);
    iox_write(16'o001545, 16'h0004);   // GO: M0
    wait_ready();
    iox_read(16'o001542, rdata);       // seek condition (CWR=0)
    check((rdata & 16'h00FF) === 16'h0000, "seek-complete still set after a transfer");
    check((rdata & 16'h1000) !== 0, "SMD-15MHz id lost");
    iox_write(16'o001545, 16'h0010);   // device clear
    iox_read(16'o001542, rdata);
    check((rdata & 16'h00FF) === 16'h0000, "device clear raised seek-complete");
    load_block(16'd0, 16'd2);
    iox_write(16'o001545, 16'h2004);   // GO: M4
    wait_ready();
    iox_read(16'o001542, rdata);
    check((rdata & 16'h0001) !== 0, "M4 did not raise seek-complete");

    // 4c: C/H/S range check, every part on its own (75 MB geometry: 5 heads,
    //     18 sectors, 823 cylinders). Head 5 used to pass (the head was
    //     compared with the cylinder limit) and aliased onto the next
    //     cylinder's track; cylinder 823 passed because the LBA test is
    //     "greater than". Mismatch = b8, abnormal completion b12, b4.
    iox_write(16'o001545, 16'h0010);   // device clear
    load_core(24'h006000);
    load_wcnt(24'd16);
    load_block(16'h0500, 16'd0);       // head 5, sector 0, cylinder 0
    iox_write(16'o001545, 16'h0004);
    wait_idle();
    iox_read(16'o001544, rdata);
    check((rdata & 16'h0100) !== 0, "head 5: address mismatch b8 not set");
    check((rdata & 16'h1000) !== 0, "head 5: abnormal completion b12 not set");
    // (cylinder 823 is checked in nd_smd_iox_tb.v: this tb instances the DUT
    //  with a huge GEO_MAX_CYL for its linear block map)
    iox_write(16'o001545, 16'h0010);
    load_block(16'h0012, 16'd0);       // sector 18 of a 18-sector track
    iox_write(16'o001545, 16'h0004);
    wait_idle();
    iox_read(16'o001544, rdata);
    check((rdata & 16'h0100) !== 0, "sector 18: address mismatch b8 not set");
    // the last legal address passes and leaves b8 and b12 clear
    iox_write(16'o001545, 16'h0010);
    load_wcnt(24'd0);
    load_block(16'h0411, 16'd822);     // head 4, sector 17, cylinder 822
    iox_write(16'o001545, 16'h0004);
    wait_ready();
    iox_read(16'o001544, rdata);
    check((rdata & 16'h0100) === 0, "last legal C/H/S flagged address mismatch");
    check((rdata & 16'h1000) === 0, "last legal C/H/S set abnormal completion");

    // 4d: illegal load (b5) is per operation. A register load while the
    //     controller is active sets b5 (and b4); the next GO starts clean.
    //     Source: nd100x (ExecuteGO clears it, citing DISC-TEMA); the SMD
    //     manual only says what sets b5. A device clear is NOT used here.
    load_core(24'h00A000);
    load_block(16'd2, 16'd1);
    load_wcnt(24'd1500);
    iox_write(16'o001545, 16'h0004);   // GO: M0, 1500 words (busy for a while)
    iox_write(16'o001543, 16'h0002);   // block address I while active: illegal
    wait_ready();
    iox_read(16'o001544, rdata);
    check((rdata & 16'h0020) !== 0, "illegal load while active: b5 not set");
    check((rdata & 16'h0010) !== 0, "illegal load while active: b4 not set");
    load_core(24'h006000);
    load_block(16'd0, 16'd0);
    load_wcnt(24'd16);
    iox_write(16'o001545, 16'h0004);   // next GO
    wait_ready();
    iox_read(16'o001544, rdata);
    check((rdata & 16'h0020) === 0, "illegal load (b5) still set after the next GO");
    check((rdata & 16'h0010) === 0, "error OR (b4) still set after the next GO");
    check((rdata & 16'h4000) !== 0, "on-cylinder b14 lost");

    // 5: interrupt + IDENT: M0 read with interrupt enabled
    check(bint11_n === 1'b1, "BINT11 asserted before enable");
    load_core(24'h006000);
    load_block(16'd0, 16'd0);
    load_wcnt(24'd16);
    iox_write(16'o001545, 16'h0005);   // GO: ACTIVE, M0, int enable (b0)
    wait_ready();
    check(bint11_n === 1'b0, "BINT11_n not asserted on completion");
    ident(16'o000011, ihit, icode);
    check(ihit === 1'b1, "IDENT PL11 no hit");
    check(icode === 16'o000017, "IDENT code not 017");
    check(bint11_n === 1'b1, "BINT11_n not released after IDENT");

    // 6: ADDRESS MISMATCH: a sector field >= sectors/track (18) is out of
    //    range -> status b8, inclusive-OR b4, disk-not-ready b13; NO transfer,
    //    ready stays low.
    for (i = 0; i < 8; i = i + 1) memory[16'h6800 + i] = 16'hBEEF;
    load_core(24'h006800);
    load_block(16'd20, 16'd0);         // sector 20 >= 18 -> out of range
    load_wcnt(24'd8);
    iox_write(16'o001545, 16'h0004);   // GO M0
    wait_idle();
    iox_read(16'o001544, rdata);
    check((rdata & 16'h0100) !== 0, "address mismatch (status b8) not set");
    check((rdata & 16'h0010) !== 0, "inclusive-OR (status b4) not set on mismatch");
    check((rdata & 16'h2000) !== 0, "disk-not-ready (status b13) not set on mismatch");
    check(memory[16'h6800] === 16'hBEEF, "mismatch still moved data");

    // 7: ERROR INTERRUPT: with ONLY the error interrupt enabled (b1, not b0),
    //    a fault must still raise BINT11 (oracle HandleError).
    iox_write(16'o001545, 16'h0010);   // device clear -> clean state
    load_block(16'd20, 16'd0);         // out-of-range again
    load_wcnt(24'd8);
    iox_write(16'o001545, 16'h0006);   // GO M0, error-int enable (b1), no b0
    wait_idle();
    check(bint11_n === 1'b0, "error interrupt (BINT11) not raised on fault");
    ident(16'o000011, ihit, icode);
    check(ihit === 1'b1, "IDENT PL11 no hit on error interrupt");
    check(bint11_n === 1'b1, "BINT11 not released after IDENT (error int)");

    // 8: 24-bit core-address readback via the mar flip-flop (LO then HI)
    iox_write(16'o001545, 16'h0010);   // device clear (clears flip-flops)
    load_core(24'h012345);             // HI=0x01, LO=0x2345
    iox_read(16'o001540, rdata);       // first read: LO 16
    check(rdata === 16'h2345, "core address LO readback wrong");
    iox_read(16'o001540, rdata);       // second read: HI 8
    check(rdata === 16'h0001, "core address HI readback wrong");

    // 9: ECC pattern register (read +4, CWR=1): bits 11-13 = 1, bit 15 = CWR
    iox_write(16'o001545, 16'h8000);   // CWR=1
    iox_read(16'o001544, rdata);       // +4 CWR=1 -> ECC pattern
    check((rdata & 16'h3800) === 16'h3800, "ECC pattern bits 11-13 not all 1");
    check((rdata & 16'h8000) !== 0, "ECC pattern bit 15 (CWR) not set");
    iox_write(16'o001545, 16'h0000);   // CWR back to 0

    // 9b: MASS STORAGE LOAD ('21540&') on the 15 MHz card. From a fresh
    //     reset (boot mode), play the IOX sequence of the ND-120 MASS
    //     microcode (Code/Microcode/ND-120-DELILAH-L.LISTING.txt CSA
    //     002217-002235): +1 <- 0 twice, +3 <- 0, +7 <- 002000 ONCE,
    //     +5 <- 000004 (GO, M0, unit 0), poll +4. On the card the single +7
    //     write is the first access of a pair and loads all 24 bits, so the
    //     word count is 00 002000 = 1024 words: block 0 must land at ND
    //     memory 0-1777 and word 2000 must be untouched.
    //     The +7 write leaves the flip-flop at "second access"; the end of
    //     the transfer must reset it. That is checked BEFORE any status
    //     read (which would also reset it) by waiting on the controller's
    //     active bit inside the DUT and then writing +1 once: a first
    //     access loads bits 16-23, a second would leave them at the end
    //     address's 0.
    begin : massload
      integer guard;
      reg [15:0] st;
      for (i = 0; i < 65536; i = i + 1) memory[i] = 16'hDEAD;
      sys_rst_n = 0;
      repeat (5) @(negedge sysclk);
      sys_rst_n = 1;
      repeat (5) @(negedge sysclk);
      iox_write(16'o001541, 16'o000000);   // +1 memory address
      iox_write(16'o001541, 16'o000000);   // +1 memory address
      iox_write(16'o001543, 16'o000000);   // +3 block address
      iox_write(16'o001547, 16'o002000);   // +7 word count, ONCE
      iox_write(16'o001545, 16'o000004);   // +5 GO
      check(u_smd.s_words_left === 24'o0002000,
            "MASS: GO must start with a word count of 00 002000 (1024)");
      check(u_smd.s_mem_addr === 24'd0, "MASS: GO must start at memory address 0");
      guard = 0;
      while (u_smd.s_active !== 1'b0 && guard < 400000) begin
        @(negedge sysclk);
        guard = guard + 1;
      end
      check(u_smd.s_active === 1'b0, "MASS: transfer never finished");
      for (i = 0; i < 1024; i = i + 1)
        if (memory[i] !== (16'h7000 + i[15:0]))
          check(1'b0, "MASS: block 0 data wrong in ND memory 0-1777");
      check(memory[1024] === 16'hDEAD, "MASS: transfer overran 1024 words");
      // end of transfer reset the flip-flop: this +1 is a FIRST access
      iox_write(16'o001541, 16'o000003);
      iox_read(16'o001544, st);           // status read: ready, not active
      check((st & 16'h0004) === 0, "MASS: still active after the transfer");
      check((st & 16'h0008) !== 0, "MASS: not ready after the transfer");
      iox_read(16'o001540, rdata);        // bits 0-15
      check(rdata === 16'o000003, "MASS: +1 after the transfer: bits 0-15 must be 000003");
      iox_read(16'o001540, rdata);        // bits 16-23
      check(rdata === 16'o000003,
            "MASS: end of transfer must reset the flip-flop (+1 loads bits 16-23 = 003)");
    end

    // 10: REAL IMAGE phase - three windows of the 75 MB SMD disk 0 (start,
    //     middle, far), each read through the controller and word-compared
    load_window(0);
    if (!img_avail) begin
      $display("[tb] SKIP real-image phase: testdata/BIGDISK0-L2-100.IMG not present");
    end else begin
      load_core(24'h007000);
      load_block(16'd0, 16'd0);        // word 0
      load_wcnt(24'd1024);
      iox_write(16'o001545, 16'h0004);
      wait_ready();
      for (i = 0; i < 1024; i = i + 1)
        if (memory[16'h7000 + i] !== image[i])
          check(1'b0, "SMD image start readback wrong");
      nzcount = 0;
      for (i = 0; i < 1024; i = i + 1) if (memory[16'h7000 + i] !== 16'd0) nzcount = nzcount + 1;
      check(nzcount > 0, "SMD start window compared only zeros (vacuous)");

      // One cylinder = 5 heads * 18 sectors * 512 words = 46080 words, so a
      // window base is cylinder * 46080. The old cylinder numbers (5120,
      // 18472) were picked for the linear blkaddr2*2048 map and land far
      // outside the 75 MB image under the real geometry.
      load_window(426 * 46080);
      load_core(24'h007000);
      load_block(16'd0, 16'd426);
      load_wcnt(24'd1024);
      iox_write(16'o001545, 16'h0004);
      wait_ready();
      for (i = 0; i < 1024; i = i + 1)
        if (memory[16'h7000 + i] !== image[i])
          check(1'b0, "SMD image middle readback wrong");
      nzcount = 0;
      for (i = 0; i < 1024; i = i + 1) if (memory[16'h7000 + i] !== 16'd0) nzcount = nzcount + 1;
      check(nzcount > 0, "SMD middle window compared only zeros (vacuous)");

      // "far" must still land on WRITTEN data or the non-zero check below is
      // vacuous - this image is only populated to about cylinder 432 under
      // the real geometry, the rest of the 75 MB is zeros.
      load_window(432 * 46080);
      load_core(24'h007000);
      load_block(16'd0, 16'd432);
      load_wcnt(24'd1024);
      iox_write(16'o001545, 16'h0004);
      wait_ready();
      for (i = 0; i < 1024; i = i + 1)
        if (memory[16'h7000 + i] !== image[i])
          check(1'b0, "SMD image far readback wrong");
      nzcount = 0;
      for (i = 0; i < 1024; i = i + 1) if (memory[16'h7000 + i] !== 16'd0) nzcount = nzcount + 1;
      check(nzcount > 0, "SMD far window compared only zeros (vacuous)");
    end

    // 11: DMA BUS FAULT -> disk-unit-not-ready (b13) via HandleError (oracle:
    //     a DMA/bus fault marks the unit not ready). Ready stays low on the
    //     fault, so poll for not-active, then a fresh command recovers.
    window_base = 0;                   // synthetic map again for this phase
    mem_stall = 1'b1;
    load_core(24'h006000);
    load_block(16'd0, 16'd0);
    load_wcnt(24'd16);
    iox_write(16'o001545, 16'h0004);   // GO M0 -> DMA into the stalled memory
    wait_idle();
    iox_read(16'o001544, rdata);
    check((rdata & 16'h2000) !== 0, "DMA fault: disk-not-ready (b13) not set");
    mem_stall = 1'b0;
    // recovery: a fresh command clears not-ready and transfers normally
    load_core(24'h006800);
    load_block(16'd0, 16'd0);
    load_wcnt(24'd8);
    iox_write(16'o001545, 16'h0004);
    wait_ready();
    iox_read(16'o001544, rdata);
    check((rdata & 16'h2000) === 0, "disk-not-ready stuck after recovery");

    if (errors == 0) $display("TB_RESULT: PASS");
    else begin
      $display("%0d errors", errors);
      $display("TB_RESULT: FAIL");
    end
    $finish;
  end

  initial begin
    #400000000;
    $display("TIMEOUT");
    $display("TB_RESULT: FAIL");
    $finish;
  end

endmodule
