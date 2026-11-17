//============================================================================
//! nd_pcie_storage - disk images served by the PC over PCIe
//!
//! Board: Microsoft Azure FPGA card X930613-001 (Verilog/fpga/azure-x930613).
//!
//! WHY. The card has no SD slot. On the MiSTer the same problem is solved by
//! the ARM side of the board: it holds the image files and serves them
//! through hps_io's block interface to nd_storage_hps
//! (Verilog/fpga/mister/rtl/nd_storage_hps.v), which answers the ND floppy,
//! Winchester and tape controllers. Here the PC holds the files. This block
//! gives the PC a set of registers and drives the SAME block interface that
//! hps_io drives, so nd_storage_hps and nd_storage_mister_devices are used
//! unchanged (docs/00-plan.md, step V2).
//!
//! WHAT THE PC DOES (one transfer at a time, the PC polls - as the ARM does):
//!   1. read PEND. A set bit n = slot n wants a block; PEND[16+n] says write.
//!   2. read LBA[n] (512-byte units) and BLKCNT[n] (number of 512-byte blocks
//!      minus 1; nd_storage_hps always asks for 3 = one 2048-byte ND block).
//!   3. write XFER with START and the slot: the slot's ack goes high, the
//!      word pointer goes to 0. nd_storage_hps drops its request on that.
//!   4. read from the file: write DATA (BLKCNT+1)*256 times, one 16-bit word
//!      each, word w = {file byte 2w+1, file byte 2w} (little-endian, as a PC
//!      reads the file into 16-bit words; nd_storage_hps swaps to ND order
//!      with BYTE_SWAP=1, exactly as for the MiSTer ARM).
//!      write to the file: read DATA the same number of times, same order.
//!   5. write XFER with END: the ack drops, which tells nd_storage_hps the
//!      block is finished.
//! Mounting: write SIZE_LO, SIZE_HI (bytes), then MOUNT with the slot and the
//! read-only bit. Size 0 = unmount. nd_storage_hps refuses requests on an
//! unmounted slot itself, so the PC never sees them.
//!
//! THE REGISTER BUS: same as nd_pcie_console. addr = byte offset, 32-bit
//! registers, wr / rd one cycle each, rdata valid while rvalid is high.
//! rvalid comes ONE cycle after rd for every register except DATA, where it
//! comes THREE cycles after (the word is read out of nd_storage_hps's write
//! buffer, which has a registered read). The master issues one access at a
//! time: no new rd or wr before rvalid of the previous rd ('busy' is high
//! in between). An access during busy is ignored and sets ERRS[0].
//!
//! REGISTERS (byte offsets, octal):
//!   0o000 VERSION  R   [31:24] number of slots, [23:16] block kind = 2
//!                      (storage), [15:0] layout version = 1
//!   0o004 PEND     R   [N-1:0] slot has a request, [16+N-1:16] it is a write
//!   0o010 XFER     W   [3:0] slot, [8] START, [9] END
//!                  R   [3:0] slot, [8] a transfer is open, [28:16] pointer
//!   0o014 DATA     R/W one 16-bit word in [15:0] at the pointer; pointer + 1
//!   0o020 PTR      W   [12:0] set the word pointer (START also zeroes it)
//!   0o024 SIZE_LO  R/W image size in bytes, low 32 bits (for MOUNT)
//!   0o030 SIZE_HI  R/W image size, high 32 bits
//!   0o034 MOUNT    W   [3:0] slot, [8] read-only. Mounts (size > 0) or
//!                      unmounts (size 0) the slot with SIZE_HI:SIZE_LO.
//!   0o040 ERRS     R/W sticky, write 1 to clear:
//!                      [0] access while busy (ignored)
//!                      [1] DATA access with no transfer open (ignored)
//!                      [2] START or MOUNT with a slot >= number of slots
//!                      [3] START while a transfer is already open (ignored)
//!   0o100+4n LBA[n]    R  sd_lba of slot n
//!   0o200+4n BLKCNT[n] R  sd_blk_cnt of slot n
//!   other offsets      R  0, W ignored
//!
//! One clock domain: the PCIe user clock. It is nd_storage_hps's clk_sys
//! side; that module carries everything across to the CPU clock itself.
//============================================================================

`default_nettype none

module nd_pcie_storage #(
    parameter integer N_SLOTS = 5  //! = nd_storage_hps N_CLIENTS, at most 16
) (
    input wire clk,    //! PCIe user clock (from pcie_hip_wrap.user_clk)
    input wire rst_n,  //! active-low reset in the same domain

    // ---- register bus (from pcie_bar_bus) ----
    input  wire [8:0]  addr,
    input  wire        wr,
    input  wire [31:0] wdata,
    input  wire        rd,
    output reg  [31:0] rdata,
    output reg         rvalid,
    output wire        busy,    //! a DATA read is in progress

    // ---- the hps_io-shaped block interface (to nd_storage_hps, clk_sys side) ----
    output reg  [N_SLOTS-1:0]    img_mounted,   //! held high a few cycles per mount event
    output reg                   img_readonly,
    output wire [63:0]           img_size,
    input  wire [N_SLOTS*32-1:0] sd_lba,
    input  wire [N_SLOTS*6-1:0]  sd_blk_cnt,
    input  wire [N_SLOTS-1:0]    sd_rd,
    input  wire [N_SLOTS-1:0]    sd_wr,
    output reg  [N_SLOTS-1:0]    sd_ack,        //! one-hot, high for the whole transfer
    output reg  [12:0]           sd_buff_addr,
    output reg  [15:0]           sd_buff_dout,
    input  wire [15:0]           sd_buff_din,
    output reg                   sd_buff_wr     //! one cycle per word read from the file
);

  localparam integer N = N_SLOTS;

  localparam [8:0] A_VERSION = 9'o000, A_PEND = 9'o004, A_XFER = 9'o010,
                   A_DATA = 9'o014, A_PTR = 9'o020, A_SIZE_LO = 9'o024,
                   A_SIZE_HI = 9'o030, A_MOUNT = 9'o034, A_ERRS = 9'o040;

  //! how long img_mounted stays high; nd_storage_hps edge-detects it
  localparam [2:0] MOUNT_HOLD = 3'd4;

  reg [31:0] size_lo, size_hi;
  assign img_size = {size_hi, size_lo};

  reg        x_open;      // a transfer is open (an ack is high)
  reg [3:0]  x_slot;
  reg [12:0] ptr;
  reg [3:0]  errs;
  reg [2:0]  m_cnt;       // img_mounted hold counter
  reg [1:0]  d_cnt;       // DATA read in progress: cycles left
  assign busy = (d_cnt != 2'd0);

  wire [3:0] w_slot = wdata[3:0];
  wire       w_slot_ok = (wdata[3:0] < N);

  // per-slot register views for the read mux
  wire [8:0] a_lba_lo = 9'o100, a_lba_hi = 9'o100 + 4 * N;
  wire [8:0] a_cnt_lo = 9'o200, a_cnt_hi = 9'o200 + 4 * N;
  wire [3:0] lba_idx = (addr - 9'o100) >> 2;
  wire [3:0] cnt_idx = (addr - 9'o200) >> 2;

  integer k;
  reg [31:0] pend_word;
  always @* begin
    pend_word = 32'd0;
    for (k = 0; k < N; k = k + 1) begin
      pend_word[k]      = sd_rd[k] | sd_wr[k];
      pend_word[16 + k] = sd_wr[k];
    end
  end

  wire acc = (rd || wr) && !busy;   // an access that is carried out

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rdata        <= 32'd0;
      rvalid       <= 1'b0;
      img_mounted  <= {N{1'b0}};
      img_readonly <= 1'b0;
      size_lo      <= 32'd0;
      size_hi      <= 32'd0;
      sd_ack       <= {N{1'b0}};
      sd_buff_addr <= 13'd0;
      sd_buff_dout <= 16'd0;
      sd_buff_wr   <= 1'b0;
      x_open       <= 1'b0;
      x_slot       <= 4'd0;
      ptr          <= 13'd0;
      errs         <= 4'd0;
      m_cnt        <= 3'd0;
      d_cnt        <= 2'd0;
    end else begin
      rvalid     <= 1'b0;
      sd_buff_wr <= 1'b0;
      // the address follows the pointer, except on the cycle a word is
      // written, where it holds that word's own address
      sd_buff_addr <= ptr;

      // ---- the mount pulse ----
      if (m_cnt != 3'd0) begin
        m_cnt <= m_cnt - 3'd1;
        if (m_cnt == 3'd1) img_mounted <= {N{1'b0}};
      end

      // ---- a DATA read finishing: sd_buff_din is wbuf[ptr] by now ----
      if (d_cnt != 2'd0) begin
        d_cnt <= d_cnt - 2'd1;
        if (d_cnt == 2'd1) begin
          rdata  <= {16'd0, sd_buff_din};
          rvalid <= 1'b1;
          ptr    <= ptr + 13'd1;
        end
      end

      if ((rd || wr) && busy) errs[0] <= 1'b1;

      // ---- reads ----
      if (rd && acc) begin
        if (addr == A_DATA) begin
          if (x_open) d_cnt <= 2'd2;
          else begin
            errs[1] <= 1'b1;
            rdata   <= 32'd0;
            rvalid  <= 1'b1;
          end
        end else begin
          rvalid <= 1'b1;
          if (addr == A_VERSION)      rdata <= {N[7:0], 8'd2, 16'd1};
          else if (addr == A_PEND)    rdata <= pend_word;
          else if (addr == A_XFER)    rdata <= {3'd0, ptr, 7'd0, x_open, 4'd0, x_slot};
          else if (addr == A_SIZE_LO) rdata <= size_lo;
          else if (addr == A_SIZE_HI) rdata <= size_hi;
          else if (addr == A_ERRS)    rdata <= {28'd0, errs};
          else if ((addr >= a_lba_lo) && (addr < a_lba_hi) && (addr[1:0] == 2'b00))
            rdata <= sd_lba[lba_idx*32 +: 32];
          else if ((addr >= a_cnt_lo) && (addr < a_cnt_hi) && (addr[1:0] == 2'b00))
            rdata <= {26'd0, sd_blk_cnt[cnt_idx*6 +: 6]};
          else rdata <= 32'd0;
        end
      end

      // ---- writes ----
      if (wr && acc) begin
        case (addr)
          A_XFER: begin
            if (wdata[8]) begin
              if (x_open)          errs[3] <= 1'b1;
              else if (!w_slot_ok) errs[2] <= 1'b1;
              else begin
                x_open <= 1'b1;
                x_slot <= w_slot;
                sd_ack <= {{(N-1){1'b0}}, 1'b1} << w_slot;
                ptr    <= 13'd0;
              end
            end else if (wdata[9]) begin
              x_open <= 1'b0;
              sd_ack <= {N{1'b0}};
            end
          end
          A_DATA: begin
            if (x_open) begin
              sd_buff_addr <= ptr;
              sd_buff_dout <= wdata[15:0];
              sd_buff_wr   <= 1'b1;
              ptr          <= ptr + 13'd1;
            end else errs[1] <= 1'b1;
          end
          A_PTR:     ptr     <= wdata[12:0];
          A_SIZE_LO: size_lo <= wdata;
          A_SIZE_HI: size_hi <= wdata;
          A_MOUNT: begin
            if (!w_slot_ok) errs[2] <= 1'b1;
            else begin
              // img_size has been stable since SIZE_LO/HI were written, so it
              // is valid when the pulse rises (nd_storage_hps latches it on
              // the rising edge)
              img_readonly <= wdata[8];
              img_mounted  <= {{(N-1){1'b0}}, 1'b1} << w_slot;
              m_cnt        <= MOUNT_HOLD;
            end
          end
          A_ERRS: errs <= errs & ~wdata[3:0];
          default: ;
        endcase
      end
    end
  end

endmodule

`default_nettype wire
