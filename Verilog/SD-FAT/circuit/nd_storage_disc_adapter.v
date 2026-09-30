`include "nd_storage_status.vh"
/****************************************************************************
** nd_storage_disc_adapter - block adapter for the ND_SMD disk backend      **
**                                                                         **
** Sits between ND_SMD's disk-image backend port (pin-for-pin, see         **
** Verilog/ND-BUS-DEVICES/SMD/circuit/ND_SMD.v) and ONE nd_storage client  **
** port (client 3 = SMD0.IMG in the v1 owner file set). Single clock:      **
** clk_cpu (the client-port domain - the CDC lives inside nd_storage).     **
**                                                                         **
** THE DEVICE CONTRACT (read from ND_SMD.v and mirrored from the TWO       **
** existing backends - the unit tb model in                                **
** Verilog/ND-BUS-DEVICES/SMD/sim/nd_smd_tb.v and the Verilator C backend  **
** process_verilog_smd() in Verilog/simDevices/NDBus.cpp - so the same     **
** image bytes work in sim and on the card):                               **
**   disk_start      in   1-cycle pulse at command start: LATCH the base   **
**                        position from the block-address registers        **
**   disk_req        in   1-cycle pulse: move ONE CHUNK (may coincide      **
**                        with disk_start - the boot path and M0 do)       **
**   disk_wr         in   0 = image -> device buffer, 1 = buffer -> image  **
**   disk_blkaddr1   in   [15:0] head b15-8, sector b7-0                   **
**   disk_blkaddr2   in   [15:0] cylinder                                  **
**   disk_unit       in   [2:0]  selected drive                            **
**   disk_wordcount  in   [10:0] words in this chunk (1..1024)             **
**   disk_done       out  1-cycle pulse (device waits on it as a level)    **
**   disk_err        out  valid with disk_done (device disk_err_in)        **
**   dbuf_addr/wdata/we out: fill the device's 1024x16 buffer (reads)      **
**   dbuf_rdata      in   device buffer readout - REGISTERED in ND_SMD     **
**                        (sync-read BSRAM): valid one cycle after the     **
**                        address, which the engine's 3-cycle write pull   **
**                        (address / wait / sample) tolerates              **
**                                                                         **
** POSITION MAPPING - the ORACLE CHS->LBA formula (same as nd100x /         **
** RetroCore, so an image prepared there reads correctly here), kept in     **
** lockstep with the Verilator C backend process_verilog_smd() in           **
** Verilog/simDevices/NDBus.cpp:                                            **
**   LBA         = (disk_blkaddr2 * GEO_HEADS + head) * GEO_SPT + sector    **
**   word offset = LBA * 512            (1024-byte sector = 512 words)      **
** with head = disk_blkaddr1[15:8], sector = disk_blkaddr1[7:0].           **
** (WAS disk_blkaddr2 * 2048 + disk_blkaddr1 * 64, which only agreed with   **
** the real geometry at block 0 - a working boot but garbage past it.)     **
** disk_start latches it; chunks advance linearly (+wordcount each done).  **
** File words are big-endian bytes, same as the nd_storage engine packs    **
** them (word w = {byte 2w, byte 2w+1}) - one image format everywhere.     **
** NOTE the unit tb Verilog/ND-BUS-DEVICES/SMD/sim/nd_smd_tb.v keeps its    **
** OWN self-contained linear map (it never touches a real image), so it     **
** deliberately does NOT use this formula.                                 **
**                                                                         **
** ZERO-BSRAM STREAM-THROUGH (deliberate divergence from the floppy        **
** adapter): the floppy adapter caches the current 2048-byte block in a    **
** local 1024x16 RAM, which costs one Gowin BSRAM. The Tang build has      **
** exactly ONE BSRAM left for the whole SMD subsystem and ND_SMD's own     **
** buffer takes it, so this adapter holds NO payload:                      **
**   READ:  a chunk may span two client blocks (position is 64-word        **
**          granular). Per covered block: one c_req block read; the        **
**          engine streams all 1024 block words in order through           **
**          c_buf_we/c_buf_addr/c_buf_wdata; the in-segment words are      **
**          forwarded (re-registered, address-translated) to dbuf_*.      **
**   WRITE: only a FULL ALIGNED BLOCK (chunk offset 0 mod 1024 words AND   **
**          wordcount 1024) is accepted: one c_req block write, and the    **
**          engine's pull (c_buf_addr walk) is served STRAIGHT from the    **
**          device buffer (dbuf_addr = c_buf_addr, c_buf_rdata =           **
**          dbuf_rdata). An UNALIGNED or PARTIAL write answers             **
**          done+err with zero traffic: read-modify-write would need a     **
**          block of storage this adapter must not have. ND_SMD turns      **
**          that into comparer-error + error interrupt - visible, never    **
**          silent. Sector-aligned SMD transfers (the normal driver        **
**          pattern: cylinder/head/sector maps to 64-word multiples,      **
**          1024-word chunks at even 512-word sectors are block-aligned    **
**          when the transfer starts on an even sector) work; arbitrary    **
**          offsets do not. The Verilator C backend has no such limit -    **
**          documented divergence.                                         **
**                                                                         **
** Errors (disk_done WITH disk_err, never a wedge, always retryable):      **
**   - file not open (c_open_ok low)                                       **
**   - out of range: chunk end past c_size_bytes (covers the tail-block    **
**     write rule too: an aligned block write ends exactly at the block    **
**     end, so a partial tail block always refuses)                        **
**   - write not a full aligned block (see above)                          **
**   - c_err from nd_storage (SD/engine failure): clean error, retryable   **
**                                                                         **
** disk_unit != UNIT is ignored COMPLETELY (all outputs parked 0), so      **
** per-unit instances can OR their disk_done/disk_err/dbuf_* outputs.      **
**                                                                         **
** open_start is a level/pulse from the board logic; while high it is      **
** passed through as c_open_req pulses (nd_storage ignores it while the    **
** port is busy), same as the floppy adapter.                              **
**                                                                         **
** Last reviewed: 31-JUL-2026                                              **
** Ronny Hansen                                                            **
*****************************************************************************/

module nd_storage_disc_adapter #(
    parameter [2:0]  UNIT = 3'd0,      // disk_unit value this instance serves
    // Drive geometry, used to turn cylinder/head/sector into a flat image
    // offset. MUST match the GEO_* parameters of the ND_SMD instance in front
    // of this adapter and the disk table in the emulator references (75 MB
    // unit = 5 heads, 18 sectors/track, 823 cylinders, 1024-byte sectors).
    parameter [15:0] GEO_HEADS = 16'd5,
    parameter [15:0] GEO_SPT   = 16'd18
) (
    input wire clk_cpu,
    input wire rst_n,                   //! Active-low reset, from the board's power-on reset (same net as ND120_CORE.sys_rst_n)

    // Disk-image backend port (to ND_SMD, pin-for-pin)
    input  wire        disk_start,      // 1-cycle pulse: latch base position
    input  wire        disk_req,        // 1-cycle pulse: move one chunk
    input  wire        disk_wr,         // 0 = image -> buffer, 1 = buffer -> image
    input  wire [15:0] disk_blkaddr1,   // head b15-8, sector b7-0
    input  wire [15:0] disk_blkaddr2,   // cylinder
    input  wire [ 2:0] disk_unit,       // unit select
    input  wire [10:0] disk_wordcount,  // words in this chunk
    output reg         disk_done,       // 1-cycle pulse
    output reg         disk_err,        // valid with disk_done
    // WHY it failed, valid with disk_done (nd_storage_status.vh). The
    // controller maps this onto a status bit ITS OWN MANUAL defines - it
    // never invents one - so the guest can tell a missing card from a
    // missing file from a block past the end of the image.
    output reg  [3:0]  disk_err_code,
    output wire [ 9:0] dbuf_addr,       // device buffer fill (reads) / readout (writes)
    output reg  [15:0] dbuf_wdata,
    output reg         dbuf_we,
    input  wire [15:0] dbuf_rdata,      // registered readout in ND_SMD

    // Board/boot control
    input wire open_start,  // (re)open the image file (held or pulsed)

    // nd_storage client port (one client, clk_cpu domain)
    output reg         c_open_req,
    input  wire        c_open_ok,
    input  wire        c_open_err,
    input  wire [31:0] c_size_bytes,
    output reg         c_req,
    output reg         c_wr,
    output reg  [15:0] c_block,
    input  wire        c_busy,
    input  wire        c_done,          // 1-cycle pulse
    input  wire        c_err,           // valid with c_done
    input  wire [3:0]  c_err_code,      // valid with c_done when c_err
    input  wire [ 9:0] c_buf_addr,
    input  wire [15:0] c_buf_wdata,
    input  wire        c_buf_we,
    output wire [15:0] c_buf_rdata      // served straight from the device buffer
);

  // ---- request decode ---------------------------------------------------
  wire s_unit_match = (disk_unit == UNIT);

  // base word position = CHS -> LBA -> words:
  //   LBA    = (cylinder * GEO_HEADS + head) * GEO_SPT + sector
  //   words  = LBA * 512            (1024-byte sector = 512 words)
  // Was blkaddr2*2048 + blkaddr1*64, which only agrees with the real geometry
  // at block 0 - hence a working boot but garbage for any later sector.
  wire [15:0] s_head = {8'd0, disk_blkaddr1[15:8]};
  wire [15:0] s_sect = {8'd0, disk_blkaddr1[7:0]};
  wire [31:0] s_lba  = ({16'd0, disk_blkaddr2} * {16'd0, GEO_HEADS} +
                        {16'd0, s_head}) * {16'd0, GEO_SPT} + {16'd0, s_sect};
  wire [31:0] s_base32 = s_lba << 9;          // * 512 words
  wire [27:0] s_base   = s_base32[27:0];
  wire        s_base_ovf = |s_base32[31:28];  // refuse rather than alias

  reg  [27:0] s_pos;  // next chunk's word position (advances across chunks)
  reg         s_pos_ovf;

  // disk_start may coincide with disk_req: the effective position of a
  // request accepted THIS cycle is the freshly latched base
  wire [27:0] s_p0     = disk_start ? s_base     : s_pos;
  wire        s_p0_ovf = disk_start ? s_base_ovf : s_pos_ovf;

  // chunk end in bytes must lie inside the file
  wire [31:0] s_end_bytes = ({3'b0, s_p0} + {21'b0, disk_wordcount}) << 1;
  wire        s_oor       = s_end_bytes > c_size_bytes;

  // client blocks are 16-bit indices: positions above 2^26 words can never
  // be in range for a slot-resident file, refuse before truncating
  wire        s_blk_ovf   = (s_p0[27:26] != 2'b00) | s_p0_ovf;

  // WRITE ACCEPTANCE. Was "full aligned 1024-word block only", which refused
  // every write SINTRAN issues: it writes 512 words = 1024 bytes = one ND page
  // = exactly ONE WINCHESTER SECTOR, the natural unit for this card. The
  // storage layer's block is 2048 bytes, so a sector write is half a block.
  // Silicon trace 10-AUG-2026: word count 001000, control 004045, status
  // 021030 - refused - and the boot died with "DISC TRANSFER ERROR IN SEGMENT
  // HANDLING".
  //
  // A partial block is now served by READ-MODIFY-WRITE (S_MREQ/S_MWAIT
  // below). What is still refused is a MULTI-block chunk whose first block is
  // partial: the merged words are staged in the device buffer above the
  // guest's own chunk, so there is only room when the chunk fits in one block
  // (s_wc <= s_seg). SINTRAN's sector writes always do.
  wire        s_wr_partial = (s_p0[9:0] != 10'd0) || (disk_wordcount != 11'd1024);
  wire [10:0] s_seg0       = ((11'd1024 - {1'b0, s_p0[9:0]}) < disk_wordcount)
                             ? (11'd1024 - {1'b0, s_p0[9:0]}) : disk_wordcount;
  wire        s_wr_badal   = s_wr_partial && (disk_wordcount > s_seg0);

  wire s_bad = !c_open_ok
             | s_oor
             | s_blk_ovf
             | (disk_wr & s_wr_badal);

  // ---- FSM ---------------------------------------------------------------
  localparam [2:0] S_IDLE  = 3'd0,  // wait for a matching disk_req
                   S_CREQ  = 3'd1,  // wait !c_busy, pulse c_req for one block
                   S_CWAIT = 3'd2,  // client op in flight (stream forwarding)
                   S_DONE  = 3'd3,  // pulse disk_done (+disk_err)
                   S_MREQ  = 3'd4,  // read-modify-write: request the block
                   S_MWAIT = 3'd5;  // ...and keep the words we are NOT writing

  reg [ 2:0] s_state;
  reg        s_merge;    // this segment is partial: merge before writing
  reg        s_op_wr;    // latched disk_wr
  reg [10:0] s_wc;       // latched disk_wordcount
  reg [27:0] s_p;        // running word position (start of current segment)
  reg [10:0] s_idx;      // chunk words already served before this segment
  reg [10:0] s_seg;      // words this block segment covers
  reg        s_err_q;    // verdict for the S_DONE pulse
  reg [3:0]  s_code_q;   // and WHY, for the same pulse
  reg [ 9:0] r_dbuf_addr;

  // current segment geometry (combinational; latched into s_seg at c_req)
  wire [ 9:0] s_off       = s_p[9:0];               // offset inside the block
  wire [10:0] s_blkrem    = 11'd1024 - {1'b0, s_off};
  wire [10:0] s_chunkrem  = s_wc - s_idx;
  wire [10:0] s_seg_next  = (s_blkrem < s_chunkrem) ? s_blkrem : s_chunkrem;

  // read-forward window: block word s_off .. s_off + s_seg - 1
  wire [10:0] s_win_lo    = {1'b0, s_off};
  wire [10:0] s_win_hi    = {1'b0, s_off} + s_seg;  // exclusive, max 1024
  wire        s_in_win    = ({1'b0, c_buf_addr} >= s_win_lo) &&
                            ({1'b0, c_buf_addr} <  s_win_hi);

  // write pull served straight from the device buffer (registered read in
  // ND_SMD; the engine's address/wait/sample pull gives it the cycle it
  // needs). Aligned full-block writes make the translation the identity.
  // Where block word c_buf_addr lives in the device buffer during a write
  // pull. For an aligned full block this is the identity, as before. For a
  // merged partial block it is NOT: the guest's own words sit at the bottom
  // of the buffer (chunk-relative, s_idx..), while the words fetched by the
  // merge read are staged ABOVE the chunk at s_seg.. in block order. Getting
  // this wrong writes the right number of words in the wrong places, which
  // looks like data corruption rather than a refusal.
  wire [10:0] s_mrg_idx = ({1'b0, c_buf_addr} < s_win_lo)
                          ? {1'b0, c_buf_addr}
                          : ({1'b0, c_buf_addr} - s_seg);
  wire [ 9:0] s_wr_dbuf = s_in_win
                          ? (s_idx[9:0] + (c_buf_addr - s_off))
                          : (s_seg[9:0] + s_mrg_idx[9:0]);

  wire s_wr_stream = (s_state == S_CWAIT) && s_op_wr;
  assign dbuf_addr   = s_wr_stream ? s_wr_dbuf : r_dbuf_addr;
  assign c_buf_rdata = dbuf_rdata;

  always @(posedge clk_cpu or negedge rst_n) begin
    if (!rst_n) begin
      disk_done   <= 1'b0;
      disk_err    <= 1'b0;
      dbuf_wdata  <= 16'd0;
      dbuf_we     <= 1'b0;
      r_dbuf_addr <= 10'd0;
      c_open_req  <= 1'b0;
      c_req       <= 1'b0;
      c_wr        <= 1'b0;
      c_block     <= 16'd0;
      s_pos       <= 28'd0;
      s_pos_ovf   <= 1'b0;
      s_state     <= S_IDLE;
      s_op_wr     <= 1'b0;
      s_wc        <= 11'd0;
      s_p         <= 28'd0;
      s_idx       <= 11'd0;
      s_seg       <= 11'd0;
      s_err_q     <= 1'b0;
      s_code_q    <= `NDS_ERR_NONE;
      disk_err_code <= `NDS_ERR_NONE;
    end else begin
      disk_done  <= 1'b0;
      disk_err   <= 1'b0;
      dbuf_we    <= 1'b0;
      c_req      <= 1'b0;
      c_open_req <= 1'b0;

      if (open_start) c_open_req <= 1'b1;

      // base-position latch (any state; the device only pulses it at
      // command start, and an accept in the same cycle uses s_p0)
      if (disk_start && s_unit_match) begin
        s_pos     <= s_base;
        s_pos_ovf <= s_base_ovf;
      end

      case (s_state)
        S_IDLE: begin
          // idle outputs parked at 0 so per-unit instances can OR their pins
          r_dbuf_addr <= 10'd0;
          dbuf_wdata  <= 16'd0;
          if (disk_req && s_unit_match) begin
            s_op_wr <= disk_wr;
            s_wc    <= disk_wordcount;
            s_p     <= s_p0;
            s_idx   <= 11'd0;
            if (s_bad) begin
              s_err_q <= 1'b1;
              // Say WHICH refusal this is. All three used to look identical
              // to the guest, and a write silently refused for being
              // unaligned is the worst of them: the data never reached the
              // card and nothing said so beyond one anonymous error bit.
              s_code_q <= !c_open_ok            ? `NDS_ERR_NOTOPEN
                        : (s_oor | s_blk_ovf)   ? `NDS_ERR_RANGE
                                                : `NDS_ERR_WRALIGN;
              s_state <= S_DONE;
            end else if (disk_wordcount == 11'd0) begin
              s_err_q  <= 1'b0;          // nothing to move: clean completion
              s_code_q <= `NDS_ERR_NONE;
              s_state <= S_DONE;
            end else if (disk_wr && s_wr_partial) begin
              s_merge <= 1'b1;           // fetch the block before writing it
              s_state <= S_MREQ;
            end else begin
              s_merge <= 1'b0;
              s_state <= S_CREQ;
            end
          end
        end

        // pulse c_req as soon as the port is free (req while busy is lost)
        S_CREQ: begin
          if (!c_busy) begin
            c_req   <= 1'b1;
            c_wr    <= s_op_wr;
            c_block <= s_p[25:10];
            s_seg   <= s_seg_next;
            s_state <= S_CWAIT;
          end
        end

        // ---- read-modify-write, phase 1: fetch the block ----------------
        // The guest supplied only part of this block. Read the whole block and
        // keep the words OUTSIDE the guest's window - the inverse of the read
        // forwarding below - staged above the chunk. The guest's own words in
        // the device buffer are left untouched. Skipping this would write a
        // half-filled block and silently destroy the other half.
        S_MREQ: begin
          if (!c_busy) begin
            c_req   <= 1'b1;
            c_wr    <= 1'b0;            // READ
            c_block <= s_p[25:10];
            s_seg   <= s_seg_next;
            s_state <= S_MWAIT;
          end
        end

        S_MWAIT: begin
          if (c_buf_we && !s_in_win) begin
            dbuf_we     <= 1'b1;
            r_dbuf_addr <= s_seg[9:0] + s_mrg_idx[9:0];
            dbuf_wdata  <= c_buf_wdata;
          end
          if (c_done) begin
            if (c_err) begin
              s_err_q  <= 1'b1;
              s_code_q <= c_err_code;
              s_state  <= S_DONE;
            end else begin
              s_state <= S_CREQ;        // now write the merged block back
            end
          end
        end

        S_CWAIT: begin
          // read stream: forward the in-segment block words to the device
          // buffer, re-registered with the chunk-relative address
          if (!s_op_wr && c_buf_we && s_in_win) begin
            dbuf_we     <= 1'b1;
            r_dbuf_addr <= s_idx[9:0] + (c_buf_addr - s_off);
            dbuf_wdata  <= c_buf_wdata;
          end
          if (c_done) begin
            if (c_err) begin
              s_err_q  <= 1'b1;
              s_code_q <= c_err_code;   // pass the storage stack's reason on
              s_state  <= S_DONE;
            end else if (s_op_wr) begin
              s_pos   <= s_p + 28'd1024;  // one full block committed
              s_err_q  <= 1'b0;
              s_code_q <= `NDS_ERR_NONE;
              s_state  <= S_DONE;
            end else if ({6'd0, s_idx} + {6'd0, s_seg} >= {6'd0, s_wc}) begin
              s_pos   <= s_p + {17'd0, s_seg};  // chunk complete
              s_err_q  <= 1'b0;
              s_code_q <= `NDS_ERR_NONE;
              s_state  <= S_DONE;
            end else begin
              s_idx   <= s_idx + s_seg;   // next covered block
              s_p     <= s_p + {17'd0, s_seg};
              s_state <= S_CREQ;
            end
          end
        end

        S_DONE: begin
          disk_done   <= 1'b1;
          disk_err      <= s_err_q;
          disk_err_code <= s_code_q;
          r_dbuf_addr <= 10'd0;
          dbuf_wdata  <= 16'd0;
          s_state     <= S_IDLE;
        end

        default: s_state <= S_IDLE;
      endcase
    end
  end

endmodule
