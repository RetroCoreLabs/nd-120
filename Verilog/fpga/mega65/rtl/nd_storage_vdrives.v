`include "nd_storage_status.vh"

/****************************************************************************
** nd_storage_vdrives - the ND-120 storage client bus served by            **
**                      MiSTer2MEGA65 virtual drives                       **
**                                                                         **
** Full path: Verilog/fpga/mega65/rtl/nd_storage_vdrives.v                 **
**                                                                         **
** The MEGA65 counterpart of fpga/mister/rtl/nd_storage_hps.v, from which  **
** it is copied (02-SEP-2026, from the version that mounted floppy0/1, WD0  **
** and tape on the DE10-Nano). Same client port (Verilog/docs/              **
** nd-storage-interface-spec.md section 4: one request = one 2048-byte      **
** block = 1024 ND words, backend masters the client's buffer), same        **
** request/mount/error rules, same two-domain design with the staging      **
** buffers and the 4-phase go/done handshake. Read that file's header for   **
** the rules; only what DIFFERS is described here.                          **
**                                                                         **
** THE OTHER SIDE is the framework's vdrives.vhd (m2m/M2M/vhdl/), which     **
** implements the MiSTer sd_* block protocol in the QNICE clock domain      **
** (50 MHz) with the QNICE soft CPU's firmware doing what the firmware does on   **
** the MiSTer: it polls sd_rd/sd_wr, raises sd_ack[slot] for the whole      **
** transaction, moves the data through sd_buff_*, drops ack. Differences   **
** from hps_io that this file absorbs:                                      **
**   - the buffer bus is BYTE wide: sd_buff_dout/din are 8 bits and        **
**     sd_buff_addr (14 bits) counts BYTES 0..2047 of the 2048-byte         **
**     transaction. The bytes arrive in file order, so ND word w =          **
**     {byte 2w, byte 2w+1} needs no byte swap at all - the staging         **
**     buffers are kept as two byte planes (high = even byte).              **
**   - sd_buff_wr is a REGISTER the firmware writes 1 then 0, so it can be  **
**     high for several clocks; the address and data are set before it and **
**     hold, so writing the byte on every cycle it is high is harmless.     **
**   - for writes (core -> file) the firmware sets sd_buff_addr and reads   **
**     sd_buff_din through MMIO instructions later: a registered read path  **
**     of two clocks is far inside that.                                     **
**   - img_size is 32 bits (hps_io: 64).                                    **
**   - sd_blk_cnt = 3 with BLKSZ 2 (512-byte blocks): one 2048-byte          **
**     transaction, as on the MiSTer; vdrives.vhd documents that the        **
**     firmware honours it ("BLK_CNT blocks long").                          **
** Slot n = vdrive n = the n-th "%s" mount line in config.vhd's OPTM_ITEMS. **
**                                                                         **
** Ronny Hansen, 02-SEP-2026                                                **
*****************************************************************************/

module nd_storage_vdrives #(
    parameter integer N_CLIENTS = 5    // = vdrives VDNUM; slot n = client n
) (
    // ---- client ports (clk_cpu domain, flattened; spec section 4) ----
    input  wire                    clk_cpu,        //! 20 MHz (from nd120_mega65_machine.clk_cpu)
    input  wire                    rst_cpu_n,      //! Active-low reset, from the board's power-on reset (same net as ND120_CORE.sys_rst_n)
    input  wire [N_CLIENTS-1:0]    open_req,
    output wire [N_CLIENTS-1:0]    open_ok,
    output wire [N_CLIENTS-1:0]    open_err,
    output wire [N_CLIENTS*32-1:0] size_bytes,
    input  wire [N_CLIENTS-1:0]    req,
    input  wire [N_CLIENTS-1:0]    wr,
    input  wire [N_CLIENTS*16-1:0] block,
    output wire [N_CLIENTS-1:0]    busy,
    output reg  [N_CLIENTS-1:0]    done,
    output reg  [N_CLIENTS-1:0]    err,
    output wire [N_CLIENTS*4-1:0]  err_code,
    output wire [N_CLIENTS*10-1:0] buf_addr,
    output wire [N_CLIENTS*16-1:0] buf_wdata,
    output wire [N_CLIENTS-1:0]    buf_we,
    input  wire [N_CLIENTS*16-1:0] buf_rdata,

    // ---- vdrives block interface (clk_sys = the QNICE clock) ----
    input  wire                    clk_sys,
    input  wire                    rst_sys_n,
    input  wire [N_CLIENTS-1:0]    img_mounted,
    input  wire                    img_readonly,
    input  wire [31:0]             img_size,
    output wire [N_CLIENTS*32-1:0] sd_lba,
    output wire [N_CLIENTS*6-1:0]  sd_blk_cnt,
    output reg  [N_CLIENTS-1:0]    sd_rd,
    output reg  [N_CLIENTS-1:0]    sd_wr,
    input  wire [N_CLIENTS-1:0]    sd_ack,
    input  wire [13:0]             sd_buff_addr,   // BYTE address within the transaction
    input  wire [7:0]              sd_buff_dout,
    output wire [7:0]              sd_buff_din,
    input  wire                    sd_buff_wr,

    // ---- diagnostics (clk_cpu domain): which slots hold a file ----
    output wire [N_CLIENTS-1:0]    mounted
);

  localparam integer N = N_CLIENTS;

  // one client block = 4 HPS blocks of 512 bytes, sent as ONE transaction
  localparam [5:0] BLK_CNT_M1 = 6'd3;

  // =======================================================================
  // clk_sys side: mount records + the QNICE firmware transaction
  // =======================================================================

  // ---- mount records, latched on the rising edge of img_mounted[n] ------
  // vdrives strobes img_mounted for a few clocks (its firmware writes the
  // register 1 then 0), so it is edge-detected. img_size/img_readonly are
  // set before the strobe (vdrives.vhd rule 2) and are stable here.
  reg [N-1:0]  m_mounted;
  reg [N-1:0]  m_ro;
  reg [N*32-1:0] m_size;
  reg [N-1:0]  m_tgl;          // flips once per mount/unmount event
  reg [N-1:0]  img_mounted_d;

  integer n;
  always @(posedge clk_sys or negedge rst_sys_n) begin
    if (!rst_sys_n) begin
      m_mounted     <= {N{1'b0}};
      m_ro          <= {N{1'b0}};
      m_size        <= {(N*32){1'b0}};
      m_tgl         <= {N{1'b0}};
      img_mounted_d <= {N{1'b0}};
    end else begin
      img_mounted_d <= img_mounted;
      for (n = 0; n < N; n = n + 1) begin
        if (img_mounted[n] && !img_mounted_d[n]) begin
          m_mounted[n]         <= |img_size;          // size 0 = unmount
          m_ro[n]              <= img_readonly;
          m_size[n*32 +: 32]   <= img_size;
          m_tgl[n]             <= ~m_tgl[n];
        end
      end
    end
  end

  // ---- request fields, written by the clk_cpu side, stable while t_go ---
  reg        t_go;             // clk_cpu: request handed to the QNICE side
  reg        t_wr;
  reg [31:0] t_lba;
  reg [N-1:0] t_sel;           // one-hot slot

  // go -> clk_sys, done -> clk_cpu, 4-phase
  reg [1:0] go_s;              // clk_sys copy of t_go
  reg       h_done;            // clk_sys: transaction finished
  reg [1:0] hd_s;              // clk_cpu copy of h_done

  // vdrives wants a per-slot array; every slot carries the same request,
  // only the selected slot's sd_rd/sd_wr bit is raised.
  genvar gs;
  generate
    for (gs = 0; gs < N; gs = gs + 1) begin : g_lba
      assign sd_lba[gs*32 +: 32]   = t_lba;
      assign sd_blk_cnt[gs*6 +: 6] = BLK_CNT_M1;
    end
  endgenerate

  // ---- the two staging buffers ------------------------------------------
  // Byte planes: the QNICE side moves one byte per strobe, the client side
  // one 16-bit word per cycle. ND words are big-endian pairs of the file's
  // bytes, so byte 2w is the HIGH half of word w.
  reg [7:0]  rbuf_hi[0:1023];  // QNICE -> client, even bytes: written on clk_sys
  reg [7:0]  rbuf_lo[0:1023];  //                  odd bytes
  reg [15:0] wbuf[0:1023];     // client -> QNICE: written on clk_cpu
  reg [15:0] wbuf_q;           // clk_sys registered read of wbuf
  reg        wsel_q;           // which half the firmware asked for
  reg [15:0] rbuf_q;           // clk_cpu registered read of rbuf

  wire ack_sel = |(sd_ack & t_sel);

  // read direction: every byte the firmware strobes lands in its plane.
  // sd_buff_wr may stay high for several clocks (it is a firmware-written
  // register); address and data hold meanwhile, so re-writing is harmless.
  // Only the low 11 address bits matter (2048 bytes).
  always @(posedge clk_sys) begin
    if (ack_sel && sd_buff_wr && !t_wr) begin
      if (!sd_buff_addr[0]) rbuf_hi[sd_buff_addr[10:1]] <= sd_buff_dout;
      else                  rbuf_lo[sd_buff_addr[10:1]] <= sd_buff_dout;
    end
    wbuf_q <= wbuf[sd_buff_addr[10:1]];
    wsel_q <= sd_buff_addr[0];
  end
  // write direction: the firmware sets the address, then reads the byte
  // through an MMIO instruction some clocks later; the two-clock registered
  // path above is ready long before that.
  assign sd_buff_din = wsel_q ? wbuf_q[7:0] : wbuf_q[15:8];

  // ---- QNICE transaction FSM (identical to the QNICE firmware one) -----------------
  localparam [1:0] H_IDLE = 2'd0,   // wait for go
                   H_REQ  = 2'd1,   // sd_rd/sd_wr raised, wait ack rising
                   H_XFER = 2'd2,   // ack high: the stream runs
                   H_DONE = 2'd3;   // tell the client side; wait go low

  reg [1:0] h_state;
  reg       ack_sel_d;

  always @(posedge clk_sys or negedge rst_sys_n) begin
    if (!rst_sys_n) begin
      go_s      <= 2'b00;
      h_state   <= H_IDLE;
      h_done    <= 1'b0;
      sd_rd     <= {N{1'b0}};
      sd_wr     <= {N{1'b0}};
      ack_sel_d <= 1'b0;
    end else begin
      go_s      <= {go_s[0], t_go};
      ack_sel_d <= ack_sel;

      case (h_state)
        H_IDLE: begin
          if (go_s[1]) begin
            // t_wr / t_lba / t_sel have been stable since before t_go rose
            if (t_wr) sd_wr <= t_sel;
            else      sd_rd <= t_sel;
            h_state <= H_REQ;
          end
        end

        H_REQ: begin
          // the request is held until the firmware has picked it up (ack rises),
          // then dropped so the next poll does not run it a second time
          if (ack_sel) begin
            sd_rd   <= {N{1'b0}};
            sd_wr   <= {N{1'b0}};
            h_state <= H_XFER;
          end
        end

        H_XFER: begin
          // the data moves in the always block above; the falling edge of
          // ack is the end of the transaction
          if (!ack_sel && ack_sel_d) begin
            h_done  <= 1'b1;
            h_state <= H_DONE;
          end
        end

        H_DONE: begin
          if (!go_s[1]) begin
            h_done  <= 1'b0;
            h_state <= H_IDLE;
          end
        end
      endcase
    end
  end

  // =======================================================================
  // clk_cpu side: mount copy, arbiter, client streaming
  // =======================================================================

  // ---- mount records copied over on the toggle ---------------------------
  reg [N-1:0]   tgl_s1, tgl_s2, tgl_seen;
  reg [N-1:0]   c_mounted;
  reg [N-1:0]   c_ro;
  reg [N*32-1:0] c_size;
  reg [N-1:0]   c_open_seen;    // an open_req was issued (for open_err)

  always @(posedge clk_cpu or negedge rst_cpu_n) begin
    if (!rst_cpu_n) begin
      tgl_s1      <= {N{1'b0}};
      tgl_s2      <= {N{1'b0}};
      tgl_seen    <= {N{1'b0}};
      c_mounted   <= {N{1'b0}};
      c_ro        <= {N{1'b0}};
      c_size      <= {(N*32){1'b0}};
      c_open_seen <= {N{1'b0}};
    end else begin
      tgl_s1 <= m_tgl;
      tgl_s2 <= tgl_s1;
      for (n = 0; n < N; n = n + 1) begin
        if (tgl_s2[n] != tgl_seen[n]) begin
          // the record was written >= 2 clk_sys cycles before the toggle
          // reached here and only changes on the next mount event, so a
          // plain copy across the domains is safe
          tgl_seen[n]        <= tgl_s2[n];
          c_mounted[n]       <= m_mounted[n];
          c_ro[n]            <= m_ro[n];
          c_size[n*32 +: 32] <= m_size[n*32 +: 32];
        end
        if (open_req[n]) c_open_seen[n] <= 1'b1;
      end
    end
  end

  // open semantics (spec: open_req pulse -> open_ok / open_err LEVELS).
  // There is nothing to "open": the file is whatever the OSD mounted. So
  // open_ok simply reports the mount, and open_err reports "you asked and
  // there is no file", which clears itself the moment one is mounted.
  assign open_ok    = c_mounted;
  assign open_err   = c_open_seen & ~c_mounted;
  assign size_bytes = c_size;
  assign mounted    = c_mounted;

  // ---- per-client request latch + round-robin arbiter --------------------
  reg [N-1:0]    pend;
  reg [N-1:0]    pend_wr;
  reg [N*16-1:0] pend_blk;
  reg [N*4-1:0]  code_q;         // err_code per client, valid with done

  assign err_code = code_q;

  localparam integer SW = (N <= 2) ? 1 : (N <= 4) ? 2 : (N <= 8) ? 3 : 4;
  reg [SW-1:0] rr;               // next slot to look at first
  reg [SW-1:0] g;                // granted client
  reg          g_act;            // a grant is being processed

  // the pick: first pending client at or after rr, wrapping
  reg [SW-1:0] pick;
  reg          pick_ok;
  integer k, m;
  always @(*) begin
    pick    = {SW{1'b0}};
    pick_ok = 1'b0;
    m       = 0;
    for (k = N - 1; k >= 0; k = k - 1) begin
      m = k + {{(32-SW){1'b0}}, rr};
      if (m >= N) m = m - N;
      if (pend[m]) begin
        pick    = m[SW-1:0];
        pick_ok = 1'b1;
      end
    end
  end

  assign busy = pend;

  // ---- client-side FSM ---------------------------------------------------
  localparam [2:0] C_IDLE   = 3'd0,  // pick a pending client, check it
                   C_PULL   = 3'd1,  // write: client buffer -> wbuf
                   C_GO     = 3'd2,  // hand to the QNICE side, wait h_done
                   C_STREAM = 3'd3,  // read: rbuf -> client buffer
                   C_DONE   = 3'd4;  // pulse done (+err)

  reg [2:0]  c_state;
  reg        g_wr;
  reg [15:0] g_blk;
  reg [10:0] idx;                // word walk, 0..1024
  reg        g_err;
  reg [3:0]  g_code;

  // the granted client's block-end check, 32-bit bytes
  wire [31:0] g_size    = c_size[g*32 +: 32];
  wire [31:0] blk_start = {5'd0, g_blk, 11'd0};        // block * 2048
  wire [31:0] blk_end   = blk_start + 32'd2048;

  // buffer mastering, one client at a time (all others parked at 0 so the
  // per-controller OR in the aggregators stays clean)
  reg [9:0]  o_addr;
  reg        o_we;
  reg [15:0] o_wdata;            // registered with o_we: same-cycle pair
  wire [15:0] g_rdata = buf_rdata[g*16 +: 16];

  genvar gc;
  generate
    for (gc = 0; gc < N; gc = gc + 1) begin : g_bus
      assign buf_addr [gc*10 +: 10] = (g_act && (g == gc)) ? o_addr : 10'd0;
      assign buf_wdata[gc*16 +: 16] = (g_act && (g == gc)) ? o_wdata : 16'd0;
      assign buf_we   [gc]          = (g_act && (g == gc)) ? o_we    : 1'b0;
    end
  endgenerate

  // rbuf registered read for the STREAM walk: address idx this cycle, word
  // out next cycle, written to the client at address idx-1
  //
  // wbuf write for the PULL walk. o_addr <= idx is registered, so the
  // client SEES address idx one cycle later, and its buffer read is itself
  // registered (every adapter: nd_storage_floppy_adapter's c_buf_rdata <=
  // s_blkbuf[c_buf_addr]; the disc adapter passes the controller's
  // registered dbuf_rdata straight through), so the word for address idx
  // is on buf_rdata TWO cycles after idx was set. Hence wbuf[idx-2].
  always @(posedge clk_cpu) begin
    rbuf_q <= {rbuf_hi[idx[9:0]], rbuf_lo[idx[9:0]]};
    if ((c_state == C_PULL) && (idx >= 11'd2)) wbuf[idx[9:0] - 10'd2] <= g_rdata;
  end

  always @(posedge clk_cpu or negedge rst_cpu_n) begin
    if (!rst_cpu_n) begin
      pend     <= {N{1'b0}};
      pend_wr  <= {N{1'b0}};
      pend_blk <= {(N*16){1'b0}};
      code_q   <= {(N*4){1'b0}};
      done     <= {N{1'b0}};
      err      <= {N{1'b0}};
      rr       <= {SW{1'b0}};
      g        <= {SW{1'b0}};
      g_act    <= 1'b0;
      g_wr     <= 1'b0;
      g_blk    <= 16'd0;
      idx      <= 11'd0;
      g_err    <= 1'b0;
      g_code   <= `NDS_ERR_NONE;
      o_addr   <= 10'd0;
      o_we     <= 1'b0;
      o_wdata  <= 16'd0;
      t_go     <= 1'b0;
      t_wr     <= 1'b0;
      t_lba    <= 32'd0;
      t_sel    <= {N{1'b0}};
      hd_s     <= 2'b00;
      c_state  <= C_IDLE;
    end else begin
      done <= {N{1'b0}};
      err  <= {N{1'b0}};
      o_we <= 1'b0;
      hd_s <= {hd_s[0], h_done};

      // latch requests (spec: a req while busy may be ignored - it is)
      for (n = 0; n < N; n = n + 1) begin
        if (req[n] && !pend[n]) begin
          pend[n]              <= 1'b1;
          pend_wr[n]           <= wr[n];
          pend_blk[n*16 +: 16] <= block[n*16 +: 16];
        end
      end

      case (c_state)
        C_IDLE: begin
          if (pick_ok) begin
            g      <= pick;
            g_act  <= 1'b1;
            g_wr   <= pend_wr[pick];
            g_blk  <= pend_blk[pick*16 +: 16];
            idx    <= 11'd0;
            g_err  <= 1'b0;
            g_code <= `NDS_ERR_NONE;
            // advance the scan past the winner: no starvation
            rr     <= ({{(32-SW){1'b0}}, pick} == N - 1) ? {SW{1'b0}} : pick + 1'b1;
            c_state <= C_GO;   // provisional; the checks below override
            // the three refusals, each with its reason
            if (!c_mounted[pick]) begin
              g_err <= 1'b1; g_code <= `NDS_ERR_NOTOPEN; c_state <= C_DONE;
            end else if (pend_wr[pick] && c_ro[pick]) begin
              g_err <= 1'b1; g_code <= `NDS_ERR_WRPROT;  c_state <= C_DONE;
            end else if (pend_wr[pick]) begin
              c_state <= C_PULL;  // range check follows in C_PULL's first cycle
            end
          end
        end

        // ---- write: walk the client buffer into wbuf, 1 word/cycle ------
        // (the range check sits here so g_* are registered when it runs)
        C_PULL: begin
          if ((idx == 11'd0) && (blk_end > g_size)) begin
            // a write must lie entirely inside the file: the QNICE firmware trims a
            // write past EOF and the image cannot grow through the core
            g_err <= 1'b1; g_code <= `NDS_ERR_RANGE; c_state <= C_DONE;
          end else begin
            if (idx < 11'd1024) o_addr <= idx[9:0];
            idx    <= idx + 11'd1;
            if (idx == 11'd1025) begin
              // the word for address 1023 landed this cycle (see the wbuf
              // write above); now hand the block to the QNICE side
              t_wr    <= 1'b1;
              t_lba   <= {14'd0, g_blk, 2'b00};   // block * 4 HPS blocks
              t_sel   <= {{(N-1){1'b0}}, 1'b1} << g;
              t_go    <= 1'b1;
              c_state <= C_GO;
            end
          end
        end

        // ---- reads arrive here straight from C_IDLE ----------------------
        C_GO: begin
          if (!t_go && !g_wr) begin
            if (blk_start >= g_size) begin
              // the block starts past the end of the file
              g_err <= 1'b1; g_code <= `NDS_ERR_RANGE; c_state <= C_DONE;
            end else begin
              t_wr  <= 1'b0;
              t_lba <= {14'd0, g_blk, 2'b00};
              t_sel <= {{(N-1){1'b0}}, 1'b1} << g;
              t_go  <= 1'b1;
            end
          end else if (hd_s[1]) begin
            // the QNICE side is finished: release the handshake
            t_go <= 1'b0;
            idx  <= 11'd0;
            if (g_wr) c_state <= C_DONE;
            else      c_state <= C_STREAM;
          end
        end

        // ---- read: walk rbuf into the client buffer, 1 word/cycle --------
        C_STREAM: begin
          // rbuf_q holds word idx-1 this cycle (registered read above);
          // address, data and strobe are registered TOGETHER so the client
          // sees them in the same cycle (the strobe alone registered, with
          // the data taken live, delivered word k+1 at address k - caught by
          // nd_storage_hps_tb test 3)
          idx <= idx + 11'd1;
          if (idx != 11'd0) begin
            o_addr  <= idx[9:0] - 10'd1;
            o_wdata <= rbuf_q;
            o_we    <= 1'b1;
          end
          if (idx == 11'd1024) c_state <= C_DONE;
        end

        C_DONE: begin
          // wait for the QNICE side to have dropped h_done before the next
          // request can raise go again (4-phase discipline)
          if (!hd_s[1]) begin
            done[g]            <= 1'b1;
            err[g]             <= g_err;
            code_q[g*4 +: 4]   <= g_err ? g_code : `NDS_ERR_NONE;
            pend[g]            <= 1'b0;
            g_act              <= 1'b0;
            o_addr             <= 10'd0;
            c_state            <= C_IDLE;
          end
        end

        default: c_state <= C_IDLE;
      endcase
    end
  end

endmodule
