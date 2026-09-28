`include "nd_storage_status.vh"
/**************************************************************************
** ND SMD DISC CONTROLLER, 15 MHz (ND632 / PCB 3043+3044), DMA           **
**                                                                       **
** Register core made 1:1 faithful to the AUTHORITATIVE C# oracle        **
**   RetroCore/Emulated.HW/ND/CPU/NDBUS/NDBusDiscControllerSMD.cs        **
** and its proven, host-gated C port                                     **
**   ND-BUS-DEVICES/portable/src/nd_smd.c  (nd_smd_*).                    **
** Where a behaviour is a documented DIVERGENCE in the C port, this RTL   **
** follows the same choice; those are marked "DIVERGENCE:" below.        **
**                                                                       **
** CONTROLLER TYPE is a strap (parameter HAS_WC_FLIPFLOP, DEFAULT 0):      **
**   0 = ECC / BIG-DISC card (DEFAULT): NO flip-flops - each of the Core   **
**       Address / Word Count registers loads its full value in ONE write  **
**       and reads back in one, and Core Address bits 16-17 come from       **
**       control-word bits 5-6. This is the type that BOOTS: the mass-      **
**       storage microcode writes the word counter ONCE (002000), which     **
**       loads 1024 only on a single-write card. A plain build boots.       **
**   1 = 15/10 MHz card (opt-in): it HAS the address/word-count FLIP-FLOPS, **
**       so the 24-bit Core Address and Word Count registers are each       **
**       loaded by TWO writes (HI 8 bits, then LO 16) and read back LO then **
**       HI; control-word bits 5-6 (address 16-17) are IGNORED (old 10MHz). **
**       Mirrors the C core nd_smd.has_flipflops exactly.                  **
**                                                                       **
** UNLIKE the floppy card there is NO command block in ND memory. The     **
** guest loads the transfer parameters into controller registers by IOX   **
** writes, then a GO (control word +5, bit 2 = active). ExecuteGO         **
** converts C/H/S -> LBA, bounds-checks the address, and moves the data.  **
**                                                                       **
** Register map (offset from base, ALL multiplexed by CWR = control       **
** word bit 15, mirrored in status bit 15):                              **
**   +0 R  Core Address (CWR=0) / Word Counter (CWR=1)  [LO then HI]      **
**   +1 W  Load Core Address (CWR=0, HI then LO) / count-mem (CWR=1)      **
**   +2 R  Seek Condition (CWR=0) / ECC Count (CWR=1)                     **
**   +3 W  Load Block Address I (CWR=0) / II (CWR=1)                      **
**   +4 R  Status (CWR=0, READING IT RESETS THE FLIP-FLOPS) / ECC Pattern **
**   +5 W  Load Control Word (GO / opcode)                               **
**   +6 R  Read Block Address I (CWR=0) / II (CWR=1)                      **
**   +7 W  Load Word Counter (CWR=0, HI then LO) / Load ECC Control (CWR=1)**
**                                                                       **
** Control word (+5): b0 int-enable (on NOT active), b1 error-int enable, **
**   b2 ACTIVE (GO), b3 test mode, b4 device clear, b5-6 addr16/17 (old   **
**   card, ignored), b7-9 unit select, b10 marginal recovery, b11-14      **
**   device operation (M0..M9), b15 register multiplex (CWR).            **
**                                                                       **
** Status (+4, CWR=0), oracle ReadStatusRegister():                      **
**   b0 int-enabled     b1 error-int-enabled   b2 active                 **
**   b3 ready-for-xfer  b4 inclusive-OR error  b5 illegal load           **
**   b6 timeout         b7 hardware error 2    b8 address mismatch        **
**   b10 comparer error b13 disk unit NOT ready (FORCED 1 when no unit    **
**   selected)          b14 on cylinder        b15 register multiplex.    **
**   Inclusive-OR (b4) = OR(illegal, timeout, hwErr2, addrMismatch,       **
**   comparerErr, seekErr) - the UNION taken by the C port so neither     **
**   reference's "error present" expectation is lost.                    **
**                                                                       **
** Seek condition (+2, CWR=0): b0-7 seek-complete (one per unit), b8-10   **
**   unit selected, b11 seek error (only M7 clears it), b12 = 1 (15 MHz   **
**   card id, SINTRAN uses it to tell the 15 MHz card from the NORD-10).  **
**                                                                       **
** Interrupt (level 11) is a LATCHED line driven at the oracle's exact    **
** SetInterruptBit() events: raised on completion iff int-enable is set   **
** (ReadEnd), raised on error iff error-int-enable is set (HandleError),  **
** re-evaluated on a non-GO control word, dropped when int-enable is      **
** cleared, and cleared on IDENT (which also clears int-enable).          **
**                                                                       **
** HARDWARE-CONSTRAINED DIVERGENCE (the only structural gap vs the        **
** oracle): the oracle's ExecuteGO pre-checks that the unit is ATTACHED   **
** and (for writes) not WRITE-PROTECTED using media metadata. This RTL    **
** controller has no such backend metadata port, so those two faults are  **
** surfaced the hardware way instead - the disk/DMA backend raises        **
** disk_err_in / dma_err during the transfer, which this core turns into  **
** the same HandleError (disk-unit-not-ready + error interrupt). The      **
** address-mismatch bound (b8) IS pre-checked, against the geometry given **
** by the GEO_* parameters (default = the 75 MB disk the C# oracle fixes  **
** every unit to). A backend that owns a different geometry should pass   **
** matching GEO_* parameters.                                            **
**                                                                       **
** BOOT MODE ('1540&', BPUN byte-server): the device-agnostic microcode    **
** loader (writes +3 bit 2, polls +2 ready, reads +0) is answered from    **
** reset until the FIRST Load Control Word - preserved BYTE-FOR-BYTE from **
** the silicon-validated implementation; it is not part of the oracle.    **
** A +1 or +7 write ALSO leaves boot mode: that loader never writes those **
** registers, but the MASS STORAGE LOAD microroutine ('21540&', CSA       **
** o2217) starts with two +1 writes and a +7 write, and boot mode used to **
** discard them - so the GO that followed ran with a zero word count and  **
** loaded nothing.                                                        **
**                                                                       **
** Thumbwheels (all level 11): tw0 01540/017, tw1 01550/020,             **
**   tw2 00540/023, tw3 00550/006 (octal). This instance = tw0 defaults.  **
**                                                                       **
** Last reviewed: 1-AUG-2026                                             **
** Ronny Hansen                                                          **
***************************************************************************/

module ND_SMD #(
    parameter [15:0] BASE_ADDR   = 16'o001540,
    parameter [15:0] IDENT_CODE  = 16'o000017,
    parameter [3:0]  INT_LEVEL   = 4'd11,
    // How long the controller stays ACTIVE after a GO before it reports
    // completion, in sysclk cycles. Do NOT set this by hand at an
    // instantiation: it is a TIME, so the board wrapper computes it from its
    // own clock frequency (see ND120_CORE.v, which turns a millisecond figure
    // into cycles). The module default stays small so the unit testbenches
    // run fast. 32 bits: 8 ms at 100 MHz is 800,000 cycles.
    parameter [31:0] DELAY_TICKS = 32'd10,
    // Geometry for the ExecuteGO address-mismatch bound. Default = the
    // 75 MB SMD disk (5 heads, 18 sectors/track, 823 cylinders), which is
    // the geometry the C# oracle fixes every unit to. 1024-byte sectors.
    parameter [15:0] GEO_HEADS   = 16'd5,
    parameter [15:0] GEO_SPT     = 16'd18,
    parameter [15:0] GEO_MAX_CYL = 16'd823,
    // Controller-type strap (docs/design/SMD-CONTROLLER-TYPE-SEAM.md).
    //   0 = ECC / BIG-DISC controller (THE DEFAULT): the Core Address and Word
    //       Counter registers have NO flip-flops - each loads its FULL value in
    //       a SINGLE write, the reads return the full value every time, and Core
    //       Address bits 16-17 come from control-word bits 5-6. This is the card
    //       that BOOTS: the mass-storage microcode (CSA o2217) writes the Word
    //       Counter ONCE with 002000, which loads 1024 on a single-write card.
    //   1 = 15/10 MHz SMD (ND632): the 24-bit Core Address and Word Counter
    //       registers load via a HI-then-LO TWO-write flip-flop, and the reads
    //       return LO then HI. Control-word bits 5-6 are ignored (old 10 MHz).
    // Mirrors the C core's nd_smd.has_flipflops EXACTLY (nd_smd_set_controller);
    // the equivalence gate drives both sides to the same value.
    //
    // DEFAULT IS 0 (no flip-flop) so a plain build BOOTS the SMD image with no
    // define. The 15 MHz two-write card is the opt-in: set HAS_WC_FLIPFLOP(1)
    // (the three flip-flop unit testbenches do exactly that, and ND120_CORE
    // exposes it via -DND120_SMD_15MHZ). A parameter, not an `input wire`,
    // because an unwired input floats to Z and would read as 0 anyway - the
    // parameter makes the choice explicit and constant-foldable.
    parameter HAS_WC_FLIPFLOP = 0,

    // WORD-COUNTER protocol, SEPARATE from the card-type strap above.
    // Defaults to the card type, but the ND-120 needs them to differ: the
    // mass-storage microroutine at CSA o2217 writes the MEMORY ADDRESS with two
    // +1 accesses (flip-flop protocol) and the WORD COUNT with ONE +7 write of
    // 002000, which only loads 1024 words if the word counter is single-access.
    // Ground truth: ND-BUS-DEVICES/SMD/sim/traces/mass-load-21540.trace.
    // Measured in nd100x 03-AUG-2026 (ND100X_SMD_TYPE=smd15 ND100X_SMD_WC_FF=0):
    // DISC-TEMA scores IDENTICALLY with the word counter single-access, so it
    // constrains only the memory address - the two requirements are compatible.
    // RetroCore models the same idea as four independent flip-flop flags.
    parameter HAS_WCNT_FLIPFLOP = HAS_WC_FLIPFLOP
) (
    input wire sysclk,
    input wire sys_rst_n,

    // Device bus (from ND_BUS_SLAVE) - IOX slave side
    input  wire [15:0] iox_addr,
    input  wire        iox_wr,
    input  wire [15:0] iox_wdata,
    input  wire        iox_rd,
    output reg  [15:0] iox_rdata,
    output wire        iox_sel,         // 1 = this core owns the captured IOX address
    output wire [3:0]  int_pending,
    input  wire        ident_strobe,
    input  wire [3:0]  ident_level,
    input  wire        ident_grant_in,
    output wire        ident_grant_out,
    output wire        ident_hit,
    output wire [15:0] ident_code,

    // DMA master client port (to ND_DMA_MASTER)
    output reg         dma_req,
    output reg         dma_wr,
    output reg  [23:0] dma_addr,
    output reg  [15:0] dma_wdata,
    input  wire [15:0] dma_rdata,
    input  wire        dma_ack,
    input  wire        dma_err,
    input  wire        dma_busy,

    // Disk backend: chunk transfers through the internal buffer.
    output reg         disk_start,
    output reg         disk_req,
    output reg         disk_wr,
    output wire [15:0] disk_blkaddr1,  // block address I (head/sector)
    output wire [15:0] disk_blkaddr2,  // block address II (cylinder)
    output wire [2:0]  disk_unit,
    output wire [10:0] disk_wordcount, // words in the current chunk
    input  wire        disk_done,
    input  wire        disk_err_in,
    // WHY the backend failed (nd_storage_status.vh), valid with disk_done
    // when disk_err_in. Mapped below onto status bits THIS card's manual
    // already defines - the code itself never reaches the guest.
    input  wire [3:0]  disk_err_code,
    input  wire [9:0]  dbuf_addr,
    input  wire [15:0] dbuf_wdata,
    input  wire        dbuf_we,
    output reg  [15:0] dbuf_rdata
);

  localparam [10:0] BUF_WORDS = 11'd1024;

  // ---- controller registers (oracle ControllerRegs) ----
  reg [15:0] s_core_addr;     // core address bits 0-15   (LO)
  reg [7:0]  s_core_addr_hi;  // core address bits 16-23  (HI)
  reg [15:0] s_word_cnt;      // word counter bits 0-15   (LO)
  reg [7:0]  s_word_cnt_hi;   // word counter bits 16-23  (HI)
  reg [15:0] s_blkaddr1;      // block address I  (head b8-15, sector b0-7)
  reg [15:0] s_blkaddr2;      // block address II (cylinder)
  reg [15:0] s_ecc_count;     // ECC count register (bit0 of ECC control resets it)

  // ---- unit selection + per-unit state ----
  reg [2:0]  s_sel_unit;      // raw unit from control word bits 7-9
  reg        s_disk_selected; // a unit 0..3 is selected
  reg [7:0]  s_on_cyl;        // per-unit on-cylinder     (status b14)
  reg [7:0]  s_not_ready;     // per-unit disk-not-ready  (status b13)
  reg [7:0]  s_seek_complete; // seek-condition b0-7 (one per unit)

  // ---- status flags ----
  reg        s_cwr;           // register multiplex bit (control b15)
  reg        s_int_en;        // control b0
  reg        s_errint_en;     // control b1
  reg        s_active;        // status b2
  reg        s_rft;           // status b3 - ready for transfer
  reg        s_test_mode;     // control b3
  reg        s_marginal;      // control b10
  reg        s_illegal;       // status b5
  reg        s_time_out;      // status b6 (never set in this port, kept for parity)
  reg        s_hw_err2;       // status b7
  reg        s_addr_mismatch; // status b8
  reg        s_comparer_err;  // status b10
  // status b11 = DMA CHANNEL ERROR (the oracle's SMDStatusRegister names bit 11
  // "DMA Channel error", reserved/never set there because its transfer is a
  // memcpy). The RTL has a real DMA master that CAN fault, and a bus/memory
  // fault used to be indistinguishable from a media fault (both ended in
  // err_active with only "disk unit not ready" showing). Setting b11 tells a
  // diagnostic which side failed. NOT part of the inclusive-OR (b4): the
  // oracle's hardwareError does not include bit 11.
  reg        s_dma_ch_err;    // status b11
  reg        s_seek_err;      // seek-condition b11

  // ---- flip-flops (15 MHz card: two-word HI/LO loads, cleared by a
  //      status read or a device clear) ----
  reg        s_maw_ff;        // core-address WRITE flip-flop
  reg        s_mar_ff;        // core-address READ  flip-flop
  reg        s_wcw_ff;        // word-counter WRITE flip-flop
  reg        s_wcr_ff;        // word-counter READ  flip-flop
  reg        s_wc_eccw_ff;    // ECC-control  WRITE flip-flop

  reg        s_irq;           // latched level-11 interrupt line

`ifdef ND120_SMD_TRACE
  reg [31:0] s_trace_cyc;     // sysclk counter for the simulation-only trace
`endif

  // ---- boot mode (not in the oracle; preserved verbatim) ----
  reg        s_boot_mode;
  reg        s_boot_fetch;
  reg        s_boot_loaded;
  reg [10:0] s_bootptr;

  assign disk_blkaddr1 = s_blkaddr1;
  assign disk_blkaddr2 = s_blkaddr2;
  assign disk_unit     = s_sel_unit;

  // ---- internal buffer ----
  // Async-read arrays do NOT map to Gowin BSRAM (they explode into ~16k FF +
  // LUT mux trees - measured 43k LUT4 standalone), so the buffer is a simple
  // dual-port RAM: one muxed write port, one registered read port whose
  // address follows the active consumer (see the RAM port block above the
  // main FSM). Same refactor as ND_FLOPPY_DMA's buffer. dbuf_rdata is driven
  // from the registered read there.
  reg [15:0] s_buffer[0:1023];

  // ---- decode ----
  wire s_addressed = (iox_addr[15:3] == BASE_ADDR[15:3]);
  assign iox_sel   = s_addressed;   // slave gates its BDRY response on this
  wire [2:0] s_reg = iox_addr[2:0];
  wire s_wr_here = iox_wr && s_addressed;
  wire s_rd_here = iox_rd && s_addressed;

  // ---- status / seek / ECC assembly (oracle ReadStatusRegister etc.) ----
  wire s_incl_or = s_illegal | s_time_out | s_hw_err2 |
                   s_addr_mismatch | s_comparer_err | s_seek_err;

  // disk-unit-not-ready is FORCED 1 when no unit is selected.
  wire s_oncyl_bit    = s_disk_selected ? s_on_cyl[s_sel_unit]    : 1'b0;
  wire s_notready_bit = s_disk_selected ? s_not_ready[s_sel_unit] : 1'b1;

  wire [15:0] s_status =
      { s_cwr,            // b15 register multiplex
        s_oncyl_bit,      // b14 on cylinder
        s_notready_bit,   // b13 disk unit not ready
        1'b0,             // b12
        s_dma_ch_err,     // b11 DMA channel error (bus/memory fault)
        s_comparer_err,   // b10 comparer error
        1'b0,             // b9
        s_addr_mismatch,  // b8  address mismatch
        s_hw_err2,        // b7  hardware error 2
        s_time_out,       // b6  timeout
        s_illegal,        // b5  illegal load
        s_incl_or,        // b4  inclusive-OR error
        s_rft,            // b3  ready for transfer
        s_active,         // b2  active
        s_errint_en,      // b1  error-interrupt enabled
        s_int_en };       // b0  interrupt enabled

  // b12 of the seek condition is the CONTROLLER-TYPE identity bit: 1 on the
  // SMD 10/15 MHz cards, 0 on the NORD-10-era BIG-DISC / ECC cards. It must
  // follow the HAS_WC_FLIPFLOP strap, because that bit is how software decides
  // which register protocol to use. Hard-coding it to 1 while strapped as the
  // single-access ECC card made the machine announce itself as a 15 MHz card:
  // TPE then drove the two-access HI/LO protocol and DISC-TEMA's Memory Address
  // Register test failed on every value (expected 00000000001b, found
  // 00000200001b = (N<<16)|N - the second read returning the low word again,
  // which is CORRECT behaviour for a single-access card). Measured on the Tang
  // 03-AUG-2026. Oracle: RetroCore NDBusDiscControllerSMD.cs gates this bit on
  // SMD_15MHZ_CONTR / SMD_10MHZ_CONTR only, and notes that SINTRAN M will not
  // read/write/boot DISC-75-1 when it is set.
  wire [15:0] s_seek_cond =
      { 3'b000,           // b15-13 address field / ECC parity / ECC correctable
        HAS_WC_FLIPFLOP ? 1'b1 : 1'b0,  // b12 SMD 10/15 MHz card id
        s_seek_err,       // b11    seek error
        s_sel_unit,       // b10-8  unit selected
        s_seek_complete };// b7-0   seek complete per unit

  // ECC pattern (read +4, CWR=1): bits 11-13 = 1, bit 15 = CWR read-back.
  // b14 is the second controller-type identity bit and is the INVERSE sense of
  // seek-condition b12: ND-11.020.01 sec 2.5 says "Bit 14: Always 0. To
  // distinguish from the old ND-100 SMD controller", so the 15 MHz card reads 0
  // and the older BIG-DISC / ECC cards read 1 (RetroCore sets it for
  // BIG_DISC_CONTR / ECC_DISC_CONTR). Follows the strap for the same reason as
  // b12 above.
  wire [15:0] s_ecc_pattern =
      { s_cwr, HAS_WC_FLIPFLOP ? 1'b0 : 1'b1, 3'b111, 11'd0 };

  // ---- interrupt / ident (latched line) ----
  assign int_pending = {(INT_LEVEL == 4'd13) && s_irq,
                        (INT_LEVEL == 4'd12) && s_irq,
                        (INT_LEVEL == 4'd11) && s_irq,
                        (INT_LEVEL == 4'd10) && s_irq};
  wire s_ident_answer = ident_strobe && ident_grant_in &&
                        (ident_level == INT_LEVEL) && s_irq;
  assign ident_hit       = s_ident_answer;
  assign ident_code      = s_ident_answer ? IDENT_CODE : 16'd0;
  assign ident_grant_out = ident_grant_in && !s_ident_answer;

  // ---- IOX read mux (CWR-multiplexed; boot mode overrides) ----
  always @(*) begin
    iox_rdata = 16'd0;
    if (s_rd_here) begin
      if (s_boot_mode) begin
        case (s_reg)
          // registered read: the port block's default read address IS the
          // boot pointer, so s_buf_dout tracks it (settles one sysclk after
          // each pointer step - far inside the IOX strobe spacing).
          3'd0: iox_rdata = s_buf_dout;
          3'd2: iox_rdata = {11'd0, s_incl_or, s_rft, 3'd0};
          default: iox_rdata = 16'd0;
        endcase
      end else begin
        // NOTE: reads are NOT gated on a selected unit. The status register,
        // ECC pattern, seek condition, core address and word counter are
        // CONTROLLER registers (cards 3043/3044) - they exist whether or not a
        // drive is selected, and only the drive-sourced bits depend on one
        // (s_oncyl_bit / s_notready_bit above already return 0 / 1 when
        // nothing is selected). The old "return 0 while no unit is selected"
        // gate was copied from the oracle, where it was a bug: it made the
        // status register unreadable exactly when a GO on a not-specified unit
        // had just raised hardware-error b7, so the error could never be seen.
        // DISC-TEMA reports that as "Read (from NOT specified unit), Status
        // Bit 7b is 0 !". Fixed in the oracle too.
        case (s_reg)
          // With flip-flops the read alternates LO then HI (the *_ff read
          // toggles below); a single-write card has no HI phase and returns the
          // full LO register every time.
          3'd0: iox_rdata = s_cwr
                          ? ((HAS_WCNT_FLIPFLOP && s_wcr_ff) ? {8'd0, s_word_cnt_hi}  : s_word_cnt)
                          : ((HAS_WC_FLIPFLOP && s_mar_ff) ? {8'd0, s_core_addr_hi} : s_core_addr);
          3'd2: iox_rdata = s_cwr ? s_ecc_count : s_seek_cond;
          3'd4: iox_rdata = s_cwr ? s_ecc_pattern : s_status;
          3'd6: iox_rdata = s_cwr ? s_blkaddr2 : s_blkaddr1;
          default: iox_rdata = 16'd0;
        endcase
      end
    end
  end

  // ---- transfer engine ----
  localparam E_IDLE    = 3'd0;
  localparam E_DISK_RD = 3'd1;  // backend: image chunk -> buffer
  localparam E_MEM_WR  = 3'd2;  // DMA: buffer -> ND memory
  localparam E_MEM_RD  = 3'd3;  // DMA: ND memory -> buffer
  localparam E_DISK_WR = 3'd4;  // backend: buffer -> image chunk
  localparam E_DELAY   = 3'd5;  // completion delay -> ReadEnd

  reg [2:0]  s_eng;
  reg [10:0] s_chunk_q;
  reg [10:0] s_sec_idx;
  reg [31:0] s_delay_cnt;
  reg        s_dma_wait;
  reg [23:0] s_mem_addr;      // running ND word address
  reg [23:0] s_words_left;    // words still to move
  reg [2:0]  s_unit;          // selected drive for this command

  assign disk_wordcount = s_chunk_q;

  // CHS -> LBA (oracle smd_chs_to_lba: uses S as-is; all-zero C/H/S -> 0).
  function [31:0] chs2lba;
    input [15:0] cyl;
    input [7:0]  head;
    input [7:0]  sector;
    begin
      if (cyl == 16'd0 && head == 8'd0 && sector == 8'd0)
        chs2lba = 32'd0;
      else
        chs2lba = (({16'd0, cyl} * {16'd0, GEO_HEADS}) + {24'd0, head})
                  * {16'd0, GEO_SPT} + {24'd0, sector};
    end
  endfunction

  // GO-time address decode (registers are stable outside a control write).
  wire [7:0]  w_head    = s_blkaddr1[15:8];
  wire [7:0]  w_sector  = s_blkaddr1[7:0];
  wire [15:0] w_cyl     = s_blkaddr2;
  wire [31:0] w_lba     = chs2lba(w_cyl, w_head, w_sector);
  wire [31:0] w_max_lba = chs2lba(GEO_MAX_CYL[15:0], GEO_HEADS[7:0], GEO_SPT[7:0]);
  wire [23:0] w_words   = {s_word_cnt_hi, s_word_cnt};

  task dma_issue(input wr, input [23:0] a, input [15:0] d);
    begin
      dma_req    <= 1'b1;
      dma_wr     <= wr;
      dma_addr   <= a;
      dma_wdata  <= d;
      s_dma_wait <= 1'b1;
    end
  endtask

  // ClearFlipFlops (oracle).
  task clr_ff;
    begin
      s_maw_ff     <= 1'b0;
      s_mar_ff     <= 1'b0;
      s_wcw_ff     <= 1'b0;
      s_wcr_ff     <= 1'b0;
      s_wc_eccw_ff <= 1'b0;
    end
  endtask

  // ==== BACKEND FAILURE -> STATUS BIT =====================================
  //
  // WHERE THESE BITS COME FROM: every bit set below is one the SMD DISC
  // CONTROLLER MANUAL ND-11.020.01, SECTION 2.5 (status register, read at
  // IOX +4 when the multiplex bit selects status) already defines for this
  // card. They are assembled into s_status above, each with its bit number
  // and manual name. NOTHING here is invented: this task chooses AMONG the
  // manual's bits, it never adds one and never puts the reason code itself
  // anywhere the guest can read it. That rule is stated in
  // Verilog/SD-FAT/circuit/nd_storage_status.vh: the SD-FAT stack is
  // clean-room and may carry a reason code, a reproduced ND card may not.
  //
  // WHERE THE REASON CODE COMES FROM: nd_storage_engine.v tags the failure
  // where it happens, and it travels engine -> nd_storage ->
  // nd_storage_disc_adapter -> disk_err_code here.
  //
  // FULL MAPPING - all nine codes of nd_storage_status.vh:
  //
  //   NDS_ERR_NOCARD    b7  hardware error 2. No SD card in the slot: the
  //                         drive electronics behind the interface cannot
  //                         serve at all, which is the general hardware
  //                         fault this bit reports.
  //   NDS_ERR_NOTOPEN   b7  same bit: SMD0.IMG is not on the card, or the
  //                         mount failed, so again there is no usable drive.
  //   NDS_ERR_RANGE     b8  address mismatch - the CHS position asked for
  //                         is past the end of the image, i.e. the address
  //                         was not found on the drive.
  //   NDS_ERR_TIMEOUT   b6  timeout. The engine watchdog fired: the backend
  //                         never answered - exactly the event b6 exists for.
  //   NDS_ERR_WRPROT    b5  illegal load. The controller was asked for a
  //   NDS_ERR_WRALIGN   b5  transfer it is not allowed to perform (write
  //                         path absent, or a partial/unaligned write that
  //                         would need a read-modify-write). The medium is
  //                         fine; the REQUEST was rejected - which is what
  //                         "illegal load" means on this card.
  //   NDS_ERR_CARDIO    b10 comparer error. The card answered but the data
  //   NDS_ERR_FATCHAIN  b10 cannot be trusted (CMD17/CMD24 failure, CRC,
  //                         card stopped mid-block, broken/circular FAT
  //                         chain). b10 is the bit this file already used
  //                         for a media write fault, so CARDIO keeps the
  //                         historical behaviour byte-for-byte.
  //   NDS_ERR_NONE          never reaches this task (no error, no call).
  //
  // b4 (inclusive OR of the error bits) follows automatically via
  // s_incl_or, and err_active additionally forces b13 disk-unit-not-ready
  // for the selected unit - both exactly as before this task existed.
  //
  // WHY THIS EXISTS: before it, every backend failure reached the guest as
  // the same anonymous "not ready" (plus, on writes only, a comparer
  // error). "No SD card", "SMD0.IMG absent", "block past the end of the
  // image", "broken FAT chain" and "the card stopped answering" were
  // indistinguishable from the guest, from DISC-TEMA and from a waveform.
  //
  // Call this BEFORE err_active (err_active clears the transfer state).
  // ========================================================================
  task set_backend_fault;
    input [3:0] code;
    begin
      case (code)
        // b7 hardware error 2 (ND-11.020.01 sec 2.5)
        `NDS_ERR_NOCARD,
        `NDS_ERR_NOTOPEN:  s_hw_err2       <= 1'b1;
        // b8 address mismatch (sec 2.5)
        `NDS_ERR_RANGE:    s_addr_mismatch <= 1'b1;
        // b6 timeout (sec 2.5)
        `NDS_ERR_TIMEOUT:  s_time_out      <= 1'b1;
        // b5 illegal load (sec 2.5)
        `NDS_ERR_WRPROT,
        `NDS_ERR_WRALIGN:  s_illegal       <= 1'b1;
        // b10 comparer error (sec 2.5) - CARDIO, FATCHAIN
        default:           s_comparer_err  <= 1'b1;
      endcase
    end
  endtask

  // HandleError for a fault raised DURING a transfer (s_unit / s_errint_en are
  // stable here). The specific error status bit is set by the caller first.
  task err_active;
    begin
      s_rft    <= 1'b0;
      s_active <= 1'b0;
      clr_ff;
      s_on_cyl[s_unit]    <= 1'b0;
      s_not_ready[s_unit] <= 1'b1;
      s_eng      <= E_IDLE;
      s_dma_wait <= 1'b0;
      if (s_errint_en) s_irq <= 1'b1;
    end
  endtask

  // ---- buffer RAM ports (BSRAM-mappable: sync write + sync read) ----------
  // One muxed WRITE port (backend fill via dbuf_we, or the DMA read-in
  // commit) and one registered READ port whose address follows the active
  // consumer: E_MEM_WR walks the sector for the DMA-out, E_DISK_WR serves
  // the backend readout (dbuf_addr), otherwise the boot-stream pointer.
  // s_buf_valid marks s_buf_dout as current for the address requested THIS
  // cycle (s_buf_dout holds s_buffer[s_buf_raddr_q]); consumers that need
  // the freshest word gate on it, adding the one cycle of read latency.
  // The write sites these ports replace lived inside the FSM below; the
  // E_MEM_RD commit condition is mirrored here exactly.
  wire        s_memrd_commit = (s_eng == E_MEM_RD) && s_dma_wait &&
                               dma_ack && !dma_err;
  wire        s_buf_we    = dbuf_we | s_memrd_commit;
  wire [ 9:0] s_buf_waddr = dbuf_we ? dbuf_addr : s_sec_idx[9:0];
  wire [15:0] s_buf_wdata = dbuf_we ? dbuf_wdata : dma_rdata;
  wire [ 9:0] s_buf_raddr = (s_eng == E_MEM_WR)  ? s_sec_idx[9:0] :
                            (s_eng == E_DISK_WR) ? dbuf_addr      :
                                                   s_bootptr[9:0];
  reg  [15:0] s_buf_dout;
  reg  [ 9:0] s_buf_raddr_q;
  wire        s_buf_valid = (s_buf_raddr_q == s_buf_raddr);

  always @(posedge sysclk) begin
    if (s_buf_we) s_buffer[s_buf_waddr] <= s_buf_wdata;
    s_buf_dout    <= s_buffer[s_buf_raddr];
    s_buf_raddr_q <= s_buf_raddr;
  end

  always @(*) dbuf_rdata = s_buf_dout;

  always @(posedge sysclk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
      s_core_addr    <= 16'd0;
      s_core_addr_hi <= 8'd0;
      s_word_cnt     <= 16'd0;
      s_word_cnt_hi  <= 8'd0;
      s_blkaddr1     <= 16'd0;
      s_blkaddr2     <= 16'd0;
      s_ecc_count    <= 16'd0;
      s_sel_unit     <= 3'd0;
      s_disk_selected<= 1'b0;
      s_on_cyl       <= 8'd0;
      s_not_ready    <= 8'd0;
      s_seek_complete<= 8'd0;
      s_cwr          <= 1'b0;
      s_int_en       <= 1'b0;
      s_errint_en    <= 1'b0;
      s_active       <= 1'b0;
      s_rft          <= 1'b1;   // reset value serves the boot handshake
      s_test_mode    <= 1'b0;
      s_marginal     <= 1'b0;
      s_illegal      <= 1'b0;
      s_time_out     <= 1'b0;
      s_hw_err2      <= 1'b0;
      s_addr_mismatch<= 1'b0;
      s_comparer_err <= 1'b0;
      s_dma_ch_err   <= 1'b0;
      s_seek_err     <= 1'b0;
      s_maw_ff       <= 1'b0;
      s_mar_ff       <= 1'b0;
      s_wcw_ff       <= 1'b0;
      s_wcr_ff       <= 1'b0;
      s_wc_eccw_ff   <= 1'b0;
      s_irq          <= 1'b0;
      s_boot_mode    <= 1'b1;
      s_boot_fetch   <= 1'b0;
      s_boot_loaded  <= 1'b0;
      s_bootptr      <= 11'd0;
      s_eng          <= E_IDLE;
      s_chunk_q      <= 11'd0;
      s_sec_idx      <= 11'd0;
      s_delay_cnt    <= 32'd0;
      s_dma_wait     <= 1'b0;
      s_mem_addr     <= 24'd0;
      s_words_left   <= 24'd0;
      s_unit         <= 3'd0;
      dma_req        <= 1'b0;
      dma_wr         <= 1'b0;
      dma_addr       <= 24'd0;
      dma_wdata      <= 16'd0;
      disk_start     <= 1'b0;
      disk_req       <= 1'b0;
      disk_wr        <= 1'b0;
    end else begin
      dma_req    <= 1'b0;
      disk_start <= 1'b0;
      disk_req   <= 1'b0;

      // (backend dbuf_we writes now land through the muxed RAM write port
      //  above - see the buffer RAM ports block)

      // ---- read-strobe side effects ----
      if (s_rd_here) begin
        if (s_boot_mode) begin
          // boot stream readout: +0 read consumes the word, clears ready
          if (s_reg == 3'd0) begin
            s_bootptr <= s_bootptr + 11'd1;
            s_rft     <= 1'b0;
          end
        end else if (s_disk_selected) begin
          case (s_reg)
            // Only the flip-flop card alternates LO/HI on successive +0 reads;
            // a single-write card has one 16-bit read, so leave the FFs alone.
            3'd0: if (s_cwr) begin
                    if (HAS_WCNT_FLIPFLOP) s_wcr_ff <= ~s_wcr_ff;  // WC: LO then HI
                  end else begin
                    if (HAS_WC_FLIPFLOP)   s_mar_ff <= ~s_mar_ff;  // CA: LO then HI
                  end
            3'd4: if (!s_cwr) clr_ff;                // status read resets FFs
            default: ;
          endcase
        end
      end

      // ---- IOX register writes ----
      if (s_wr_here) begin
        case (s_reg)
          // +1  Load Core Address (CWR=0) / count-mem (CWR=1, maint. only)
          // A +1 write ALSO leaves boot mode. The BPUN byte-server the boot
          // mode exists for never writes +1 or +7 (it writes +3 with bit 2,
          // polls +2, reads +0), while the microcode MASS STORAGE LOAD
          // routine at CSA o2217 (Code/Microcode/ND-120-DELILAH-L.LISTING.txt
          // line 5866, "MASS STORAGE LOAD, BECAUSE BIT 13 IS 1") starts with
          // TWO +1 writes (core address HI then LO) before +3 / +7 / +5.
          // Swallowing them left '21540&' loading a word count of zero, so
          // the GO completed instantly and transferred nothing.
          3'd1: begin
            s_boot_mode <= 1'b0;
            if (s_cwr) begin
              if (s_test_mode && s_marginal) begin
                s_core_addr <= s_core_addr + 16'd1;
                s_word_cnt  <= s_word_cnt  - 16'd1;
              end
            end else if (s_active) begin
              // Illegal load while active: raise b5 and IGNORE the write. It is
              // a status flag only (ND-11.020.01 sec 2.5 b5) - the running
              // operation continues and the drive does NOT go not-ready, so
              // err_active must not be called here. DISC-TEMA loads this
              // register during an active parity check and then expects to read
              // status with b5 AND b2 both set.
              s_illegal <= 1'b1;
            end else if (!HAS_WC_FLIPFLOP) begin
              // ECC / BIG-DISC: no flip-flop - one write loads the full 16 bits.
              // Bits 16-17 are NOT loaded here; they come from control-word
              // bits 5-6 at the next +5 write (mirrors the nd100x oracle).
              s_core_addr <= iox_wdata;
            end else if (s_maw_ff) begin
              s_core_addr <= iox_wdata;      // second write: LO 16
              s_maw_ff    <= 1'b0;
            end else begin
              s_core_addr_hi <= iox_wdata[7:0]; // first write: HI 8
              s_maw_ff       <= 1'b1;
            end
          end

          // +3  boot activate / Load Block Address I (CWR=0) / II (CWR=1)
          3'd3: begin
            if (s_boot_mode) begin
              // BOOT byte-server (preserved verbatim)
              if (iox_wdata[2] && s_eng == E_IDLE) begin
                if (!s_boot_loaded && !s_boot_fetch) begin
                  s_active     <= 1'b1;
                  // The FIRST fetch must drop ready-for-transfer exactly like
                  // the wrap-around fetch below does. Without this the loader
                  // polls +2, sees the RESET value of ready (1) while the
                  // block read is still in flight, and reads +0 before the
                  // buffer holds anything - so word 0 of the boot stream is
                  // garbage and every word after it is shifted by one.
                  // Measured with ND120_SMD_TRACE: "RD +0 -> 000062" arrived
                  // while active=1, before the first disk_done.
                  s_rft        <= 1'b0;
                  s_hw_err2    <= 1'b0;
                  s_illegal    <= 1'b0;
                  s_boot_fetch <= 1'b1;
                  s_blkaddr1   <= 16'd0;
                  s_blkaddr2   <= 16'd0;
                  s_chunk_q    <= BUF_WORDS;
                  disk_start   <= 1'b1;
                  disk_req     <= 1'b1;
                  disk_wr      <= 1'b0;
                  s_eng        <= E_DISK_RD;
                end else if (s_bootptr == 11'd1024) begin
                  s_bootptr    <= 11'd0;
                  s_active     <= 1'b1;
                  s_rft        <= 1'b0;
                  s_boot_fetch <= 1'b1;
                  s_chunk_q    <= BUF_WORDS;
                  disk_req     <= 1'b1;
                  disk_wr      <= 1'b0;
                  s_eng        <= E_DISK_RD;
                end else begin
                  s_rft <= 1'b1;  // next word already buffered
                end
              end
            end else if (s_active) begin
              // Illegal load while active - b5 only, operation continues.
              // See the +1 case above.
              s_illegal <= 1'b1;
            end else if (s_cwr) begin
              s_blkaddr2 <= iox_wdata;       // cylinder
            end else begin
              s_blkaddr1 <= iox_wdata;       // head b8-15, sector b0-7
            end
          end

          // +5  Load Control Word (GO / opcode). Leaves boot mode.
          // A control word loaded while the controller is active is an ILLEGAL
          // LOAD like any other register write - ND-11.020.01 sec 2.5 b5, "Load
          // of any register while status bit 2 is true". This used to be dropped
          // silently, and DISC-TEMA caught it: "Error after Illegal Load
          // (Control Word), Bit 5b was 0 !".
          //
          // Device clear (b4) is the one exception - it is the programmed master
          // clear (ND-11.013.01A: "Programmed master clear, i.e., control word
          // bit 4 (device clear)") and must always reach the controller, or an
          // active controller could never be recovered.
          3'd5: if (s_active && !iox_wdata[4]) begin
            s_illegal <= 1'b1;
          end else begin
            s_boot_mode <= 1'b0;
            s_int_en    <= iox_wdata[0];
            s_errint_en <= iox_wdata[1];
            s_test_mode <= iox_wdata[3];
            s_marginal  <= iox_wdata[10];
            s_sel_unit  <= iox_wdata[9:7];
            s_disk_selected <= ~iox_wdata[9];  // unit 0..3 -> selected
            s_cwr       <= iox_wdata[15];
            // ECC / BIG-DISC: control-word bits 5-6 ARE core-address bits 16-17
            // (the oracle's deviceSMD.c:465-468). On the flip-flop card these
            // bits are "old 10 MHz, ignored" and the HI byte comes from the
            // second +1 write instead. Only affects addresses above 64 K words.
            if (!HAS_WC_FLIPFLOP) s_core_addr_hi <= {6'd0, iox_wdata[6:5]};
            s_active    <= iox_wdata[2];        // oracle: active = bit 2 (clear/GO override below)
            s_rft       <= 1'b1;               // oracle: ready = true (top)
            if (!iox_wdata[0]) s_irq <= 1'b0;  // int-enable clear drops line

            // selecting a unit puts it on-cylinder
            if (~iox_wdata[9]) s_on_cyl[iox_wdata[9:7]] <= 1'b1;

            if (iox_wdata[4]) begin
              // ---- Device clear ----
              s_active <= 1'b0;
              if (~iox_wdata[9]) s_not_ready[iox_wdata[9:7]] <= 1'b0;
              s_seek_complete[iox_wdata[9:7]] <= 1'b1;
              s_core_addr    <= 16'd0;
              s_core_addr_hi <= 8'd0;
              s_blkaddr1     <= 16'd0;
              s_blkaddr2     <= 16'd0;
              s_word_cnt     <= 16'd0;
              s_word_cnt_hi  <= 8'd0;
              s_rft          <= 1'b0;
              clr_ff;
              s_illegal      <= 1'b0;
              s_time_out     <= 1'b0;
              s_hw_err2      <= 1'b0;
              s_addr_mismatch<= 1'b0;
              s_comparer_err <= 1'b0;
              s_dma_ch_err   <= 1'b0;
              s_seek_err     <= 1'b0;
              s_eng          <= E_IDLE;
              s_dma_wait     <= 1'b0;
              // else-branch interrupt eval with rft now false: ie && test
              s_irq          <= iox_wdata[0] && iox_wdata[3];
            end else if (iox_wdata[2]) begin
              // ---- GO ----
              if (iox_wdata[9]) begin
                // no unit selected -> DRIVE_NOT_SELECTED
                s_hw_err2 <= 1'b1;
                s_rft     <= 1'b0;
                s_active  <= 1'b0;
                clr_ff;
                s_eng      <= E_IDLE;
                s_dma_wait <= 1'b0;
                if (iox_wdata[1]) s_irq <= 1'b1;
              end else begin
                s_active            <= 1'b1;
                // Unlike the oracle, whose transfer executes instantly inside
                // the control-word write (so ready=true at top is already
                // final), the RTL engine takes real time: ready-for-transfer
                // must be LOW until completion (E_DELAY) raises it.
                s_rft               <= 1'b0;
                s_unit              <= iox_wdata[9:7];
                s_not_ready[iox_wdata[9:7]] <= 1'b0;
                s_seek_complete[iox_wdata[9:7]] <= 1'b0; // clear for the xfer
                // On the single-write card the HI bits arrive with THIS control
                // word (bits 5-6), so use them directly - the s_core_addr_hi
                // register write above is non-blocking and not visible yet.
                s_mem_addr   <= HAS_WC_FLIPFLOP ? {s_core_addr_hi, s_core_addr}
                                                : {6'd0, iox_wdata[6:5], s_core_addr};
                s_words_left <= w_words;

                if (!iox_wdata[3] &&
                    ((w_lba > w_max_lba) ||
                     (w_sector >= GEO_SPT[7:0]) ||
                     ({8'd0, w_head} >= GEO_MAX_CYL))) begin
                  // ---- address mismatch ----
                  s_addr_mismatch <= 1'b1;
                  s_rft    <= 1'b0;
                  s_active <= 1'b0;
                  clr_ff;
                  s_on_cyl[iox_wdata[9:7]]    <= 1'b0;
                  s_not_ready[iox_wdata[9:7]] <= 1'b1;
                  s_eng      <= E_IDLE;
                  s_dma_wait <= 1'b0;
                  if (iox_wdata[1]) s_irq <= 1'b1;
                end else begin
                  case (iox_wdata[14:11])
                    4'd0: begin  // M0 read transfer (disk -> memory)
                      if (w_words != 24'd0) begin
                        disk_start <= 1'b1;
                        disk_req   <= 1'b1;
                        disk_wr    <= 1'b0;
                        s_chunk_q  <= (w_words > {13'd0, BUF_WORDS}) ?
                                      BUF_WORDS : w_words[10:0];
                        s_sec_idx  <= 11'd0;
                        s_eng      <= E_DISK_RD;
                      end else begin
                        s_delay_cnt <= DELAY_TICKS;
                        s_eng       <= E_DELAY;
                      end
                    end
                    4'd1: begin  // M1 write transfer (memory -> disk)
                      if (w_words != 24'd0) begin
                        disk_start <= 1'b1;
                        s_chunk_q  <= (w_words > {13'd0, BUF_WORDS}) ?
                                      BUF_WORDS : w_words[10:0];
                        s_sec_idx  <= 11'd0;
                        s_eng      <= E_MEM_RD;
                      end else begin
                        s_delay_cnt <= DELAY_TICKS;
                        s_eng       <= E_DELAY;
                      end
                    end
                    4'd4: begin  // M4 initiate seek
                      s_seek_err  <= 1'b0;
                      s_delay_cnt <= DELAY_TICKS;
                      s_eng       <= E_DELAY;
                    end
                    4'd6: begin  // M6 seek-complete search
                      s_on_cyl[iox_wdata[9:7]] <= 1'b1;
                      s_seek_err  <= 1'b0;
                      s_seek_complete[iox_wdata[9:7]] <= 1'b1;
                      s_delay_cnt <= DELAY_TICKS;
                      s_eng       <= E_DELAY;
                    end
                    4'd7: begin  // M7 return to zero (only op that clears seekErr)
                      s_seek_err  <= 1'b0;
                      s_on_cyl[iox_wdata[9:7]] <= 1'b1;
                      s_seek_complete[iox_wdata[9:7]] <= 1'b1;
                      s_delay_cnt <= DELAY_TICKS;
                      s_eng       <= E_DELAY;
                    end
                    4'd9: begin  // M9 select release (DIVERGENCE: complete, no hang)
                      s_disk_selected <= 1'b0;
                      s_delay_cnt <= DELAY_TICKS;
                      s_eng       <= E_DELAY;
                    end
                    default: begin  // M2/M3/M5/M8 stub completion
                      s_delay_cnt <= DELAY_TICKS;
                      s_eng       <= E_DELAY;
                    end
                  endcase
                end
              end
            end else begin
              // ---- not a GO: re-evaluate the interrupt line ----
              // rft was just set true, so ie && (test?1:rft) == ie
              s_irq <= iox_wdata[0];
            end
          end

          // +7  Load Word Counter (CWR=0) / Load ECC Control (CWR=1)
          // Leaves boot mode for the same reason as +1 above (MASS writes the
          // word count 2000 octal = 1024 words here).
          3'd7: begin
            // Illegal load (status b5): "Load of any register while status bit
            // 2 is true" - ND-11.020.01 sec 2.5. The word counter is a register
            // like the others, and this check was missing entirely, so DISC-TEMA
            // reported "Error after Illegal Load (Word Count), Bit 5b was 0 !".
            // The load is ignored; the running operation is NOT disturbed.
            if (s_active) begin
              s_illegal <= 1'b1;
            end else begin
              s_boot_mode <= 1'b0;
              if (s_cwr) begin
                // Load ECC Control. Flip-flop card: HI write is a no-op, the LO
                // (second) write acts. Single-write card: the one write acts.
                if (!HAS_WC_FLIPFLOP || s_wc_eccw_ff) begin
                  if (iox_wdata[0]) s_ecc_count <= 16'd0; // bit0: reset ECC
                  if (iox_wdata[1]) s_hw_err2   <= 1'b1;  // bit1: force parity
                  s_wc_eccw_ff  <= 1'b0;
                end else begin
                  s_wc_eccw_ff  <= 1'b1;   // HI byte unused (as in the oracle)
                end
              end else if (!HAS_WCNT_FLIPFLOP) begin
                // Single-access word counter: one write loads the full 16 bits.
                // THE line that makes the mass-storage boot work - the microcode's
                // single +7 write of 002000 now lands as 1024 words, not 0.
                s_word_cnt    <= iox_wdata;
                s_word_cnt_hi <= 8'd0;
              end else if (s_wcw_ff) begin
                s_word_cnt <= iox_wdata;        // second write: LO 16
                s_wcw_ff   <= 1'b0;
              end else begin
                s_word_cnt_hi <= iox_wdata[7:0];// first write: HI 8
                s_wcw_ff      <= 1'b1;
              end
            end
          end

          default: ;
        endcase
      end

      // ---- transfer engine ----
      case (s_eng)
        E_IDLE: ;

        E_DISK_RD: begin
          if (disk_done) begin
            if (disk_err_in && s_boot_fetch) begin
              // boot fetch error (boot path, no unit semantics)
              s_hw_err2    <= 1'b1;
              s_boot_fetch <= 1'b0;
              s_active     <= 1'b0;
              s_rft        <= 1'b1;
              s_eng        <= E_IDLE;
            end else if (disk_err_in) begin
              // media read fault -> disk unit not ready (oracle READ_ERROR),
              // plus the bit that says which fault it actually was
              set_backend_fault(disk_err_code);
              err_active;
            end else if (s_boot_fetch) begin
              s_boot_fetch  <= 1'b0;
              s_boot_loaded <= 1'b1;
              s_active      <= 1'b0;
              s_rft         <= 1'b1;
              s_eng         <= E_IDLE;
            end else begin
              s_sec_idx <= 11'd0;
              s_eng     <= E_MEM_WR;
            end
          end
        end

        E_MEM_WR: begin
          // s_buf_valid: wait the one read-latency cycle after entering the
          // state / advancing s_sec_idx so s_buf_dout holds THIS word.
          if (!s_dma_wait && !dma_busy && s_buf_valid) begin
            dma_issue(1'b1, s_mem_addr, s_buf_dout);
          end else if (s_dma_wait && dma_ack) begin
            s_dma_wait <= 1'b0;
            if (dma_err) begin
              s_dma_ch_err <= 1'b1;    // b11: the fault came from the ND bus
              err_active;              // bus/memory fault -> not ready
            end else begin
              s_mem_addr   <= s_mem_addr   + 24'd1;
              s_words_left <= s_words_left - 24'd1;
              if (s_sec_idx + 11'd1 >= s_chunk_q || s_words_left == 24'd1) begin
                if (s_words_left == 24'd1) begin
                  s_delay_cnt <= DELAY_TICKS;
                  s_eng       <= E_DELAY;
                end else begin
                  s_chunk_q <= ((s_words_left - 24'd1) > {13'd0, BUF_WORDS}) ?
                               BUF_WORDS : (s_words_left[10:0] - 11'd1);
                  disk_req  <= 1'b1;
                  disk_wr   <= 1'b0;
                  s_eng     <= E_DISK_RD;
                end
              end else begin
                s_sec_idx <= s_sec_idx + 11'd1;
              end
            end
          end
        end

        E_MEM_RD: begin
          if (!s_dma_wait && !dma_busy) begin
            dma_issue(1'b0, s_mem_addr, 16'd0);
          end else if (s_dma_wait && dma_ack) begin
            s_dma_wait <= 1'b0;
            if (dma_err) begin
              s_dma_ch_err <= 1'b1;    // b11: the fault came from the ND bus
              err_active;              // bus/memory fault -> not ready
            end else begin
              // buffer write happens through the muxed RAM write port
              // (s_memrd_commit mirrors this exact condition)
              s_mem_addr   <= s_mem_addr   + 24'd1;
              s_words_left <= s_words_left - 24'd1;
              if (s_sec_idx + 11'd1 >= s_chunk_q || s_words_left == 24'd1) begin
                disk_req <= 1'b1;
                disk_wr  <= 1'b1;
                s_eng    <= E_DISK_WR;
              end else begin
                s_sec_idx <= s_sec_idx + 11'd1;
              end
            end
          end
        end

        E_DISK_WR: begin
          if (disk_done) begin
            if (disk_err_in) begin
              // media write fault (oracle WriteBlock false). The reason
              // picks the bit; NDS_ERR_CARDIO keeps the historical
              // comparer-error bit this branch always set.
              set_backend_fault(disk_err_code);
              err_active;
            end else if (s_words_left == 24'd0) begin
              s_delay_cnt <= DELAY_TICKS;
              s_eng       <= E_DELAY;
            end else begin
              s_chunk_q <= (s_words_left > {13'd0, BUF_WORDS}) ?
                           BUF_WORDS : s_words_left[10:0];
              s_sec_idx <= 11'd0;
              s_eng     <= E_MEM_RD;
            end
          end
        end

        // Completion delay, then ReadEnd (oracle SMDReadEnd). Boot completions
        // use the same delay slot but skip the register sync / interrupt.
        E_DELAY: begin
          if (s_delay_cnt != 32'd0) begin
            s_delay_cnt <= s_delay_cnt - 32'd1;
          end else if (s_boot_mode) begin
            s_active <= 1'b0;
            s_rft    <= 1'b1;
            s_eng    <= E_IDLE;
          end else begin
            s_active <= 1'b0;
            s_rft    <= 1'b1;
            clr_ff;
            s_core_addr    <= s_mem_addr[15:0];
            s_core_addr_hi <= s_mem_addr[23:16];
            s_word_cnt     <= 16'd0;
            s_word_cnt_hi  <= 8'd0;
            s_seek_complete<= (8'd1 << s_unit);
            s_eng          <= E_IDLE;
            s_irq          <= s_int_en;   // ReadEnd: interrupt iff int-enabled
          end
        end

        default: s_eng <= E_IDLE;
      endcase

`ifdef ND120_SMD_TRACE
      // Simulation-only IOX trace (define ND120_SMD_TRACE to enable). Prints
      // every register access with the controller state that decides what the
      // access MEANS, which is what settles questions like "does the mass
      // storage load microroutine write +7 once or twice".
      // s_trace_cyc counts sysclk edges: the difference between two lines is
      // the real cost of one loader step ($time is useless here - the sim
      // model has no timescale and prints 0).
      s_trace_cyc <= s_trace_cyc + 32'd1;
      if (s_wr_here)
        $display("[SMD] cyc=%0d WR +%0d val=%o boot=%b cwr=%b mawff=%b wcwff=%b",
                 s_trace_cyc, s_reg, iox_wdata, s_boot_mode, s_cwr, s_maw_ff, s_wcw_ff);
      if (s_rd_here)
        $display("[SMD] cyc=%0d RD +%0d -> %o boot=%b active=%b rft=%b",
                 s_trace_cyc, s_reg, iox_rdata, s_boot_mode, s_active, s_rft);
      // Every IOX the CPU issues to a DISC-range address that is NOT ours.
      // The controller sees the whole bus, so this answers "which device is
      // the test program actually driving" without touching the bus RTL.
      if ((iox_rd || iox_wr) && !s_addressed &&
          iox_addr >= 16'o000400 && iox_addr < 16'o002000)
        $display("[SMD-OTHER] cyc=%0d %s dev=%06o data=%06o",
                 s_trace_cyc, iox_wr ? "WR" : "RD", iox_addr, iox_wdata);
`endif

      // IDENT answered: clear interrupt-enable and drop the line (oracle IDENT).
      if (s_ident_answer) begin
        s_int_en <= 1'b0;
        s_irq    <= 1'b0;
      end
    end
  end

endmodule
