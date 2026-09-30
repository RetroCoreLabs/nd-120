`include "nd_storage_status.vh"
/****************************************************************************
** nd_storage_mister_devices - the ND-120 storage subsystem on the MiSTer  **
**                                                                         **
** The MiSTer counterpart of Verilog/SD-FAT/circuit/nd_storage_devices.v:  **
** the same "storage subsystem in a box" with pin-for-pin FDISK_* and FDBUF_*, **
** WDISK_* and WDBUF_* and TAPE byte-source seams matching ND120_CORE, but **
** with nd_storage_hps behind the adapters instead of the SD/FAT stack.    **
** No SD card, no SPI, no FAT: the images are files the user mounts from   **
** the MiSTer OSD, one per slot.                                           **
**                                                                         **
** SLOT MAP (= OSD "S<n>" lines in nd120.sv's CONF_STR, = hps_io VDNUM     **
** index, = nd_storage_hps client):                                        **
**   0  floppy drive 0   (ND_FLOPPY_DMA command word b7:6 = 0)             **
**   1  floppy drive 1   (b7:6 = 1)                                        **
**   2  Winchester unit 0 (ND_WINCHESTER control word b9 = 0)              **
**   3  Winchester unit 1 (b9 = 1)                                         **
**   4  paper tape       (ND_TAPE_400 byte stream, read from byte 0)       **
** The Winchester card has a ONE-bit unit field, so two units is all it   **
** can address (ND_WINCHESTER.v header). The four-unit device would be the **
** SMD card, which this board does not build.                              **
**                                                                         **
** TWO ADAPTERS PER CONTROLLER. nd_storage_floppy_adapter and              **
** nd_storage_disc_adapter each serve ONE drive/unit (parameter DRIVE /    **
** UNIT) and ignore a request for any other completely - every output      **
** parked at 0 - so two instances share the controller's disk_* inputs and **
** their disk_done/disk_err/err_code/dbuf_* outputs are ORed. The Tang and **
** Nexys aggregator only ever instantiated ONE of each; this is the first  **
** build with a second floppy drive and a second Winchester unit, and the  **
** OR is what nd_storage_mister_devices_tb proves.                         **
**                                                                         **
** OPEN. There is nothing to open on this board - the file is whatever the **
** OSD mounted, and nd_storage_hps reports that as open_ok directly - so   **
** open_start is a single pulse after reset, purely to satisfy the         **
** adapters' contract. A drive whose slot has no image simply answers      **
** every request with err + NDS_ERR_NOTOPEN, which the controllers map     **
** onto their own "not ready" / "disk fault" status bits.                  **
**                                                                         **
** FLOPPY MEDIA FORMAT follows the SELECTED drive: FDISK_MEDIA_FMT is      **
** derived from slot 0's or slot 1's image size according to FDISK_DRIVE,  **
** by the same size rule the Tang aggregator and the C reference use       **
** (315392 bytes = 8-inch 512 B/sector -> 0; else the 1.2 MB 1024 B/sector **
** double-sided double-density descriptor -> 0xF).                         **
**                                                                         **
** Ronny Hansen, 01-SEP-2026                                                **
*****************************************************************************/

module nd_storage_mister_devices #(
    parameter integer BYTE_SWAP = 1     // see nd_storage_hps
) (
    input  wire clk_cpu,  //! 20 MHz, the ND-120 CPU/bus/device domain (from pll_cpu.outclk_0)
    input  wire rst_cpu_n,  //! Active-low reset, from the board's power-on reset (same net as ND120_CORE.sys_rst_n)
    input  wire clk_sys,  //! pixel clock, 40.000 MHz for 800x600@60 (same net as nd120_console_mister.clk)
    input  wire rst_sys_n,  //! async reset, active low, in the pixel domain (same net as nd120_console_mister.rst_n)

    // ---- ND_TAPE_400 byte source port (pin-for-pin) ----
    input  wire       byte_req,  //! pulse: fetch next tape byte (from ND120_CORE.TAPE_BYTE_REQ)
    output wire       byte_valid,  //! pulse: TAPE_BYTE_DATA is the byte (to ND120_CORE.TAPE_BYTE_VALID)
    output wire [7:0] byte_data,
    input  wire       source_rewind,  //! pulse: rewind the tape source (from ND120_CORE.TAPE_REWIND)
    // sticky tape diagnostic - see nd_storage_tape_adapter's header: the
    // ND-400 reader has no register for "no image", so it is published here
    output wire       TDISK_FAULT,
    output wire [3:0] TDISK_ERR_CODE,

    // ---- ND_FLOPPY_DMA disk-image backend seam (slots 0 and 1) ----
    input  wire        FDISK_REQ,
    input  wire        FDISK_WR,
    input  wire [15:0] FDISK_LSECT,
    input  wire [ 1:0] FDISK_FORMAT,
    input  wire [ 1:0] FDISK_DRIVE,
    input  wire [10:0] FDISK_WORDCOUNT,
    output wire        FDISK_DONE,
    output wire        FDISK_ERR,
    output wire [ 3:0] FDISK_ERR_CODE,
    output wire [ 3:0] FDISK_MEDIA_FMT,
    output wire [ 9:0] FDBUF_ADDR,
    output wire [15:0] FDBUF_WDATA,
    output wire        FDBUF_WE,
    input  wire [15:0] FDBUF_RDATA,

    // ---- ND_WINCHESTER disk-image backend seam (slots 2 and 3) ----
    input  wire        WDISK_START,
    input  wire        WDISK_REQ,
    input  wire        WDISK_WR,
    input  wire [15:0] WDISK_BLKADDR1,  //! head b15-8, sector b7-0 (from ND_WINCHESTER.disk_blkaddr1)
    input  wire [15:0] WDISK_BLKADDR2,
    input  wire [ 2:0] WDISK_UNIT,  //! only bit 0 is used - two units (from ND_WINCHESTER.disk_unit)
    input  wire [10:0] WDISK_WORDCOUNT,  //! words in the current chunk (from ND_WINCHESTER.disk_wordcount)
    output wire        WDISK_DONE,
    output wire        WDISK_ERR,
    output wire [ 3:0] WDISK_ERR_CODE,
    output wire [ 9:0] WDBUF_ADDR,
    output wire [15:0] WDBUF_WDATA,
    output wire        WDBUF_WE,
    input  wire [15:0] WDBUF_RDATA,

    // ---- hps_io block interface (clk_sys), flattened per slot ----
    input  wire [4:0]   img_mounted,
    input  wire         img_readonly,
    input  wire [63:0]  img_size,
    output wire [5*32-1:0] sd_lba,
    output wire [5*6-1:0]  sd_blk_cnt,
    output wire [4:0]   sd_rd,
    output wire [4:0]   sd_wr,
    input  wire [4:0]   sd_ack,
    input  wire [12:0]  sd_buff_addr,
    input  wire [15:0]  sd_buff_dout,
    output wire [15:0]  sd_buff_din,
    input  wire         sd_buff_wr,

    // ---- diagnostics (clk_cpu): which slots hold a file ----
    output wire [4:0]   MOUNTED
);

  localparam integer N = 5;
  localparam integer CL_FD0  = 0;
  localparam integer CL_FD1  = 1;
  localparam integer CL_WD0  = 2;
  localparam integer CL_WD1  = 3;
  localparam integer CL_TAPE = 4;

  // ---- flattened client buses ------------------------------------------------
  wire [N-1:0]    open_req_w, open_ok_w, open_err_w, req_w, wr_w;
  wire [N-1:0]    busy_w, done_w, err_w, buf_we_w;
  wire [N*4-1:0]  err_code_w;
  wire [N*32-1:0] size_bytes_w;
  wire [N*16-1:0] block_w, buf_wdata_w, buf_rdata_w;
  wire [N*10-1:0] buf_addr_w;

  // one open pulse after reset, for every adapter at once (nd_storage_hps
  // takes any number of concurrent open_req - there is no card to bring up)
  reg s_open_done;
  always @(posedge clk_cpu or negedge rst_cpu_n)
    if (!rst_cpu_n) s_open_done <= 1'b0;
    else            s_open_done <= 1'b1;
  wire s_open_pulse = !s_open_done;

  // ---- floppy: two adapters, outputs ORed ----------------------------------
  wire        f0_done, f0_err, f0_we, f1_done, f1_err, f1_we;
  wire [3:0]  f0_code, f1_code;
  wire [9:0]  f0_addr, f1_addr;
  wire [15:0] f0_wdata, f1_wdata;

  assign FDISK_DONE     = f0_done  | f1_done;
  assign FDISK_ERR      = f0_err   | f1_err;
  assign FDISK_ERR_CODE = f0_code  | f1_code;
  assign FDBUF_ADDR     = f0_addr  | f1_addr;
  assign FDBUF_WDATA    = f0_wdata | f1_wdata;
  assign FDBUF_WE       = f0_we    | f1_we;

  // media format of the SELECTED drive, from its image size (see header)
  wire [31:0] f0_size = size_bytes_w[CL_FD0*32 +: 32];
  wire [31:0] f1_size = size_bytes_w[CL_FD1*32 +: 32];
  wire [3:0]  f0_fmt  = (f0_size == 32'd315392) ? 4'h0 : 4'hF;
  wire [3:0]  f1_fmt  = (f1_size == 32'd315392) ? 4'h0 : 4'hF;
  assign FDISK_MEDIA_FMT = (FDISK_DRIVE == 2'd1) ? f1_fmt : f0_fmt;

  nd_storage_floppy_adapter #(.DRIVE(2'd0)) u_fd0 (
      .clk_cpu(clk_cpu), .rst_n(rst_cpu_n),
      .disk_req(FDISK_REQ), .disk_wr(FDISK_WR), .disk_lsect(FDISK_LSECT),
      .disk_format(FDISK_FORMAT), .disk_drive(FDISK_DRIVE), .disk_wordcount(FDISK_WORDCOUNT),
      .disk_done(f0_done), .disk_err(f0_err), .disk_err_code(f0_code),
      .dbuf_addr(f0_addr), .dbuf_wdata(f0_wdata), .dbuf_we(f0_we), .dbuf_rdata(FDBUF_RDATA),
      .open_start(s_open_pulse),
      .c_open_req(open_req_w[CL_FD0]), .c_open_ok(open_ok_w[CL_FD0]), .c_open_err(open_err_w[CL_FD0]),
      .c_size_bytes(f0_size),
      .c_req(req_w[CL_FD0]), .c_wr(wr_w[CL_FD0]), .c_block(block_w[CL_FD0*16 +: 16]),
      .c_busy(busy_w[CL_FD0]), .c_done(done_w[CL_FD0]), .c_err(err_w[CL_FD0]),
      .c_err_code(err_code_w[CL_FD0*4 +: 4]),
      .c_buf_addr(buf_addr_w[CL_FD0*10 +: 10]), .c_buf_wdata(buf_wdata_w[CL_FD0*16 +: 16]),
      .c_buf_we(buf_we_w[CL_FD0]), .c_buf_rdata(buf_rdata_w[CL_FD0*16 +: 16])
  );

  nd_storage_floppy_adapter #(.DRIVE(2'd1)) u_fd1 (
      .clk_cpu(clk_cpu), .rst_n(rst_cpu_n),
      .disk_req(FDISK_REQ), .disk_wr(FDISK_WR), .disk_lsect(FDISK_LSECT),
      .disk_format(FDISK_FORMAT), .disk_drive(FDISK_DRIVE), .disk_wordcount(FDISK_WORDCOUNT),
      .disk_done(f1_done), .disk_err(f1_err), .disk_err_code(f1_code),
      .dbuf_addr(f1_addr), .dbuf_wdata(f1_wdata), .dbuf_we(f1_we), .dbuf_rdata(FDBUF_RDATA),
      .open_start(s_open_pulse),
      .c_open_req(open_req_w[CL_FD1]), .c_open_ok(open_ok_w[CL_FD1]), .c_open_err(open_err_w[CL_FD1]),
      .c_size_bytes(f1_size),
      .c_req(req_w[CL_FD1]), .c_wr(wr_w[CL_FD1]), .c_block(block_w[CL_FD1*16 +: 16]),
      .c_busy(busy_w[CL_FD1]), .c_done(done_w[CL_FD1]), .c_err(err_w[CL_FD1]),
      .c_err_code(err_code_w[CL_FD1*4 +: 4]),
      .c_buf_addr(buf_addr_w[CL_FD1*10 +: 10]), .c_buf_wdata(buf_wdata_w[CL_FD1*16 +: 16]),
      .c_buf_we(buf_we_w[CL_FD1]), .c_buf_rdata(buf_rdata_w[CL_FD1*16 +: 16])
  );

  // ---- Winchester: two adapters, outputs ORed --------------------------------
  // The same nd_storage_disc_adapter the Tang uses for the Winchester, with
  // the Micropolis 1325 / DISC-74-1 geometry (8 heads, 9 sectors/track,
  // 1024-byte sectors), one per unit.
  wire        w0_done, w0_err, w0_we, w1_done, w1_err, w1_we;
  wire [3:0]  w0_code, w1_code;
  wire [9:0]  w0_addr, w1_addr;
  wire [15:0] w0_wdata, w1_wdata;

  assign WDISK_DONE     = w0_done  | w1_done;
  assign WDISK_ERR      = w0_err   | w1_err;
  assign WDISK_ERR_CODE = w0_code  | w1_code;
  assign WDBUF_ADDR     = w0_addr  | w1_addr;
  assign WDBUF_WDATA    = w0_wdata | w1_wdata;
  assign WDBUF_WE       = w0_we    | w1_we;

  nd_storage_disc_adapter #(.UNIT(3'd0), .GEO_HEADS(16'd8), .GEO_SPT(16'd9)) u_wd0 (
      .clk_cpu(clk_cpu), .rst_n(rst_cpu_n),
      .disk_start(WDISK_START), .disk_req(WDISK_REQ), .disk_wr(WDISK_WR),
      .disk_blkaddr1(WDISK_BLKADDR1), .disk_blkaddr2(WDISK_BLKADDR2), .disk_unit(WDISK_UNIT),
      .disk_wordcount(WDISK_WORDCOUNT),
      .disk_done(w0_done), .disk_err(w0_err), .disk_err_code(w0_code),
      .dbuf_addr(w0_addr), .dbuf_wdata(w0_wdata), .dbuf_we(w0_we), .dbuf_rdata(WDBUF_RDATA),
      .open_start(s_open_pulse),
      .c_open_req(open_req_w[CL_WD0]), .c_open_ok(open_ok_w[CL_WD0]), .c_open_err(open_err_w[CL_WD0]),
      .c_size_bytes(size_bytes_w[CL_WD0*32 +: 32]),
      .c_req(req_w[CL_WD0]), .c_wr(wr_w[CL_WD0]), .c_block(block_w[CL_WD0*16 +: 16]),
      .c_busy(busy_w[CL_WD0]), .c_done(done_w[CL_WD0]), .c_err(err_w[CL_WD0]),
      .c_err_code(err_code_w[CL_WD0*4 +: 4]),
      .c_buf_addr(buf_addr_w[CL_WD0*10 +: 10]), .c_buf_wdata(buf_wdata_w[CL_WD0*16 +: 16]),
      .c_buf_we(buf_we_w[CL_WD0]), .c_buf_rdata(buf_rdata_w[CL_WD0*16 +: 16])
  );

  nd_storage_disc_adapter #(.UNIT(3'd1), .GEO_HEADS(16'd8), .GEO_SPT(16'd9)) u_wd1 (
      .clk_cpu(clk_cpu), .rst_n(rst_cpu_n),
      .disk_start(WDISK_START), .disk_req(WDISK_REQ), .disk_wr(WDISK_WR),
      .disk_blkaddr1(WDISK_BLKADDR1), .disk_blkaddr2(WDISK_BLKADDR2), .disk_unit(WDISK_UNIT),
      .disk_wordcount(WDISK_WORDCOUNT),
      .disk_done(w1_done), .disk_err(w1_err), .disk_err_code(w1_code),
      .dbuf_addr(w1_addr), .dbuf_wdata(w1_wdata), .dbuf_we(w1_we), .dbuf_rdata(WDBUF_RDATA),
      .open_start(s_open_pulse),
      .c_open_req(open_req_w[CL_WD1]), .c_open_ok(open_ok_w[CL_WD1]), .c_open_err(open_err_w[CL_WD1]),
      .c_size_bytes(size_bytes_w[CL_WD1*32 +: 32]),
      .c_req(req_w[CL_WD1]), .c_wr(wr_w[CL_WD1]), .c_block(block_w[CL_WD1*16 +: 16]),
      .c_busy(busy_w[CL_WD1]), .c_done(done_w[CL_WD1]), .c_err(err_w[CL_WD1]),
      .c_err_code(err_code_w[CL_WD1*4 +: 4]),
      .c_buf_addr(buf_addr_w[CL_WD1*10 +: 10]), .c_buf_wdata(buf_wdata_w[CL_WD1*16 +: 16]),
      .c_buf_we(buf_we_w[CL_WD1]), .c_buf_rdata(buf_rdata_w[CL_WD1*16 +: 16])
  );

  // ---- paper tape -----------------------------------------------------------
  nd_storage_tape_adapter u_tape (
      .clk_cpu(clk_cpu), .rst_n(rst_cpu_n),
      .byte_req(byte_req), .byte_valid(byte_valid), .byte_data(byte_data),
      .source_rewind(source_rewind),
      .fault(TDISK_FAULT), .fault_code(TDISK_ERR_CODE),
      .open_start(s_open_pulse),
      .c_open_req(open_req_w[CL_TAPE]), .c_open_ok(open_ok_w[CL_TAPE]), .c_open_err(open_err_w[CL_TAPE]),
      .c_size_bytes(size_bytes_w[CL_TAPE*32 +: 32]),
      .c_req(req_w[CL_TAPE]), .c_wr(wr_w[CL_TAPE]), .c_block(block_w[CL_TAPE*16 +: 16]),
      .c_busy(busy_w[CL_TAPE]), .c_done(done_w[CL_TAPE]), .c_err(err_w[CL_TAPE]),
      .c_err_code(err_code_w[CL_TAPE*4 +: 4]),
      .c_buf_addr(buf_addr_w[CL_TAPE*10 +: 10]), .c_buf_wdata(buf_wdata_w[CL_TAPE*16 +: 16]),
      .c_buf_we(buf_we_w[CL_TAPE]), .c_buf_rdata(buf_rdata_w[CL_TAPE*16 +: 16])
  );

  // ---- the backend -------------------------------------------------------------
  nd_storage_hps #(.N_CLIENTS(N), .BYTE_SWAP(BYTE_SWAP)) u_hps (
      .clk_cpu(clk_cpu), .rst_cpu_n(rst_cpu_n),
      .open_req(open_req_w), .open_ok(open_ok_w), .open_err(open_err_w), .size_bytes(size_bytes_w),
      .req(req_w), .wr(wr_w), .block(block_w), .busy(busy_w), .done(done_w), .err(err_w),
      .err_code(err_code_w),
      .buf_addr(buf_addr_w), .buf_wdata(buf_wdata_w), .buf_we(buf_we_w), .buf_rdata(buf_rdata_w),
      .clk_sys(clk_sys), .rst_sys_n(rst_sys_n),
      .img_mounted(img_mounted), .img_readonly(img_readonly), .img_size(img_size),
      .sd_lba(sd_lba), .sd_blk_cnt(sd_blk_cnt), .sd_rd(sd_rd), .sd_wr(sd_wr), .sd_ack(sd_ack),
      .sd_buff_addr(sd_buff_addr), .sd_buff_dout(sd_buff_dout), .sd_buff_din(sd_buff_din),
      .sd_buff_wr(sd_buff_wr),
      .mounted(MOUNTED)
  );

endmodule
