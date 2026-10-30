/****************************************************************************
** TESTBENCH: ND_WINCHESTER -> adapter -> nd_storage -> SD card, END TO END **
**                                                                         **
** THE HOLE THIS CLOSES                                                    **
**                                                                         **
** Four Winchester benches existed before this one and not one of them had **
** nd_storage in it:                                                       **
**                                                                         **
**   nd_winchester_iox_tb.v      register protocol, disk_done faked        **
**   nd_winchester_oracle_tb.v   replays the C model's IOX trace, disk     **
**                               chunks completed by a two-cycle stub      **
**   nd_winchester_bus_tb.v      the card behind the real ND_BUS_SLAVE     **
**   nd_winchester_adapter_tb.v  CHS->LBA arithmetic and write refusal,    **
**                               with NO storage behind the adapter        **
**                                                                         **
** So the whole path from "the guest set GO" to "bytes off the FAT volume" **
** was never simulated. On silicon 08-AUG-2026 that path failed in the one **
** way none of those four benches can see: the controller reported status  **
** 060010 - finished (b3), on cylinder (b14), b13 always-1, NO error bits  **
** at all - the memory address register had advanced by exactly 2000 octal **
** (1024 words, a full DMA), and every one of those 1024 words was ZERO.   **
** A backend that answers "done, no error" while handing over a zero block **
** is invisible to every bench that fakes the backend.                     **
**                                                                         **
** WHAT IS EXERCISED                                                       **
**                                                                         **
** The REAL chain, in the wiring the Tang build uses: ND_WINCHESTER ->     **
** nd_storage_devices(INCLUDE_WD=1) -> nd_storage_disc_adapter (client 6, **
** Winchester geometry) -> nd_storage (mount + engine + Phase-4 cache) ->  **
** the behavioral SD card serving the real FAT16 image, with WD0.IMG on    **
** it. Client 6 is a CACHED client, so a cold block-0 read must MISS,      **
** fetch four card sectors, fill the region line, publish the tag and only **
** then serve the controller.                                             **
**                                                                         **
** The IOX sequence is the ORACLE's, captured from the nd100x C model      **
** (see nd_winchester_oracle_tb.v): block address, memory address HI then  **
** LO, word count, then activate+read. Two transfers are run back to back  **
** because the silicon symptom included "sometimes the second one works" - **
** a cold MISS and then a warm HIT of the same block must BOTH deliver the **
** card's bytes, and the second must not quietly serve a line the first    **
** one never filled.                                                       **
**                                                                         **
** Checks                                                                  **
**   1. transfer 1 (cold, cache MISS): finished, no error bits, and every  **
**      DMA word equals WD0.IMG                                            **
**   2. the memory address register advanced by the word count             **
**   3. transfer 2 (same block, cache HIT): same data, still no error      **
**   4. a block further into the file (past the first cluster) also reads  **
**      correctly - a wrong FAT walk shows up here and not at block 0      **
**                                                                         **
** The card image is the shared one built by                               **
** Verilog/SD-FAT/sim/make_storage_image.sh (target test-nds-mount), which **
** carries WD0.IMG.                                                        **
**                                                                         **
** Verdict: TB_RESULT: PASS / TB_RESULT: FAIL <reason>                     **
**                                                                         **
** Ronny Hansen                                                            **
*****************************************************************************/
`timescale 1ns / 1ps

module nd_winchester_dmapath_tb;

  // Micropolis 1325 / DISC-74-1, the geometry nd_storage_devices binds.
  localparam [15:0] WD_HEADS = 16'd8;
  localparam [15:0] WD_SPT   = 16'd9;

  // WD0.IMG on the shared card image (make_storage_image.sh).
  localparam integer WD_BYTES = 16384;
  localparam IMG_BYTES = 4 * 1024 * 1024;

  integer errors = 0;

  // WD0.IMG payload pattern - MUST match make_storage_image.sh
  function [7:0] pat_wd(input integer k);
    pat_wd = ((k % 256) + 61 * ((k / 256) % 256) + 83) % 256;
  endfunction

  // ------------------------------------------------------------- clocks
  // clk_cpu carries the controller AND the client side of nd_storage; the
  // card/region side runs on the skewed clk_stor, as on the board.
  reg clk_cpu = 0;
  always #21.7 clk_cpu = ~clk_cpu;    // ~23.04 MHz
  reg clk_stor = 0;
  always #18.5 clk_stor = ~clk_stor;  // ~27.03 MHz

  reg rst_n = 0;
  wire sysclk = clk_cpu;

  // ------------------------------------------------------------- IOX port
  reg  [15:0] iox_addr  = 16'd0;
  reg         iox_wr    = 1'b0;
  reg  [15:0] iox_wdata = 16'd0;
  reg         iox_rd    = 1'b0;
  wire [15:0] iox_rdata;
  wire        iox_sel;
  wire [3:0]  int_pending;
  // IDENT daisy chain, driven for real: the captured driver trace shows FSI
  // does NOT poll a transfer to completion - it reads status once while the
  // card is active and then WAITS FOR THE LEVEL-11 INTERRUPT. A completion
  // interrupt that never arrives is indistinguishable, from SINTRAN's side,
  // from a disc error. No Winchester bench had ever checked that the line
  // rises on a real transfer, so these pins were tied off here too.
  reg         ident_strobe   = 1'b0;
  reg  [3:0]  ident_level    = 4'd0;
  reg         ident_grant_in = 1'b0;
  wire        ident_grant_out, ident_hit;
  wire [15:0] ident_code;

  // ------------------------------------------------- REAL DMA PATH
  // The DMA is NOT faked here, and that is the whole point of this bench.
  // Every other Winchester testbench answers dma_req with dma_ack on the next
  // clock and ties dma_busy to 0, so ND_DMA_MASTER - the thing that actually
  // arbitrates for the ND-100 bus - has never been exercised with this card.
  // The SINTRAN boot hangs with the disc side FINISHED (all five reads
  // reported done) and the controller still ACTIVE, which is the signature of
  // the memory side never answering. A bench that always answers cannot
  // reproduce that, so this one runs the real master against a BCU + memory
  // model that implements the bus handshake (BREQ/BAPR/BDAP/BDRY).
  wire        dma_req, dma_wr;
  wire [23:0] dma_addr;
  wire [15:0] dma_wdata;
  wire [15:0] dma_rdata_w;
  wire        dma_ack, dma_err, dma_busy;
  integer     dma_writes = 0;
  integer     dma_reads  = 0;

  wire        m_breq_n;
  reg         grant_head_n = 1'b1;
  reg         bmem_n = 1'b1;
  reg  [23:0] mem_bd_n = 24'hFFFFFF;
  wire [23:0] m_bd_out_n;
  wire [23:0] mbd_bus_n = m_bd_out_n & mem_bd_n;
  wire        m_bapr_n, m_binput_n, m_bdap_n;
  reg         m_bdry_n = 1'b1;

  ND_DMA_MASTER #(.TIMEOUT_TICKS(16'd0), .MIN_GAP_TICKS(8'd4)) u_dma (
      .sysclk(sysclk), .sys_rst_n(rst_n),
      .dma_req(dma_req), .dma_wr(dma_wr), .dma_addr(dma_addr),
      .dma_wdata(dma_wdata), .dma_rdata(dma_rdata_w),
      .dma_ack(dma_ack), .dma_err(dma_err), .dma_busy(dma_busy),
      .BREQ_n(m_breq_n),
      .INGRANT_n(grant_head_n), .OUTGRANT_n(),
      .BMEM_n(bmem_n),
      .BD_23_0_n_OUT(m_bd_out_n), .BD_23_0_n_IN(mbd_bus_n),
      .BAPR_n(m_bapr_n), .BINPUT_n(m_binput_n), .BDAP_n(m_bdap_n),
      .BDRY_n(m_bdry_n)
  );

  // BCU + ND memory model - same protocol as nd_dma_master_tb.v and
  // nd_floppy_dma_tb.v, so the handshake is the proven one.
  reg [15:0] dmamem [0:65535];
  reg [23:0] m_addr;
  reg        m_write;
  reg [3:0]  m_state = 4'd0;
  reg [3:0]  m_cnt = 4'd0;

  always @(posedge sysclk) begin
    if (!rst_n) begin
      m_state <= 4'd0; grant_head_n <= 1'b1; bmem_n <= 1'b1;
      m_bdry_n <= 1'b1; mem_bd_n <= 24'hFFFFFF;
    end else case (m_state)
      4'd0: if (m_breq_n == 1'b0) begin m_cnt <= 4'd2; m_state <= 4'd1; end
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
        if (m_write) begin
          dmamem[m_addr[15:0]] <= ~mbd_bus_n[15:0];
          dma_writes = dma_writes + 1;
        end else begin
          mem_bd_n <= ~{8'd0, dmamem[m_addr[15:0]]};
          dma_reads = dma_reads + 1;
        end
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

  // ------------------------------------------------------------- backend seam
  wire        WDISK_START, WDISK_REQ, WDISK_WR;
  wire [15:0] WDISK_BLKADDR1, WDISK_BLKADDR2;
  wire [ 2:0] WDISK_UNIT;
  wire [10:0] WDISK_WORDCOUNT;
  wire        WDISK_DONE, WDISK_ERR;
  wire [ 9:0] WDBUF_ADDR;
  wire [15:0] WDBUF_WDATA;
  wire        WDBUF_WE;
  wire [15:0] WDBUF_RDATA;

  ND_WINCHESTER #(.DELAY_TICKS(32'd20)) dut (
      .sysclk         (sysclk),
      .sys_rst_n      (rst_n),
      .iox_addr       (iox_addr),
      .iox_wr         (iox_wr),
      .iox_wdata      (iox_wdata),
      .iox_rd         (iox_rd),
      .iox_rdata      (iox_rdata),
      .iox_sel        (iox_sel),
      .int_pending    (int_pending),
      .ident_strobe   (ident_strobe),
      .ident_level    (ident_level),
      .ident_grant_in (ident_grant_in),
      .ident_grant_out(ident_grant_out),
      .ident_hit      (ident_hit),
      .ident_code     (ident_code),
      .dma_req        (dma_req),
      .dma_wr         (dma_wr),
      .dma_addr       (dma_addr),
      .dma_wdata      (dma_wdata),
      // Served from the DMA memory, not a constant. A WRITE makes the
      // controller READ host memory, so a tied constant makes every write
      // test meaningless - it would store the same word everywhere and a
      // byte-order or address-stepping fault would look perfect.
      .dma_rdata      (dma_rdata_w),
      .dma_ack        (dma_ack),
      .dma_err        (dma_err),
      .dma_busy       (dma_busy),
      .disk_start     (WDISK_START),
      .disk_req       (WDISK_REQ),
      .disk_wr        (WDISK_WR),
      .disk_blkaddr1  (WDISK_BLKADDR1),
      .disk_blkaddr2  (WDISK_BLKADDR2),
      .disk_unit      (WDISK_UNIT),
      .disk_wordcount (WDISK_WORDCOUNT),
      .disk_done      (WDISK_DONE),
      .disk_err_in    (WDISK_ERR),
      .disk_err_code  (WDISK_ERR_CODE),
      .dbuf_addr      (WDBUF_ADDR),
      .dbuf_wdata     (WDBUF_WDATA),
      .dbuf_we        (WDBUF_WE),
      .dbuf_rdata     (WDBUF_RDATA)
  );

  // ------------------------------------------------------------- storage
  wire        sd_clk, sd_cmd_o, sd_cmd_oe, sd_dat0_o, sd_dat0_oe;
  wire        c_cmd_o, c_cmd_oe, c_dat0_o, c_dat0_oe;
  // SD lines resolved by MUX, no tristates: host output-enable wins, then
  // the card, then the bus pullup - the same rule as nd_storage_tb.v.
  wire        sd_cmd  = sd_cmd_oe  ? sd_cmd_o  : (c_cmd_oe  ? c_cmd_o  : 1'b1);
  wire        sd_dat0 = sd_dat0_oe ? sd_dat0_o : (c_dat0_oe ? c_dat0_o : 1'b1);

  wire        mem_start, mem_we, mem_busy, mem_done;
  wire [19:0] mem_addr;
  wire [31:0] mem_wdata, mem_rdata;

  nd_storage_devices #(
      .SIMULATE      (1),
      .INCLUDE_TAPE  (0),
      .INCLUDE_FLOPPY(1),   // as the Tang build: floppy AND Winchester both mount
      .INCLUDE_SMD   (0),
      .INCLUDE_WD    (1)
  ) u_src (
      .clk_stor  (clk_stor),
      .rst_stor_n(rst_n),
      .clk_cpu   (clk_cpu),
      .rst_cpu_n (rst_n),

      .byte_req     (1'b0),
      .byte_valid   (),
      .byte_data    (),
      .source_rewind(1'b0),

      .FDISK_REQ      (1'b0),
      .FDISK_WR       (1'b0),
      .FDISK_LSECT    (16'd0),
      .FDISK_FORMAT   (2'd0),
      .FDISK_DRIVE    (2'd0),
      .FDISK_WORDCOUNT(11'd0),
      .FDISK_DONE     (),
      .FDISK_ERR      (),
      .FDISK_ERR_CODE (),
      .FDISK_MEDIA_FMT(),
      .FDBUF_ADDR     (),
      .FDBUF_WDATA    (),
      .FDBUF_WE       (),
      .FDBUF_RDATA    (16'd0),

      .SDISK_START    (1'b0),
      .SDISK_REQ      (1'b0),
      .SDISK_WR       (1'b0),
      .SDISK_BLKADDR1 (16'd0),
      .SDISK_BLKADDR2 (16'd0),
      .SDISK_UNIT     (3'd0),
      .SDISK_WORDCOUNT(11'd0),
      .SDISK_DONE     (),
      .SDISK_ERR      (),
      .SDBUF_ADDR     (),
      .SDBUF_WDATA    (),
      .SDBUF_WE       (),
      .SDBUF_RDATA    (16'd0),

      .WDISK_START    (WDISK_START),
      .WDISK_REQ      (WDISK_REQ),
      .WDISK_WR       (WDISK_WR),
      .WDISK_BLKADDR1 (WDISK_BLKADDR1),
      .WDISK_BLKADDR2 (WDISK_BLKADDR2),
      .WDISK_UNIT     (WDISK_UNIT),
      .WDISK_WORDCOUNT(WDISK_WORDCOUNT),
      .WDISK_DONE     (WDISK_DONE),
      .WDISK_ERR      (WDISK_ERR),
      .WDBUF_ADDR     (WDBUF_ADDR),
      .WDBUF_WDATA    (WDBUF_WDATA),
      .WDBUF_WE       (WDBUF_WE),
      .WDBUF_RDATA    (WDBUF_RDATA),

      .sd_clk_o  (sd_clk),
      .sd_cmd_i  (sd_cmd),
      .sd_cmd_o  (sd_cmd_o),
      .sd_cmd_oe (sd_cmd_oe),
      .sd_dat0_i (sd_dat0),
      .sd_dat0_o (sd_dat0_o),
      .sd_dat0_oe(sd_dat0_oe),

      .mem_start(mem_start),
      .mem_we   (mem_we),
      .mem_addr (mem_addr),
      .mem_wdata(mem_wdata),
      .mem_rdata(mem_rdata),
      .mem_busy (mem_busy),
      .mem_done (mem_done),

      .sd_status()
  );

  // ---- the region -----------------------------------------------------
  // TWO builds from this one source, because the region is the ONE part of
  // the chain that differs between this bench and the board:
  //
  //   default            nds_mem_model - the abstract mem-port contract
  //   -DWD_TB_REAL_SDRAM the REAL MEM_RAM_49_SDRAM (ND_SDRAM_PACK16 +
  //                      ND_STORAGE_PORT) driving the behavioral SDRAM
  //                      chip, i.e. exactly what the Tang synthesizes
  //
  // Both nd_storage and MEM_RAM_49_SDRAM have their own passing benches, but
  // they had never been COMPOSED: nd_storage's benches all use
  // nds_mem_model, and mem_ram_49_sdram_tb.v drives the device port from a
  // synthetic task. A disagreement between those two mem-port contracts
  // would pass both benches and lose the data on the board - which is what a
  // read that finishes with no error and delivers 1024 zero words looks
  // like. This build is what makes that composition a tested thing.
`ifdef WD_TB_REAL_SDRAM
  // OSC and 2x clock, edge-aligned (same shape as mem_ram_49_sdram_tb.v).
  localparam OSC_PERIOD = 37;  // ~27 MHz
  reg clk2x = 1;
  always #(OSC_PERIOD / 4.0) clk2x = ~clk2x;
  reg osc = 1;
  always @(clk2x) if (clk2x) osc = ~osc;
  wire clk2x_sdram = ~clk2x;

  // Sheet-49 CPU side held idle: the device port is granted in the idle
  // slots, which is the case the board spends most of its time in anyway.
  wire sd_clk_c, sd_cke, sd_cs_n, sd_cas_n, sd_ras_n, sd_wen_n;
  wire [31:0] sd_dq;
  wire [10:0] sd_a;
  wire [ 1:0] sd_ba;
  wire [ 3:0] sd_dqm;

  MEM_RAM_49_SDRAM #(
      .CLK2X_FREQ(54_000_000)
  ) u_mem (
      .sysclk    (osc),
      .sys_rst_n (rst_n),
      .AA_9_0    (10'd0),
      .BANK0     (1'b0),
      .BANK1     (1'b0),
      .BANK2     (1'b0),
      .CAS       (1'b0),
      .RAS       (1'b0),
      .MWRITE50_n(1'b1),
      .DD_17_0_IN(18'd0),
      .DD_17_0_OUT(),
      .CORR_n    (),

      .clk2x      (clk2x),
      .clk2x_sdram(clk2x_sdram),

      .O_sdram_clk  (sd_clk_c),
      .O_sdram_cke  (sd_cke),
      .O_sdram_cs_n (sd_cs_n),
      .O_sdram_cas_n(sd_cas_n),
      .O_sdram_ras_n(sd_ras_n),
      .O_sdram_wen_n(sd_wen_n),
      .IO_sdram_dq  (sd_dq),
      .O_sdram_addr (sd_a),
      .O_sdram_ba   (sd_ba),
      .O_sdram_dqm  (sd_dqm),

      .stor_clk  (clk_stor),
      .stor_rst_n(rst_n),
      .mem_start (mem_start),
      .mem_we    (mem_we),
      .mem_addr  (mem_addr),
      .mem_wdata (mem_wdata),
      .mem_rdata (mem_rdata),
      .mem_busy  (mem_busy),
      .mem_done  (mem_done)
  );

  sdram_model u_sdram (
      .clk  (sd_clk_c),
      .cke  (sd_cke),
      .cs_n (sd_cs_n),
      .ras_n(sd_ras_n),
      .cas_n(sd_cas_n),
      .we_n (sd_wen_n),
      .a    (sd_a),
      .ba   (sd_ba),
      .dqm  (sd_dqm),
      .dq   (sd_dq)
  );
`else
  // Blocks 0 (staging) and 1.. (the cache pool) are all this needs;
  // 64K words covers pool lines 0..127.
  nds_mem_model #(
      .MEM_WORDS(65536)
  ) u_mem (
      .clk  (clk_stor),
      .rst_n(rst_n),
      .start(mem_start),
      .we   (mem_we),
      .addr (mem_addr),
      .wdata(mem_wdata),
      .rdata(mem_rdata),
      .busy (mem_busy),
      .done (mem_done)
  );
`endif

  sd_card_model #(
      .IMAGE           ("../../../SD-FAT/sim/nds_storage.img"),
      .MAX_BYTES       (IMG_BYTES),
      .LEGAL_MIN_SECTOR(0)
  ) card (
      .sd_clk   (sd_clk),
      .sd_cmd_i (sd_cmd),
      .sd_cmd_o (c_cmd_o),
      .sd_cmd_oe(c_cmd_oe),
      .sd_dat0_i(sd_dat0),
      .sd_dat0_o(c_dat0_o),
      .sd_dat0_oe(c_dat0_oe),
      .sd_dat1_i(1'b1), .sd_dat1_o(), .sd_dat1_oe(),
      .sd_dat2_i(1'b1), .sd_dat2_o(), .sd_dat2_oe(),
      .sd_dat3_i(1'b1), .sd_dat3_o(), .sd_dat3_oe()
  );

  // ------------------------------------------------------------- IOX driver
  task iox_write(input [15:0] a, input [15:0] d);
    begin
      @(posedge sysclk);
      iox_addr  <= a;
      iox_wdata <= d;
      iox_wr    <= 1'b1;
      @(posedge sysclk);
      iox_wr <= 1'b0;
      @(posedge sysclk);
    end
  endtask

  reg [15:0] rdlat;
  task iox_read(input [15:0] a);
    begin
      @(posedge sysclk);
      iox_addr <= a;
      iox_rd   <= 1'b1;
      @(posedge sysclk);
      // mirror ND_BUS_SLAVE: sample at the edge the strobe is still up
      rdlat  <= iox_rdata;
      iox_rd <= 1'b0;
      @(posedge sysclk);
    end
  endtask

  // Wait for the controller to report finished (status b3) rather than
  // guessing a cycle count. Reading +4 resets the flip-flops, so read it
  // ONCE per poll and stop as soon as b3 shows.
  reg [15:0] st;
  task wait_finished(input [255:0] what);
    integer guard;
    begin
      st    = 16'd0;
      guard = 0;
      // 40000 was enough only because the CACHED build had already filled
      // the early blocks, so a 4-block read was mostly hits. With the disc
      // clients DIRECT every block is a fresh fetch - 16 card sectors for a
      // 4096-word read - and the poll budget has to cover the slowest case,
      // not the luckiest.
      while (!st[3] && guard < 400000) begin
        iox_read(16'o504);
        st = rdlat;
        guard = guard + 1;
        repeat (20) @(posedge sysclk);
      end
      if (!st[3]) begin
        $display("TB_RESULT: FAIL %0s: never finished (last status %06o)",
                 what, st);
        $finish;
      end
    end
  endtask

  // One full transfer, exactly the oracle's register order.
  task do_transfer(input [15:0] blkaddr, input [15:0] memaddr,
                   input [15:0] wc, input [255:0] what);
    begin
      iox_write(16'o503, blkaddr);      // block address
      iox_write(16'o501, 16'd0);        // memory address, HI first
      iox_write(16'o501, memaddr);      // memory address, LO second
      iox_write(16'o507, wc);           // word count
      iox_write(16'o505, 16'd4);        // activate, M0 = read, no interrupt
      wait_finished(what);
    end
  endtask

  // M1 = WRITE. Op is control-word bits 13:11 (ND_WINCHESTER.v:198-205), so
  // M1 is (1 << 11) = 004000 octal, plus the activate bit 2.
  task do_write(input [15:0] blkaddr, input [15:0] memaddr,
                input [15:0] wc, input [255:0] what);
    begin
      iox_write(16'o503, blkaddr);      // block address
      iox_write(16'o501, 16'd0);        // memory address, HI first
      iox_write(16'o501, memaddr);      // memory address, LO second
      iox_write(16'o507, wc);           // word count
      iox_write(16'o505, 16'o004004);   // activate, M1 = write, no interrupt
      wait_finished(what);
    end
  endtask

  // Every DMA'd word must be the file's bytes. Byte 2w of the block is the
  // HIGH half of client word w (the packing the whole stack uses).
  task check_words(input [15:0] base, input integer fbyte0, input integer nwords,
                   input [255:0] what);
    integer w;
    reg [15:0] got, want;
    begin
      for (w = 0; w < nwords; w = w + 1) begin
        want = {pat_wd(fbyte0 + 2*w), pat_wd(fbyte0 + 2*w + 1)};
        got  = dmamem[base + w[15:0]];
        if (got !== want) begin
          if (errors < 8)
            $display("FAIL: %0s word %0d at %06o: got %06o want %06o",
                     what, w, base + w, got, want);
          errors = errors + 1;
        end
      end
    end
  endtask

  integer i;
  integer w1_writes;
  reg [15:0] ma_lo, ma_hi;

  initial begin
    for (i = 0; i < 65536; i = i + 1) dmamem[i] = 16'hFFFF;  // poison

    repeat (10) @(posedge clk_stor);
    rst_n = 1;
    repeat (50) @(posedge sysclk);

    // The mount runs on its own after reset (nd_storage_devices pulses the
    // open once the card reports OK). Give it the card init + scan before the
    // first command; the adapter refuses with an error if it has not opened,
    // so a too-short wait shows up as an error bit, never as silence.
    for (i = 0; i < 3_000_000 && !u_src.gen_wd.s_wopened; i = i + 1)
      @(posedge clk_cpu);
    if (!u_src.gen_wd.s_wopened) begin
      $display("TB_RESULT: FAIL WD0.IMG never opened (mount did not complete)");
      $finish;
    end
    $display("[ ok ] WD0.IMG mounted, size %0d bytes",
             u_src.size_bytes_w[223:192]);
    if (u_src.size_bytes_w[223:192] !== WD_BYTES) begin
      $display("FAIL: WD0.IMG size %0d, want %0d",
               u_src.size_bytes_w[223:192], WD_BYTES);
      errors = errors + 1;
    end

    // ---- 0. THE DRIVER'S OPENING SEQUENCE, replayed from the C model ----
    // images/FILSYS-INV-Q04.BPUN (the same File System Investigator that
    // fails on the Tang) under nd100x against the real 75 MiB WD0.IMG, device
    // name DISC-74MB-1. In the C model it WORKS - LIST-FILE-NAMES prints the
    // real SINTRAN directory - so this sequence and its status words are the
    // specification, exactly as nd_winchester_oracle_tb.v treats the
    // DISC-TEMA trace. The capture is ../oracle/fsi-lifi-nd100x.trace (how
    // it was made: ../oracle/README.md).
    //
    // POWER-ON IS ON CYLINDER. The current model reads 060000 first and the
    // FSI goes straight to its first read; a real 3041 with a Micropolis 1325
    // read 060011 after its first control word, with no return to zero before
    // it (DISC-TEMA start-up trace kept in RetroCore's
    // NDBusDiscControllerWinchester.cs), and master clear puts the heads on
    // cylinder 0 (ND-11.015.01 sec 3.4.8, 5.5). The older model read 020000,
    // and the FSI then opened with the M7 below
    // (../oracle/fsi-lifi-nd100x-old-model.trace); the M7 is kept here because
    // it still has to end on cylinder, with no error.
    //
    //   IOX READ  504 -> 060000     power-on: not finished, on cylinder
    //   IOX WRITE 505 =  034005     M7 return-to-zero (older capture only)
    //   IOX READ  504 -> 060005     active, on cylinder
    //   IOX READ  504 -> 060011     finished, on cylinder
    //   IOX WRITE 507 =  000000     word count cleared
    //   IOX WRITE 503 =  000000     block address C/H/S 0/0/0
    //   IOX WRITE 501 =  000000     memory address HI
    //   IOX WRITE 501 =  061100     memory address LO
    //   IOX WRITE 507 =  002000     word count 1024
    //   IOX WRITE 505 =  000005     M0 read, activate, int enable
    //   IOX READ  504 -> 060011     finished
    //   IOX READ  500 -> 063100     memory address advanced by 002000
    //
    // EVERY existing Winchester bench jumps straight to a read. NONE of them
    // issues M7 first - and M7 is what puts the drive ON CYLINDER. That is
    // the bit the failing silicon status (020010 = finished, NOT on cylinder,
    // no error bits) says never got set.
    iox_read(16'o504);
    if (rdlat !== 16'o060000) begin
      $display("FAIL: power-on status %06o, oracle says 060000", rdlat);
      errors = errors + 1;
    end

    // M7 return-to-zero
    iox_write(16'o505, 16'o034005);
    wait_finished("M7 return-to-zero");
    if (!st[14]) begin
      $display("FAIL: M7 completed but NOT on cylinder (status %06o) - this is", st);
      $display("      the silicon symptom: SINTRAN reads b14=0 and calls it a");
      $display("      Winchester disk read error");
      errors = errors + 1;
    end
    if (st[4]) begin
      $display("FAIL: M7 reported an error, status %06o", st);
      errors = errors + 1;
    end

    // the driver's first data read, register order and values verbatim
    for (i = 0; i < 1024; i = i + 1) dmamem[16'o61100 + i] = 16'hFFFF;
    dma_writes = 0;
    iox_write(16'o507, 16'o000000);
    iox_write(16'o503, 16'o000000);
    iox_write(16'o501, 16'o000000);
    iox_write(16'o501, 16'o061100);
    iox_write(16'o507, 16'o002000);
    iox_write(16'o505, 16'o000005);
    wait_finished("FSI first read");
    if (st[4] || !st[14]) begin
      $display("FAIL: FSI first read status %06o (want b3+b13+b14, no b4)", st);
      errors = errors + 1;
    end
    if (dma_writes !== 1024) begin
      $display("FAIL: FSI first read moved %0d DMA words, want 1024", dma_writes);
      errors = errors + 1;
    end
    check_words(16'o61100, 0, 1024, "FSI first read");

    // ---- 0b. THE COMPLETION INTERRUPT ----------------------------------
    // The read above was activated with control word 000005: bit 0 = the
    // controller-not-active interrupt enable. Section 4.1 makes the level-11
    // line the AND of "ready" and "enabled", so once the transfer has
    // finished the line MUST be up - that pulse is the only thing telling
    // SINTRAN the transfer is over.
    if (int_pending !== 4'b0010) begin
      $display("FAIL: no level-11 interrupt after a completed read (int_pending=%b)",
               int_pending);
      $display("      SINTRAN waits on this line; without it the transfer looks");
      $display("      to the driver exactly like a disc error");
      errors = errors + 1;
    end

    // IDENT on level 11 with the grant must answer with the card's code and
    // drop the line; a card that answers but never drops it wedges the level.
    @(posedge sysclk);
    ident_level    <= 4'd11;
    ident_grant_in <= 1'b1;
    ident_strobe   <= 1'b1;
    @(posedge sysclk);
    if (!ident_hit) begin
      $display("FAIL: IDENT level 11 not answered while the interrupt is up");
      errors = errors + 1;
    end
    if (ident_code !== 16'o1) begin
      $display("FAIL: IDENT code %06o, want 000001", ident_code);
      errors = errors + 1;
    end
    if (ident_grant_out !== 1'b0) begin
      $display("FAIL: card answered IDENT but still passed the grant on");
      errors = errors + 1;
    end
    @(posedge sysclk);
    ident_strobe   <= 1'b0;
    ident_grant_in <= 1'b0;
    repeat (4) @(posedge sysclk);
    if (int_pending !== 4'd0) begin
      $display("FAIL: interrupt line still up after IDENT (int_pending=%b)",
               int_pending);
      errors = errors + 1;
    end
    iox_read(16'o500); ma_lo = rdlat;
    iox_read(16'o500); ma_hi = rdlat;
    if (ma_lo !== 16'o063100 || ma_hi !== 16'd0) begin
      $display("FAIL: FSI memory address %06o/%06o, oracle says 063100/000000",
               ma_lo, ma_hi);
      errors = errors + 1;
    end

    // ---- 1. cold transfer: C/H/S 0/0/0, 1024 words to 010000 -----------
    // 1024 words = 2048 bytes = exactly one storage block, so this is a
    // single cold cache MISS: lookup, four card sectors, region fill, tag
    // publish, then serve. The failing silicon run was this command.
    dma_writes = 0;
    do_transfer(16'd0, 16'o10000, 16'd1024, "cold blk0");
    w1_writes = dma_writes;
    if (st[4] || st[9] || st[10] || st[11] || st[8]) begin
      $display("FAIL: cold read reported errors, status %06o", st);
      errors = errors + 1;
    end
    if (w1_writes !== 1024) begin
      $display("FAIL: cold read moved %0d DMA words, want 1024", w1_writes);
      errors = errors + 1;
    end
    check_words(16'o10000, 0, 1024, "cold blk0");

    // ---- 2. the memory address register advanced by the word count -----
    iox_read(16'o500); ma_lo = rdlat;
    iox_read(16'o500); ma_hi = rdlat;
    if (ma_lo !== 16'o12000 || ma_hi !== 16'd0) begin
      $display("FAIL: memory address after transfer = %06o/%06o, want 012000/000000",
               ma_lo, ma_hi);
      errors = errors + 1;
    end

    // ---- 3. same block again: now a cache HIT --------------------------
    // The silicon report was "sometimes it works the second time". A HIT
    // must deliver the SAME bytes; a HIT on a line that was never filled
    // would deliver zeros, and poisoning the target makes that visible.
    for (i = 0; i < 1024; i = i + 1) dmamem[16'o20000 + i] = 16'hFFFF;
    dma_writes = 0;
    do_transfer(16'd0, 16'o20000, 16'd1024, "warm blk0");
    if (st[4]) begin
      $display("FAIL: warm read reported error, status %06o", st);
      errors = errors + 1;
    end
    check_words(16'o20000, 0, 1024, "warm blk0");

    // ---- 4. a block further into the file ------------------------------
    // C/H/S 0/0/4 = LBA 4 = word 2048 = storage block 2. Past the first
    // cluster of the image, so the FAT walk has to be right; block 0 alone
    // can pass with a completely broken chain resolve.
    for (i = 0; i < 1024; i = i + 1) dmamem[16'o30000 + i] = 16'hFFFF;
    dma_writes = 0;
    do_transfer(16'd4, 16'o30000, 16'd1024, "blk2 via CHS 0/0/4");
    if (st[4]) begin
      $display("FAIL: deep read reported error, status %06o", st);
      errors = errors + 1;
    end
    check_words(16'o30000, 4096, 1024, "blk2 via CHS 0/0/4");

    // ---- 5. MULTI-BLOCK read: 2048 words = TWO storage blocks ----------
    // Everything above this point transfers exactly 1024 words - ONE block -
    // and so did every silicon run that has ever been called working. A
    // segment is many blocks, and SINTRAN's segment handling is the first
    // thing on this machine to ask for more than one block in a single
    // command: on 10-AUG-2026 the disc booted, ran, and then failed with
    // "DISC TRANSFER ERROR IN SEGMENT HANDLING". A multi-block transfer
    // drives the adapter's chunking (s_seg/s_idx/s_wc walking the window
    // across several storage blocks) which a 1024-word command never enters.
    for (i = 0; i < 2048; i = i + 1) dmamem[16'o40000 + i] = 16'hFFFF;
    dma_writes = 0;
    do_transfer(16'd0, 16'o40000, 16'd2048, "multiblock read 2048w");
    if (st[4] || st[9] || st[10] || st[11] || st[8]) begin
      $display("FAIL: 2048-word read reported errors, status %06o", st);
      errors = errors + 1;
    end
    if (dma_writes !== 2048) begin
      $display("FAIL: 2048-word read moved %0d DMA words, want 2048",
               dma_writes);
      errors = errors + 1;
    end
    check_words(16'o40000, 0, 2048, "multiblock read 2048w");

    // ---- 6. MULTI-BLOCK read: 4096 words = FOUR storage blocks ---------
    // Two blocks can pass with an off-by-one that only bites on the third.
    for (i = 0; i < 4096; i = i + 1) dmamem[16'o50000 + i] = 16'hFFFF;
    dma_writes = 0;
    do_transfer(16'd0, 16'o50000, 16'd4096, "multiblock read 4096w");
    if (st[4]) begin
      $display("FAIL: 4096-word read reported error, status %06o", st);
      errors = errors + 1;
    end
    if (dma_writes !== 4096) begin
      $display("FAIL: 4096-word read moved %0d DMA words, want 4096",
               dma_writes);
      errors = errors + 1;
    end
    check_words(16'o50000, 0, 4096, "multiblock read 4096w");

    // ---- 7. MULTI-BLOCK read NOT starting at block 0 -------------------
    // blkaddr counts 1024-byte units (case 4: blkaddr 4 = byte 4096), so
    // blkaddr 4 with 2048 words spans bytes 4096..8191 - two blocks, both
    // past the first, so the chain walk must be right for BOTH.
    for (i = 0; i < 2048; i = i + 1) dmamem[16'o60000 + i] = 16'hFFFF;
    dma_writes = 0;
    do_transfer(16'd4, 16'o60000, 16'd2048, "multiblock read from blk2");
    if (st[4]) begin
      $display("FAIL: offset multiblock read error, status %06o", st);
      errors = errors + 1;
    end
    check_words(16'o60000, 4096, 2048, "multiblock read from blk2");

    // ---- 8. MULTI-BLOCK WRITE, then read it back -----------------------
    // The other half of segment handling: it is the swapper, so it WRITES.
    // Nothing in this tree has ever driven the Winchester write path from a
    // guest command - the adapter accepts only whole aligned 1024-word
    // blocks, and that rule has never met a real driver. Writes go to bytes
    // 8192..12287 (blkaddr 8, two blocks), which is inside the 16384-byte
    // image. Writes land at blkaddr 4 = bytes 4096..8191, inside cylinder 0
    // head 0, and the read cases above have already verified that span BEFORE
    // it is overwritten.
    // ADDRESSING, because getting this wrong looks exactly like an RTL bug:
    // the block-address register is CHS-PACKED, not a linear block number.
    // ND_WINCHESTER.v:213-214 splits it as [15:5] cylinder, [4:0] sector,
    // and the head comes from the control word. With GEO_SPT = 9 the only
    // valid sectors are 0..8, so blkaddr 12 is sector 12 on a 9-sector track
    // and the card correctly answers ADDRESS MISMATCH (status bit 8) with no
    // transfer. LBA = (cyl*HEADS + head)*SPT + sector, and one sector here is
    // 1024 BYTES, so inside cylinder 0 head 0 the addressable span is
    // blkaddr 0..8 = bytes 0..9215. Every write below stays inside it; going
    // past sector 8 needs a head change, which these cases deliberately do
    // not exercise.
    //
    // 8a first: ONE block. If a single-block write already fails then the
    // fault is the write path itself, not the chunking, and the multi-block
    // result below would be a misleading place to start looking.
    for (i = 0; i < 1024; i = i + 1)
      dmamem[16'o64000 + i] = 16'hA000 | i[13:0];
    dma_writes = 0;
    dma_reads  = 0;
    do_write(16'd4, 16'o64000, 16'd1024, "single-block write 1024w");
    if (st[4]) begin
      $display("FAIL: 1024-word write reported error, status %06o", st);
      errors = errors + 1;
    end
    // Split the write into its two halves so the failure names itself:
    // host memory -> the controller's own s_buffer (the DMA read side), then
    // s_buffer -> the adapter -> staging -> card. Printing the controller
    // buffer after the command says which half lost the payload.
    // Split the write into its two halves so a future failure names itself:
    // host memory -> the controller's own s_buffer (the DMA side), and then
    // s_buffer -> adapter -> staging -> card. When buf_rdata_w was missing the
    // Winchester slice, THIS check passed and the read-back below failed,
    // which is what located the fault to the second half in one run.
    for (i = 0; i < 4; i = i + 1) begin
      if (dut.s_buffer[i] !== (16'hA000 | i[13:0])) begin
        $display("FAIL: DMA half: controller s_buffer[%0d] = %06o, want %06o",
                 i, dut.s_buffer[i], (16'hA000 | i[13:0]));
        errors = errors + 1;
      end
    end
    if (dma_reads !== 1024) begin
      $display("FAIL: 1024-word write fetched %0d DMA words, want 1024",
               dma_reads);
      errors = errors + 1;
    end
    for (i = 0; i < 1024; i = i + 1) dmamem[16'o66000 + i] = 16'hFFFF;
    do_transfer(16'd4, 16'o66000, 16'd1024, "read back 1-block write");
    for (i = 0; i < 1024; i = i + 1) begin
      if (dmamem[16'o66000 + i] !== (16'hA000 | i[13:0])) begin
        if (errors < 4)
          $display("FAIL: 1-BLOCK write read-back word %0d: got %06o want %06o",
                   i, dmamem[16'o66000 + i], (16'hA000 | i[13:0]));
        errors = errors + 1;
      end
    end

    for (i = 0; i < 2048; i = i + 1)
      dmamem[16'o70000 + i] = 16'hC000 | i[13:0];   // position-dependent
    dma_writes = 0;
    dma_reads  = 0;
    do_write(16'd4, 16'o70000, 16'd2048, "multiblock write 2048w");
    if (st[4] || st[9] || st[10] || st[11] || st[8]) begin
      $display("FAIL: 2048-word write reported errors, status %06o", st);
      errors = errors + 1;
    end
    if (dma_reads !== 2048) begin
      $display("FAIL: write fetched %0d DMA words from memory, want 2048",
               dma_reads);
      errors = errors + 1;
    end

    // read it back into fresh, poisoned memory and compare with what was
    // written - NOT with the image pattern, which those blocks no longer hold
    for (i = 0; i < 2048; i = i + 1) dmamem[16'o100000 + i] = 16'hFFFF;
    dma_writes = 0;
    do_transfer(16'd4, 16'o100000, 16'd2048, "read back written blocks");
    if (st[4]) begin
      $display("FAIL: read-back reported error, status %06o", st);
      errors = errors + 1;
    end
    for (i = 0; i < 2048; i = i + 1) begin
      if (dmamem[16'o100000 + i] !== (16'hC000 | i[13:0])) begin
        if (errors < 12)
          $display("FAIL: read-back word %0d: got %06o want %06o", i,
                   dmamem[16'o100000 + i], (16'hC000 | i[13:0]));
        errors = errors + 1;
      end
    end
    if (errors == 0)
      $display("[ ok ] multi-block read and write, 1-4 blocks per command");

    // ---- 9. MULTI-BLOCK read ACROSS THE TRACK BOUNDARY -----------------
    // Everything above stays inside cylinder 0 head 0, where sectors run 0..8
    // (GEO_SPT = 9). A real transfer of any size crosses that: sector 8 is
    // followed by head 1 sector 0, not by sector 9. SINTRAN's segment
    // handling reads many blocks at once and must cross it constantly, and
    // on silicon the boot dies with "DISC TRANSFER ERROR IN SEGMENT
    // HANDLING" - so the rollover is the first thing to prove.
    //
    // blkaddr 8 with 1024 words spans bytes 8192..10239: sector 8, the LAST
    // sector of cylinder 0 head 0, followed by the first sector of the next
    // track. That is the rollover, in one command.
    //
    // It must also avoid bytes 4096..8191, which the write cases above
    // deliberately overwrote - reading those back and comparing against the
    // ORIGINAL image pattern fails on correct data. That mistake was made
    // once here already.
    for (i = 0; i < 1024; i = i + 1) dmamem[16'o110000 + i] = 16'hFFFF;
    dma_writes = 0;
    do_transfer(16'd8, 16'o110000, 16'd1024, "read across track boundary");
    if (st[4] || st[8]) begin
      $display("FAIL: track-crossing read reported error, status %06o", st);
      $display("      (bit 8 = address mismatch: the CHS advance refused to");
      $display("       roll sector 8 -> head 1 sector 0)");
      errors = errors + 1;
    end
    if (dma_writes !== 1024) begin
      $display("FAIL: track-crossing read moved %0d DMA words, want 1024",
               dma_writes);
      errors = errors + 1;
    end
    check_words(16'o110000, 8192, 1024, "read across track boundary");

    // ---- 10. SUB-BLOCK WRITE: 512 words, half a storage block -----------
    // THE CASE THAT KILLS THE SINTRAN BOOT (silicon trace, 10-AUG-2026):
    //
    //   WRITE +7 word count    = 001000   (512 words)
    //   WRITE +5 control word  = 004045   (M1 write, GO)
    //   READ  +4 status        -> 021030  (b9 + b4: refused)
    //
    // 512 words = 1024 bytes = one ND page = EXACTLY ONE WINCHESTER SECTOR.
    // That is the natural write unit for this card. The storage layer's block
    // is 2048 bytes, and the adapter accepted only a full aligned 1024-word
    // block, so every write SINTRAN issues is refused before it reaches the
    // data path - which is also why fixing the buf_rdata slice changed
    // nothing about the boot: writes never got that far.
    //
    // Serving this needs READ-MODIFY-WRITE. The half that is NOT written must
    // survive, and that is the real risk: an implementation that fetches
    // nothing and writes a half-filled block passes "did my data land" while
    // silently destroying 1024 bytes on every write.
    //
    // blkaddr 3 = byte 3072 = the SECOND half of storage block 1 (bytes
    // 2048..4095). Block 1 is untouched by every case above, so the first
    // half must still equal the image.
    for (i = 0; i < 512; i = i + 1)
      dmamem[16'o120000 + i] = 16'h5000 | i[13:0];
    dma_reads = 0;
    do_write(16'd3, 16'o120000, 16'd512, "sub-block write 512w");
    if (st[4]) begin
      $display("FAIL: 512-word write refused, status %06o", st);
      $display("      b9+b4 = the adapter's full-aligned-block rule; SINTRAN");
      $display("      writes one 1024-byte sector and cannot satisfy it");
      errors = errors + 1;
    end

    // read the WHOLE block back and check BOTH halves
    for (i = 0; i < 1024; i = i + 1) dmamem[16'o122000 + i] = 16'hFFFF;
    do_transfer(16'd2, 16'o122000, 16'd1024, "read back sub-block write");
    for (i = 0; i < 512; i = i + 1) begin
      if (dmamem[16'o122000 + i] !== {pat_wd(2048 + 2*i), pat_wd(2048 + 2*i + 1)}) begin
        if (errors < 16)
          $display("FAIL: UNTOUCHED half word %0d destroyed: got %06o want %06o",
                   i, dmamem[16'o122000 + i],
                   {pat_wd(2048 + 2*i), pat_wd(2048 + 2*i + 1)});
        errors = errors + 1;
      end
    end
    for (i = 0; i < 512; i = i + 1) begin
      if (dmamem[16'o122000 + 512 + i] !== (16'h5000 | i[13:0])) begin
        if (errors < 20)
          $display("FAIL: written half word %0d: got %06o want %06o", i,
                   dmamem[16'o122000 + 512 + i], (16'h5000 | i[13:0]));
        errors = errors + 1;
      end
    end

    $display("");
    if (errors == 0) $display("TB_RESULT: PASS");
    else             $display("TB_RESULT: FAIL %0d errors", errors);
    $finish;
  end

  // absolute backstop
  initial begin
    #4_000_000_000;
    $display("TB_RESULT: FAIL global timeout");
    $finish;
  end

endmodule
