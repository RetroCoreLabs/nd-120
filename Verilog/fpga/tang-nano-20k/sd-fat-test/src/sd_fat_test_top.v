/****************************************************************************
** Tang Nano 20K SD + FAT test (Milestone 1 of the SD-BPUN device plan)    **
**                                                                         **
** Interactive UART menu (BL616 USB serial, 9600 8N1) over the reusable    **
** SD/FAT library in Verilog/SD-FAT/:                                      **
**                                                                         **
**   SD: OK                     (persistent card status)                   **
**   1=LIST 2=DUMP BOOT.BPUN 3=COPY TO TEST.TXT H=HELP                     **
**   #                                                                     **
**                                                                         **
**   1  re-init the card, mount FAT16/FAT32, list the root directory:      **
**      size (or <DIR>), date and name of every file and subdirectory      **
**             2342  10-JAN-2025  BOOT.BPUN                                **
**            <DIR>  11-JUL-2026  HDD                                      **
**      then a disk-info line: card capacity (from the CMD9 CSD), volume   **
**      size (total sectors) and free space (one FAT #0 scan counting      **
**      free entries; a SCANNING line is printed first - a 32 GB card      **
**      takes seconds):                                                    **
**             CARD 30436 MB  VOL 30425 MB  FREE 30298 MB                  **
**   2  find BOOT.BPUN, buffer it (64 KB BRAM) and hex/octal-dump it       **
**   3  COPY: read BOOT.BPUN into the buffer, then make TEST.TXT an exact **
**      copy. If TEST.TXT's allocation is big enough its data sectors are  **
**      rewritten in place and only the size field is patched; if it is    **
**      TOO SMALL (or empty) it is REPLACED: sd_fat_rewrite frees the old  **
**      cluster chain, allocates a fresh contiguous chain and patches the  **
**      directory entry, then the data is written. TEST.TXT must already   **
**      exist on the card (any size).                                      **
**   4  WRBLK1: write a counter pattern (1024 big-endian 16-bit words,     **
**      word[w] = w) into 1-kiloword block 1 of BOOT.BPUN. ND-120 block    **
**      framing: 1 block = 1024 words = 2048 bytes = 4 SD sectors; block   **
**      N of a file lives at file_first_sector + 4*N. Refuses when the     **
**      file is smaller than (N+1)*2048 bytes (a shorter file's cluster    **
**      chain ends inside the block - writing there would corrupt the      **
**      NEXT file). Validate with 2 (DUMP): block 1 shows the pattern,     **
**      blocks 0 and 2 are untouched.                                      **
**   8  BLOCK: dump 1-kiloword block N of the target file WITHOUT          **
**      buffering the file. The reader runs with no_stream=1 (directory    **
**      match only), the 4 sectors of the block are read one at a time     **
**      through the sd_writer engine's READ path and dumped. Cost and      **
**      memory are the same for a 7 KB file and a 75 MB one - which is the **
**      point: command 2 cannot look at anything past its 64 KB buffer.    **
**      The block number is typed on the console in decimal.               **
**   9  SECTOR: dump one ABSOLUTE SD sector, number typed in decimal, with **
**      the FAT not consulted at all. This is what separates "the          **
**      directory entry points at the wrong place" from "the card really   **
**      holds zeros there" - the two look identical through command 2.     **
**   R  RANGE: read a run of consecutive blocks (start block and count     **
**      typed on the console) the same streaming way, keeping only a       **
**      16-bit checksum of every word and a block count - the data never   **
**      reaches the console, because a 1000-block hex dump at 9600 baud    **
**      would take about six hours. One progress line per 64 blocks, then  **
**      a summary: blocks, sectors, checksum, 27 MHz cycles of card        **
**      traffic, PASS or FAIL. A failed card read stops the run and names  **
**      the exact sector and block - that is what this command is for:     **
**      every earlier check read a SINGLE block, and SINTRAN segment       **
**      handling is the first thing that reads many in a row.              **
**   N  set the target file name at runtime (root directory only, 8.3      **
**      name, length-exact - that is all sd_file_reader can match)         **
**   H  detailed help; any other key reprints the menu                     **
**   S1 / S2 (either button) full reset                                    **
**                                                                         **
** DEFAULT BUILD IS READ-ONLY (src/sd_fat_test_config.vh): 3, 4, 6 are     **
** compiled out and the sd_writer engine's rd_mode is tied to a constant   **
** 1. A write-capable bitstream must never be pointed at a card that is    **
** being diagnosed.                                                        **
**                                                                         **
** Robustness: every wait state has a watchdog - no card, no file,         **
** unmountable filesystem, stuck reads and failed writes all print an      **
** ERROR line and fall back to the menu; the menu SD: line shows           **
** NOT CHECKED / NO CARD / ERROR / OK.                                     **
**                                                                         **
** SD pins per the Sipeed Tang Nano 20K schematic (verified against       **
** sipeed/TangNano-20K-example, nestang and snestang constraint files):    **
** CLK=83 CMD=82 DAT0=84 DAT1=85 DAT2=80 DAT3=81. CMD and DAT0-3 are       **
** bidirectional per the SD specification; the ONLY tristate drivers sit   **
** here at the top-level pads (repo rule: no 'z' inside the FPGA fabric).  **
**                                                                         **
** LEDs (active low): [0] alive  [1] FS mounted  [2] file found            **
**                    [3] command done  [4] truncated  [5] error           **
**                                                                         **
** Single 27 MHz clock domain - no PLL, no derived clocks (the SD          **
** library and sd_writer divide their bus clocks with enable-style         **
** dividers). Reader CLK_DIV=1 (init 137 kHz - inside the spec's           **
** 100-400 kHz identification band - data 3.375 MHz); writer CLKDIV=1      **
** (13.5 MHz bit clock, inside the mandatory 25 MHz default-speed limit).  **
**                                                                         **
** Speed tests: menu 6 writes IO.DAT in CMD25 multi-block bursts (ACMD23   **
** pre-erase + up to 128 sectors per burst + CMD12), menu 7 reads it back  **
** in CMD18 bursts through the same MIT engine - the file reader only      **
** mounts the filesystem and locates the file. With USE_4BIT=1 (default,   **
** speed-plan rung c) every writer-engine operation switches the card to   **
** the 4-bit DAT bus via CMD55+ACMD6 and moves data on DAT3..DAT0; the     **
** reader keeps its proven 1-bit path for mount/locate.                    **
**                                                                         **
** Design plan: Verilog/docs/sd-bpun-device-plan.md (section 9).           **
**                                                                         **
** Last reviewed: 11-JUL-2026                                              **
** Ronny Hansen                                                            **
*****************************************************************************/

`include "sd_fat_test_config.vh"
`include "sd_fat_features.vh"

module sd_fat_test_top #(
    parameter            CLK_FREQ      = 27_000_000,   // crystal, used directly
    parameter            BAUD          = 9600,
    parameter            SIMULATE      = 0,            // 1: shorter SD init (sim only)
    parameter [31:0]     WD_MAX        = 270_000_000,  // watchdog: 10 s at 27 MHz
    parameter            FILE_NAME_LEN = 9,
    parameter [52*8-1:0] FILE_NAME     = "BOOT.BPUN",
    parameter            FILE2_LEN     = 8,
    parameter [52*8-1:0] FILE2_NAME    = "TEST.TXT",   // COPY target (pre-created)
    parameter            FILE3_LEN     = 6,
    parameter [52*8-1:0] FILE3_NAME    = "IO.DAT",     // speed-test file (pre-created)
    parameter            IO_BLOCKS     = 1000,         // speed test: 1KW blocks
    parameter [87:0]     FILE2_83      = "TEST    TXT", // 8.3 form for creation
    parameter [87:0]     FILE3_83      = "IO      DAT",
    parameter [15:0]     FDATE         = 16'h5CEB,      // 11-JUL-2026 (create stamp)
    parameter            BUF_AW        = 16,           // 2^16 = 64 KB buffer
    // USE_4BIT - SD bus width for ALL bulk data through the sd_writer
    // engine (speed tests, CHECK/COPY/WRBLK1 FAT + payload traffic):
    //   1 = DAT0..DAT3, four data wires: ~4x throughput (sim: 5.9 MB/s
    //       write / 6.4 MB/s read). THE production / full-speed setting.
    //       Each operation switches the card via CMD55+ACMD6 first, so
    //       the reader's card re-inits between commands are harmless.
    //   0 = DAT0 only (sim: ~1.6 MB/s). For diagnosis, or boards where
    //       only DAT0 is wired. Commands/CRC-status/busy are on their
    //       single lines in BOTH modes; the FAT mount/scan path
    //       (sd_file_reader) always runs 1-bit regardless.
    // Full story: README.md "USE_4BIT" + Verilog/docs/sd-cmd18-block-gap-research.md.
    parameter            USE_4BIT      = 1             // full speed. (11-JUL "all BAD" incident: 1-bit isolation build proved card+logic healthy; suspect was the snooped RCA, now taken from the reader's card_rca export)
) (
    input  sys_clk,   // 27 MHz crystal
    input  s1,        // S1 push button - full reset
    input  s2,        // S2 push button - full reset (same, for convenience)
    input  uart_rxp,  // from BL616 USB serial
    output uart_txp,  // to BL616 USB serial

    // microSD slot, SD-native mode; the reader runs 1-bit, the writer
    // engine switches to 4-bit per operation when USE_4BIT=1 (rung c)
    output sd_clk,
    inout  sd_cmd,    // bidirectional: host commands / card responses
    inout  sd_dat0,   // bidirectional: card read data / host write data
    inout  sd_dat1,   // bidirectional in 4-bit mode (parked high otherwise)
    inout  sd_dat2,
    inout  sd_dat3,

    output [5:0] led  // active low

`ifdef SDFAT_EXT_TEST
    // External test commands (Nexys 4 DDR memory tests). Gated: builds that
    // do not define SDFAT_EXT_TEST are byte-identical to before. The external
    // module runs a self-contained test and prints through this design's UART.
    ,
    output reg       ext_start,     // 1-cycle pulse: run test ext_id
    output reg [3:0] ext_id,        // 0 = DDR2, 1 = ND-120 memory path (BRAM)
    input  wire      ext_busy,      // high while the external test runs
    input  wire [7:0] ext_tx_data,  // its character stream...
    input  wire      ext_tx_valid,  // ...with the same handshake as the others
    output wire      ext_tx_busy    // the shared UART's busy flag
`endif
);

  localparam DELAY_FRAMES = CLK_FREQ / BAUD;

  wire clk = sys_clk;  // single 27 MHz domain, no PLL

  /*******************************************************************************
   ** Reset: power-on counter, reloaded by S1 = full restart                     **
   *******************************************************************************/
  reg s1_r1, s1_r2, s1_r3, s2_r1, s2_r2, s2_r3;
  always @(posedge clk) begin
    s1_r1 <= s1;
    s1_r2 <= s1_r1;
    s1_r3 <= s1_r2;
    s2_r1 <= s2;
    s2_r2 <= s2_r1;
    s2_r3 <= s2_r2;
  end
  wire btn_press = (s1_r2 & ~s1_r3) | (s2_r2 & ~s2_r3);

  reg [10:0] rst_cnt = 0;
  wire sys_rst_n = rst_cnt[10];

  always @(posedge clk) begin
    if (btn_press) rst_cnt <= 0;
    else if (!rst_cnt[10]) rst_cnt <= rst_cnt + 1;
  end

  // The SD reader is held in reset between commands; each menu command
  // releases it for a full init+mount+scan run (= the future tape rewind).
  // COPY resets it a second time (rdrst_cnt) to re-scan for TEST.TXT, and
  // parks it (phase_write) while the sd_writer owns the card.
  reg       cmd_running;
  reg [4:0] rdrst_cnt;
  reg       phase_write;
  wire sd_rst_n = sys_rst_n & cmd_running & (rdrst_cnt == 0) & ~phase_write;

  /*******************************************************************************
   ** Command mode and runtime target file name                                 **
   *******************************************************************************/
  localparam M_DUMP = 4'd0;
  localparam M_LIST = 4'd1;
  localparam M_COPY = 4'd2;
  localparam M_BLK  = 4'd3;  // write the test pattern into 1KW block 1
  localparam M_CHK  = 4'd4;  // validate every root file's cluster chain
  localparam M_IOW  = 4'd5;  // write speed test (rewrites IO.DAT)
  localparam M_IOR  = 4'd6;  // read speed test (streams IO.DAT)
  localparam M_BDMP = 4'd7;  // dump 1KW block N of the file, nothing buffered
  localparam M_SDMP = 4'd8;  // dump one absolute SD sector, FAT bypassed
  localparam M_RDMP = 4'd9;  // read a RANGE of blocks, checksum only

  localparam [31:0] IO_BYTES = IO_BLOCKS * 32'd2048;
  localparam [12:0] IO_SECT  = IO_BLOCKS * 13'd4;
  // KB/s numerator: KB * clock frequency (40-bit: 2000 * 27e6 overflows 32)
  localparam [39:0] SPEED_NUM = 40'd2 * IO_BLOCKS * CLK_FREQ;

  localparam [8:0] BLK_NO = 9'd1;  // the block the menu command updates

  reg [3:0] mode;
  reg       copy_phase;  // COPY: 0 = read BOOT.BPUN, 1 = locate TEST.TXT
  reg       list_done;   // LIST: listing captured - the reader's automatic
                         // restart after the free scan must not append again
  wire      mode_list = (mode == M_LIST);

  wire [52*8-1:0] tgt_boot, tgt_test, tgt_io;
  generate
    genvar tk;
    for (tk = 0; tk < 52; tk = tk + 1) begin : g_target_names
      assign tgt_boot[8*tk+:8] =
          (tk < FILE_NAME_LEN) ? FILE_NAME[8*(FILE_NAME_LEN-1-tk)+:8] : 8'h00;
      assign tgt_test[8*tk+:8] =
          (tk < FILE2_LEN) ? FILE2_NAME[8*(FILE2_LEN-1-tk)+:8] : 8'h00;
      assign tgt_io[8*tk+:8] =
          (tk < FILE3_LEN) ? FILE3_NAME[8*(FILE3_LEN-1-tk)+:8] : 8'h00;
    end
  endgenerate

  // ---- runtime target file name (menu key N) ------------------------------
  // Typed on the console; empty (rt_len = 0, the state after reset) means the
  // compile-time FILE_NAME parameter is used, so nothing changes for an
  // operator who never presses N. sd_file_reader matches ROOT-DIRECTORY
  // entries only and compares the name LENGTH-EXACTLY (case-insensitively),
  // which is why the help text spells that out.
  reg [52*8-1:0] rt_name;
  reg [7:0]      rt_len;
  wire           rt_use = (rt_len != 8'd0);

  wire copy2 = (mode == M_COPY) && copy_phase;
  wire io_mode = (mode == M_IOW) || (mode == M_IOR);
  // block dump (8), sector dump (9) and the range read (R): nothing is
  // buffered, so all three are "streaming" modes as far as the buffer, the
  // engine direction and the error texts are concerned
  wire dump_mode = (mode == M_BDMP) || (mode == M_SDMP) || (mode == M_RDMP);
  wire [52*8-1:0] target_name = io_mode ? tgt_io : copy2 ? tgt_test
                              : rt_use ? rt_name : tgt_boot;
  // the absolute-sector dump never looks at a file: target_len 0 = scan only
  wire scan_only = mode_list || (mode == M_CHK) || (mode == M_SDMP);
  wire [7:0] target_len = scan_only ? 8'd0
                        : io_mode ? FILE3_LEN[7:0]
                        : copy2 ? FILE2_LEN[7:0]
                        : rt_use ? rt_len : FILE_NAME_LEN[7:0];
  // BLOCK: stop at the directory match. Reading a 75 MB file into a 64 KB
  // buffer only to look at 2 KB of it is what this command exists to avoid,
  // and no_stream also ends the reader's run at a clean card boundary.
  wire no_stream = (mode == M_BDMP) || (mode == M_RDMP);

  /*******************************************************************************
   ** SD card + FAT filesystem library (Verilog/SD-FAT/, board-independent)     **
   *******************************************************************************/
  wire        rd_sdclk;
  wire        rd_cmd_o, rd_cmd_oe;
  wire [3:0]  card_stat;
  wire [1:0]  card_type;
  wire [1:0]  fs_type;
  wire        file_found;
  wire        f_outen;
  wire [7:0]  f_outbyte;
  wire        scan_done;
  wire [31:0] file_size;
  wire        dir_valid;
  wire [52*8-1:0] dir_name;
  wire [7:0]  dir_len;
  wire [31:0] dir_size;
  wire [15:0] dir_date;
  wire [31:0] dir_cluster;
  wire        dir_isdir;
  wire [31:0] file_first_sector;
  wire [7:0]  fs_cs;
  wire [31:0] fs_fat0, fs_spf, fs_dbase, fs_total, fs_rootclus;
  wire [7:0]  fs_nfat;
  wire [31:0] fnd_dir_sec;
  wire [3:0]  fnd_dir_idx;
  wire [31:0] fnd_cluster;
  wire [31:0] rd_cap_mb;  // card capacity from the CMD9 CSD (0 = unknown)
  wire [15:0] rd_rca;     // CMD3-published RCA

  sd_file_reader #(
      .CLK_DIV (3'd1),      // 27 MHz: init 137 kHz (spec 100-400 kHz), data 3.375 MHz
      .SIMULATE(SIMULATE)
  ) u_sd (
      .rstn           (sd_rst_n),
      .clk            (clk),
      .sdclk          (rd_sdclk),
      .sdcmd_i        (sd_cmd),
      .sdcmd_o        (rd_cmd_o),
      .sdcmd_oe       (rd_cmd_oe),
      .sddat0         (sd_dat0),
      .card_stat      (card_stat),
      .card_type      (card_type),
      .filesystem_type(fs_type),
      .file_found     (file_found),
      .outen          (f_outen),
      .outbyte        (f_outbyte),
      .scan_done      (scan_done),
      .found_file_size(file_size),
      .target_name    (target_name),
      .no_stream      (no_stream),
      .target_len     (target_len),
      .dir_entry_valid(dir_valid),
      .dir_entry_name (dir_name),
      .dir_entry_len  (dir_len),
      .dir_entry_size (dir_size),
      .dir_entry_date (dir_date),
      .dir_entry_cluster(dir_cluster),
      .dir_entry_is_dir(dir_isdir),
      .found_file_first_sector(file_first_sector),
      .fs_cluster_size(fs_cs),
      .fs_fat0_sector(fs_fat0),
      .fs_sectors_per_fat(fs_spf),
      .fs_num_fats(fs_nfat),
      .fs_data_base_sector(fs_dbase),
      .fs_total_sectors(fs_total),
      .fs_root_cluster(fs_rootclus),
      .found_dir_entry_sector(fnd_dir_sec),
      .found_dir_entry_index(fnd_dir_idx),
      .found_file_cluster(fnd_cluster),
      .card_capacity_mb(rd_cap_mb),
      .card_rca       (rd_rca)
  );

  // card init done = sector-read FSM reached its CMD17 idle state (8) or beyond
  wire card_ready = (card_stat >= 4'd8);

  /*******************************************************************************
   ** RCA hold: the burst writer needs the CMD3-assigned RCA for CMD55 (the    **
   ** ACMD23/ACMD6 prefixes), but the reader that owns it is parked - reset -  **
   ** while the writer runs (phase_write). Track the reader's exported RCA     **
   ** while it is live and hold the last good value through the parking.       **
   ** (This replaces the old CMD-line response snoop: with CMD9's 136-bit R2   **
   ** now following CMD3, a bit pattern inside the CSD could have retriggered  **
   ** the snoop and corrupted the captured RCA.)                               **
   *******************************************************************************/
  reg [15:0] card_rca;

  always @(posedge clk) begin
    if (!sys_rst_n) card_rca <= 16'h0000;
    else if (card_ready) card_rca <= rd_rca;
  end

  /*******************************************************************************
   ** SD sector writer (project code, MIT) - owns the card during COPY writes   **
   *******************************************************************************/
  reg             wr_start;
  reg  [31:0]     tgt_sector;
  reg  [12:0]     nsec, seccnt;
  reg  [8:0]      wr_burst;  // burst length for the next engine start (menus 6/7)
  reg  [BUF_AW:0] copy_len;

  wire       wr_sdclk, wr_cmd_o, wr_cmd_oe, wr_dat0_o, wr_dat0_oe;
  wire       wr_dat1_o, wr_dat1_oe, wr_dat2_o, wr_dat2_oe, wr_dat3_o, wr_dat3_oe;
  wire       s_use4 = (USE_4BIT != 0);
  wire       wr_busy, wr_done, wr_err, wr_block_next;
  wire [8:0] wr_rd_addr;
  wire [7:0] wr_data_in;

  // menus 6/7 burst in chunks of up to 128 sectors (IO.DAT is contiguous)
  wire [12:0] sec_left  = nsec - seccnt;
  wire [8:0]  burst_now = (sec_left > 13'd128) ? 9'd128 : sec_left[8:0];

  // engine control is muxed: the FAT surgeon owns it while fx_busy,
  // the data-sector loop otherwise
  wire        fx_busy, fx_done, fx_err;
  wire [1:0]  fx_err_kind;  // surgeon verdict: 0 no-space, 1 read, 2 write, 3 corrupt
  reg         fx_start, fx_realloc, fx_create;
  wire [31:0] fx_new_first;
  wire        fx_eng_start, fx_eng_rd;
  wire [31:0] fx_eng_sector;
  wire        eng_rx_we;
  wire [8:0]  eng_rx_addr;
  wire [7:0]  eng_rx_data;
  wire [7:0]  fx_tx_data;

  // free-space scanner (LIST info line) - shares the engine like the checker
  reg         fsn_start;
  wire        fsn_busy, fsn_done, fsn_err, fsn_tick;
  wire        fsn_eng_start, fsn_eng_rd;
  wire [31:0] fsn_eng_sector;
  wire [31:0] fsn_free_clusters, fsn_free_mb;

  // geometry/target latches (captured while the reader still holds them)
  reg        cp_is32;
  reg [7:0]  cp_cs, cp_nfat;
  reg [31:0] cp_fat0, cp_spf, cp_dbase, cp_total;
  reg [31:0] cp_rootclus;
  reg [31:0] cp_dir_sec;
  reg [3:0]  cp_dir_idx;
  reg [31:0] cp_old_cluster;
  reg [31:0] cp_cap;  // card capacity in MB, held for the LIST info line

`ifdef SDFAT_WRITE
  sd_writer #(
      .CLKDIV(8'd1)  // 27 MHz / 2 = 13.5 MHz bit clock (25 MHz default-speed limit)
  ) u_wr (
      .clk       (clk),
      .rst_n     (sys_rst_n),
      .sd_clk_o  (wr_sdclk),
      .sd_cmd_i  (sd_cmd),
      .sd_cmd_o  (wr_cmd_o),
      .sd_cmd_oe (wr_cmd_oe),
      .sd_dat0_i (sd_dat0),
      .sd_dat0_o (wr_dat0_o),
      .sd_dat0_oe(wr_dat0_oe),
      .sd_dat1_i (sd_dat1),
      .sd_dat1_o (wr_dat1_o),
      .sd_dat1_oe(wr_dat1_oe),
      .sd_dat2_i (sd_dat2),
      .sd_dat2_o (wr_dat2_o),
      .sd_dat2_oe(wr_dat2_oe),
      .sd_dat3_i (sd_dat3),
      .sd_dat3_o (wr_dat3_o),
      .sd_dat3_oe(wr_dat3_oe),
      .use_4bit  (s_use4),
      // this design's reader re-initialises the card between commands, so a
      // negotiated width never survives: renegotiate every operation
      .width_hold(1'b0),
      .start     (fx_busy ? fx_eng_start : ck_busy ? ck_eng_start
                          : fsn_busy ? fsn_eng_start : wr_start),
`ifdef SDFAT_TEST_READONLY
      // READ-ONLY BUILD: a constant, so the engine's CMD24/CMD25 write paths
      // have no reachable driver and synthesis prunes them. This is the last
      // line of defence behind the missing menu keys - see
      // src/sd_fat_test_config.vh for why the tool defaults this way.
      .rd_mode   (1'b1),
`else
      .rd_mode   (fx_busy ? fx_eng_rd : ck_busy ? ck_eng_rd
                          : fsn_busy ? fsn_eng_rd
                          : ((mode == M_IOR) || dump_mode)),
`endif
      .sector    (fx_busy ? fx_eng_sector : ck_busy ? ck_eng_sector
                          : fsn_busy ? fsn_eng_sector
                          : tgt_sector + {19'b0, seccnt}),
      .busy      (wr_busy),
      .done      (wr_done),
      .err       (wr_err),
      .burst_len ((fx_busy || ck_busy || fsn_busy) ? 9'd1 : wr_burst),
      .rca       (card_rca),
      .block_next(wr_block_next),
      .rd_addr   (wr_rd_addr),
      .rd_data   (fx_busy ? fx_tx_data : wr_data_in),
      .rx_we     (eng_rx_we),
      .rx_addr   (eng_rx_addr),
      .rx_data   (eng_rx_data)
  );
`else
  // write engine stripped: commands depending on it answer NOT IMPLEMENTED
  assign wr_sdclk = 1'b0;
  assign wr_cmd_o = 1'b1;
  assign wr_cmd_oe = 1'b0;
  assign wr_dat0_o = 1'b1;
  assign wr_dat0_oe = 1'b0;
  assign wr_dat1_o = 1'b1;
  assign wr_dat1_oe = 1'b0;
  assign wr_dat2_o = 1'b1;
  assign wr_dat2_oe = 1'b0;
  assign wr_dat3_o = 1'b1;
  assign wr_dat3_oe = 1'b0;
  assign wr_busy = 1'b0;
  assign wr_done = 1'b0;
  assign wr_err = 1'b1;
  assign wr_block_next = 1'b0;
  assign wr_rd_addr = 9'd0;
  assign eng_rx_we = 1'b0;
  assign eng_rx_addr = 9'd0;
  assign eng_rx_data = 8'h00;
`endif

  // ---- CHECK: root entry table captured during the scan -------------------
  reg [127:0] vt_name  [0:15];
  reg [31:0] vt_cluster[0:15];
  reg [31:0] vt_size   [0:15];
  reg [15:0] vt_isdir;
  reg [4:0]  vt_n;

  always @(posedge clk) begin
    if (!sd_rst_n) begin
      vt_n <= 0;
    end else if (mode == M_CHK && dir_valid && dir_len != 0 && !vt_n[4]) begin
      vt_name[vt_n[3:0]]    <= dir_name[127:0];
      vt_cluster[vt_n[3:0]] <= dir_cluster;
      vt_size[vt_n[3:0]]    <= dir_size;
      vt_isdir[vt_n[3:0]]   <= dir_isdir;
      vt_n <= vt_n + 5'd1;
    end
  end

  reg         ck_start;
  wire        ck_busy, ck_done, ck_err;
  wire [3:0]  ck_t_idx;
  wire        ck_eng_start, ck_eng_rd;
  wire [31:0] ck_eng_sector;
  wire        ck_we;
  wire [7:0]  ck_byte;
  reg  [4:0]  vt_n_r;  // latched entry count for the checker run

`ifdef SDFAT_CHECK
  sd_fat_check u_ck (
      .clk             (clk),
      .rst_n           (sys_rst_n),
      .start           (ck_start),
      .busy            (ck_busy),
      .done            (ck_done),
      .err             (ck_err),
      .fs_is_fat32     (cp_is32),
      .cluster_size    (cp_cs),
      .fat0_sector     (cp_fat0),
      .data_base_sector(cp_dbase),
      .total_sectors   (cp_total),
      .n_entries       (vt_n_r),
      .t_idx           (ck_t_idx),
      .t_name          (vt_name[ck_t_idx]),
      .t_cluster       (vt_cluster[ck_t_idx]),
      .t_size          (vt_size[ck_t_idx]),
      .t_isdir         (vt_isdir[ck_t_idx]),
      .eng_start       (ck_eng_start),
      .eng_rd          (ck_eng_rd),
      .eng_sector      (ck_eng_sector),
      .eng_done        (wr_done),
      .eng_err         (wr_err),
      .eng_rx_we       (eng_rx_we),
      .eng_rx_addr     (eng_rx_addr),
      .eng_rx_data     (eng_rx_data),
      .ck_we           (ck_we),
      .ck_byte         (ck_byte)
  );
`else
  assign ck_busy = 1'b0;
  assign ck_done = 1'b0;
  assign ck_err = 1'b1;
  assign ck_t_idx = 4'd0;
  assign ck_eng_start = 1'b0;
  assign ck_eng_rd = 1'b0;
  assign ck_eng_sector = 32'd0;
  assign ck_we = 1'b0;
  assign ck_byte = 8'h00;
`endif

`ifdef SDFAT_FREESCAN
  sd_fat_freescan u_fsn (
      .clk             (clk),
      .rst_n           (sys_rst_n),
      .start           (fsn_start),
      .busy            (fsn_busy),
      .done            (fsn_done),
      .err             (fsn_err),
      .sec_tick        (fsn_tick),
      .fs_is_fat32     (cp_is32),
      .cluster_size    (cp_cs),
      .fat0_sector     (cp_fat0),
      .sectors_per_fat (cp_spf),
      .data_base_sector(cp_dbase),
      .total_sectors   (cp_total),
      .eng_start       (fsn_eng_start),
      .eng_rd          (fsn_eng_rd),
      .eng_sector      (fsn_eng_sector),
      .eng_done        (wr_done),
      .eng_err         (wr_err),
      .eng_rx_we       (eng_rx_we),
      .eng_rx_addr     (eng_rx_addr),
      .eng_rx_data     (eng_rx_data),
      .free_clusters   (fsn_free_clusters),
      .free_mb         (fsn_free_mb)
  );
`else
  // stripped: LIST prints the CARD/VOL sizes and reports FREE N/A
  assign fsn_busy = 1'b0;
  assign fsn_done = 1'b0;
  assign fsn_err = 1'b1;
  assign fsn_tick = 1'b0;
  assign fsn_eng_start = 1'b0;
  assign fsn_eng_rd = 1'b0;
  assign fsn_eng_sector = 32'd0;
  assign fsn_free_clusters = 32'd0;
  assign fsn_free_mb = 32'd0;
`endif

`ifdef SDFAT_REWRITE
  sd_fat_rewrite u_fx (
      .clk              (clk),
      .rst_n            (sys_rst_n),
      .start            (fx_start),
      .realloc          (fx_realloc),
      .busy             (fx_busy),
      .done             (fx_done),
      .err              (fx_err),
      .err_kind         (fx_err_kind),
      .fs_is_fat32      (cp_is32),
      .cluster_size     (cp_cs),
      .fat0_sector      (cp_fat0),
      .sectors_per_fat  (cp_spf),
      .num_fats         (cp_nfat),
      .data_base_sector (cp_dbase),
      .total_sectors    (cp_total),
      .root_start       (cp_fat0 + cp_spf * {24'b0, cp_nfat}),
      .root_secs        ((cp_dbase + {24'b0, cp_cs} * 32'd2) -
                         (cp_fat0 + cp_spf * {24'b0, cp_nfat})),
      .root_cluster     (cp_rootclus),
      .create           (fx_create),
      .name83           ((mode == M_IOW) ? FILE3_83 : FILE2_83),
      .fdate            (FDATE),
      .dir_sector       (cp_dir_sec),
      .dir_index        (cp_dir_idx),
      .old_first_cluster(cp_old_cluster),
      .new_size         ((mode == M_IOW) ? IO_BYTES : {{(31-BUF_AW){1'b0}}, copy_len}),
      .new_first_cluster(fx_new_first),
      .eng_start        (fx_eng_start),
      .eng_rd           (fx_eng_rd),
      .eng_sector       (fx_eng_sector),
      .eng_busy         (wr_busy),
      .eng_done         (wr_done),
      .eng_err          (wr_err),
      .eng_rx_we        (eng_rx_we),
      .eng_rx_addr      (eng_rx_addr),
      .eng_rx_data      (eng_rx_data),
      .eng_tx_addr      (wr_rd_addr),
      .eng_tx_data      (fx_tx_data)
  );
`else
  assign fx_busy = 1'b0;
  assign fx_done = 1'b0;
  assign fx_err = 1'b1;
  assign fx_err_kind = 2'd0;
  assign fx_new_first = 32'd0;
  assign fx_eng_start = 1'b0;
  assign fx_eng_rd = 1'b0;
  assign fx_eng_sector = 32'd0;
  assign fx_tx_data = 8'h00;
`endif

  /*******************************************************************************
   ** SD pin muxes - the ONLY tristate drivers, at the pads (repo rule).        **
   **                                                                            **
   ** EVERY pad must use the single-ternary form  oe ? val : 1'bz  - it is the  **
   ** only tristate idiom yosys maps to a real IOBUF. The previous DAT1-3       **
   ** expression (park-driven-1 with 1'bz in the INNER ternary branch) was      **
   ** silently collapsed to an always-driving OBUF: the FPGA fought the card    **
   ** on DAT1-3 through every 4-bit read data phase and all 4-bit reads failed  **
   ** on silicon while simulating perfectly (z-semantics in sim, none in the    **
   ** netlist). Proven from the synthesis netlist 12-JUL-2026: sd_dat1-3 came  **
   ** out as direction "output"/OBUF, sd_cmd/sd_dat0 (this form) as inout.     **
   ** The pads idle released; the slot's external 10K pull-ups (R53-R57) hold  **
   ** the lines high, incl. DAT3 at CMD0 (SD-native mode select). The pad oe   **
   ** wires below also feed the simulation contention monitors.                 **
   *******************************************************************************/
  assign sd_clk = phase_write ? wr_sdclk : rd_sdclk;
  wire cmd_oe = phase_write ? wr_cmd_oe : rd_cmd_oe;
  wire cmd_o  = phase_write ? wr_cmd_o : rd_cmd_o;
  wire s_dat0_pad_oe = phase_write & wr_dat0_oe;
  wire s_dat1_pad_oe = phase_write & wr_dat1_oe;
  wire s_dat2_pad_oe = phase_write & wr_dat2_oe;
  wire s_dat3_pad_oe = phase_write & wr_dat3_oe;
  assign sd_cmd  = cmd_oe ? cmd_o : 1'bz;
  assign sd_dat0 = s_dat0_pad_oe ? wr_dat0_o : 1'bz;
  assign sd_dat1 = s_dat1_pad_oe ? wr_dat1_o : 1'bz;
  assign sd_dat2 = s_dat2_pad_oe ? wr_dat2_o : 1'bz;
  assign sd_dat3 = s_dat3_pad_oe ? wr_dat3_o : 1'bz;

  /*******************************************************************************
   ** LIST mode: pack "      size  DD-MMM-YYYY  NAME" lines into the buffer     **
   *******************************************************************************/
  function [31:0] pow10(input [3:0] i);
    case (i)
      4'd0: pow10 = 32'd1;
      4'd1: pow10 = 32'd10;
      4'd2: pow10 = 32'd100;
      4'd3: pow10 = 32'd1000;
      4'd4: pow10 = 32'd10000;
      4'd5: pow10 = 32'd100000;
      4'd6: pow10 = 32'd1000000;
      4'd7: pow10 = 32'd10000000;
      4'd8: pow10 = 32'd100000000;
      default: pow10 = 32'd1000000000;
    endcase
  endfunction

  function [7:0] hexd(input [3:0] n);
    hexd = (n < 4'd10) ? (8'h30 + {4'b0, n}) : (8'h37 + {4'b0, n});
  endfunction

  function [23:0] month3(input [3:0] m);
    case (m)
      4'd1:  month3 = "JAN";
      4'd2:  month3 = "FEB";
      4'd3:  month3 = "MAR";
      4'd4:  month3 = "APR";
      4'd5:  month3 = "MAY";
      4'd6:  month3 = "JUN";
      4'd7:  month3 = "JUL";
      4'd8:  month3 = "AUG";
      4'd9:  month3 = "SEP";
      4'd10: month3 = "OCT";
      4'd11: month3 = "NOV";
      4'd12: month3 = "DEC";
      default: month3 = "???";
    endcase
  endfunction

  localparam S_DIRPAD = "     <DIR>";  // 10 chars, right-aligned like the sizes

  localparam PK_IDLE   = 4'd0;
  localparam PK_DEC    = 4'd1;  // decimal emit engine (size / day / year)
  localparam PK_DIRSTR = 4'd2;
  localparam PK_SPA    = 4'd3;  // two spaces after the size column
  localparam PK_DASH1  = 4'd4;
  localparam PK_MON    = 4'd5;
  localparam PK_DASH2  = 4'd6;
  localparam PK_SPB    = 4'd7;  // two spaces after the date column
  localparam PK_WR     = 4'd8;  // the name
  localparam PK_CR     = 4'd9;
  localparam PK_LF     = 4'd10;
  localparam PK_CL     = 4'd11;  // 8 hex digits of the first cluster
  localparam PK_SPC    = 4'd12;  // two spaces after the cluster column
  localparam PK_SPD    = 4'd13;  // two spaces after the absolute-sector column

  reg [3:0]      pk_state, pk_ret;
  reg [52*8-1:0] pk_name;
  reg [7:0]      pk_len, pk_i;
  reg [15:0]     pk_date;
  reg [31:0]     pk_cluster;
  reg [31:0]     pk_abs;     // first absolute sector of this entry
  reg            pk_we;
  reg [7:0]      pk_byte;
  reg [31:0]     pk_dval;    // decimal engine value
  reg [3:0]      pk_dpow;    // current power-of-ten index
  reg [3:0]      pk_ddig;    // current digit
  reg            pk_dpad;    // 1 = zero-pad (day/year), 0 = space-pad (size)
  reg            pk_dstart;  // a nonzero digit has been emitted

  wire pk_print_num = pk_dpad || pk_dstart || (pk_ddig != 0) || (pk_dpow == 0);

  always @(posedge clk) begin
    if (!sd_rst_n) begin
      pk_state  <= PK_IDLE;
      pk_ret    <= PK_IDLE;
      pk_name   <= 0;
      pk_len    <= 0;
      pk_i      <= 0;
      pk_date   <= 0;
      pk_we     <= 1'b0;
      pk_byte   <= 8'h00;
      pk_dval   <= 0;
      pk_dpow   <= 0;
      pk_ddig   <= 0;
      pk_dpad   <= 1'b0;
      pk_dstart <= 1'b0;
    end else begin
      pk_we <= 1'b0;
      case (pk_state)
        PK_IDLE:
        if (mode_list && !list_done && dir_valid && dir_len != 0) begin
          pk_name    <= dir_name;
          pk_len     <= dir_len;
          pk_date    <= dir_date;
          pk_cluster <= dir_cluster;
          // first ABSOLUTE sector of the entry, straight from the geometry
          // the reader publishes: data_base_sector is already biased so that
          // cluster c starts at base + cluster_size*c. Printed so the
          // operator can feed it to command 9 (or compare it against what
          // the ND-120 storage stack thinks the file's address is) without
          // doing the arithmetic by hand. Clusters 0/1 do not exist (an
          // empty file records cluster 0), so those print 0.
          pk_abs     <= (dir_cluster < 32'd2) ? 32'd0
                        : (fs_dbase + {24'b0, fs_cs} * dir_cluster);
          pk_i       <= 0;
          if (dir_isdir) begin
            pk_state <= PK_DIRSTR;
          end else begin
            pk_dval   <= dir_size;
            pk_dpow   <= 4'd9;
            pk_ddig   <= 0;
            pk_dpad   <= 1'b0;
            pk_dstart <= 1'b0;
            pk_ret    <= PK_SPA;
            pk_state  <= PK_DEC;
          end
        end

        PK_DEC:  // one decimal number, MSD first, one char per emit cycle
        if (pk_dval >= pow10(pk_dpow)) begin
          pk_dval <= pk_dval - pow10(pk_dpow);
          pk_ddig <= pk_ddig + 4'd1;
        end else begin
          pk_byte   <= pk_print_num ? (8'h30 + {4'b0, pk_ddig}) : 8'h20;
          pk_we     <= 1'b1;
          pk_dstart <= pk_dstart | (pk_ddig != 0);
          pk_ddig   <= 0;
          if (pk_dpow == 0) pk_state <= pk_ret;
          else pk_dpow <= pk_dpow - 4'd1;
        end

        PK_DIRSTR: begin
          pk_byte <= S_DIRPAD[8*(9-pk_i)+:8];
          pk_we   <= 1'b1;
          if (pk_i == 8'd9) begin
            pk_i     <= 0;
            pk_state <= PK_SPA;
          end else pk_i <= pk_i + 8'd1;
        end

        PK_SPA: begin
          pk_byte <= 8'h20;
          pk_we   <= 1'b1;
          if (pk_i == 8'd1) begin
            // load the day (2 digits, zero-padded)
            pk_i     <= 0;
            pk_dval  <= {27'b0, pk_date[4:0]};
            pk_dpow  <= 4'd1;
            pk_ddig  <= 0;
            pk_dpad  <= 1'b1;
            pk_ret   <= PK_DASH1;
            pk_state <= PK_DEC;
          end else pk_i <= pk_i + 8'd1;
        end

        PK_DASH1: begin
          pk_byte  <= "-";
          pk_we    <= 1'b1;
          pk_i     <= 0;
          pk_state <= PK_MON;
        end

        PK_MON: begin
          pk_byte <= month3(pk_date[8:5]) >> (8 * (2 - pk_i));
          pk_we   <= 1'b1;
          if (pk_i == 8'd2) begin
            pk_i     <= 0;
            pk_state <= PK_DASH2;
          end else pk_i <= pk_i + 8'd1;
        end

        PK_DASH2: begin
          pk_byte  <= "-";
          pk_we    <= 1'b1;
          // load the year (4 digits, zero-padded; FAT epoch 1980)
          pk_dval  <= 32'd1980 + {25'b0, pk_date[15:9]};
          pk_dpow  <= 4'd3;
          pk_ddig  <= 0;
          pk_dpad  <= 1'b1;
          pk_ret   <= PK_SPB;
          pk_state <= PK_DEC;
        end

        PK_SPB: begin
          pk_byte <= 8'h20;
          pk_we   <= 1'b1;
          if (pk_i == 8'd1) begin
            pk_i     <= 0;
            pk_state <= PK_CL;
          end else pk_i <= pk_i + 8'd1;
        end

        PK_CL: begin  // first cluster, 8 hex digits
          pk_byte <= hexd(pk_cluster[31-4*pk_i[2:0]-:4]);
          pk_we   <= 1'b1;
          if (pk_i == 8'd7) begin
            pk_i     <= 0;
            pk_state <= PK_SPC;
          end else pk_i <= pk_i + 8'd1;
        end

        PK_SPC: begin
          pk_byte <= 8'h20;
          pk_we   <= 1'b1;
          if (pk_i == 8'd1) begin
            // load the first absolute sector (10 digits, space-padded)
            pk_i      <= 0;
            pk_dval   <= pk_abs;
            pk_dpow   <= 4'd9;
            pk_ddig   <= 0;
            pk_dpad   <= 1'b0;
            pk_dstart <= 1'b0;
            pk_ret    <= PK_SPD;
            pk_state  <= PK_DEC;
          end else pk_i <= pk_i + 8'd1;
        end

        PK_SPD: begin
          pk_byte <= 8'h20;
          pk_we   <= 1'b1;
          if (pk_i == 8'd1) begin
            pk_i     <= 0;
            pk_state <= PK_WR;
          end else pk_i <= pk_i + 8'd1;
        end

        PK_WR:
        if (pk_i < pk_len) begin
          pk_byte <= pk_name[8*pk_i+:8];
          pk_we   <= 1'b1;
          pk_i    <= pk_i + 8'd1;
        end else pk_state <= PK_CR;

        PK_CR: begin
          pk_byte  <= 8'h0D;
          pk_we    <= 1'b1;
          pk_state <= PK_LF;
        end

        PK_LF: begin
          pk_byte  <= 8'h0A;
          pk_we    <= 1'b1;
          pk_state <= PK_IDLE;
        end

        default: pk_state <= PK_IDLE;
      endcase
    end
  end

  /*******************************************************************************
   ** LIST disk-info line: "CARD c MB  VOL v MB  FREE f MB" appended to the    **
   ** buffer after the file listing. CARD = CMD9 CSD capacity (latched in      **
   ** cp_cap), VOL = total sectors / 2048, FREE = the free-space scanner's     **
   ** result (or N/A when the scan is stripped/failed). Decimal, no padding.   **
   *******************************************************************************/
  localparam S_IL_CARD = "CARD ";           // 5 chars
  localparam S_IL_VOL  = " MB  VOL ";       // 9 chars
  localparam S_IL_FREE = " MB  FREE ";      // 10 chars
  localparam S_IL_SPC1 = " MB  SPC ";       // 9 chars, follows a numeric FREE
  localparam S_IL_SPC2 = " SPC ";           // 5 chars, follows "N/A"
  localparam S_IL_DBAS = " DBASE ";         // 7 chars
  localparam S_IL_TAIL = "\015\012";        // 2 chars
  localparam S_IL_NA   = "N/A";             // 3 chars

  function [7:0] ilchr(input [8*10-1:0] s, input [3:0] len, input [3:0] i);
    ilchr = (i < len) ? s[8*(len-1-i)+:8] : 8'h00;
  endfunction

  // MB values stay below 10^7 (10 TB) for every CSD we decode, so this
  // decimal engine is 24-bit / 8 digits (the 32-bit pow10 would waste LUTs)
  function [23:0] pow10i(input [2:0] i);
    case (i)
      3'd0: pow10i = 24'd1;
      3'd1: pow10i = 24'd10;
      3'd2: pow10i = 24'd100;
      3'd3: pow10i = 24'd1000;
      3'd4: pow10i = 24'd10000;
      3'd5: pow10i = 24'd100000;
      3'd6: pow10i = 24'd1000000;
      default: pow10i = 24'd10000000;
    endcase
  endfunction

  localparam IL_IDLE = 2'd0;
  localparam IL_STR  = 2'd1;  // current segment's characters
  localparam IL_DEC  = 2'd2;  // one decimal number, leading zeros skipped

  // Segment order (a segment is a label, optionally followed by a decimal
  // number). SPC and DBASE are the two numbers an operator needs to turn a
  // LIST first-cluster column into an absolute sector by hand:
  //   first sector = DBASE + SPC * first cluster
  // which is exactly what the listing's own sector column computes.
  //   0 "CARD "      capacity      -> 1
  //   1 " MB  VOL "  volume MB     -> 2
  //   2 " MB  FREE " free MB       -> 3   (or, with no scanner, -> 6)
  //   3 " MB  SPC "  sectors/clus  -> 5
  //   4 " SPC "      sectors/clus  -> 5   (the same after an "N/A" free)
  //   5 " DBASE "    data base sec -> 7
  //   6 "N/A"        no number     -> 4
  //   7 CR LF        no number     -> end
  reg [1:0]  il_state;
  reg [2:0]  il_seg;
  reg [3:0]  il_si;
  reg        il_we;
  reg [7:0]  il_byte;
  reg [23:0] il_dval;
  reg [2:0]  il_dpow;
  reg [3:0]  il_ddig;
  reg        il_dstart;
  reg        il_go;         // pulsed by the menu FSM
  reg        il_have_free;  // 0: the FREE column prints N/A

  wire il_busy = (il_state != IL_IDLE);

  reg [7:0] il_ch;
  always @(*) begin
    case (il_seg)
      3'd0: il_ch = ilchr({40'b0, S_IL_CARD}, 4'd5, il_si);
      3'd1: il_ch = ilchr({8'b0, S_IL_VOL}, 4'd9, il_si);
      3'd2: il_ch = ilchr(S_IL_FREE, 4'd10, il_si);
      3'd3: il_ch = ilchr({8'b0, S_IL_SPC1}, 4'd9, il_si);
      3'd4: il_ch = ilchr({40'b0, S_IL_SPC2}, 4'd5, il_si);
      3'd5: il_ch = ilchr({24'b0, S_IL_DBAS}, 4'd7, il_si);
      3'd6: il_ch = ilchr({56'b0, S_IL_NA}, 4'd3, il_si);
      default: il_ch = ilchr({64'b0, S_IL_TAIL}, 4'd2, il_si);
    endcase
  end

  // segment that follows a printed number
  function [2:0] il_nxt(input [2:0] s);
    case (s)
      3'd0: il_nxt = 3'd1;
      3'd1: il_nxt = 3'd2;
      3'd2: il_nxt = 3'd3;
      3'd3: il_nxt = 3'd5;
      3'd4: il_nxt = 3'd5;
      default: il_nxt = 3'd7;
    endcase
  endfunction

  always @(posedge clk) begin
    if (!sys_rst_n) begin
      il_state  <= IL_IDLE;
      il_seg    <= 0;
      il_si     <= 0;
      il_we     <= 1'b0;
      il_byte   <= 8'h00;
      il_dval   <= 0;
      il_dpow   <= 0;
      il_ddig   <= 0;
      il_dstart <= 1'b0;
    end else begin
      il_we <= 1'b0;
      case (il_state)
        IL_IDLE:
        if (il_go) begin
          il_seg   <= 0;
          il_si    <= 0;
          il_state <= IL_STR;
        end

        IL_STR:
        if (il_ch == 8'h00) begin
          il_dpow   <= 3'd7;
          il_ddig   <= 0;
          il_dstart <= 1'b0;
          case (il_seg)
            3'd0: begin
              il_dval  <= cp_cap[23:0];       // CARD capacity in MB
              il_state <= IL_DEC;
            end
            3'd1: begin
              il_dval  <= {3'd0, cp_total[31:11]};  // sectors * 512 / 1 MB
              il_state <= IL_DEC;
            end
            3'd2:
            if (il_have_free) begin
              il_dval  <= fsn_free_mb[23:0];
              il_state <= IL_DEC;
            end else begin
              il_seg <= 3'd6;                 // "N/A", then straight to SPC
              il_si  <= 0;
            end
            3'd3, 3'd4: begin
              il_dval  <= {16'd0, cp_cs};     // sectors per cluster
              il_state <= IL_DEC;
            end
            3'd5: begin
              il_dval  <= cp_dbase[23:0];     // biased data base sector
              il_state <= IL_DEC;
            end
            3'd6: begin                       // "N/A" carries no number
              il_seg <= 3'd4;
              il_si  <= 0;
            end
            default: il_state <= IL_IDLE;     // segment 7 = CR LF: line done
          endcase
        end else begin
          il_we   <= 1'b1;
          il_byte <= il_ch;
          il_si   <= il_si + 4'd1;
        end

        IL_DEC:  // MSD first; leading zeros skipped entirely (no padding)
        if (il_dval >= pow10i(il_dpow)) begin
          il_dval <= il_dval - pow10i(il_dpow);
          il_ddig <= il_ddig + 4'd1;
        end else begin
          if (il_dstart || il_ddig != 0 || il_dpow == 0) begin
            il_we   <= 1'b1;
            il_byte <= 8'h30 + {4'b0, il_ddig};
          end
          il_dstart <= il_dstart | (il_ddig != 0);
          il_ddig   <= 0;
          if (il_dpow == 0) begin
            il_seg   <= il_nxt(il_seg);  // next segment header / tail
            il_si    <= 0;
            il_state <= IL_STR;
          end else il_dpow <= il_dpow - 3'd1;
        end

        default: il_state <= IL_IDLE;
      endcase
    end
  end

  /*******************************************************************************
   ** IO speed report: KB/s = SPEED_NUM / io_cycles (40/32-bit restoring       **
   ** divider), formatted as "WRITE NNNNN KB/S" into the text buffer           **
   *******************************************************************************/
`ifdef SDFAT_SPEED
  localparam SP_IDLE = 3'd0;
  localparam SP_DIV  = 3'd1;
  localparam SP_LBL  = 3'd2;
  localparam SP_DIG  = 3'd3;
  localparam SP_TAIL = 3'd4;

  reg [2:0]  spf_state;
  reg        spf_we;
  reg [7:0]  spf_byte;
  reg        spf_rd_r;
  reg [3:0]  spf_i;
  reg [39:0] div_q;
  reg [40:0] div_r;
  reg [5:0]  div_i;
  reg [31:0] div_d;
  reg [16:0] sp_val;
  reg [3:0]  sp_pow, sp_dig;

  wire spf_busy = (spf_state != SP_IDLE);

  wire [40:0] div_shift = {div_r[39:0], SPEED_NUM[6'd39-div_i]};
  wire        div_ge    = (div_shift >= {9'b0, div_d});
  wire [39:0] div_qn    = {div_q[38:0], div_ge};

  function [7:0] spstr(input rd, input tail, input [3:0] i);
    begin
      if (tail) begin
        case (i)  // " KB/S" CR LF
          4'd0: spstr = " ";
          4'd1: spstr = "K";
          4'd2: spstr = "B";
          4'd3: spstr = "/";
          4'd4: spstr = "S";
          4'd5: spstr = 8'h0D;
          4'd6: spstr = 8'h0A;
          default: spstr = 8'h00;
        endcase
      end else if (rd) begin
        case (i)
          4'd0: spstr = "R";
          4'd1: spstr = "E";
          4'd2: spstr = "A";
          4'd3: spstr = "D";
          4'd4: spstr = " ";
          default: spstr = 8'h00;
        endcase
      end else begin
        case (i)
          4'd0: spstr = "W";
          4'd1: spstr = "R";
          4'd2: spstr = "I";
          4'd3: spstr = "T";
          4'd4: spstr = "E";
          4'd5: spstr = " ";
          default: spstr = 8'h00;
        endcase
      end
    end
  endfunction

  always @(posedge clk) begin
    if (!sys_rst_n) begin
      spf_state <= SP_IDLE;
      spf_we    <= 1'b0;
      spf_byte  <= 0;
      spf_rd_r  <= 1'b0;
      spf_i     <= 0;
      div_q     <= 0;
      div_r     <= 0;
      div_i     <= 0;
      div_d     <= 1;
      sp_val    <= 0;
      sp_pow    <= 0;
      sp_dig    <= 0;
    end else begin
      spf_we <= 1'b0;
      case (spf_state)
        SP_IDLE:
        if (spf_go) begin
          spf_rd_r  <= spf_read;
          div_d     <= (io_cycles == 0) ? 32'd1 : io_cycles;
          div_q     <= 0;
          div_r     <= 0;
          div_i     <= 0;
          spf_state <= SP_DIV;
        end

        SP_DIV: begin
          div_r <= div_ge ? (div_shift - {9'b0, div_d}) : div_shift;
          div_q <= div_qn;
          if (div_i == 6'd39) begin
            sp_val    <= (div_qn > 40'd99999) ? 17'd99999 : div_qn[16:0];
            spf_i     <= 0;
            spf_state <= SP_LBL;
          end else div_i <= div_i + 6'd1;
        end

        SP_LBL:
        if (spstr(spf_rd_r, 1'b0, spf_i) == 8'h00) begin
          sp_pow    <= 4'd4;
          sp_dig    <= 0;
          spf_state <= SP_DIG;
        end else begin
          spf_we   <= 1'b1;
          spf_byte <= spstr(spf_rd_r, 1'b0, spf_i);
          spf_i    <= spf_i + 4'd1;
        end

        SP_DIG:  // 5 decimal digits, zero padded
        if ({15'b0, sp_val} >= pow10(sp_pow)) begin
          sp_val <= sp_val - pow10(sp_pow);  // sp_pow <= 4: fits in 17 bits
          sp_dig <= sp_dig + 4'd1;
        end else begin
          spf_we   <= 1'b1;
          spf_byte <= 8'h30 + {4'b0, sp_dig};
          sp_dig   <= 0;
          if (sp_pow == 0) begin
            spf_i     <= 0;
            spf_state <= SP_TAIL;
          end else sp_pow <= sp_pow - 4'd1;
        end

        SP_TAIL:
        if (spstr(1'b0, 1'b1, spf_i) == 8'h00) begin
          spf_state <= SP_IDLE;
        end else begin
          spf_we   <= 1'b1;
          spf_byte <= spstr(1'b0, 1'b1, spf_i);
          spf_i    <= spf_i + 4'd1;
        end

        default: spf_state <= SP_IDLE;
      endcase
    end
  end
`else
  wire       spf_busy = 1'b0;
  wire       spf_we = 1'b0;
  wire [7:0] spf_byte = 8'h00;
`endif

  /*******************************************************************************
   ** 64 KB byte buffer (BRAM): file bytes (DUMP/COPY) or list lines (LIST) in, **
   ** hex_dumper / buf_text_printer / sd_writer out                             **
   *******************************************************************************/
  // SDFAT_BUF_BLOCKRAM: Vivado maps this array to DISTRIBUTED RAM by default
  // (measured 20-AUG-2026 on xc7a100t: 24,576 RAMD64E cells against 19,000
  // sites, so place_design fails outright) even though the write and the read
  // are both clocked. The attribute forces block RAM. It is gated so that
  // builds which do not define it - Tang Nano 20K (Gowin) and Basys3 - compile
  // byte-identically to before.
`ifdef SDFAT_BUF_BLOCKRAM
  (* ram_style = "block" *)
`endif
  reg [7:0] file_buf[0:(1 << BUF_AW)-1];

  reg [BUF_AW:0] wptr;
  reg            trunc;

  // COPY phase 1 (locating TEST.TXT) must not disturb the buffered file
  wire       wr_gate = (mode == M_COPY) && copy_phase;
  wire [7:0] wr_byte = (mode == M_CHK) ? ck_byte
                     : io_mode ? spf_byte
                     : mode_list ? (il_we ? il_byte : pk_byte) : f_outbyte;
  wire       wr_req  = !wr_gate && ((mode == M_CHK) ? ck_we
                                    : io_mode ? spf_we
                                    : mode_list ? (pk_we | il_we) : f_outen);
  wire       buf_we  = wr_req && !wptr[BUF_AW];

  // BLOCK (8) / SECTOR (9): sectors land in the buffer straight off the
  // engine's read port as they arrive, at most 4 sectors (2048 bytes) per
  // command whatever the file size - the buffer is only a landing pad here,
  // never a copy of the file. seccnt is the sector index inside the block.
  wire              rx_buf_we   = phase_write && dump_mode && eng_rx_we;
  wire [BUF_AW-1:0] rx_buf_addr = {{(BUF_AW-11){1'b0}}, seccnt[1:0], eng_rx_addr};

  // ONE write port, explicitly muxed. Written as two if/else branches with
  // two different address expressions - which is what this was - Vivado
  // counts them as two separate write ports, needs a third for the read, and
  // gives up on block RAM ("Infeasible attribute ram_style", measured
  // 20-AUG-2026: 6144 RAM64M primitives instead of 16 RAMB36, which no longer
  // fits any part here). The priority is unchanged: rx_buf_we wins.
  wire [BUF_AW-1:0] buf_waddr = rx_buf_we ? rx_buf_addr : wptr[BUF_AW-1:0];
  wire [7:0]        buf_wdata = rx_buf_we ? eng_rx_data : wr_byte;
  wire              buf_wen   = rx_buf_we | buf_we;

  always @(posedge clk) begin
    if (buf_wen) file_buf[buf_waddr] <= buf_wdata;
  end

  // the buffer pointer clears with the reader reset EXCEPT while the
  // reader is merely parked (phase_write): the CHECK report and the COPY
  // write phase need the buffer to stay alive through that
  always @(posedge clk) begin
    if (!sys_rst_n || (!sd_rst_n && !phase_write)) begin
      wptr  <= 0;
      trunc <= 0;
    end else begin
      if (buf_we) wptr <= wptr + 1;
      if (wr_req && wptr[BUF_AW]) trunc <= 1;
    end
  end

  wire [BUF_AW:0]   widx = {seccnt[BUF_AW-9:0], 9'b0} + {8'b0, wr_rd_addr};
  // speed-test pattern: distinct per sector and offset, cheap to generate
  wire [7:0] io_pat = seccnt[7:0] ^ wr_rd_addr[7:0] ^ {seccnt[12:9], 4'hA};
  wire [BUF_AW-1:0] dump_addr, text_addr;
  reg  [7:0]        buf_rdata;
  wire              tp_busy;
  // the text printer wins even while the reader is parked (phase_write):
  // the CHECK/SPEED/LIST reports print with the card still parked so the
  // reader is not restarted just to be reset mid-command at the menu
  // in the BLOCK/SECTOR dumps the reader stays parked (phase_write) while
  // hex_dumper prints, so the dumper - not the write-data path - owns the
  // read port there
  wire [BUF_AW-1:0] rd_addr = tp_busy ? text_addr
                            : (phase_write && !dump_mode) ? widx[BUF_AW-1:0]
                            : dump_addr;
  always @(posedge clk) buf_rdata <= file_buf[rd_addr];

  // COPY: buffer bytes, zero-filled past the file end (real tapes had zero
  // trailers). WRBLK1: counter pattern - 1024 big-endian 16-bit words,
  // word[w] = w, so every sector of the block is distinct and a misplaced
  // write cannot pass the dump check.
  wire [10:0] blk_off  = widx[10:0];              // byte offset inside the block
  wire [9:0]  blk_word = blk_off[10:1];           // word index 0..1023
  wire [7:0]  blk_pat  = blk_off[0] ? blk_word[7:0] : {6'b0, blk_word[9:8]};
  assign wr_data_in = (mode == M_BLK) ? blk_pat
                    : (mode == M_IOW) ? io_pat
                    : (widx < copy_len) ? buf_rdata : 8'h00;

  /*******************************************************************************
   ** UART: rx = menu keys, tx shared by the three printers                     **
   *******************************************************************************/
  wire [7:0] rx_data;
  wire       rx_valid;

  uart_rx #(
      .DELAY_FRAMES(DELAY_FRAMES)
  ) u_rx (
      .clk(clk),
      .rst_n(sys_rst_n),
      .rxd(uart_rxp),
      .rx_data(rx_data),
      .rx_valid(rx_valid)
  );

  reg        sp_start;
  reg  [5:0] sp_msg;
  wire       sp_busy;
  wire [7:0] sp_tx_data;
  wire       sp_tx_valid;

  status_printer u_sp (
      .clk(clk),
      .rst_n(sys_rst_n),
      .start(sp_start),
      .msg(sp_msg),
      .busy(sp_busy),
      .tx_data(sp_tx_data),
      .tx_valid(sp_tx_valid),
      .tx_busy(tx_busy)
  );

  reg        hd_start;
  wire       hd_busy;
  wire [7:0] hd_tx_data;
  wire       hd_tx_valid;

  // BLOCK/SECTOR dump exactly the sectors just read (nsec * 512 bytes);
  // every other command dumps what the buffer collected
  wire [BUF_AW:0] hd_length = dump_mode ? {{(BUF_AW-11){1'b0}}, nsec[2:0], 9'b0}
                                        : wptr;

  hex_dumper #(
      .ADDR_W(BUF_AW)
  ) u_dump (
      .clk(clk),
      .rst_n(sys_rst_n),
      .start(hd_start),
      .length(hd_length),
      .busy(hd_busy),
      .mem_addr(dump_addr),
      .mem_data(buf_rdata),
      .tx_data(hd_tx_data),
      .tx_valid(hd_tx_valid),
      .tx_busy(tx_busy)
  );

  reg        tp_start;
  wire [7:0] tp_tx_data;
  wire       tp_tx_valid;

  buf_text_printer #(
      .ADDR_W(BUF_AW)
  ) u_text (
      .clk(clk),
      .rst_n(sys_rst_n),
      .start(tp_start),
      .length(wptr),
      .busy(tp_busy),
      .mem_addr(text_addr),
      .mem_data(buf_rdata),
      .tx_data(tp_tx_data),
      .tx_valid(tp_tx_valid),
      .tx_busy(tx_busy)
  );

  // the FSM serializes the printers; the pulse selects whose byte is latched
  // menu-key echo (owner request 12-JUL-2026): every ACCEPTED key is
  // echoed back as <key> CR LF before its command output starts, so a
  // captured console log has copy-pasteable command boundaries
  reg        ec_valid;
  reg  [7:0] ec_byte;

`ifdef SDFAT_EXT_TEST
  // the external test owns the console while it runs - nothing else prints
  // during a memory test, so top priority is safe and keeps its lines intact
  wire [7:0] tx_data = ext_tx_valid ? ext_tx_data
                     : hd_tx_valid ? hd_tx_data : tp_tx_valid ? tp_tx_data
                     : ec_valid ? ec_byte : sp_tx_data;
  wire       tx_valid = ext_tx_valid | hd_tx_valid | tp_tx_valid | ec_valid | sp_tx_valid;
  assign     ext_tx_busy = tx_busy;
`else
  wire [7:0] tx_data = hd_tx_valid ? hd_tx_data : tp_tx_valid ? tp_tx_data
                     : ec_valid ? ec_byte : sp_tx_data;
  wire       tx_valid = hd_tx_valid | tp_tx_valid | ec_valid | sp_tx_valid;
`endif
  wire       tx_busy;

  uart_tx #(
      .DELAY_FRAMES(DELAY_FRAMES)
  ) u_tx (
      .clk(clk),
      .rst_n(sys_rst_n),
      .tx_data(tx_data),
      .tx_valid(tx_valid),
      .tx_busy(tx_busy),
      .txd(uart_txp)
  );

  /*******************************************************************************
   ** Menu FSM                                                                  **
   *******************************************************************************/
  // status_printer message codes (must match status_printer.v)
  localparam MSG_BANNER = 6'd0;
  localparam MSG_FS_UNKNOWN = 6'd6;
  localparam MSG_FILE_FOUND = 6'd7;
  localparam MSG_FILE_NOTFND = 6'd8;
  localparam MSG_ERR_CARD_TO = 6'd9;
  localparam MSG_ERR_SCAN_TO = 6'd10;
  localparam MSG_ERR_TRUNC = 6'd11;
  localparam MSG_MENU = 6'd12;
  localparam MSG_NOTIMPL = 6'd13;
  localparam MSG_SD_STATUS0 = 6'd14;  // + sd_status
  localparam MSG_COPYING = 6'd18;
  localparam MSG_COPY_DONE = 6'd19;
  localparam MSG_ERR_NOTGT = 6'd20;
  localparam MSG_ERR_SMALL = 6'd21;
  localparam MSG_ERR_WRITE = 6'd22;
  localparam MSG_BLK_WRITING = 6'd23;
  localparam MSG_BLK_DONE = 6'd24;
  localparam MSG_ERR_RANGE = 6'd25;
  localparam MSG_HELP1 = 6'd26;  // ..MSG_HELP7 = 32, printed in sequence
  localparam MSG_HELP7 = 6'd32;
  localparam MSG_ERR_IOSZ = 6'd33;
  localparam MSG_IOW_RUN = 6'd34;
  localparam MSG_IOR_RUN = 6'd35;
  localparam MSG_SCANNING = 6'd36;
  localparam MSG_ERR_READ = 6'd37;
  localparam MSG_ERR_FATRD = 6'd38;
  localparam MSG_ERR_FATCOR = 6'd39;
  localparam MSG_MENU2 = 6'd40;
  localparam MSG_ASK_BLK = 6'd41;
  localparam MSG_ASK_SEC = 6'd42;
  localparam MSG_ASK_NAME = 6'd43;
  localparam MSG_ERR_NUM = 6'd44;
  localparam MSG_AT_SEC = 6'd45;
  localparam MSG_NAME_SET = 6'd46;
  localparam MSG_HELP8 = 6'd47;   // ..MSG_HELP13 = 52
  localparam MSG_HELP13 = 6'd52;
  localparam MSG_ASK_STA = 6'd53;
  localparam MSG_ASK_CNT = 6'd54;
  localparam MSG_R_RUN = 6'd55;
  localparam MSG_R_AT = 6'd56;
  localparam MSG_R_BLOCKS = 6'd57;
  localparam MSG_R_SECS = 6'd58;
  localparam MSG_R_CHK = 6'd59;
  localparam MSG_R_CYC = 6'd60;
  localparam MSG_R_PASS = 6'd61;
  localparam MSG_R_FAIL = 6'd62;

  localparam ST_BANNER   = 6'd0;
  localparam ST_MENU     = 6'd1;   // print the SD status line, then
  localparam ST_MENU2    = 6'd15;  // the menu itself, then
  localparam ST_MENU3    = 6'd31;  // its second line (64-char message limit)
  localparam ST_KEY      = 6'd2;
  localparam ST_CARD     = 6'd3;
  localparam ST_FS       = 6'd4;
  localparam ST_FILE     = 6'd5;
  localparam ST_STREAM   = 6'd6;
  localparam ST_DUMP     = 6'd7;
  localparam ST_DUMP_W   = 6'd8;
  localparam ST_LSCAN    = 6'd9;
  localparam ST_LPRINT   = 6'd10;
  localparam ST_LPRINT_W = 6'd11;
  localparam ST_CMD_END  = 6'd12;
  localparam ST_PRINT    = 6'd13;  // pulse sp_start, then
  localparam ST_PRINT_W  = 6'd14;  // wait for the message to finish
  localparam ST_C_FIND   = 6'd16;  // COPY: wait for the TEST.TXT scan
  localparam ST_C_WRITE  = 6'd17;  // COPY/WRBLK1/BLOCK/SECTOR: kick a sector
  localparam ST_C_NEXT   = 6'd18;  // and wait for that sector to finish
  localparam ST_HELP     = 6'd19;  // print MSG_HELP1..12 in sequence
  localparam ST_C_FIX    = 6'd20;  // COPY: kick sd_fat_rewrite
  localparam ST_C_FIX_W  = 6'd21;  // COPY: wait for it, then write the data
  localparam ST_CHK      = 6'd22;  // CHECK: park the reader, kick the checker
  localparam ST_CHK_W    = 6'd23;  // CHECK: wait, then print the report
  localparam ST_SPEED    = 6'd24;  // IO speed: kick the KB/s formatter
  localparam ST_SPEED_W  = 6'd25;  // IO speed: wait, then print the line
  localparam ST_FREE     = 6'd26;  // LIST: park the reader, kick the free scan
  localparam ST_FREE_W   = 6'd27;  // LIST: wait for the FAT scan
  localparam ST_INFO     = 6'd28;  // LIST: kick the disk-info line formatter
  localparam ST_INFO_W   = 6'd29;  // LIST: wait, then print the whole buffer
  localparam ST_ECHO     = 6'd30;  // echo the accepted menu key (+ CR-LF)
  localparam ST_NUM      = 6'd32;  // BLOCK/SECTOR: read a decimal number in
  localparam ST_NAME     = 6'd33;  // N: read a file name in
  localparam ST_HEXOUT   = 6'd34;  // print 8 hex digits + CR LF (hx_val)
  localparam ST_SWAIT    = 6'd35;  // SECTOR: let the reader's run end cleanly
  localparam ST_R_NEXT   = 6'd36;  // RANGE: one block done - advance or report
  localparam ST_R_SUM    = 6'd37;  // RANGE: print the summary, field by field
  localparam ST_R_ERR    = 6'd38;  // RANGE: a read failed - print the sector
  localparam ST_R_ERR2   = 6'd39;  // RANGE: ...and the block, then summarise
`ifdef SDFAT_EXT_TEST
  localparam ST_EXT_W    = 6'd40;  // external test running - wait for ext_busy
  reg ext_kicked;
`endif

  // persistent SD status shown in the menu (survives between commands)
  localparam SD_NOTCHK = 2'd0;
  localparam SD_NOCARD = 2'd1;
  localparam SD_ERROR  = 2'd2;
  localparam SD_OK     = 2'd3;

  reg [5:0]  state;
  reg [5:0]  next_after_print;
  reg [7:0]  echo_ch;    // the accepted key being echoed
  reg [5:0]  echo_next;  // state after the echo finishes
  reg [1:0]  ec_i;       // echo byte index: key, CR, LF
  reg        ec_crlf;    // 0 = echo the key alone (console number entry)
  reg        ec_gap;     // one-cycle gap for tx_busy to assert

  // ---- console number entry (BLOCK / SECTOR) and name entry (N) ----------
  reg [31:0] num_val;    // decimal accumulator
  reg        num_dig;    // at least one digit seen (an empty entry is an error)
  reg [23:0] blk_no;     // 1KW block index inside the file
  reg [31:0] sec_no;     // absolute SD sector number
  reg [31:0] hx_val;     // value printed by ST_HEXOUT
  reg [3:0]  hx_i;       // 0..7 digits, 8 = CR, 9 = LF
  reg [5:0]  hx_next;    // state after the hex value has been printed

  // num_val * 10, built from shifts (no multiplier for a console keypress).
  // The guard below stops the accumulator at 10 digits: 4294967295 is the
  // largest sector number a 32-bit SD address can carry (2 TB), so anything
  // beyond that is a typo, not an address.
  wire [31:0] num_x10 = {num_val[28:0], 3'b0} + {num_val[30:0], 1'b0};
  wire        num_fits = (num_val < 32'd400_000_000);

  // ---- multi-block range read (menu R) ------------------------------------
  // Segment handling in SINTRAN is the first thing that reads MANY
  // consecutive blocks in one go, and everything validated before this
  // command only ever read ONE block. So this reads a run of blocks the
  // same way command 8 reads one - sector by sector, nothing buffered - and
  // keeps only a running checksum and a block count. The console never sees
  // the data: a 1000-block hex dump at 9600 baud would take about six hours.
  reg [23:0] rng_start;  // first block of the run
  reg [23:0] rng_cnt;    // number of blocks requested
  reg [23:0] rng_blk;    // blocks completed so far
  reg [15:0] rng_sum;    // sum of every 16-bit big-endian word read
  reg [7:0]  rng_hi;     // high byte of the word being assembled
  reg        num_second; // number entry: 0 = start block, 1 = block count
  reg [2:0]  r_i;        // summary field index

  // sum of the two block indices: (start + count) * 2048 is the number of
  // bytes the file must have. 25-bit sum shifted by 11 = 36 bits, so the
  // arithmetic is done in 40 - in 32 it would wrap and pass a bad range.
  wire [39:0] rng_need = ({15'b0, rng_start} + {15'b0, rng_cnt}) << 11;

  // bytes a file must contain for block blk_no to lie entirely inside it:
  // (blk_no + 1) * 2048, computed in 40 bits because a 24-bit block index
  // times 2048 is 35 bits - the same expression in 32 bits would wrap and
  // let an out-of-range block through
  wire [39:0] blk_need = ({16'b0, blk_no} + 40'd1) << 11;
  reg        io_run;      // IO speed test: cycle counter enable
  reg [31:0] io_cycles;
  reg        spf_go, spf_read;
  reg [1:0]  sd_status;
  reg [31:0] wd;  // watchdog for the waiting states
  reg        err_flag, done_flag;

  assign led = ~{err_flag,               // led[5] error (last command)
                 trunc,                  // led[4] truncated
                 done_flag,              // led[3] last command completed
                 file_found,             // led[2] file found
                 fs_type[1],             // led[1] FS mounted
                 sys_rst_n};             // led[0] alive

  always @(posedge clk) begin
    if (!sys_rst_n) begin
      state            <= ST_BANNER;
      next_after_print <= ST_BANNER;
      cmd_running      <= 1'b0;
`ifdef SDFAT_EXT_TEST
      ext_start        <= 1'b0;
      ext_id           <= 4'd0;
      ext_kicked       <= 1'b0;
`endif
      rdrst_cnt        <= 0;
      phase_write      <= 1'b0;
      mode             <= M_DUMP;
      copy_phase       <= 1'b0;
      copy_len         <= 0;
      tgt_sector       <= 0;
      nsec             <= 0;
      seccnt           <= 0;
      wr_burst         <= 9'd1;
      wr_start         <= 1'b0;
      fx_start         <= 1'b0;
      ck_start         <= 1'b0;
      fsn_start        <= 1'b0;
      il_go            <= 1'b0;
      il_have_free     <= 1'b0;
      list_done        <= 1'b0;
      cp_cap           <= 0;
      vt_n_r           <= 0;
      spf_go           <= 1'b0;
      spf_read         <= 1'b0;
      io_run           <= 1'b0;
      io_cycles        <= 0;
      fx_realloc       <= 1'b0;
      cp_is32          <= 1'b0;
      cp_cs            <= 0;
      cp_nfat          <= 0;
      cp_fat0          <= 0;
      cp_spf           <= 0;
      cp_dbase         <= 0;
      cp_total         <= 0;
      cp_rootclus      <= 0;
      cp_dir_sec       <= 0;
      cp_dir_idx       <= 0;
      cp_old_cluster   <= 0;
      sp_start         <= 1'b0;
      sp_msg           <= MSG_BANNER;
      hd_start         <= 1'b0;
      tp_start         <= 1'b0;
      wd               <= 0;
      err_flag         <= 1'b0;
      done_flag        <= 1'b0;
      sd_status        <= SD_NOTCHK;
      echo_ch          <= 8'h00;
      echo_next        <= ST_MENU;
      ec_i             <= 2'd0;
      ec_crlf          <= 1'b1;
      ec_gap           <= 1'b0;
      ec_valid         <= 1'b0;
      ec_byte          <= 8'h00;
      num_val          <= 0;
      num_dig          <= 1'b0;
      blk_no           <= 0;
      sec_no           <= 0;
      hx_val           <= 0;
      hx_i             <= 0;
      hx_next          <= ST_MENU;
      rt_name          <= 0;
      rt_len           <= 0;
      rng_start        <= 0;
      rng_cnt          <= 0;
      rng_blk          <= 0;
      rng_sum          <= 0;
      rng_hi           <= 0;
      num_second       <= 1'b0;
      r_i              <= 0;
    end else begin
      sp_start  <= 1'b0;
      hd_start  <= 1'b0;
      tp_start  <= 1'b0;
      wr_start  <= 1'b0;
      fx_start  <= 1'b0;
      ck_start  <= 1'b0;
      fsn_start <= 1'b0;
      il_go     <= 1'b0;
      spf_go    <= 1'b0;
      ec_valid  <= 1'b0;
      if (rdrst_cnt != 0) rdrst_cnt <= rdrst_cnt - 5'd1;
      if (io_run) io_cycles <= io_cycles + 1;

      // RANGE: fold every 16-bit word into the checksum as its bytes arrive
      // off the engine. ND-120 words are big-endian on the card, so the even
      // byte offset is the high half. Kept in this process (not in the
      // buffer's) so rng_sum has exactly one driver.
      //
      // ROTATE-then-add, not a plain sum: the checksum has to notice a block
      // read from the WRONG PLACE, and a plain 16-bit sum cannot. Blocks are
      // 1024 words, so shifting a run by whole blocks shifts it by a
      // multiple of 1024 words, and for any position-linear content the
      // difference that makes to a plain sum is a multiple of 2^20 - always
      // zero in 16 bits. Rotating the accumulator by one bit per word
      // destroys that cancellation for one wire and one adder.
      if ((mode == M_RDMP) && phase_write && eng_rx_we) begin
        if (!eng_rx_addr[0]) rng_hi <= eng_rx_data;
        else rng_sum <= {rng_sum[14:0], rng_sum[15]} + {rng_hi, eng_rx_data};
      end

      case (state)
        ST_BANNER: begin
          sp_msg           <= MSG_BANNER;
          next_after_print <= ST_MENU;
          state            <= ST_PRINT;
        end

        ST_MENU: begin
          cmd_running      <= 1'b0;
          phase_write      <= 1'b0;
          copy_phase       <= 1'b0;
          sp_msg           <= MSG_SD_STATUS0 + {4'b0000, sd_status};
          next_after_print <= ST_MENU2;
          state            <= ST_PRINT;
        end

        ST_MENU2: begin
          sp_msg           <= MSG_MENU;
          next_after_print <= ST_MENU3;
          state            <= ST_PRINT;
        end

        // the menu does not fit in one 64-character status message, so its
        // tail (and the "# " prompt) is a second one
        ST_MENU3: begin
          sp_msg           <= MSG_MENU2;
          next_after_print <= ST_KEY;
          state            <= ST_PRINT;
        end

        ST_KEY:
        if (rx_valid) begin
          echo_ch    <= rx_data;  // echoed as <key> CR LF for accepted keys
          ec_i       <= 2'd0;
          ec_crlf    <= 1'b1;
          ec_gap     <= 1'b0;
          err_flag   <= 1'b0;
          done_flag  <= 1'b0;
          wd         <= 0;
          copy_phase <= 1'b0;
          fx_create  <= 1'b0;
          list_done  <= 1'b0;
          case (rx_data)
            "1": begin
              mode        <= M_LIST;
              cmd_running <= 1'b1;
              echo_next   <= ST_CARD;
              state       <= ST_ECHO;
            end
            "2": begin
              mode        <= M_DUMP;
              cmd_running <= 1'b1;
              echo_next   <= ST_CARD;
              state       <= ST_ECHO;
            end
            "3": begin
`ifdef SDFAT_REWRITE
              mode        <= M_COPY;
              cmd_running <= 1'b1;
              echo_next   <= ST_CARD;
              state       <= ST_ECHO;
`else
              sp_msg           <= MSG_NOTIMPL;
              next_after_print <= ST_MENU;
              echo_next        <= ST_PRINT;
              state            <= ST_ECHO;
`endif
            end
            "4": begin
`ifdef SDFAT_TEST_READONLY
              // the read-only build contains no block-write path at all
              sp_msg           <= MSG_NOTIMPL;
              next_after_print <= ST_MENU;
              echo_next        <= ST_PRINT;
              state            <= ST_ECHO;
`else
`ifdef SDFAT_WRITE
              mode        <= M_BLK;
              cmd_running <= 1'b1;
              echo_next   <= ST_CARD;
              state       <= ST_ECHO;
`else
              sp_msg           <= MSG_NOTIMPL;
              next_after_print <= ST_MENU;
              echo_next        <= ST_PRINT;
              state            <= ST_ECHO;
`endif
`endif
            end
            "5": begin
`ifdef SDFAT_CHECK
              mode        <= M_CHK;
              cmd_running <= 1'b1;
              echo_next   <= ST_CARD;
              state       <= ST_ECHO;
`else
              sp_msg           <= MSG_NOTIMPL;
              next_after_print <= ST_MENU;
              echo_next        <= ST_PRINT;
              state            <= ST_ECHO;
`endif
            end
            "6": begin
`ifdef SDFAT_SPEED
              mode        <= M_IOW;
              cmd_running <= 1'b1;
              echo_next   <= ST_CARD;
              state       <= ST_ECHO;
`else
              sp_msg           <= MSG_NOTIMPL;
              next_after_print <= ST_MENU;
              echo_next        <= ST_PRINT;
              state            <= ST_ECHO;
`endif
            end
            "7": begin
`ifdef SDFAT_SPEED
              mode        <= M_IOR;
              cmd_running <= 1'b1;
              echo_next   <= ST_CARD;
              state       <= ST_ECHO;
`else
              sp_msg           <= MSG_NOTIMPL;
              next_after_print <= ST_MENU;
              echo_next        <= ST_PRINT;
              state            <= ST_ECHO;
`endif
            end
            // ---- streaming diagnostics: both ask for a number first ------
            // Both read their sectors through the sd_writer engine's READ
            // path, so they need that engine compiled in (SDFAT_WRITE names
            // the module, not the direction - the read-only build keeps it
            // and ties its rd_mode to 1).
            "8": begin
`ifdef SDFAT_WRITE
              mode             <= M_BDMP;
              num_val          <= 0;
              num_dig          <= 1'b0;
              sp_msg           <= MSG_ASK_BLK;
              next_after_print <= ST_NUM;
              echo_next        <= ST_PRINT;
              state            <= ST_ECHO;
`else
              sp_msg           <= MSG_NOTIMPL;
              next_after_print <= ST_MENU;
              echo_next        <= ST_PRINT;
              state            <= ST_ECHO;
`endif
            end
            "9": begin
`ifdef SDFAT_WRITE
              mode             <= M_SDMP;
              num_val          <= 0;
              num_dig          <= 1'b0;
              sp_msg           <= MSG_ASK_SEC;
              next_after_print <= ST_NUM;
              echo_next        <= ST_PRINT;
              state            <= ST_ECHO;
`else
              sp_msg           <= MSG_NOTIMPL;
              next_after_print <= ST_MENU;
              echo_next        <= ST_PRINT;
              state            <= ST_ECHO;
`endif
            end
            "R", "r": begin
`ifdef SDFAT_WRITE
              mode             <= M_RDMP;
              num_val          <= 0;
              num_dig          <= 1'b0;
              num_second       <= 1'b0;   // start block first, then the count
              sp_msg           <= MSG_ASK_STA;
              next_after_print <= ST_NUM;
              echo_next        <= ST_PRINT;
              state            <= ST_ECHO;
`else
              sp_msg           <= MSG_NOTIMPL;
              next_after_print <= ST_MENU;
              echo_next        <= ST_PRINT;
              state            <= ST_ECHO;
`endif
            end
            "N", "n": begin
              rt_len           <= 0;   // typing a name replaces the old one
              rt_name          <= 0;
              sp_msg           <= MSG_ASK_NAME;
              next_after_print <= ST_NAME;
              echo_next        <= ST_PRINT;
              state            <= ST_ECHO;
            end
            "H", "h", "?": begin
              sp_msg           <= MSG_HELP1;
              next_after_print <= ST_HELP;
              echo_next        <= ST_PRINT;
              state            <= ST_ECHO;
            end
`ifdef SDFAT_EXT_TEST
            // ---- external memory tests (Nexys 4 DDR) --------------------
            // The external module owns the console until it clears ext_busy;
            // the card is not touched, so no reader phase is entered here.
            "M", "m": begin
              ext_id      <= 4'd0;      // DDR2
              cmd_running <= 1'b1;
              echo_next   <= ST_EXT_W;
              state       <= ST_ECHO;
            end
            "B", "b": begin
              ext_id      <= 4'd1;      // ND-120 memory path (BRAM)
              cmd_running <= 1'b1;
              echo_next   <= ST_EXT_W;
              state       <= ST_ECHO;
            end
`endif
            default: state <= ST_MENU;  // anything else: reprint the menu
          endcase
        end

        // ---- echo the accepted key + CR-LF, then run the command --------
        // ec_crlf = 0 echoes the character alone (console number/name entry,
        // where the line ends only when the operator presses CR); entering
        // with ec_i = 1 and ec_crlf = 1 emits just the CR LF.
        ST_ECHO:
        if (ec_gap) ec_gap <= 1'b0;  // let tx_busy assert before polling
        else if (ec_i == (ec_crlf ? 2'd3 : 2'd1)) state <= echo_next;
        else if (!tx_busy) begin
          ec_valid <= 1'b1;
          ec_byte  <= (ec_i == 2'd0) ? echo_ch : (ec_i == 2'd1) ? 8'h0D : 8'h0A;
          ec_i     <= ec_i + 2'd1;
          ec_gap   <= 1'b1;
        end

        // ---- decimal number entry (commands 8 and 9) --------------------
        ST_NUM:
        if (rx_valid) begin
          if (rx_data >= "0" && rx_data <= "9") begin
            if (num_fits) num_val <= num_x10 + {28'b0, rx_data[3:0]};
            num_dig   <= 1'b1;
            echo_ch   <= rx_data;
            ec_i      <= 2'd0;
            ec_crlf   <= 1'b0;   // echo the digit, stay on the same line
            ec_gap    <= 1'b0;
            echo_next <= ST_NUM;
            state     <= ST_ECHO;
          end else if (rx_data == 8'h0D || rx_data == 8'h0A) begin
            ec_i    <= 2'd1;     // CR LF only, then act on the number
            ec_crlf <= 1'b1;
            ec_gap  <= 1'b0;
            if (!num_dig) begin
              sp_msg           <= MSG_ERR_NUM;
              err_flag         <= 1'b1;
              next_after_print <= ST_MENU;
              echo_next        <= ST_PRINT;
            end else if ((mode == M_RDMP) && !num_second) begin
              // RANGE takes two numbers: this was the start block, now ask
              // for the count (the CR LF goes out first, then the prompt)
              rng_start        <= num_val[23:0];
              num_val          <= 0;
              num_dig          <= 1'b0;
              num_second       <= 1'b1;
              sp_msg           <= MSG_ASK_CNT;
              next_after_print <= ST_NUM;
              echo_next        <= ST_PRINT;
            end else begin
              blk_no      <= num_val[23:0];
              sec_no      <= num_val;
              rng_cnt     <= num_val[23:0];
              cmd_running <= 1'b1;    // release the reader: init + mount
              wd          <= 0;
              echo_next   <= ST_CARD;
            end
            state <= ST_ECHO;
          end else begin
            // any other key aborts the entry - safer than guessing
            sp_msg           <= MSG_ERR_NUM;
            err_flag         <= 1'b1;
            next_after_print <= ST_MENU;
            echo_ch          <= rx_data;
            ec_i             <= 2'd0;
            ec_crlf          <= 1'b1;
            ec_gap           <= 1'b0;
            echo_next        <= ST_PRINT;
            state            <= ST_ECHO;
          end
        end

        // ---- file name entry (command N) --------------------------------
        // Lower case is folded to upper case for the console echo only; the
        // reader compares case-insensitively either way. The length limit is
        // 12 = 8 + '.' + 3, the longest 8.3 name there is.
        ST_NAME:
        if (rx_valid) begin
          if (rx_data == 8'h0D || rx_data == 8'h0A) begin
            sp_msg           <= (rt_len == 0) ? MSG_ERR_NUM : MSG_NAME_SET;
            err_flag         <= (rt_len == 0);
            next_after_print <= ST_MENU;
            ec_i             <= 2'd1;   // CR LF only
            ec_crlf          <= 1'b1;
            ec_gap           <= 1'b0;
            echo_next        <= ST_PRINT;
            state            <= ST_ECHO;
          end else if (rx_data > 8'h20 && rt_len < 8'd12) begin
            rt_name[8*rt_len+:8] <= (rx_data >= "a" && rx_data <= "z")
                                    ? (rx_data - 8'd32) : rx_data;
            rt_len    <= rt_len + 8'd1;
            echo_ch   <= (rx_data >= "a" && rx_data <= "z")
                         ? (rx_data - 8'd32) : rx_data;
            ec_i      <= 2'd0;
            ec_crlf   <= 1'b0;
            ec_gap    <= 1'b0;
            echo_next <= ST_NAME;
            state     <= ST_ECHO;
          end
        end

        // ---- print hx_val as 8 hex digits + CR LF ------------------------
        ST_HEXOUT:
        if (ec_gap) ec_gap <= 1'b0;
        else if (hx_i == 4'd10) state <= hx_next;
        else if (!tx_busy) begin
          ec_valid <= 1'b1;
          ec_byte  <= (hx_i < 4'd8) ? hexd(hx_val[31-4*hx_i[2:0]-:4])
                     : (hx_i == 4'd8) ? 8'h0D : 8'h0A;
          hx_i     <= hx_i + 4'd1;
          ec_gap   <= 1'b1;
        end

        ST_CARD:
        if (card_ready) begin
          // card_type 1/2/3 maps directly onto MSG_CARD_SDV1/SDV2/SDHC
          sp_msg           <= {4'b0000, card_type};
          // the absolute-sector dump deliberately skips the FS: line - it
          // must work on a card whose filesystem does not mount at all
          next_after_print <= (mode == M_SDMP) ? ST_SWAIT : ST_FS;
          state            <= ST_PRINT;
        end else if (wd == WD_MAX) begin
          sp_msg           <= MSG_ERR_CARD_TO;
          err_flag         <= 1'b1;
          sd_status        <= SD_NOCARD;
          next_after_print <= ST_MENU;
          state            <= ST_PRINT;
        end else wd <= wd + 1;

        ST_FS:
        if (fs_type[1]) begin
          // fs_type 2/3 maps onto MSG_FS_FAT16/FAT32 (= fs_type + 2)
          sp_msg           <= 6'd2 + {4'b0000, fs_type};
          sd_status        <= SD_OK;
          next_after_print <= scan_only ? ST_LSCAN : ST_FILE;
          state            <= ST_PRINT;
        end else if (scan_done) begin
          sp_msg           <= MSG_FS_UNKNOWN;
          err_flag         <= 1'b1;
          sd_status        <= SD_ERROR;
          next_after_print <= ST_MENU;
          state            <= ST_PRINT;
        end else if (wd == WD_MAX) begin
          sp_msg           <= MSG_ERR_SCAN_TO;
          err_flag         <= 1'b1;
          sd_status        <= SD_ERROR;
          next_after_print <= ST_MENU;
          state            <= ST_PRINT;
        end else wd <= wd + 1;

        // ---- DUMP / COPY phase 0: read BOOT.BPUN into the buffer -------
        ST_FILE:
        if (file_found) begin
          if (mode == M_IOR && file_size != IO_BYTES) begin
            sp_msg           <= MSG_ERR_IOSZ;
            err_flag         <= 1'b1;
            next_after_print <= ST_MENU;
            state            <= ST_PRINT;
          end else if (mode == M_IOR) begin
            // size OK - but the reader is still mid-transaction: file_found
            // rises WHILE the directory sector is streaming from the card,
            // and the reader then streams the found file itself. Parking it
            // here left a REAL card in the SENDING-DATA state, where the
            // writer's next command is illegal and gets no response -> err
            // (silicon failure 11-JUL-2026; a stateless card model masked
            // it). Wait for scan_done like every other command: ST_STREAM
            // captures the sector and parks the reader cleanly.
            state <= ST_STREAM;
          end else begin
            sp_msg           <= MSG_FILE_FOUND;
            next_after_print <= ST_STREAM;
            state            <= ST_PRINT;
          end
        end else if (scan_done) begin
          if (mode == M_IOW) begin
            // IO.DAT does not exist yet: create it and go straight to the
            // allocation + timed write
            cp_is32        <= (fs_type == 2'd3);
            cp_cs          <= fs_cs;
            cp_fat0        <= fs_fat0;
            cp_spf         <= fs_spf;
            cp_nfat        <= fs_nfat;
            cp_dbase       <= fs_dbase;
            cp_total       <= fs_total;
            cp_rootclus    <= fs_rootclus;
            cp_old_cluster <= 0;
            fx_create      <= 1'b1;
            fx_realloc     <= 1'b1;
            phase_write    <= 1'b1;
            sp_msg         <= MSG_IOW_RUN;
            next_after_print <= ST_C_FIX;
            state          <= ST_PRINT;
          end else begin
            sp_msg           <= MSG_FILE_NOTFND;
            err_flag         <= 1'b1;
            next_after_print <= ST_MENU;
            state            <= ST_PRINT;
          end
        end else if (wd == WD_MAX) begin
          sp_msg           <= MSG_ERR_SCAN_TO;
          err_flag         <= 1'b1;
          sd_status        <= SD_ERROR;
          next_after_print <= ST_MENU;
          state            <= ST_PRINT;
        end else wd <= wd + 1;

        ST_STREAM:
        if (scan_done) begin
          if (trunc) begin
            // DUMP: still dump what fit; COPY: abort (never write a
            // truncated copy)
            sp_msg           <= MSG_ERR_TRUNC;
            err_flag         <= (mode == M_COPY);
            next_after_print <= (mode == M_COPY) ? ST_MENU : ST_DUMP;
            state            <= ST_PRINT;
          end else if (mode == M_COPY) begin
            // phase 1: re-scan for TEST.TXT while announcing the copy
            copy_len         <= wptr;
            copy_phase       <= 1'b1;
            rdrst_cnt        <= 5'd31;
            sp_msg           <= MSG_COPYING;
            next_after_print <= ST_C_FIND;
            state            <= ST_PRINT;
          end else if (mode == M_IOR) begin
            // reader finished (scan_done: it streamed IO.DAT once in 1-bit
            // and sent its CMD12 - the card is back in TRANSFER state and
            // idle): NOW capture the sector and park it for the timed
            // CMD18 burst read through the writer engine
            tgt_sector       <= file_first_sector;
            nsec             <= IO_SECT;
            seccnt           <= 0;
            phase_write      <= 1'b1;
            sp_msg           <= MSG_IOR_RUN;
            next_after_print <= ST_C_WRITE;
            state            <= ST_PRINT;
          end else if (mode == M_IOW) begin
            // rewrite IO.DAT from scratch: free + allocate IO_BLOCKS blocks
            cp_is32        <= (fs_type == 2'd3);
            cp_cs          <= fs_cs;
            cp_fat0        <= fs_fat0;
            cp_spf         <= fs_spf;
            cp_nfat        <= fs_nfat;
            cp_dbase       <= fs_dbase;
            cp_total       <= fs_total;
            cp_rootclus    <= fs_rootclus;
            cp_dir_sec     <= fnd_dir_sec;
            cp_dir_idx     <= fnd_dir_idx;
            cp_old_cluster <= fnd_cluster;
            fx_realloc     <= 1'b1;   // 6 always deletes the old file first
            fx_create      <= 1'b0;
            phase_write    <= 1'b1;
            sp_msg         <= MSG_IOW_RUN;
            next_after_print <= ST_C_FIX;
            state          <= ST_PRINT;
          end else if (mode == M_RDMP) begin
            // RANGE: the whole run must lie inside the file, and an empty
            // run is a typo, not a request
            if (rng_cnt == 24'd0 || {8'b0, file_size} < rng_need) begin
              sp_msg           <= MSG_ERR_RANGE;
              err_flag         <= 1'b1;
              next_after_print <= ST_MENU;
              state            <= ST_PRINT;
            end else begin
              // capture BEFORE phase_write parks the reader (same edge)
              tgt_sector       <= file_first_sector + {6'b0, rng_start, 2'b00};
              hx_val           <= file_first_sector + {6'b0, rng_start, 2'b00};
              nsec             <= 13'd4;   // the loop runs ONE block at a time
              seccnt           <= 0;
              rng_blk          <= 0;
              rng_sum          <= 0;
              rng_hi           <= 0;
              io_cycles        <= 0;       // 27 MHz cycles, card traffic only
              phase_write      <= 1'b1;
              hx_i             <= 0;
              hx_next          <= ST_C_WRITE;
              sp_msg           <= MSG_R_RUN;  // "...AT SECTOR " + 8 hex digits
              next_after_print <= ST_HEXOUT;
              state            <= ST_PRINT;
            end
          end else if (mode == M_BDMP) begin
            // 1KW block read: same framing as WRBLK1 (ND-120 block = 1024
            // 16-bit words = 2048 bytes = 4 SD sectors, block N at
            // file_first_sector + 4*N, which assumes the file occupies
            // consecutive sectors - command 9 is how that assumption gets
            // checked). Refuse a block that starts past the end of the
            // file: those sectors belong to another file and reporting
            // them as this file's data is exactly the confusion this tool
            // exists to remove.
            if ({8'b0, file_size} < blk_need) begin
              sp_msg           <= MSG_ERR_RANGE;
              err_flag         <= 1'b1;
              next_after_print <= ST_MENU;
              state            <= ST_PRINT;
            end else begin
              // capture BEFORE phase_write parks the reader (same edge)
              tgt_sector       <= file_first_sector + {6'b0, blk_no, 2'b00};
              hx_val           <= file_first_sector + {6'b0, blk_no, 2'b00};
              nsec             <= 13'd4;
              seccnt           <= 0;
              phase_write      <= 1'b1;
              hx_i             <= 0;
              hx_next          <= ST_C_WRITE;
              sp_msg           <= MSG_AT_SEC;   // "AT SECTOR " + 8 hex digits
              next_after_print <= ST_HEXOUT;
              state            <= ST_PRINT;
            end
          end else if (mode == M_BLK) begin
            // 1KW block write: the block must lie entirely inside the file
            // (past its end = inside the NEXT file's clusters)
            if (file_size < ({23'b0, BLK_NO} + 32'd1) * 32'd2048) begin
              sp_msg           <= MSG_ERR_RANGE;
              err_flag         <= 1'b1;
              next_after_print <= ST_MENU;
              state            <= ST_PRINT;
            end else begin
              // capture BEFORE phase_write parks the reader (same edge)
              tgt_sector       <= file_first_sector + {25'b0, BLK_NO, 2'b00};
              nsec             <= 13'd4;  // 1 block = 4 SD sectors
              seccnt           <= 0;
              phase_write      <= 1'b1;
              sp_msg           <= MSG_BLK_WRITING;
              next_after_print <= ST_C_WRITE;
              state            <= ST_PRINT;
            end
          end else begin
            state <= ST_DUMP;
          end
        end else if (wd == WD_MAX) begin
          sp_msg           <= MSG_ERR_SCAN_TO;
          err_flag         <= 1'b1;
          sd_status        <= SD_ERROR;
          next_after_print <= ST_MENU;
          state            <= ST_PRINT;
        end else wd <= wd + 1;

        // ---- SECTOR (9): the FAT is not consulted at all -----------------
        // The reader still runs to completion first: parking it mid-command
        // leaves a real card in the SENDING-DATA state and the next command
        // on the bus gets no answer (silicon failure 11-JUL-2026, see the
        // note in ST_FILE). scan_done arrives even when the volume did not
        // mount, which is what makes this command usable on a broken card.
        ST_SWAIT:
        if (scan_done) begin
          tgt_sector       <= sec_no;
          hx_val           <= sec_no;
          nsec             <= 13'd1;
          seccnt           <= 0;
          phase_write      <= 1'b1;
          hx_i             <= 0;
          hx_next          <= ST_C_WRITE;
          sp_msg           <= MSG_AT_SEC;
          next_after_print <= ST_HEXOUT;
          state            <= ST_PRINT;
        end else if (wd == WD_MAX) begin
          sp_msg           <= MSG_ERR_SCAN_TO;
          err_flag         <= 1'b1;
          sd_status        <= SD_ERROR;
          next_after_print <= ST_MENU;
          state            <= ST_PRINT;
        end else wd <= wd + 1;

        ST_DUMP: begin
          hd_start <= 1'b1;
          state    <= ST_DUMP_W;
        end

        ST_DUMP_W: if (!hd_start && !hd_busy) state <= ST_CMD_END;

        // ---- LIST -------------------------------------------------------
        ST_LSCAN:
        if (scan_done && pk_state == PK_IDLE) begin
          if (mode == M_CHK) begin
            // capture the geometry before phase_write parks the reader
            cp_is32  <= (fs_type == 2'd3);
            cp_cs    <= fs_cs;
            cp_fat0  <= fs_fat0;
            cp_spf   <= fs_spf;
            cp_nfat  <= fs_nfat;
            cp_dbase <= fs_dbase;
            cp_total <= fs_total;
            cp_rootclus <= fs_rootclus;
            vt_n_r   <= vt_n;
            phase_write <= 1'b1;
            wd       <= 0;
            state    <= ST_CHK;
          end else begin
            // LIST: freeze the listing, capture the geometry + capacity
            // (same edge - the reader parks next cycle), then scan FAT #0
            // for the free count and append the disk-info line
            list_done <= 1'b1;
            cp_is32   <= (fs_type == 2'd3);
            cp_cs     <= fs_cs;
            cp_fat0   <= fs_fat0;
            cp_spf    <= fs_spf;
            cp_nfat   <= fs_nfat;
            cp_dbase  <= fs_dbase;
            cp_total  <= fs_total;
            cp_rootclus <= fs_rootclus;
            cp_cap    <= rd_cap_mb;
`ifdef SDFAT_FREESCAN
            phase_write      <= 1'b1;
            sp_msg           <= MSG_SCANNING;
            next_after_print <= ST_FREE;
            state            <= ST_PRINT;
`else
            il_have_free <= 1'b0;  // no scanner: the line says FREE N/A
            state        <= ST_INFO;
`endif
          end
        end else if (wd == WD_MAX) begin
          sp_msg           <= MSG_ERR_SCAN_TO;
          err_flag         <= 1'b1;
          sd_status        <= SD_ERROR;
          next_after_print <= ST_MENU;
          state            <= ST_PRINT;
        end else wd <= wd + 1;

        ST_LPRINT: begin
          tp_start <= 1'b1;
          state    <= ST_LPRINT_W;
        end

        ST_LPRINT_W: if (!tp_start && !tp_busy) state <= ST_CMD_END;

        // ---- LIST tail: free-space scan + disk-info line ------------------
        ST_FREE:
        if (!fsn_busy && !fsn_start) begin
          fsn_start <= 1'b1;
          wd        <= 0;
          state     <= ST_FREE_W;
        end

        ST_FREE_W:
        if (fsn_done) begin
          il_have_free <= 1'b1;
          state        <= ST_INFO;
        end else if (fsn_err || wd == WD_MAX) begin
          il_have_free <= 1'b0;  // scan failed: the line says FREE N/A
          state        <= ST_INFO;
        end else begin
          if (fsn_tick) wd <= 0;  // per-sector progress feeds the watchdog
          else wd <= wd + 1;
        end

        ST_INFO:
        if (!il_busy && !il_go) begin
          il_go <= 1'b1;
          state <= ST_INFO_W;
        end

        ST_INFO_W:
        if (!il_go && !il_busy) begin
          // reader stays parked through the print (see ST_CHK_W)
          state <= ST_LPRINT;
        end

        // ---- CHECK: walk every root file's cluster chain -----------------
        ST_CHK:
        if (!ck_busy && !ck_start) begin
          ck_start <= 1'b1;
          wd       <= 0;
          state    <= ST_CHK_W;
        end

        ST_CHK_W:
        if (ck_done) begin
          // reader stays parked while the report prints (ST_MENU releases
          // it together with cmd_running - no truncated restart commands)
          state <= ST_LPRINT;
        end else if (ck_err || wd == WD_MAX) begin
          phase_write      <= 1'b0;
          // CHECK only READS (FAT chains through the engine): the truthful
          // failure text is a FAT read error, never "SD WRITE FAILED"
          sp_msg           <= MSG_ERR_FATRD;
          err_flag         <= 1'b1;
          sd_status        <= SD_ERROR;
          next_after_print <= ST_MENU;
          state            <= ST_PRINT;
        end else wd <= wd + 1;

        // ---- IO speed: divide, format, print ------------------------------
        ST_SPEED:
        if (!spf_busy && !spf_go) begin
          spf_go   <= 1'b1;
          spf_read <= (mode == M_IOR);
          wd       <= 0;
          state    <= ST_SPEED_W;
        end

        ST_SPEED_W:
        if (!spf_go && !spf_busy) begin
          // reader stays parked through the print (see ST_CHK_W)
          state <= ST_LPRINT;  // print "WRITE/READ NNNNN KB/S"
        end else if (wd == WD_MAX) begin
          phase_write      <= 1'b0;
          sp_msg           <= (mode == M_IOR) ? MSG_ERR_READ : MSG_ERR_WRITE;
          err_flag         <= 1'b1;
          next_after_print <= ST_MENU;
          state            <= ST_PRINT;
        end else wd <= wd + 1;

        // ---- HELP: MSG_HELP1..12 then back to the menu -------------------
        // The help texts are not one contiguous run of message codes: 1..7
        // were allocated before the error/status codes 33..39, so 8..12 sit
        // above those and the sequence hops once.
        ST_HELP:
        if (sp_msg == MSG_HELP13) begin
          state <= ST_MENU;
        end else begin
          sp_msg           <= (sp_msg == MSG_HELP7) ? MSG_HELP8 : (sp_msg + 6'd1);
          next_after_print <= ST_HELP;
          state            <= ST_PRINT;
        end

        // ---- COPY phases 1-2: locate TEST.TXT, rewrite it in place ------
        ST_C_FIND:
        if (scan_done) begin
          if (!file_found) begin
            // TEST.TXT does not exist: create it (fresh 8.3 root entry)
            cp_is32        <= (fs_type == 2'd3);
            cp_cs          <= fs_cs;
            cp_fat0        <= fs_fat0;
            cp_spf         <= fs_spf;
            cp_nfat        <= fs_nfat;
            cp_dbase       <= fs_dbase;
            cp_total       <= fs_total;
            cp_rootclus    <= fs_rootclus;
            cp_old_cluster <= 0;
            fx_create      <= 1'b1;
            fx_realloc     <= 1'b1;
            phase_write    <= 1'b1;
            wd             <= 0;
            state          <= ST_C_FIX;
          end else begin
            // capture EVERYTHING before phase_write parks the reader
            // (same clock edge; the reader's registers reset next cycle)
            tgt_sector     <= file_first_sector;  // kept when realloc=0
            nsec           <= {4'b0, (copy_len + 17'd511) >> 9};
            seccnt         <= 0;
            cp_is32        <= (fs_type == 2'd3);
            cp_cs          <= fs_cs;
            cp_fat0        <= fs_fat0;
            cp_spf         <= fs_spf;
            cp_nfat        <= fs_nfat;
            cp_dbase       <= fs_dbase;
            cp_total       <= fs_total;
            cp_rootclus    <= fs_rootclus;
            cp_dir_sec     <= fnd_dir_sec;
            cp_dir_idx     <= fnd_dir_idx;
            cp_old_cluster <= fnd_cluster;
            // too small (or empty) -> full replacement; else size patch only
            fx_realloc     <= (file_size < {{(31 - BUF_AW){1'b0}}, copy_len});
            fx_create      <= 1'b0;
            phase_write    <= 1'b1;
            wd             <= 0;
            state          <= ST_C_FIX;
          end
        end else if (wd == WD_MAX) begin
          sp_msg           <= MSG_ERR_SCAN_TO;
          err_flag         <= 1'b1;
          sd_status        <= SD_ERROR;
          next_after_print <= ST_MENU;
          state            <= ST_PRINT;
        end else wd <= wd + 1;

        ST_C_FIX:
        if (!fx_busy && !fx_start) begin
          fx_start <= 1'b1;
          wd       <= 0;
          state    <= ST_C_FIX_W;
        end

        ST_C_FIX_W:
        if (fx_done) begin
          // the (possibly new) contiguous data area of the target
          tgt_sector <= cp_dbase + {24'b0, cp_cs} * fx_new_first;
          if (mode == M_IOW) begin
            nsec      <= IO_SECT;
            seccnt    <= 0;
            io_cycles <= 0;
            io_run    <= 1'b1;  // the write clock starts with the first sector
          end
          wd         <= 0;
          state      <= ST_C_WRITE;
        end else if (fx_err || wd == WD_MAX) begin
          phase_write      <= 1'b0;
          // truthful surgeon verdicts: only a COMPLETED scan without a
          // free run is "NO CONTIGUOUS FREE SPACE"; a failed FAT read is a
          // read error (silicon 12-JUL-2026 printed no-space for garbage
          // FAT reads and sent the operator hunting a full card)
          sp_msg           <= !fx_err ? MSG_ERR_WRITE
                            : (fx_err_kind == 2'd0) ? MSG_ERR_SMALL
                            : (fx_err_kind == 2'd1) ? MSG_ERR_FATRD
                            : (fx_err_kind == 2'd3) ? MSG_ERR_FATCOR
                            : MSG_ERR_WRITE;
          err_flag         <= 1'b1;
          sd_status        <= SD_ERROR;
          next_after_print <= ST_MENU;
          state            <= ST_PRINT;
        end else wd <= wd + 1;

        ST_C_WRITE:
        if (seccnt >= nsec) begin
          if (mode == M_RDMP) begin
            io_run <= 1'b0;   // stop the clock before any console traffic
            state  <= ST_R_NEXT;
          end else if (dump_mode) begin
            // the sectors are in the buffer; the reader stays parked while
            // hex_dumper prints them (see ST_CHK_W for why)
            state <= ST_DUMP;
          end else if (io_mode) begin
            io_run <= 1'b0;
            state  <= ST_SPEED;  // phase_write stays up: the report uses the buffer
          end else begin
            // reader stays parked through the print (see ST_CHK_W)
            sp_msg           <= (mode == M_BLK) ? MSG_BLK_DONE : MSG_COPY_DONE;
            next_after_print <= ST_CMD_END;
            state            <= ST_PRINT;
          end
        end else if (!wr_busy && !wr_start) begin
          // menus 6/7 go in CMD25/CMD18 bursts of up to 128 sectors;
          // COPY/WRBLK1 keep the proven single-sector path (burst_len=1)
          wr_burst <= io_mode ? burst_now : 9'd1;
          // RANGE times the CARD traffic only: the counter runs while
          // sectors move and is stopped around every console line
          if (mode == M_RDMP) io_run <= 1'b1;
          if (mode == M_IOR && seccnt == 0) begin
            io_cycles <= 0;
            io_run    <= 1'b1;  // the read clock starts with the first burst
          end
          wr_start <= 1'b1;
          wd       <= 0;
          state    <= ST_C_NEXT;
        end

        ST_C_NEXT:
        if (wr_done) begin
          seccnt <= seccnt + 13'd1;  // the final block of the burst
          state  <= ST_C_WRITE;
        end else if (wr_block_next) begin
          seccnt <= seccnt + 13'd1;  // block k>=1 of the burst: advance the source
          wd     <= 0;
        end else if (wr_err || wd == WD_MAX) begin
          // menu 7/8/9/R are READS through the engine: report them as such
          sp_msg    <= ((mode == M_IOR) || dump_mode) ? MSG_ERR_READ
                                                     : MSG_ERR_WRITE;
          err_flag  <= 1'b1;
          sd_status <= SD_ERROR;
          if (mode == M_RDMP) begin
            // THE point of the range command: name the exact place it died,
            // then still print the summary. The reader stays parked for it
            // (ST_MENU releases it) exactly as after a completed run.
            io_run           <= 1'b0;
            next_after_print <= ST_R_ERR;
          end else begin
            phase_write      <= 1'b0;
            next_after_print <= ST_MENU;
          end
          state <= ST_PRINT;
        end else wd <= wd + 1;

        // ---- RANGE: one block finished ----------------------------------
        // Nothing here scales with the run length: the same 4-sector loop is
        // re-armed one block further on, and only the counters move.
        ST_R_NEXT: begin
          rng_blk <= rng_blk + 24'd1;
          if (rng_blk + 24'd1 >= rng_cnt) begin
            r_i   <= 0;
            state <= ST_R_SUM;
          end else begin
            tgt_sector <= tgt_sector + 32'd4;  // next block = 4 more sectors
            seccnt     <= 0;
            // a sign of life every 64 blocks (128 KB): at 9600 baud one
            // line per block would cost more time than the reading does
            if (rng_blk[5:0] == 6'd63) begin
              hx_val           <= {8'b0, rng_blk + 24'd1};
              hx_i             <= 0;
              hx_next          <= ST_C_WRITE;
              sp_msg           <= MSG_R_AT;
              next_after_print <= ST_HEXOUT;
              state            <= ST_PRINT;
            end else state <= ST_C_WRITE;
          end
        end

        // ---- RANGE: a card read failed - say exactly where ---------------
        // The sector is the block base plus the index the engine was on;
        // both registers still hold the failing values here.
        ST_R_ERR: begin
          sp_msg           <= MSG_AT_SEC;
          hx_val           <= tgt_sector + {19'b0, seccnt};
          hx_i             <= 0;
          hx_next          <= ST_R_ERR2;
          next_after_print <= ST_HEXOUT;
          state            <= ST_PRINT;
        end

        ST_R_ERR2: begin
          sp_msg           <= MSG_R_AT;   // "AT BLOCK " + 8 hex digits
          hx_val           <= {8'b0, rng_blk};
          hx_i             <= 0;
          hx_next          <= ST_R_SUM;
          r_i              <= 0;
          next_after_print <= ST_HEXOUT;
          state            <= ST_PRINT;
        end

        // ---- RANGE: the summary, one labelled hex field per step ---------
        // err_flag is set by the read loop when the card failed, so the same
        // sequence reports a completed run and an aborted one - an aborted
        // one has already named the block and sector it died on.
        ST_R_SUM: begin
          r_i <= r_i + 3'd1;
          case (r_i)
            3'd0: begin
              sp_msg           <= MSG_R_BLOCKS;
              hx_val           <= {8'b0, rng_blk};
              hx_i             <= 0;
              hx_next          <= ST_R_SUM;
              next_after_print <= ST_HEXOUT;
              state            <= ST_PRINT;
            end
            3'd1: begin
              sp_msg           <= MSG_R_SECS;
              hx_val           <= {6'b0, rng_blk, 2'b00};  // 4 sectors a block
              hx_i             <= 0;
              hx_next          <= ST_R_SUM;
              next_after_print <= ST_HEXOUT;
              state            <= ST_PRINT;
            end
            3'd2: begin
              sp_msg           <= MSG_R_CHK;
              hx_val           <= {16'b0, rng_sum};
              hx_i             <= 0;
              hx_next          <= ST_R_SUM;
              next_after_print <= ST_HEXOUT;
              state            <= ST_PRINT;
            end
            3'd3: begin
              sp_msg           <= MSG_R_CYC;
              hx_val           <= io_cycles;  // 27 MHz; seconds = n / 27000000
              hx_i             <= 0;
              hx_next          <= ST_R_SUM;
              next_after_print <= ST_HEXOUT;
              state            <= ST_PRINT;
            end
            default: begin
              sp_msg           <= err_flag ? MSG_R_FAIL : MSG_R_PASS;
              next_after_print <= err_flag ? ST_MENU : ST_CMD_END;
              state            <= ST_PRINT;
            end
          endcase
        end

        // ---- common tail ------------------------------------------------
        ST_CMD_END: begin
          done_flag <= 1'b1;
          state     <= ST_MENU;
        end

`ifdef SDFAT_EXT_TEST
        // Kick the external test once, then wait for it to release ext_busy.
        // Kicking here rather than in ST_KEY keeps the echoed key and the
        // test's own output from interleaving.
        ST_EXT_W:
        if (!ext_kicked) begin
          ext_start  <= 1'b1;
          ext_kicked <= 1'b1;
        end else begin
          ext_start <= 1'b0;
          if (!ext_busy && !ext_start) begin
            ext_kicked <= 1'b0;
            state      <= ST_CMD_END;
          end
        end
`endif

        ST_PRINT: begin
          sp_start <= 1'b1;
          wd       <= 0;
          state    <= ST_PRINT_W;
        end

        ST_PRINT_W: if (!sp_start && !sp_busy) state <= next_after_print;

        default: state <= ST_BANNER;
      endcase
    end
  end

endmodule
