/****************************************************************************
** floppy_seam_top - autonomous silicon probe for the Nexys 4 DDR floppy   **
** seam fault (see ../HANDOFF-floppy-dma-investigation.md, retired -       **
** git c4896a4).                                                           **
**                                                                         **
** WHAT IT IS: the EXACT storage configuration of the ND-120 top           **
** (nd120_nexys4ddr_top.v) - nd_storage at the same parameters, the same   **
** MMCM clocks (clk_cpu 12.5 MHz, clk_stor 27.027 MHz, DDR2 ui 75 MHz),    **
** the same nd_ddr2_storage/nd_ddr2_port region, the real SD card - but    **
** with the CPU replaced by a reporter FSM that owns the UART (9600 8N1)   **
** and prints, in an endless ~2 s loop:                                    **
**                                                                         **
**   S=s O=hh E=hh Z0=xxxxxxxx Z1=xxxxxxxx Z6=xxxxxxxx                     **
**   R0=ec wwww wwww     (FDISK read sector 0, fmt 3, 512 words:           **
**   R1=ec wwww wwww      e=err flag, c=err code, then device-buffer       **
**   R2=ec wwww wwww      words 0 and 1)                                   **
**   R3=ec wwww wwww                                                       **
**                                                                         **
** so the open question "does the clk_cpu side see size_bytes = 0 for the  **
** floppy client, and why is a sector-0 read answered RANGE" is measured   **
** with no buttons, switches or eyes - build, JTAG-program, read the UART. **
**                                                                         **
** The floppy path uses the REAL nd_storage_floppy_adapter on client 1,    **
** driven exactly like ND_FLOPPY_DMA drives it. Clients 0 (BOOT.TAP) and   **
** 6 (WD0.IMG) are opened the same way the devices wrapper opens them, so  **
** the mount sequence matches the ND-120 build.                            **
**                                                                         **
** Ronny Hansen                                                            **
*****************************************************************************/
`default_nettype none

module floppy_seam_top (
    input  wire clk100,       // E3, 100 MHz oscillator
    input  wire cpu_resetn,   // C12, red CPU RESET (active low)
    input  wire btnc,         // N17, centre button - second reset

    input  wire uart_txd_in,  // C4, PC -> FPGA (unused, kept for the pinout)
    output wire uart_rxd_out, // D4, FPGA -> PC

    output wire sd_reset,     // E2, LOW powers the slot
    input  wire sd_cd,        // A1
    output wire sd_clk,       // B1
    inout  wire sd_cmd,       // C1
    inout  wire sd_dat0,      // C2
    inout  wire sd_dat1,      // E1
    inout  wire sd_dat2,      // F1
    inout  wire sd_dat3,      // D2

    output wire [7:0] led,

    inout  wire [15:0] ddr2_dq,
    inout  wire [ 1:0] ddr2_dqs_p,
    inout  wire [ 1:0] ddr2_dqs_n,
    output wire [12:0] ddr2_addr,
    output wire [ 2:0] ddr2_ba,
    output wire        ddr2_ras_n,
    output wire        ddr2_cas_n,
    output wire        ddr2_we_n,
    output wire [ 0:0] ddr2_ck_p,
    output wire [ 0:0] ddr2_ck_n,
    output wire [ 0:0] ddr2_cke,
    output wire [ 0:0] ddr2_cs_n,
    output wire [ 1:0] ddr2_dm,
    output wire [ 0:0] ddr2_odt
);

  /*********************************************
  *  Clocks - same values as the ND-120 build  *
  *  (build.tcl clk=12: MMCM VCO 1000 MHz)     *
  **********************************************/
`ifndef SEAM_CPU_DIV
  `define SEAM_CPU_DIV 80.0
`endif
  wire clk_cpu_pre, clk_stor_pre, clk200_pre, clkfb_out, clkfb_in, mmcm_locked;
  wire clk_cpu, clk_stor, clk200;

  MMCME2_BASE #(
      .BANDWIDTH       ("OPTIMIZED"),
      .CLKFBOUT_MULT_F (10.0),          // 100 MHz x10 = 1000 MHz VCO
      .CLKIN1_PERIOD   (10.0),
      .CLKOUT0_DIVIDE_F(`SEAM_CPU_DIV), // 1000/80 = 12.5 MHz (ND-120 clk=12)
      .CLKOUT1_DIVIDE  (37),            // 27.027 MHz - SD/FAT stack
      .CLKOUT2_DIVIDE  (5),             // 200 MHz    - DDR2 controller
      .DIVCLK_DIVIDE   (1)
  ) mmcm (
      .CLKIN1  (clk100),
      .CLKFBIN (clkfb_in),
      .CLKFBOUT(clkfb_out),
      .CLKOUT0 (clk_cpu_pre),
      .CLKOUT1 (clk_stor_pre),
      .CLKOUT2 (clk200_pre),
      .LOCKED  (mmcm_locked),
      .PWRDWN  (1'b0),
      .RST     (1'b0),
      .CLKOUT0B(), .CLKOUT1B(), .CLKOUT2B(), .CLKOUT3(), .CLKOUT3B(),
      .CLKOUT4(), .CLKOUT5(), .CLKOUT6(), .CLKFBOUTB()
  );

  BUFG bufg_fb  (.I(clkfb_out),    .O(clkfb_in));
  BUFG bufg_cpu (.I(clk_cpu_pre),  .O(clk_cpu));
  BUFG bufg_st  (.I(clk_stor_pre), .O(clk_stor));
  BUFG bufg_200 (.I(clk200_pre),   .O(clk200));

  wire rst_req_n = cpu_resetn & ~btnc & mmcm_locked;

  reg [3:0] rst_cpu_sh = 4'd0;
  always @(posedge clk_cpu)
    if (!rst_req_n) rst_cpu_sh <= 4'd0;
    else            rst_cpu_sh <= {rst_cpu_sh[2:0], 1'b1};
  wire rst_cpu_n = rst_cpu_sh[3];

  reg [3:0] rst_st_sh = 4'd0;
  always @(posedge clk_stor)
    if (!rst_req_n) rst_st_sh <= 4'd0;
    else            rst_st_sh <= {rst_st_sh[2:0], 1'b1};
  wire rst_stor_n = rst_st_sh[3];

  /*********************************************
  *  SD pads - same tristate rule as the top   *
  **********************************************/
  assign sd_reset = 1'b0;

  wire s_sd_clk_o, s_sd_cmd_o, s_sd_cmd_oe, s_sd_dat0_o, s_sd_dat0_oe;
  assign sd_clk  = s_sd_clk_o;
  assign sd_cmd  = s_sd_cmd_oe  ? s_sd_cmd_o  : 1'bz;
  assign sd_dat0 = s_sd_dat0_oe ? s_sd_dat0_o : 1'bz;
  assign sd_dat1 = 1'bz;
  assign sd_dat2 = 1'bz;
  assign sd_dat3 = 1'bz;

  /*********************************************
  *  DDR2 region - identical to the ND-120 top *
  **********************************************/
  wire        mem_start, mem_we, mem_busy, mem_done;
  wire [19:0] mem_addr;
  wire [31:0] mem_wdata, mem_rdata;

  wire          ui_clk, ui_rst, calib_done;
  wire          req_valid, req_we, req_ready, rsp_valid;
  wire [ 26:0]  req_addr;
  wire [127:0]  req_wdata, rsp_rdata;
  wire [ 15:0]  req_wmask;

  nd_ddr2_storage u_region (
      .stor_clk(clk_stor), .stor_rst_n(rst_stor_n),
      .mem_start(mem_start), .mem_we(mem_we), .mem_addr(mem_addr),
      .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
      .mem_busy(mem_busy), .mem_done(mem_done),
      .ui_clk(ui_clk), .ui_rst(ui_rst),
      .req_valid(req_valid), .req_we(req_we), .req_addr(req_addr),
      .req_wdata(req_wdata), .req_wmask(req_wmask), .req_ready(req_ready),
      .rsp_valid(rsp_valid), .rsp_rdata(rsp_rdata)
  );

  nd_ddr2_port u_ddr2 (
      .sys_clk_200(clk200), .rst_n(rst_req_n),
      .ui_clk(ui_clk), .ui_rst(ui_rst), .calib_done(calib_done),
      .req_valid(req_valid), .req_we(req_we), .req_addr(req_addr),
      .req_wdata(req_wdata), .req_wmask(req_wmask), .req_ready(req_ready),
      .rsp_valid(rsp_valid), .rsp_rdata(rsp_rdata),
      .ddr2_dq(ddr2_dq), .ddr2_dqs_p(ddr2_dqs_p), .ddr2_dqs_n(ddr2_dqs_n),
      .ddr2_addr(ddr2_addr), .ddr2_ba(ddr2_ba), .ddr2_ras_n(ddr2_ras_n),
      .ddr2_cas_n(ddr2_cas_n), .ddr2_we_n(ddr2_we_n),
      .ddr2_ck_p(ddr2_ck_p), .ddr2_ck_n(ddr2_ck_n), .ddr2_cke(ddr2_cke),
      .ddr2_cs_n(ddr2_cs_n), .ddr2_dm(ddr2_dm), .ddr2_odt(ddr2_odt)
  );

  /*********************************************
  *  nd_storage - same parameters the ND-120   *
  *  build resolves to (wrapper INCLUDE_TAPE/  *
  *  FLOPPY/WD => CACHE_MASK 11000000,         *
  *  FILE0 = BOOT.TAP)                         *
  **********************************************/
  localparam N = 8;
  wire [N-1:0]    open_req_w, open_ok_w, open_err_w, req_w, wr_w;
  wire [N-1:0]    busy_w, done_w, err_w, buf_we_w;
  wire [N*4-1:0]  err_code_w;
  wire [N*32-1:0] size_bytes_w;
  wire [N*16-1:0] block_w, buf_wdata_w, buf_rdata_w;
  wire [N*10-1:0] buf_addr_w;
  wire [1:0]      sd_status;

  nd_storage #(
      .SIMULATE   (0),
      .CACHE_MASK (8'b11000000),
      .FILE0_NAME ("BOOT.TAP"), .FILE0_LEN(8'd8)
  ) u_nd_storage (
      .clk_stor  (clk_stor),
      .rst_stor_n(rst_stor_n),
      .clk_cpu   (clk_cpu),
      .rst_cpu_n (rst_cpu_n),
      .sd_clk_o  (s_sd_clk_o),
      .sd_cmd_i  (sd_cmd),
      .sd_cmd_o  (s_sd_cmd_o),
      .sd_cmd_oe (s_sd_cmd_oe),
      .sd_dat0_i (sd_dat0),
      .sd_dat0_o (s_sd_dat0_o),
      .sd_dat0_oe(s_sd_dat0_oe),
      .mem_start (mem_start),
      .mem_we    (mem_we),
      .mem_addr  (mem_addr),
      .mem_wdata (mem_wdata),
      .mem_rdata (mem_rdata),
      .mem_busy  (mem_busy),
      .mem_done  (mem_done),
      .open_req  (open_req_w),
      .open_ok   (open_ok_w),
      .open_err  (open_err_w),
      .size_bytes(size_bytes_w),
      .req       (req_w),
      .wr        (wr_w),
      .block     (block_w),
      .busy      (busy_w),
      .done      (done_w),
      .err       (err_w),
      .err_code  (err_code_w),
      .dbg_state(), .dbg_lba(), .dbg_wdata(), .dbg_rdata(), .dbg_bufw(),
      .dbg_bufwe(), .dbg_fsec(), .dbg_rx_stb(), .dbg_rx_raw(),
      .dbg_rx_byte(), .dbg_past_eof(), .dbg_grant(),
      .buf_addr  (buf_addr_w),
      .buf_wdata (buf_wdata_w),
      .buf_we    (buf_we_w),
      .buf_rdata (buf_rdata_w),
      .sd_status (sd_status),
      .card_type (),
      .fs_type   ()
  );

  // Client 1 = the real floppy adapter (driven by the FSM below).
  reg         fd_req = 1'b0, fd_wr = 1'b0;
  reg  [15:0] fd_lsect = 16'd0;
  reg  [ 1:0] fd_format = 2'd3;
  reg  [10:0] fd_wc = 11'd512;
  wire        fd_done, fd_err;
  wire [3:0]  fd_code;
  wire [9:0]  fdb_addr;
  wire [15:0] fdb_wdata;
  wire        fdb_we;

  wire        f_open_req, f_req, f_wr;
  wire [15:0] f_block, f_buf_rdata;

  // held open, exactly like the devices wrapper (gen_floppy)
  reg s_fopened = 1'b0;
  always @(posedge clk_cpu or negedge rst_cpu_n)
    if (!rst_cpu_n) s_fopened <= 1'b0;
    else if (open_ok_w[1]) s_fopened <= 1'b1;
  wire s_fopen_pulse = !s_fopened;

  nd_storage_floppy_adapter #(.DRIVE(2'd0)) u_floppy_adapter (
      .clk_cpu       (clk_cpu),
      .rst_n         (rst_cpu_n),
      .disk_req      (fd_req),
      .disk_wr       (fd_wr),
      .disk_lsect    (fd_lsect),
      .disk_format   (fd_format),
      .disk_drive    (2'd0),
      .disk_wordcount(fd_wc),
      .disk_done     (fd_done),
      .disk_err      (fd_err),
      .disk_err_code (fd_code),
      .dbuf_addr     (fdb_addr),
      .dbuf_wdata    (fdb_wdata),
      .dbuf_we       (fdb_we),
      .dbuf_rdata    (16'd0),
      .open_start    (s_fopen_pulse),
      .c_open_req    (f_open_req),
      .c_open_ok     (open_ok_w[1]),
      .c_open_err    (open_err_w[1]),
      .c_size_bytes  (size_bytes_w[63:32]),
      .c_req         (f_req),
      .c_wr          (f_wr),
      .c_block       (f_block),
      .c_busy        (busy_w[1]),
      .c_done        (done_w[1]),
      .c_err         (err_w[1]),
      .c_err_code    (err_code_w[7:4]),
      .c_buf_addr    (buf_addr_w[19:10]),
      .c_buf_wdata   (buf_wdata_w[31:16]),
      .c_buf_we      (buf_we_w[1]),
      .c_buf_rdata   (f_buf_rdata)
  );

  // Clients 0 (tape) and 6 (WD): held opens like the wrapper's sequencers.
  reg s_topened = 1'b0, s_wopened = 1'b0;
  always @(posedge clk_cpu or negedge rst_cpu_n)
    if (!rst_cpu_n) begin s_topened <= 1'b0; s_wopened <= 1'b0; end
    else begin
      if (open_ok_w[0]) s_topened <= 1'b1;
      if (open_ok_w[6]) s_wopened <= 1'b1;
    end

  assign open_req_w = {1'b0, !s_wopened, 4'b0000, f_open_req, !s_topened};
  assign req_w      = {6'b0, f_req, 1'b0};
  assign wr_w       = {6'b0, f_wr, 1'b0};
  assign block_w    = {96'd0, f_block, 16'd0};
  assign buf_rdata_w= {96'd0, f_buf_rdata, 16'd0};

  // Device sector buffer (stands in for ND_FLOPPY_DMA's 1024x16 buffer):
  // captures the adapter's dbuf writes; words 0 and 1 are printed.
  reg [15:0] devbuf0 = 16'd0, devbuf1 = 16'd0;
  always @(posedge clk_cpu) begin
    if (fdb_we && fdb_addr == 10'd0) devbuf0 <= fdb_wdata;
    if (fdb_we && fdb_addr == 10'd1) devbuf1 <= fdb_wdata;
  end

  /*********************************************
  *  UART reporter, 9600 8N1 on clk_cpu        *
  **********************************************/
  localparam integer CPU_HZ = 12_500_000;
  wire       tx_busy;
  reg  [7:0] tx_data = 8'd0;
  reg        tx_valid = 1'b0;
  uart_tx #(.DELAY_FRAMES(CPU_HZ / 9600)) u_tx (
      .clk(clk_cpu), .rst_n(rst_cpu_n),
      .tx_data(tx_data), .tx_valid(tx_valid), .tx_busy(tx_busy),
      .txd(uart_rxd_out)
  );

  function [7:0] hx(input [3:0] n);
    hx = (n < 4'd10) ? (8'h30 + {4'd0, n}) : (8'h41 + {4'd0, n} - 8'd10);
  endfunction

  // latched values for one report round
  reg [1:0]  v_st;
  reg [7:0]  v_ok, v_er;
  reg [31:0] v_z0, v_z1, v_z6;
  reg        v_rderr;
  reg [3:0]  v_rdcode;
  reg [15:0] v_w0, v_w1;
  reg [1:0]  v_sect;

  // status line: S=s O=hh E=hh Z0=xxxxxxxx Z1=xxxxxxxx Z6=xxxxxxxx\r\n
  function [7:0] stat_char(input [5:0] i);
    case (i)
      6'd0: stat_char = "S";   6'd1: stat_char = "=";
      6'd2: stat_char = hx({2'b0, v_st});
      6'd3: stat_char = " ";   6'd4: stat_char = "O"; 6'd5: stat_char = "=";
      6'd6: stat_char = hx(v_ok[7:4]); 6'd7: stat_char = hx(v_ok[3:0]);
      6'd8: stat_char = " ";   6'd9: stat_char = "E"; 6'd10: stat_char = "=";
      6'd11: stat_char = hx(v_er[7:4]); 6'd12: stat_char = hx(v_er[3:0]);
      6'd13: stat_char = " ";  6'd14: stat_char = "Z"; 6'd15: stat_char = "0";
      6'd16: stat_char = "=";
      6'd17: stat_char = hx(v_z0[31:28]); 6'd18: stat_char = hx(v_z0[27:24]);
      6'd19: stat_char = hx(v_z0[23:20]); 6'd20: stat_char = hx(v_z0[19:16]);
      6'd21: stat_char = hx(v_z0[15:12]); 6'd22: stat_char = hx(v_z0[11:8]);
      6'd23: stat_char = hx(v_z0[7:4]);   6'd24: stat_char = hx(v_z0[3:0]);
      6'd25: stat_char = " ";  6'd26: stat_char = "Z"; 6'd27: stat_char = "1";
      6'd28: stat_char = "=";
      6'd29: stat_char = hx(v_z1[31:28]); 6'd30: stat_char = hx(v_z1[27:24]);
      6'd31: stat_char = hx(v_z1[23:20]); 6'd32: stat_char = hx(v_z1[19:16]);
      6'd33: stat_char = hx(v_z1[15:12]); 6'd34: stat_char = hx(v_z1[11:8]);
      6'd35: stat_char = hx(v_z1[7:4]);   6'd36: stat_char = hx(v_z1[3:0]);
      6'd37: stat_char = " ";  6'd38: stat_char = "Z"; 6'd39: stat_char = "6";
      6'd40: stat_char = "=";
      6'd41: stat_char = hx(v_z6[31:28]); 6'd42: stat_char = hx(v_z6[27:24]);
      6'd43: stat_char = hx(v_z6[23:20]); 6'd44: stat_char = hx(v_z6[19:16]);
      6'd45: stat_char = hx(v_z6[15:12]); 6'd46: stat_char = hx(v_z6[11:8]);
      6'd47: stat_char = hx(v_z6[7:4]);   6'd48: stat_char = hx(v_z6[3:0]);
      6'd49: stat_char = 8'h0D;
      default: stat_char = 8'h0A;
    endcase
  endfunction
  localparam [5:0] STAT_LAST = 6'd50;

  // read line: Rn=ec wwww wwww\r\n
  function [7:0] rd_char(input [4:0] i);
    case (i)
      5'd0: rd_char = "R";
      5'd1: rd_char = hx({2'b0, v_sect});
      5'd2: rd_char = "=";
      5'd3: rd_char = v_rderr ? "1" : "0";
      5'd4: rd_char = hx(v_rdcode);
      5'd5: rd_char = " ";
      5'd6: rd_char = hx(v_w0[15:12]); 5'd7: rd_char = hx(v_w0[11:8]);
      5'd8: rd_char = hx(v_w0[7:4]);   5'd9: rd_char = hx(v_w0[3:0]);
      5'd10: rd_char = " ";
      5'd11: rd_char = hx(v_w1[15:12]); 5'd12: rd_char = hx(v_w1[11:8]);
      5'd13: rd_char = hx(v_w1[7:4]);   5'd14: rd_char = hx(v_w1[3:0]);
      5'd15: rd_char = 8'h0D;
      default: rd_char = 8'h0A;
    endcase
  endfunction
  localparam [4:0] RD_LAST = 5'd16;

  localparam P_WAIT   = 3'd0;   // post-reset settle (mounts run meanwhile)
  localparam P_STATL  = 3'd1;   // latch + print the status line
  localparam P_RDGO   = 3'd2;   // pulse one FDISK read
  localparam P_RDWAIT = 3'd3;   // wait for done (or timeout)
  localparam P_RDPR   = 3'd4;   // print the read line
  localparam P_GAP    = 3'd5;   // ~2 s pause, then loop

  reg [2:0]  ph = P_WAIT;
  reg [27:0] delay = 28'd0;
  reg [5:0]  ci = 6'd0;
  reg        sent = 1'b0;    // one char handed to the uart, awaiting !busy

  always @(posedge clk_cpu) begin
    if (!rst_cpu_n) begin
      ph <= P_WAIT; delay <= 28'd0; ci <= 6'd0; sent <= 1'b0;
      fd_req <= 1'b0; tx_valid <= 1'b0;
      v_sect <= 2'd0;
    end else begin
      tx_valid <= 1'b0;
      fd_req   <= 1'b0;

      case (ph)
        P_WAIT: begin
          delay <= delay + 28'd1;
          if (delay == 28'd62_500_000) begin  // 5 s: mounts done
            delay <= 28'd0;
            ph    <= P_STATL;
            ci    <= 6'd0;
          end
        end

        P_STATL: begin
          if (ci == 6'd0 && !sent) begin
            v_st <= sd_status;
            v_ok <= open_ok_w;
            v_er <= open_err_w;
            v_z0 <= size_bytes_w[31:0];
            v_z1 <= size_bytes_w[63:32];
            v_z6 <= size_bytes_w[223:192];
          end
          if (!sent && !tx_busy) begin
            tx_data  <= stat_char(ci);
            tx_valid <= 1'b1;
            sent     <= 1'b1;
          end else if (sent && tx_busy) begin
            sent <= 1'b0;         // uart took it; wait for the frame
          end else if (!sent && tx_busy) begin
            // frame in flight - wait
          end
          if (sent && tx_busy) begin
            if (ci == STAT_LAST) begin
              ci     <= 6'd0;
              v_sect <= 2'd0;
              ph     <= P_RDGO;
            end else ci <= ci + 6'd1;
          end
        end

        P_RDGO: begin
          fd_lsect  <= {14'd0, v_sect};
          fd_format <= 2'd3;
          fd_wc     <= 11'd512;
          fd_wr     <= 1'b0;
          fd_req    <= 1'b1;
          delay     <= 28'd0;
          ph        <= P_RDWAIT;
        end

        P_RDWAIT: begin
          delay <= delay + 28'd1;
          if (fd_done) begin
            v_rderr  <= fd_err;
            v_rdcode <= fd_code;
            v_w0     <= devbuf0;
            v_w1     <= devbuf1;
            ci       <= 6'd0;
            ph       <= P_RDPR;
          end else if (delay == 28'd150_000_000) begin  // 12 s: wedge marker
            v_rderr  <= 1'b1;
            v_rdcode <= 4'hF;                            // F = never completed
            v_w0     <= 16'hDEAD;
            v_w1     <= 16'hDEAD;
            ci       <= 6'd0;
            ph       <= P_RDPR;
          end
        end

        P_RDPR: begin
          if (!sent && !tx_busy) begin
            tx_data  <= rd_char(ci[4:0]);
            tx_valid <= 1'b1;
            sent     <= 1'b1;
          end else if (sent && tx_busy) begin
            sent <= 1'b0;
          end
          if (sent && tx_busy) begin
            if (ci[4:0] == RD_LAST) begin
              ci <= 6'd0;
              if (v_sect == 2'd3) begin
                delay <= 28'd0;
                ph    <= P_GAP;
              end else begin
                v_sect <= v_sect + 2'd1;
                ph     <= P_RDGO;
              end
            end else ci <= ci + 6'd1;
          end
        end

        P_GAP: begin
          delay <= delay + 28'd1;
          if (delay == 28'd25_000_000) begin  // 2 s
            delay <= 28'd0;
            ci    <= 6'd0;
            ph    <= P_STATL;
          end
        end

        default: ph <= P_WAIT;
      endcase
    end
  end

  assign led[0] = mmcm_locked;
  assign led[1] = calib_done;
  assign led[2] = sd_status[0];
  assign led[3] = open_ok_w[0];
  assign led[4] = open_ok_w[1];
  assign led[5] = open_ok_w[6];
  assign led[6] = |open_err_w;
  assign led[7] = sd_cd;

  /* verilator lint_off UNUSEDSIGNAL */
  wire _unused = &{1'b0, uart_txd_in, sd_dat1, sd_dat2, sd_dat3,
                   busy_w, done_w[0], done_w[7:2], err_w[0], err_w[7:2],
                   err_code_w[3:0], err_code_w[31:8], size_bytes_w,
                   block_w, buf_addr_w, buf_wdata_w, buf_we_w, fdb_addr,
                   fdb_wdata, fdb_we, open_ok_w, open_err_w, ui_rst, 1'b0};
  /* verilator lint_on UNUSEDSIGNAL */

endmodule

`default_nettype wire
