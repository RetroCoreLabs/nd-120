/****************************************************************************
** nd_storage_cache - tag / LRU directory for the shared block cache       **
**                                                                         **
** Phase 4 of the storage facade. docs/nd-storage-design.md section 2.1    **
** named "the Phase-4 tag-based cache" but never specified it; this module **
** and the engine changes that use it ARE that specification.              **
**                                                                         **
** WHY                                                                     **
**   v1 mapped a client block straight onto a region block in one line     **
**   (nd_storage_engine.v: s_blk_abs <= slot_base + op_block), so an image **
**   could never exceed its slot and the mount refused size > slot. A real **
**   Winchester image is 75 MB against a 256 KB slot. The region is 2048   **
**   blocks = 4 MB and cannot be widened cheaply (s_blk_abs is [10:0] and  **
**   feeds mem_addr into ND120_CORE / ND3202D / MEM_43), so the region     **
**   stops being a COPY of the image and becomes a CACHE of it: every      **
**   block of an arbitrarily large image is reachable and the resident set **
**   is whatever the guest is actually touching.                           **
**                                                                         **
** WHAT IS CACHED                                                          **
**   Per client, via CACHE_MASK in nd_storage: 1 = through this directory, **
**   0 = DIRECT (block requests go straight to the card, region untouched).**
**   Tape and floppy are DIRECT - the card is quick enough for them, and   **
**   caching them would spend region on devices that do not need it. The   **
**   disc classes (SMD, Winchester) are CACHED because SINTRAN's working   **
**   set is what decides whether the machine feels quick. Enabling the     **
**   floppy later is one bit in CACHE_MASK and nothing else.               **
**                                                                         **
** ORGANISATION                                                            **
**   ONE SHARED pool over all cached clients, not a fixed window per unit: **
**   the tag carries the client id, so the disc doing the work gets the    **
**   whole pool and an idle second unit costs nothing.                     **
**                                                                         **
**     line         = one 2048-byte region block (the block granularity    **
**                    the whole stack already uses)                        **
**     set index    = client_block[SETIDX-1:0]                             **
**     tag          = { client[2:0], client_block[BLKW-1:SETIDX] }         **
**     region block = POOL_BASE_BLK + set*WAYS + way                       **
**                                                                         **
** STORAGE SHAPE - the thing that decides whether this fits the FPGA       **
**   ONE array. A set's tags AND ranks AND valid bits live in a single     **
**   word, so a set is one registered read, all ways compare in the same   **
**   cycle, and the whole directory is a single-clock BSRAM with one write **
**   port. Two rules that are not optional:                                **
**                                                                         **
**     - NEVER reset the array with a loop over its entries. That infers   **
**       flip-flops instead of block RAM; at 512 sets it cost ~26k flip-   **
**       flops in the first version of this module, more than the part     **
**       has. The mass clear is a WALKING clear instead (SETS cycles after **
**       reset), invisible because the first open spends hundreds of       **
**       thousands of cycles in SD card init before any lookup arrives.    **
**                                                                         **
**     - NEVER split rank or valid into their own arrays read              **
**       combinationally. The second version did exactly that, because the **
**       valid bits need a mass clear, and it measured 187283 AND gates at **
**       512x4 under yosys/synth_gowin - tens of thousands of LUT4 on a    **
**       part with 20736, nearly all of it the SETS-deep read multiplexer  **
**       and write decoder that an indexed FF array builds per bit. Folded **
**       into the BSRAM word there is no multiplexer at all.               **
**                                                                         **
** ONE OUTSTANDING LOOKUP                                                  **
**   The engine serializes: one granted client, one block op at a time. So **
**   there is no pipeline hazard here and no bypass network - IDLE -> RD   **
**   -> CMP and back. A lookup costs 3 cycles, which is noise against the  **
**   four-sector card read a miss then performs.                           **
**                                                                         **
** LRU                                                                     **
**   2 bits of rank per way per set: 0 = most recently used, WAYS-1 =      **
**   least. A hit or a fill promotes its way to 0 and pushes every way     **
**   that outranked it down one. The victim is the way at rank WAYS-1.     **
**   Invalid ways are taken before any valid way, so a cold pool fills     **
**   before it evicts anything. Ranks are read-modify-written in CMP.      **
**                                                                         **
** WRITE POLICY                                                            **
**   Write-through, write-allocate. The engine commits to the card FIRST,  **
**   then the region copy, then reports done - the existing ordering rule, **
**   so a failed CMD24 never leaves the region holding data the card does  **
**   not have. No dirty bit and no writeback exists here, which is what    **
**   makes a reset or a card pull safe at any instant.                     **
**                                                                         **
** INVALIDATION                                                            **
**   inval_req drops every line of one client - used when a client is      **
**   re-opened (card swap, remount) so lines from the old file cannot      **
**   survive into the new one. Walks the sets, two cycles each, and only   **
**   ever runs at open.                                                    **
**                                                                         **
** Ronny Hansen                                                            **
*****************************************************************************/

module nd_storage_cache #(
    parameter        WAYS          = 4,
    parameter        SETS          = 512,
    parameter        SETIDX        = 9,      // log2(SETS)
    parameter [31:0] POOL_BASE_BLK = 32'd0,  // first region block of the pool
    // Client block numbers are 16-bit throughout the stack (n_blocks is
    // [15:0], r_nblk = size[26:11]) - 65536 blocks = 128 MB of image.
    parameter        BLKW          = 16
) (
    input  wire clk,
    input  wire rst_n,

    // ---- lookup (one outstanding) --------------------------------------
    input  wire             lookup_req,     // 1-cycle pulse
    input  wire [2:0]       lookup_client,
    input  wire [BLKW-1:0]  lookup_block,
    output reg              lookup_done,    // 1-cycle pulse
    output reg              lookup_hit,
    output reg  [2:0]       lookup_way,     // way to serve (hit) or fill (miss)
    output reg  [10:0]      lookup_line,    // region block to read/write

    // ---- allocate: publish a filled line --------------------------------
    // Issued by the engine only AFTER the card read for the line completed,
    // so a line is never advertised resident while its contents are in
    // flight. Uses the way the matching lookup returned.
    input  wire             alloc_req,
    input  wire [2:0]       alloc_client,
    input  wire [BLKW-1:0]  alloc_block,
    input  wire [2:0]       alloc_way,
    output reg              alloc_done,

    // ---- invalidate every line of one client -----------------------------
    input  wire             inval_req,      //! tied to 0 (in nd_storage)
    input  wire [2:0]       inval_client,   //! tied to 0 (in nd_storage)
    output reg              inval_done
);

  localparam WAYW = (WAYS <= 2) ? 1 : (WAYS <= 4) ? 2 : 3;
  localparam TAGW = 3 + (BLKW - SETIDX);   // { client, block[BLKW-1:SETIDX] }

  // ---- directory storage ---------------------------------------------------
  // ONE array, one word per set, holding every way's tag AND rank AND valid
  // bit; registered read, single write port, never reset by a loop. That
  // shape is what infers block RAM.
  //
  // The second version of this module kept rank and valid in SEPARATE arrays
  // of flip-flops, read combinationally, because the valid bits need a mass
  // clear. Measured with yosys/synth_gowin at the default 512x4 geometry,
  // that cost 187283 AND gates - tens of thousands of LUT4 on a part with
  // 20736 of them, most of it the SETS-deep read multiplexer and write
  // decoder that a combinationally-read indexed array has to build for every
  // single bit. Folding rank and valid into the same word removes both: the
  // read is the BSRAM's own registered read, the write is the BSRAM's own
  // write port, and there is no multiplexer at all.
  //
  // Word layout, tag at the bottom so the per-way tag slicing is unchanged:
  //   [ valid(WAYS) | rank(WAYS*2) | tag(WAYS*TAGW) ]
  //
  // The mass clear is still a WALKING clear (SETS cycles after reset), which
  // is now simply SETS ordinary writes to this array. Ranks come out of it
  // defined - way k at rank k - because an undefined rank leaves the victim
  // choice arbitrary, which is a bug the first version of this module
  // shipped: eviction appeared to work, by luck.
  localparam RANK_LSB = WAYS * TAGW;
  localparam VLD_LSB  = WAYS * TAGW + WAYS * 2;
  localparam DIRW     = WAYS * TAGW + WAYS * 2 + WAYS;

  reg [DIRW-1:0] dir_ram[0:SETS-1];
  reg [DIRW-1:0] dir_q;                        // registered (BSRAM) read

  wire [WAYS*TAGW-1:0] tag_q   = dir_q[0        +: WAYS*TAGW];
  wire [WAYS*2-1:0]    rank_q  = dir_q[RANK_LSB +: WAYS*2];
  wire [WAYS-1:0]      valid_q = dir_q[VLD_LSB  +: WAYS];
  // The invalidate sweep reads through the same registered port (rd_set
  // selects inv_set in S_INV and inv_rd gives that read its cycle), so the
  // swept set's valid bits are just this word's valid field.
  wire [WAYS-1:0]      valid_i = valid_q;

  // Way k starts at rank k, so the victim is well defined from the very
  // first eviction instead of every way claiming to be least-recently-used.
  wire [WAYS*2-1:0] rank_init;
  genvar gi;
  generate
    for (gi = 0; gi < WAYS; gi = gi + 1) begin : g_rank_init
      assign rank_init[gi*2 +: 2] = gi[1:0];
    end
  endgenerate

  // Ways of the swept set whose tag carries the client being invalidated.
  reg [WAYS-1:0] inv_mask;
  integer im;
  always @(*) begin
    inv_mask = {WAYS{1'b0}};
    for (im = 0; im < WAYS; im = im + 1)
      if (tag_q[im*TAGW + (TAGW-3) +: 3] == inv_cli) inv_mask[im] = 1'b1;
  end

  integer is;
  integer sw;   // sequential-block loop var; w belongs to the comb block

  // ---- request latch -------------------------------------------------------
  reg [2:0]         rq_client;
  reg [BLKW-1:0]    rq_block;
  reg               rq_is_alloc;
  wire [SETIDX-1:0] rq_set = rq_block[SETIDX-1:0];
  wire [TAGW-1:0]   rq_tag = {rq_client, rq_block[BLKW-1:SETIDX]};

  // ---- way match / victim select (combinational over the registered set word) ---
  reg             m_hit;
  reg [WAYW-1:0]  m_way;
  reg             m_free;
  reg [WAYW-1:0]  m_free_way;
  reg [WAYW-1:0]  m_lru_way;

  integer w;
  always @(*) begin
    m_hit      = 1'b0;
    m_way      = {WAYW{1'b0}};
    m_free     = 1'b0;
    m_free_way = {WAYW{1'b0}};
    m_lru_way  = {WAYW{1'b0}};
    for (w = 0; w < WAYS; w = w + 1) begin
      if (valid_q[w] && tag_q[w*TAGW +: TAGW] == rq_tag) begin
        m_hit = 1'b1;
        m_way = w[WAYW-1:0];
      end
      if (!valid_q[w] && !m_free) begin
        m_free     = 1'b1;
        m_free_way = w[WAYW-1:0];
      end
      if (rank_q[w*2 +: 2] == (WAYS-1)) m_lru_way = w[WAYW-1:0];
    end
  end

  wire [WAYW-1:0] sel_way = m_hit  ? m_way
                          : m_free ? m_free_way
                          :          m_lru_way;

  // Promoted rank word: sel goes to 0, everything that outranked it drops one.
  reg [WAYW-1:0]   alloc_way_q;
  reg [WAYS*2-1:0] rank_promoted;
  reg [WAYW-1:0]   pw;
  integer k;
  always @(*) begin
    pw            = rq_is_alloc ? alloc_way_q : sel_way;
    rank_promoted = rank_q;
    for (k = 0; k < WAYS; k = k + 1) begin
      if (k[WAYW-1:0] == pw)
        rank_promoted[k*2 +: 2] = 2'd0;
      else if (rank_q[k*2 +: 2] < rank_q[pw*2 +: 2])
        rank_promoted[k*2 +: 2] = rank_q[k*2 +: 2] + 2'd1;
    end
  end


  // ---- FSM -----------------------------------------------------------------
  localparam S_IDLE = 2'd0;
  localparam S_RD   = 2'd1;   // registered read of the set word in flight
  localparam S_CMP  = 2'd2;   // compare, emit, write back rank/tag/valid
  localparam S_INV  = 2'd3;

  reg [1:0]         state;
  reg               init_busy;
  reg [SETIDX-1:0]  init_ptr;
  reg [SETIDX-1:0]  inv_set;
  reg [2:0]         inv_cli;
  reg               inv_rd;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state       <= S_IDLE;
      lookup_done <= 1'b0;
      lookup_hit  <= 1'b0;
      lookup_way  <= {WAYW{1'b0}};
      lookup_line <= 11'd0;
      alloc_done  <= 1'b0;
      inval_done  <= 1'b0;
      inv_set     <= {SETIDX{1'b0}};
      inv_rd      <= 1'b0;
      rq_is_alloc <= 1'b0;
      // No for-loop over the arrays here. A delayed assignment to an array
      // inside a loop is unsupported by Verilator, and clearing every entry
      // on one edge would infer a mass reset across thousands of flip-flops.
      // A walking clear runs for SETS cycles after reset instead, which is
      // invisible: the first open spends hundreds of thousands of cycles in
      // SD card init before any lookup can happen.
      init_busy <= 1'b1;
      init_ptr  <= {SETIDX{1'b0}};
    end else begin
      lookup_done <= 1'b0;
      alloc_done  <= 1'b0;
      inval_done  <= 1'b0;

      if (init_busy) begin
        // the array write itself lives in the reset-free process below
        if (init_ptr == (SETS-1)) init_busy <= 1'b0;
        else                      init_ptr  <= init_ptr + 1'b1;
      end

      case (state)
        S_IDLE: begin
          if (init_busy) begin
            // directory not usable until the walking clear finishes
          end else if (lookup_req) begin
            rq_client   <= lookup_client;
            rq_block    <= lookup_block;
            rq_is_alloc <= 1'b0;
            state       <= S_RD;
          end else if (alloc_req) begin
            rq_client   <= alloc_client;
            rq_block    <= alloc_block;
            alloc_way_q <= alloc_way[WAYW-1:0];
            rq_is_alloc <= 1'b1;
            state       <= S_RD;
          end else if (inval_req) begin
            inv_cli <= inval_client;
            inv_set <= {SETIDX{1'b0}};
            inv_rd  <= 1'b0;
            state   <= S_INV;
          end
        end

        // Registered read: the set word is presented to tag_q/rank_q/valid_q
        // by the synchronous block below, valid in S_CMP.
        S_RD: state <= S_CMP;

        S_CMP: begin
          if (rq_is_alloc) begin
            alloc_done <= 1'b1;   // directory word written below
          end else begin
            lookup_done <= 1'b1;
            lookup_hit  <= m_hit;
            lookup_way  <= {{(3-WAYW){1'b0}}, sel_way};
            lookup_line <= POOL_BASE_BLK[10:0] +
                           {{(11-SETIDX-WAYW){1'b0}}, rq_set, sel_way};
            // A hit is a use. A miss promotes at alloc_req instead, once the
            // line's contents actually exist.
            // a hit re-ranks the set; that write is issued below
          end
          state <= S_IDLE;
        end

        S_INV: begin
          // Two cycles per set: read, then clear the ways carrying inv_cli.
          if (!inv_rd) begin
            inv_rd <= 1'b1;
          end else begin
            inv_rd <= 1'b0;   // the clear of this set is written below
            if (inv_set == (SETS-1)) begin
              inval_done <= 1'b1;
              state      <= S_IDLE;
            end else begin
              inv_set <= inv_set + 1'b1;
            end
          end
        end

        default: state <= S_IDLE;
      endcase
    end
  end

  // ---- directory memory: ONE write port, ONE registered read, NO RESET ----
  // This process must stay free of any reset, asynchronous or synchronous.
  // The array was originally written inside the FSM's
  // "always @(posedge clk or negedge rst_n)" block, and that alone stopped
  // block-RAM inference dead: measured under yosys/synth_gowin at 512x4 the
  // array came out as 28672 flip-flops plus their multiplexers, 844694 AND
  // gates. The array contents do not need a reset - init_busy walks every
  // set and clears it before the FSM will answer a single lookup.
  wire [SETIDX-1:0] rd_set = (state == S_INV) ? inv_set : rq_set;

  // Write-back word for a lookup hit / an alloc / an invalidate sweep step.
  wire [WAYS*TAGW-1:0] tag_alloc =
      (tag_q & ~({{(WAYS*TAGW-TAGW){1'b0}}, {TAGW{1'b1}}} << (alloc_way_q*TAGW)))
      | ({{(WAYS*TAGW-TAGW){1'b0}}, rq_tag} << (alloc_way_q*TAGW));

  reg              dir_we;
  reg [SETIDX-1:0] dir_wa;
  reg [DIRW-1:0]   dir_wd;
  always @(*) begin
    dir_we = 1'b0;
    dir_wa = rq_set;
    dir_wd = {valid_q, rank_promoted, tag_q};
    if (init_busy) begin
      dir_we = 1'b1;
      dir_wa = init_ptr;
      dir_wd = {{WAYS{1'b0}}, rank_init, {(WAYS*TAGW){1'b0}}};
    end else if (state == S_CMP) begin
      if (rq_is_alloc) begin
        dir_we = 1'b1;
        dir_wd = {valid_q | ({{(WAYS-1){1'b0}}, 1'b1} << alloc_way_q),
                  rank_promoted, tag_alloc};
      end else if (m_hit) begin
        dir_we = 1'b1;   // a hit is a use: re-rank the set
      end
    end else if (state == S_INV && inv_rd) begin
      dir_we = 1'b1;
      dir_wa = inv_set;
      dir_wd = {valid_i & ~inv_mask, rank_q, tag_q};
    end
  end

  always @(posedge clk) begin
    if (dir_we) dir_ram[dir_wa] <= dir_wd;
    dir_q <= dir_ram[rd_set];
  end

endmodule
