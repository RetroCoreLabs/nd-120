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
** THE REFERENCE IS NOW nd100x (src/devices/smd/device_smd.c). Where     **
** nd100x and the manual ND-11.020.01 disagree this card does what       **
** nd100x does, and the place says so, naming the nd100x function and   **
** its BUGS.md entry (S1-S11). The portable C twin NDDeviceCore nd_smd.c **
** follows the same rule.                                                **
**                                                                       **
** CONTROLLER TYPE is a strap (parameter HAS_WC_FLIPFLOP, DEFAULT 1):      **
**   0 = ECC / BIG-DISC card (opt-in): NO flip-flops - each of the Core  **
**       Address / Word Count registers loads its full value in ONE write  **
**       and reads back in one, and Core Address bits 16-17 come from       **
**       control-word bits 5-6.                                          **
**       ADDRESS LIMIT (matches the card's manual, so not modelled short):  **
**       the ECC card has an 18-bit core address. ND-11.013.01 Appendix N, **
**       N.3.1 Control Word Content: "5 Address bit 16", "6 Address bit    **
**       17"; section 9.10 (1155 - Bus Control) lists "Bit 16 and 17 of    **
**       the core address register (17B)" and no higher bits. SINTRAN L on  **
**       the BIGDISK image loads segments at 05 xxxxxx and 037 xxxxxx, so   **
**       on this card bits 18-23 are lost (05 lands at 01), it overwrites  **
**       what it loaded before and halts in ERRFATAL. The ECC setting       **
**       cannot run that system; the 15 MHz card can.                     **
**   1 = 15/10 MHz card (DEFAULT): ONE flip-flop (4E on card 3044) serves **
**       the 24-bit Core Address AND the Word Count, writes and reads      **
**       alike. The FIRST access of a pair loads all 24 bits (bits 16-23   **
**       from A bits 0-7, bits 0-15 from A); the SECOND loads bits 0-15     **
**       only. Reads give bits 0-15 first, then bits 16-23. Control-word    **
**       bits 5-6 (address 16-17) are IGNORED (old 10 MHz). See s_ma_wc_ff. **
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
**   b9 data error      b10 comparer error     b11 always 0 (nd100x       **
**   never sets it, BUGS.md S8)                                           **
**   b12 abnormal completion (any error end, cleared                      **
**   at the next GO; sec 3.7.2)                                           **
**   b13 disk unit NOT ready (FORCED 1 when no unit                       **
**   selected)          b14 on cylinder        b15 register multiplex.    **
**   Inclusive-OR (b4) = OR(illegal, timeout, hwErr2, addrMismatch,       **
**   dataErr, comparerErr, seekErr) - the UNION taken by the C port so    **
**   neither reference's "error present" expectation is lost; nd100x     **
**   smd_read has the same set.                                          **
**                                                                       **
** Seek condition (+2, CWR=0): b0-7 seek-complete (one per unit), b8-10   **
**   unit selected, b11 seek error (only M7 clears it), b12 = 1 (15 MHz   **
**   card id, SINTRAN uses it to tell the 15 MHz card from the NORD-10).  **
**                                                                       **
** Interrupt (level 11) is a LATCHED line driven at nd100x's events:      **
** raised at the end of every operation, error ends included, iff         **
** int-enable (control bit 0) is set (smd_read_end, finish_operation,     **
** smd_timeout_end); control bit 1, error-int-enable, is latched and read **
** back in status b1 but raises nothing, as in nd100x (BUGS.md S6; the    **
** manual's Fig. 14 has it raise the line on an error). Re-evaluated on a **
** non-GO control word, dropped when int-enable is cleared, and cleared   **
** on IDENT (which also clears int-enable).                               **
**                                                                       **
** DRIVES: each unit 0-3 has its own arm (s_arm). M4 and M7 end the      **
** controller's operation at once; the drive then drops on-cylinder,     **
** moves its heads in its own time and raises on-cylinder (and, for M4,  **
** its seek-complete bit) when they arrive (g_unit below). A transfer    **
** moves the arm to its cylinder as part of its own time. FAST = 1 gives **
** every drive movement the flat DELAY_TICKS; FAST = 0 times it with     **
** nd100x's SMD seek curve and the disc's rotation (DRIVE TIMING below). **
**                                                                       **
** HARDWARE-CONSTRAINED DIVERGENCE (the only structural gap vs the        **
** oracle): the oracle's ExecuteGO pre-checks that the unit is ATTACHED   **
** and (for writes) not WRITE-PROTECTED using media metadata. This RTL    **
** controller has no such backend metadata port, so those two faults are  **
** surfaced the hardware way instead - the disk backend raises            **
** disk_err_in during the transfer, which this core turns into a          **
** disk-unit-not-ready error end (see err_active). The                    **
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
    // Drive timing, the same scheme as ND_WINCHESTER.v. FAST = 1 (the
    // default): a transfer or a format ends DELAY_TICKS after its data has
    // moved, and a drive's seek (M4, M7) takes DELAY_TICKS. FAST = 0: they
    // take as long as the drive does - nd100x's SMD seek curve and the disc's
    // rotation, in sysclk cycles worked out from CLK_HZ (see "DRIVE TIMING"
    // below). CLK_HZ is the frequency of sysclk; the board wrapper passes its
    // own, like DELAY_TICKS. CLK_HZ also sets the controller's 500 ms search
    // timeout (M6), in both modes.
    parameter integer CLK_HZ     = 100_000_000,
    parameter [0:0]  FAST        = 1'b1,
    // Geometry for the ExecuteGO address-mismatch bound. Default = the
    // 75 MB SMD disk (5 heads, 18 sectors/track, 823 cylinders), which is
    // the geometry the C# oracle fixes every unit to. 1024-byte sectors.
    parameter [15:0] GEO_HEADS   = 16'd5,
    parameter [15:0] GEO_SPT     = 16'd18,
    parameter [15:0] GEO_MAX_CYL = 16'd823,
    // Controller-type strap (docs/design/SMD-CONTROLLER-TYPE-SEAM.md).
    //   0 = ECC / BIG-DISC controller (opt-in): the Core Address and Word
    //       Counter registers have NO flip-flops - each loads its FULL value in
    //       a SINGLE write, the reads return the full value every time, and Core
    //       Address bits 16-17 come from control-word bits 5-6.
    //   1 = 15/10 MHz SMD (ND632, cards 3043/3044, THE DEFAULT): the 24-bit Core Address
    //       and Word Counter share ONE flip-flop (s_ma_wc_ff). The first access
    //       of a pair loads all 24 bits, the second bits 0-15 only; reads
    //       return bits 0-15 first, then bits 16-23. Control-word bits 5-6 are
    //       ignored (old 10 MHz). The single +7 write of 002000 that the
    //       mass-storage microcode makes therefore loads 1024 words on this
    //       card too.
    //
    // DEFAULT IS 1, the 15 MHz card: it is the type that boots SINTRAN L from
    // the BIGDISK image in Verilator (the ECC setting stops in ERRFATAL, see
    // the address-bit note in the header). The ECC card is the opt-in: set
    // HAS_WC_FLIPFLOP(0) (nd_smd_ecc_tb.v does, and ND120_CORE exposes it via
    // -DND120_SMD_ECC_CARD). A parameter, not an `input wire`, because an
    // unwired input floats to Z - the parameter makes the choice explicit and
    // constant-foldable.
    parameter HAS_WC_FLIPFLOP = 1
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

  /*---------------------------------------------
  *  DRIVE TIMING (used when FAST = 0)
  *--------------------------------------------*/
  // nd100x device_smd.c "THE DRIVE'S TIMING", in sysclk cycles instead of
  // instruction ticks, built the same way as ND_WINCHESTER.v. The figures are
  // the CDC SMD family's (DISC-75MB is a CDC 9762), from the CDC 976x brochure
  // nd100x cites: 3600 r/min, accessing time one track 6 ms, average 30 ms,
  // full stroke 55 ms.
  //
  // NOT in the brochure, and so an assumption (nd100x's, smd_seek_ticks): the
  // shape of the seek curve between those three points. Two straight lines
  // through (1 cylinder, 6 ms), (one third of the stroke, 30 ms) and (full
  // stroke, 55 ms). A seek to the cylinder the arm is on takes no time.
  //
  // One revolution is CLK_HZ / 60 cycles, rounded down to a whole number of
  // sector times so every sector starts on a whole cycle; nd100x rounds the
  // revolution to 16.7 ms instead. T_MIN, 20 us, is the floor nd100x gives
  // every operation with IODELAY_HDD_SMD (10 instruction ticks, 19 us).
  //
  // T_TIMEOUT is the controller's own search window, 500 ms (nd100x
  // SMD_TIMEOUT_TICKS: "the real card gives up after 500 ms"). It belongs to
  // the controller, not to the drive, so FAST does not change it.
  localparam [31:0] CLK32       = CLK_HZ;
  localparam [31:0] SPT32       = {16'd0, GEO_SPT};
  localparam [31:0] T_MS        = CLK32 / 32'd1000;
  localparam [31:0] T_SEEK_ONE  = 32'd6  * T_MS;
  localparam [31:0] T_SEEK_AVG  = 32'd30 * T_MS;
  localparam [31:0] T_SEEK_FULL = 32'd55 * T_MS;
  localparam [31:0] T_SECTOR    = (CLK32 / 32'd60) / SPT32;
  localparam [31:0] T_REV       = T_SECTOR * SPT32;
  localparam [31:0] T_MIN       = (CLK32 / 32'd50_000) != 32'd0 ? (CLK32 / 32'd50_000) : 32'd1;
  localparam [31:0] T_TIMEOUT   = CLK32 / 32'd2;
  // The seek curve, charged one cylinder per clock exactly as ND_WINCHESTER.v
  // does it (see seek_inc): a seek of d cylinders totals nd100x's
  // smd_seek_ticks, 6 ms + (d-1) * (30-6) ms / (third-1) up to the knee,
  // 30 ms + (d-third) * (55-30) ms / (full-third) past it, each rounded down
  // once. CYL_FULL is the full stroke in cylinders, CYL_THIRD the knee.
  localparam [31:0] CYL_FULL    = {16'd0, GEO_MAX_CYL} - 32'd1;
  localparam [31:0] CYL_THIRD   = CYL_FULL / 32'd3;
  // A drive too small for a curve (nd100x: full < 3 or third < 2) takes the
  // track-to-track time for every seek.
  localparam        SEEK_FLAT   = (CYL_FULL < 32'd3) || (CYL_THIRD < 32'd2);
  localparam [31:0] S1_B        = SEEK_FLAT ? 32'd1 : (CYL_THIRD - 32'd1);
  localparam [31:0] S1_Q        = (T_SEEK_AVG - T_SEEK_ONE) / S1_B;
  localparam [31:0] S1_R        = (T_SEEK_AVG - T_SEEK_ONE) % S1_B;
  localparam [31:0] S2_B        = SEEK_FLAT ? 32'd1 : (CYL_FULL - CYL_THIRD);
  localparam [31:0] S2_Q        = (T_SEEK_FULL - T_SEEK_AVG) / S2_B;
  localparam [31:0] S2_R        = (T_SEEK_FULL - T_SEEK_AVG) % S2_B;

  // What a completion waits for after the data has moved: the flat delay
  // when FAST, otherwise nothing more than the drive time left (s_drv_left).
  localparam [31:0] END_DELAY   = FAST ? DELAY_TICKS : 32'd0;

  // One cylinder's worth of a seek being charged: the cycles cylinder `k`
  // (2, 3, ...) adds, and the running remainder after it. Returns
  // {remainder, cycles}. Same arithmetic as ND_WINCHESTER.v seek_charge:
  // the segment's quotient, plus one when the remainder carried past the
  // segment's divisor. seek_step does one step given the segment (seg1 = up
  // to the knee) and the remainder with this cylinder's share added.
  function [63:0] seek_step;
    input        seg1;
    input [31:0] sum;
    seek_step = (sum >= (seg1 ? S1_B : S2_B))
              ? {sum - (seg1 ? S1_B : S2_B), (seg1 ? S1_Q : S2_Q) + 32'd1}
              : {sum, (seg1 ? S1_Q : S2_Q)};
  endfunction
  function [63:0] seek_inc;
    input [15:0] k;
    input [31:0] acc;
    seek_inc = seek_step(({16'd0, k} <= CYL_THIRD),
                         acc + (({16'd0, k} <= CYL_THIRD) ? S1_R : S2_R));
  endfunction

  // The distance a seek charges along the curve: at most the full stroke,
  // and 1 (the track-to-track time only) on a drive too small for a curve.
  function [15:0] seek_span;
    input [15:0] cyls;
    begin
      seek_span = SEEK_FLAT ? 16'd1 :
                  (({16'd0, cyls} > CYL_FULL) ? CYL_FULL[15:0] : cyls);
    end
  endfunction

  // The disc turns all the time: r_rot is where it is, 0 .. T_REV-1, and
  // sector s starts under the head when r_rot = s * T_SECTOR. One phase for
  // all units, as in nd100x (the instruction counter); real spindles are not
  // locked together, an assumption that only shifts each wait. It starts at 0
  // on the card reset, which a real spindle does not do; only the phase is
  // affected.
  reg [31:0] r_rot;
  always @(posedge sysclk or negedge sys_rst_n) begin
    if (!sys_rst_n)                    r_rot <= 32'd0;
    else if (r_rot >= T_REV - 1)       r_rot <= 32'd0;
    else                               r_rot <= r_rot + 32'd1;
  end

  // Cycles from now until sector `sec` is under the head (nd100x
  // smd_rotation_wait), and the floor of T_MIN. rot_wait takes the disc's
  // position as an argument, not from r_rot directly: a continuous assignment
  // that calls it is re-evaluated only when its arguments change, so reading
  // r_rot inside left the wires below stuck at their first value in
  // simulation (measured with nd_smd_timing_tb.v).
  function [31:0] sec_start(input [7:0] sec);
    sec_start = ({24'd0, sec} % SPT32) * T_SECTOR;
  endfunction
  function [31:0] rot_wait(input [31:0] start, input [31:0] rot);
    rot_wait = (start >= rot) ? (start - rot) : (start + T_REV - rot);
  endfunction
  function [31:0] at_least_min(input [31:0] t);
    at_least_min = (t < T_MIN) ? T_MIN : t;
  endfunction

  /*---------------------------------------------
  *  WRITE FORMAT (M5) WORD COUNT
  *--------------------------------------------*/
  // M5's word count is two address-field words per sector, a whole number of
  // tracks: nd100x execute_go, DEVICE_OP_WRITE_FORMAT, ends the operation
  // with a timeout when it is zero or not a multiple of FMT_D = 2 * sectors
  // per track. The quotient (the number of tracks) and the remainder are taken
  // by multiplying with the reciprocal, so no divider is built:
  //   q = floor(wc * FMT_M / 2^(24 + FMT_L)),  FMT_M = ceil(2^(24 + FMT_L) / FMT_D),
  //   FMT_L = ceil(log2(FMT_D)).
  // Exact for every 24-bit wc: FMT_M * FMT_D = 2^(24+FMT_L) + e with 0 <= e <
  // FMT_D, so wc * FMT_M / 2^(24+FMT_L) = wc / FMT_D + wc * e / (FMT_D *
  // 2^(24+FMT_L)), and the added part is below wc / 2^(24+FMT_L) < 2^-FMT_L
  // <= 1 / FMT_D, too little to carry the fraction of wc / FMT_D (at most
  // (FMT_D - 1) / FMT_D) past the next whole number.
  localparam [63:0]  FMT_D = 64'd2 * {48'd0, GEO_SPT};
  localparam integer FMT_L = $clog2(FMT_D);
  localparam [63:0]  FMT_M = ((64'd1 << (24 + FMT_L)) + FMT_D - 64'd1) / FMT_D;
  localparam [23:0]  FMT_D24 = FMT_D[23:0];
  // nd100x reads the fields only when a track has at most
  // SMD_MAX_SECTORS_PER_TRACK (64) sectors, its table's width.
  localparam         FMT_FETCH = (GEO_SPT <= 16'd64);

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
  // Units with a seek given (M4 or M7) that no transfer has consumed yet
  // (nd100x seekIssuedMask). A Seek Complete Search (M6) waits for one of
  // THESE units to show its seek-complete bit; with none it can only time out.
  // A transfer on a unit clears its bit, a device clear clears them all.
  reg [3:0]  s_seek_issued;
  // The cylinder each unit's arm is over, or moving to (nd100x armCylinder).
  // Every drive powers up with its heads on cylinder 0. Only the drive timing
  // reads it.
  reg [15:0] s_arm [0:3];

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
  // status b9 = DATA ERROR (ND-11.020.01 sec 2.5, nd100x crcError). Set where
  // nd100x sets it: at the end of a test-mode read (M0) or compare (M3), whose
  // pattern generator carries no valid check word (sec 4.4: a test-mode read
  // reads status 041030). Long mode, the other place nd100x sets it, is not
  // modelled here (Verilog/TODO.md). Cleared by a device clear only, as in
  // nd100x (clear_errors); a GO leaves it.
  reg        s_crc_err;       // status b9
  reg        s_comparer_err;  // status b10
  // status b11 is "FIFO over/underrun or ND-100 Bus error" (sec 2.5). nd100x
  // never sets it (BUGS.md S1, S8): a failed memory write in M0 is ignored, a
  // failed read ends M1 with abnormal completion only, ends M3 as a compare
  // error, and is taken as a zero field word in M5. This card does the same,
  // so b11 reads 0. (It used to be set on every DMA fault here, which nd100x
  // does not do.)
  // status b12 = ABNORMAL COMPLETION. ND-11.020.01 sec 3.7.2 lists the five
  // conditions that set it: loss of ready (SB13), address mismatch (SB8),
  // fault line / ECC parity / missing clocks (SB7), illegal load while the
  // controller is busy (SB5), and timeout (SB6). It was hard-wired to 0 here.
  // Set where those conditions are raised, cleared at the next GO and by a
  // device clear. NOT part of the inclusive-OR (b4): it is the consequence of
  // the other error bits, not a cause.
  reg        s_abnormal;      // status b12
  reg        s_seek_err;      // seek-condition b11

  // ---- flip-flops (15 MHz card only, HAS_WC_FLIPFLOP = 1) ----
  //
  // s_ma_wc_ff: the memory address / word count flip-flop. From the 15 MHz
  // card's logic diagram, card 3044 sheet 3, block "MEMORY ADDRESS & WORD
  // COUNT" (ND-11.020.01, scan page 118), simulated gate by gate in
  // Logisim/ND-BUS-DEVICES/SMD-3044 (readme.md there):
  //  - ONE flip-flop (4E) serves the memory address (+1 write, +0 read with
  //    CWR=0) AND the word count (+7 write with CWR=0, +0 read with CWR=1),
  //    writes and reads alike. It toggles at the end of each of those four
  //    accesses. It does NOT toggle on the control word (+5), the block
  //    address (+3) or the ECC control register (+7 with CWR=1, a different
  //    decoder).
  //  - 0 = the next access is the FIRST of a pair. The first write loads all
  //    24 bits: bits 16-23 get A bits 0-7 (through the 11B byte swapper) and
  //    bits 0-15 get A. The second write loads bits 0-15 only. So one write
  //    of V leaves (V & 0377) in bits 16-23 and V in bits 0-15.
  //  - The first read gives bits 0-15, the second bits 16-23 on A bits 0-7.
  //  - Reset to 0 by device clear, a status read (+4 with CWR=0) and the end
  //    of a transfer (clr_ff).
  // The ECC control register has NO flip-flop: one write loads it (sec 2.8
  // gives the two-access rule for the word count only), as nd100x does it
  // ("Load ECC Control: ONE write loads the whole register"). It used to take
  // two writes here (a flip-flop of its own), so a single write did nothing;
  // nd100x's comment says a single write is all DISC-TEMA and SINTRAN make.
  reg        s_ma_wc_ff;      // memory address / word count flip-flop (4E)

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
                   s_addr_mismatch | s_crc_err | s_comparer_err | s_seek_err;

  // Is loading a data register (memory address +1, block address +3, word
  // counter or ECC control +7) an illegal load right now? nd100x
  // load_is_illegal, two conditions: the controller is ACTIVE (ND-11.020.01
  // sec 2.5 b5, "Load of any register while status bit 2 is true"), or the
  // selected unit is NOT ON CYLINDER (the DISC-TEMA manual ND-830005.3, status
  // table, b5: "load while the unit is NOT ON CYLINDER"; nd100x takes the two
  // as one rule). nd100x asks the latter only for a unit with a pack mounted;
  // this card has no attach information (see the header), so every selected
  // unit 0-3 counts as mounted. The control word is gated by ACTIVE only (the
  // +5 case below): it must be loadable off cylinder, or the seeks that move
  // the heads could never be given.
  wire w_load_illegal = s_active || (s_disk_selected && !s_on_cyl[s_sel_unit]);

  // disk-unit-not-ready is FORCED 1 when no unit is selected.
  wire s_oncyl_bit    = s_disk_selected ? s_on_cyl[s_sel_unit]    : 1'b0;
  wire s_notready_bit = s_disk_selected ? s_not_ready[s_sel_unit] : 1'b1;

  wire [15:0] s_status =
      { s_cwr,            // b15 register multiplex
        s_oncyl_bit,      // b14 on cylinder
        s_notready_bit,   // b13 disk unit not ready
        s_abnormal,       // b12 abnormal completion
        1'b0,             // b11 FIFO over/underrun / bus error: never set (nd100x, BUGS.md S1, S8)
        s_comparer_err,   // b10 comparer error
        s_crc_err,        // b9  data error
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
          // With the flip-flop the read alternates bits 0-15 then bits 16-23
          // (s_ma_wc_ff, toggled below); a single-write card has no HI phase
          // and returns the full LO register every time.
          3'd0: iox_rdata = s_cwr
                          ? ((HAS_WC_FLIPFLOP && s_ma_wc_ff) ? {8'd0, s_word_cnt_hi}  : s_word_cnt)
                          : ((HAS_WC_FLIPFLOP && s_ma_wc_ff) ? {8'd0, s_core_addr_hi} : s_core_addr);
          3'd2: iox_rdata = s_cwr ? s_ecc_count : s_seek_cond;
          3'd4: iox_rdata = s_cwr ? s_ecc_pattern : s_status;
          3'd6: iox_rdata = s_cwr ? s_blkaddr2 : s_blkaddr1;
          default: iox_rdata = 16'd0;
        endcase
      end
    end
  end

  // ---- transfer engine ----
  // Four bits: the eight three-bit codes were all in use, and M5, M6 and the
  // two test-mode transfers each need a state of their own.
  localparam [3:0] E_IDLE     = 4'd0;
  localparam [3:0] E_DISK_RD  = 4'd1;  // backend: image chunk -> buffer
  localparam [3:0] E_MEM_WR   = 4'd2;  // DMA: buffer -> ND memory
  localparam [3:0] E_MEM_RD   = 4'd3;  // DMA: ND memory -> buffer
  localparam [3:0] E_DISK_WR  = 4'd4;  // backend: buffer -> image chunk
  localparam [3:0] E_DELAY    = 4'd5;  // completion delay -> ReadEnd
  localparam [3:0] E_PARITY   = 4'd6;  // M2: the chunk's words pass, NO memory cycle
  localparam [3:0] E_COMPARE  = 4'd7;  // M3: memory word read and compared with the disk word
  localparam [3:0] E_SEARCH   = 4'd8;  // M6: wait for a seek-complete bit, or the timeout
  localparam [3:0] E_FMT      = 4'd9;  // M5: DMA-read the address fields from memory
  localparam [3:0] E_TEST_WR  = 4'd10; // test-mode M0: pattern generator -> ND memory
  localparam [3:0] E_TEST_CMP = 4'd11; // test-mode M3: ND memory compared with the pattern

  reg [3:0]  s_eng;
  reg [10:0] s_chunk_q;
  reg [10:0] s_sec_idx;
  reg [31:0] s_delay_cnt;
  reg        s_dma_wait;
  reg [23:0] s_mem_addr;      // running ND word address
  reg [23:0] s_words_left;    // words still to move
  reg [2:0]  s_unit;          // selected drive for this command
  reg [3:0]  s_op;            // device operation code (M0-M9) of this command

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
      s_ma_wc_ff   <= 1'b0;
    end
  endtask

  // ---- the controller's drive time (FAST = 0) ----
  // How long the operation in progress keeps the controller ACTIVE besides
  // moving its data, run in stages: the implied seek (charged along the curve
  // one cylinder per clock, as ND_WINCHESTER.v does it), then the wait for the
  // first sector to come round, then s_rot_n units of one sector time (a
  // transfer) or one revolution (Write Format). nd100x smd_transfer_ticks and
  // the DEVICE_OP_WRITE_FORMAT timing in execute_go.
  reg [31:0] s_drv_left;   // cycles left in the current stage
  reg [15:0] s_seek_k;     // next cylinder of the seek to charge (2 ..)
  reg [15:0] s_seek_d;     // the seek's distance in cylinders
  reg [31:0] s_seek_acc;   // the running remainder of the curve
  reg        s_rot_pend;   // the rotation wait is still to be loaded
  reg [7:0]  s_rot_sec;    // the sector the rotation wait is for
  reg [23:0] s_rot_n;      // sector times / revolutions after the wait
  reg        s_rot_rev;    // the unit is a revolution (M5), not a sector
  wire       w_seek_charging = (s_seek_k <= s_seek_d);
  wire       w_drv_busy = (s_drv_left != 32'd0) || w_seek_charging ||
                          s_rot_pend || (s_rot_n != 24'd0);
  wire [31:0] w_rot_unit = s_rot_rev ? T_REV : T_SECTOR;

  // No drive time (an operation that ended, or FAST = 1).
  task drive_none;
    begin
      s_drv_left <= 32'd0;
      s_seek_d   <= 16'd0;
      s_seek_k   <= 16'd1;
      s_seek_acc <= 32'd0;
      s_rot_pend <= 1'b0;
      s_rot_n    <= 24'd0;
    end
  endtask

  // The flat 10 instruction ticks nd100x gives a test-mode transfer
  // (IODELAY_HDD_SMD): T_MIN when FAST = 0.
  task drive_flat;
    begin
      drive_none;
      if (!FAST) s_drv_left <= T_MIN;
    end
  endtask

  // A transfer (rev = 0, n = sectors) or a Write Format (rev = 1, n = tracks,
  // sector 0): the seek of `cyls` cylinders from where the arm is, the wait
  // for sector `sec`, then n units. nd100x floors the total at
  // IODELAY_HDD_SMD; it can only be below T_MIN with no seek and no unit.
  task drive_xfer;
    input [15:0] cyls;
    input [7:0]  sec;
    input [23:0] n;
    input        rev;
    input [31:0] rw;     // rot_wait to sector `sec`, from this clock
    begin
      drive_none;
      s_rot_sec <= sec;
      s_rot_rev <= rev;
      s_seek_k  <= 16'd2;
      if (FAST) begin
        // drive_none above: completion is END_DELAY after the data
      end else if (cyls != 16'd0) begin
        s_drv_left <= T_SEEK_ONE;
        s_seek_d   <= seek_span(cyls);
        s_rot_pend <= 1'b1;
        s_rot_n    <= n;
      end else if (n == 24'd0) begin
        s_drv_left <= at_least_min(rw);
      end else if (rw == 32'd0) begin
        s_drv_left <= rev ? T_REV : T_SECTOR;
        s_rot_n    <= n - 24'd1;
      end else begin
        s_drv_left <= rw;
        s_rot_n    <= n;
      end
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

  // The end of an operation that does not wait for its completion time:
  // nd100x finish_operation. Not active, ready for transfer (b3, "controller
  // finished with a device operation" - an error end has finished too), the
  // flip-flop reset, and the interrupt iff int-enable (bit 0 only, BUGS.md
  // S6). `ie` is the int-enable to use: in the cycle of the control-word write
  // that is the written bit 0, since s_int_en is not loaded yet.
  task end_now;
    input ie;
    begin
      s_active   <= 1'b0;
      s_rft      <= 1'b1;
      clr_ff;
      s_eng      <= E_IDLE;
      s_dma_wait <= 1'b0;
      drive_none;
      if (ie) s_irq <= 1'b1;
    end
  endtask

  // The address counter and the word counter step with every word moved (one
  // Am2942 chain); nd100x steps its registers word by word too
  // (increment_core_address, decrement_word_counter). Copy the running pair
  // into the registers the guest reads.
  task sync_regs;
    begin
      s_core_addr    <= s_mem_addr[15:0];
      s_core_addr_hi <= s_mem_addr[23:16];
      s_word_cnt     <= s_words_left[15:0];
      s_word_cnt_hi  <= s_words_left[23:16];
    end
  endtask

  // The disk backend failed DURING a transfer. The status bit that says which
  // fault it was is set by the caller first (set_backend_fault). This has no
  // nd100x counterpart (nd100x reads its image file, see the header), so it
  // keeps this card's own choice: abnormal completion, the selected unit NOT
  // READY (b13), and the end of the operation. nd100x's nearest case, a media
  // read error, shows b12 only (BUGS.md S11). Verilog/TODO.md has the open
  // point.
  task err_active;
    begin
      s_abnormal <= 1'b1;
      sync_regs;
      s_not_ready[s_unit] <= 1'b1;
      end_now(s_int_en);
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
  wire [ 9:0] s_buf_raddr = (s_eng == E_MEM_WR || s_eng == E_COMPARE) ? s_sec_idx[9:0] :
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

  // ---- the drives' own seeks (M4, M7) ----
  // The controller ends an Initiate Seek or a Return To Zero at once; the
  // drive then moves its heads in its own time and comes back on cylinder
  // when they arrive (nd100x queues smd_seek_end / smd_rtz_end for that
  // unit). One timer per unit 0-3, started by a pulse on s_u_start with the
  // distance s_u_dist. When the heads arrive the unit is on cylinder again,
  // and after an M4 (not an M7) its seek-complete bit is set; the main block
  // below does both on w_u_arrive. The time is nd100x's smd_seek_ticks, the
  // seek curve above, and a seek of no distance takes T_MIN (nd100x: "NOT
  // verified: what the drive does for a seek to the cylinder it is on; it is
  // given the old 10 ticks"). FAST = 1: DELAY_TICKS, the same as every drive
  // movement.
  //
  // A second seek given while a unit's heads are still moving starts its
  // timer again, so only the last arrival is seen. nd100x keeps both queued
  // and the first one still raises on-cylinder early (Verilog/TODO.md).
  reg  [3:0]  s_u_start;   // one-clock start pulse per unit
  reg  [15:0] s_u_dist;    // the seek's distance, valid with s_u_start
  reg         s_u_rtz;     // the seek is a Return To Zero, valid with s_u_start
  wire [3:0]  w_u_arrive;  // one-clock pulse: the unit's heads are there
  wire [3:0]  w_u_rtz;     // the arrival ends a Return To Zero

  genvar gu;
  generate
    for (gu = 0; gu < 4; gu = gu + 1) begin : g_unit
      reg [31:0] r_left;
      reg [15:0] r_k, r_d;
      reg [31:0] r_acc;
      reg        r_busy, r_rtz, r_arrive;
      always @(posedge sysclk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
          r_left   <= 32'd0;
          r_k      <= 16'd1;
          r_d      <= 16'd0;
          r_acc    <= 32'd0;
          r_busy   <= 1'b0;
          r_rtz    <= 1'b0;
          r_arrive <= 1'b0;
        end else begin
          r_arrive <= 1'b0;
          if (s_u_start[gu]) begin
            r_busy <= 1'b1;
            r_rtz  <= s_u_rtz;
            r_acc  <= 32'd0;
            r_k    <= 16'd2;
            if (FAST) begin
              r_left <= (DELAY_TICKS != 32'd0) ? DELAY_TICKS : 32'd1;
              r_d    <= 16'd0;
            end else if (s_u_dist == 16'd0) begin
              r_left <= T_MIN;
              r_d    <= 16'd0;
            end else begin
              r_left <= T_SEEK_ONE;
              r_d    <= seek_span(s_u_dist);
            end
          end else if (r_busy) begin
            if (r_k <= r_d) begin : charge
              reg [63:0] inc;
              inc    = seek_inc(r_k, r_acc);
              r_acc  <= inc[63:32];
              r_k    <= r_k + 16'd1;
              r_left <= r_left + inc[31:0] - 32'd1;
            end else if (r_left > 32'd1) begin
              r_left <= r_left - 32'd1;
            end else begin
              r_left   <= 32'd0;
              r_busy   <= 1'b0;
              r_arrive <= 1'b1;
            end
          end
        end
      end
      assign w_u_arrive[gu] = r_arrive;
      assign w_u_rtz[gu]    = r_rtz;
    end
  endgenerate

  // The distance from where the selected unit's arm is to the block address's
  // cylinder, for the control word being written now.
  wire [15:0] w_arm_now  = s_arm[iox_wdata[8:7]];
  wire [15:0] w_arm_dist = (w_arm_now > w_cyl) ? (w_arm_now - w_cyl) : (w_cyl - w_arm_now);
  // Sectors a transfer of the loaded word count passes, rounded up (nd100x
  // smd_transfer_ticks: (words + 511) / 512).
  wire [23:0] w_xfer_secs = {9'd0, w_words[23:9]} + ((w_words[8:0] != 9'd0) ? 24'd1 : 24'd0);
  // Write Format: the number of tracks and the remainder (see FMT_M above).
  wire [63:0] w_fmt_prod  = {40'd0, w_words} * FMT_M;
  wire [23:0] w_fmt_q     = w_fmt_prod[24 + FMT_L +: 24];
  wire [23:0] w_fmt_r     = w_words - w_fmt_q * FMT_D24;
  // The rotation wait from this clock to the transfer's first sector, and to
  // sector 0 (the index) where a Write Format starts.
  wire [31:0] w_rw_xfer   = rot_wait(sec_start(w_sector), r_rot);
  wire [31:0] w_rw_fmt    = rot_wait(32'd0, r_rot);

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
      s_on_cyl       <= 8'hFF;   // powered-up drives sit on cylinder
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
      s_crc_err      <= 1'b0;
      s_abnormal     <= 1'b0;
      s_seek_err     <= 1'b0;
      s_seek_issued  <= 4'd0;
      s_arm[0]       <= 16'd0;   // every drive powers up on cylinder 0
      s_arm[1]       <= 16'd0;
      s_arm[2]       <= 16'd0;
      s_arm[3]       <= 16'd0;
      s_u_start      <= 4'd0;
      s_u_dist       <= 16'd0;
      s_u_rtz        <= 1'b0;
      s_drv_left     <= 32'd0;
      s_seek_k       <= 16'd1;
      s_seek_d       <= 16'd0;
      s_seek_acc     <= 32'd0;
      s_rot_pend     <= 1'b0;
      s_rot_sec      <= 8'd0;
      s_rot_n        <= 24'd0;
      s_rot_rev      <= 1'b0;
      s_ma_wc_ff     <= 1'b0;
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
      s_op           <= 4'd0;
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
      s_u_start  <= 4'd0;

      // (backend dbuf_we writes now land through the muxed RAM write port
      //  above - see the buffer RAM ports block)

      // ---- a drive's heads arrive (g_unit) ----
      // On cylinder again; after an Initiate Seek also the unit's
      // seek-complete bit (nd100x smd_seek_end; smd_rtz_end gives on-cylinder
      // only). Ahead of the register writes, so a GO in the same clock that
      // clears the bit for a transfer has the last word.
      begin : arrive
        integer ui;
        for (ui = 0; ui < 4; ui = ui + 1) begin
          if (w_u_arrive[ui]) begin
            s_on_cyl[ui] <= 1'b1;
            if (!w_u_rtz[ui]) s_seek_complete[ui] <= 1'b1;
          end
        end
      end

      // ---- the controller's drive time runs down (FAST = 0 only) ----
      // A GO further down loads new values over these.
      if (w_seek_charging) begin : seek_charge
        reg [63:0] inc;
        inc        = seek_inc(s_seek_k, s_seek_acc);
        s_seek_acc <= inc[63:32];
        s_seek_k   <= s_seek_k + 16'd1;
        s_drv_left <= s_drv_left + inc[31:0] - ((s_drv_left != 32'd0) ? 32'd1 : 32'd0);
      end else if (s_drv_left > 32'd1) begin
        s_drv_left <= s_drv_left - 32'd1;
      end else if (s_rot_pend) begin : rot_load
        // The seek ends with this clock; from the next one the disc has to
        // turn to the first sector (nd100x smd_rotation_wait at now + seek).
        // The disc is one cycle further on then, so the wait is one less.
        reg [31:0] rw;
        rw = rot_wait(sec_start(s_rot_sec), r_rot);
        rw = (rw == 32'd0) ? (T_REV - 32'd1) : (rw - 32'd1);
        s_rot_pend <= 1'b0;
        if (rw != 32'd0) begin
          s_drv_left <= rw;
        end else if (s_rot_n != 24'd0) begin
          s_drv_left <= w_rot_unit;
          s_rot_n    <= s_rot_n - 24'd1;
        end else begin
          s_drv_left <= 32'd0;
        end
      end else if (s_rot_n != 24'd0) begin
        s_drv_left <= w_rot_unit;
        s_rot_n    <= s_rot_n - 24'd1;
      end else begin
        s_drv_left <= 32'd0;
      end

      // ---- read-strobe side effects ----
      if (s_rd_here) begin
        if (s_boot_mode) begin
          // boot stream readout: +0 read consumes the word, clears ready
          if (s_reg == 3'd0) begin
            s_bootptr <= s_bootptr + 11'd1;
            s_rft     <= 1'b0;
          end
        end else begin
          // Not gated on a selected unit: the flip-flop is on the controller
          // card (3044) and has no unit input, so a read toggles or resets it
          // whether or not a drive is selected.
          case (s_reg)
            // Only the flip-flop card alternates bits 0-15 / 16-23 on
            // successive +0 reads, memory address (CWR=0) and word count
            // (CWR=1) alike; a single-write card has one 16-bit read.
            3'd0: if (HAS_WC_FLIPFLOP) s_ma_wc_ff <= ~s_ma_wc_ff;
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
          // TWO +1 writes (core address, 0 both times) before +3 / +7 / +5.
          // Swallowing them left '21540&' loading a word count of zero, so
          // the GO completed instantly and transferred nothing.
          3'd1: begin
            s_boot_mode <= 1'b0;
            if (s_cwr) begin
              if (s_test_mode && s_marginal) begin
                s_core_addr <= s_core_addr + 16'd1;
                s_word_cnt  <= s_word_cnt  - 16'd1;
              end
            end else if (w_load_illegal) begin
              // Illegal load (active, or the selected unit off cylinder - see
              // w_load_illegal): raise b5 and IGNORE the write. It is
              // a status flag only (ND-11.020.01 sec 2.5 b5) - the running
              // operation continues and the drive does NOT go not-ready, so
              // err_active must not be called here. DISC-TEMA loads this
              // register during an active parity check and then expects to read
              // status with b5 AND b2 both set.
              s_illegal <= 1'b1;
              s_abnormal <= 1'b1;
            end else if (!HAS_WC_FLIPFLOP) begin
              // ECC / BIG-DISC: no flip-flop - one write loads the full 16 bits.
              // Bits 16-17 are NOT loaded here; they come from control-word
              // bits 5-6 at the next +5 write (mirrors the nd100x oracle).
              s_core_addr <= iox_wdata;
            end else begin
              // 15 MHz card (s_ma_wc_ff above): the first access of a pair
              // loads all 24 bits - bits 16-23 from A bits 0-7 through the
              // 11B byte swapper, bits 0-15 from A. The second loads bits
              // 0-15 only.
              if (!s_ma_wc_ff) s_core_addr_hi <= iox_wdata[7:0];
              s_core_addr <= iox_wdata;
              s_ma_wc_ff  <= ~s_ma_wc_ff;
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
            end else if (w_load_illegal) begin
              // Illegal load (active or off cylinder) - b5 only, operation
              // continues. See the +1 case above.
              s_illegal <= 1'b1;
              s_abnormal <= 1'b1;
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
            s_abnormal <= 1'b1;
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

            // No forcing of s_on_cyl here: on-cylinder is drive state. A powered-up
            // drive sits on cylinder; an Initiate Seek (M4) or a Return To Zero
            // (M7) drops it, and the drive raises it again when its heads arrive
            // (g_unit). Forcing it on at every control word made status b14
            // permanently 1. Source: nd100x (device_smd.c), whose DISC-TEMA fixes
            // removed the same forcing ("Bit 16b (on cylinder) remained 1" after
            // RTZ, "became 1 immediately" after M4).

            if (iox_wdata[4]) begin
              // ---- Device clear ----
              s_active <= 1'b0;
              if (~iox_wdata[9]) s_not_ready[iox_wdata[9:7]] <= 1'b0;
              // A device clear does NOT raise seek-complete: ND-11.020.01
              // (seek condition, bits 0-3) says that bit is "only set if an
              // initiate seek command for that unit has first been issued".
              // It forgets the seeks given, as nd100x does (seekIssuedMask =
              // 0), so a Seek Complete Search after it can only time out. The
              // drives' own seeks (g_unit) go on: a device clear stops the
              // controller, not the arms (nd100x leaves smd_seek_end queued).
              s_seek_issued  <= 4'd0;
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
              s_crc_err      <= 1'b0;
              s_abnormal     <= 1'b0;
              s_seek_err     <= 1'b0;
              s_eng          <= E_IDLE;
              s_dma_wait     <= 1'b0;
              drive_none;
              // else-branch interrupt eval with rft now false: ie && test
              s_irq          <= iox_wdata[0] && iox_wdata[3];
            end else if (iox_wdata[2]) begin
              // ---- GO ----
              if (iox_wdata[9]) begin
                // No unit selected (4-7): nd100x smd_write, "GO on a
                // not-specified unit": hardware error 2 (b7, DISC-TEMA "Read
                // (from NOT specified unit), Status Bit 7b is 0 !"), abnormal
                // completion, and the operation ends at once (finish_operation).
                // This path does not reach execute_go, so the illegal-load,
                // timeout and abnormal bits of the last operation are NOT
                // cleared first.
                s_hw_err2  <= 1'b1;
                s_abnormal <= 1'b1;
                end_now(iox_wdata[0]);
              end else begin
                // b12, b5 and b6 report on THIS operation: nd100x execute_go
                // clears them at every GO (it cites DISC-TEMA; ND-11.020.01
                // does not say so).
                s_abnormal  <= 1'b0;
                s_illegal   <= 1'b0;
                s_time_out  <= 1'b0;
                s_active    <= 1'b1;
                // Unlike the oracle, whose transfer executes instantly inside
                // the control-word write (so ready=true at top is already
                // final), the RTL engine takes real time: ready-for-transfer
                // must be LOW until completion (E_DELAY) raises it.
                s_rft       <= 1'b0;
                s_unit      <= iox_wdata[9:7];
                s_not_ready[iox_wdata[9:7]] <= 1'b0;
                // Only a transfer (M0-M3) consumes the unit's seek-complete
                // condition: "the condition will last until a transfer command
                // is given" (ND-11.020.01, seek condition). nd100x execute_go
                // clears it here, before the address check, for M0-M3 only; an
                // M6 must not wipe the very bit it is about to search for.
                if (iox_wdata[14:11] <= 4'd3)
                  s_seek_complete[iox_wdata[9:7]] <= 1'b0;
                // On the single-write card the HI bits arrive with THIS control
                // word (bits 5-6), so use them directly - the s_core_addr_hi
                // register write above is non-blocking and not visible yet.
                s_mem_addr   <= HAS_WC_FLIPFLOP ? {s_core_addr_hi, s_core_addr}
                                                : {6'd0, iox_wdata[6:5], s_core_addr};
                s_words_left <= w_words;
                s_op         <= iox_wdata[14:11];
                s_sec_idx    <= 11'd0;

                // Each part of the C/H/S address is range-checked on its own.
                // The head used to be compared with GEO_MAX_CYL (a transcription
                // slip), so heads 5..822 passed and aliased onto other tracks,
                // and cylinder GEO_MAX_CYL itself passed because the LBA test
                // is "greater than". Every operation is checked, outside test
                // mode, as in nd100x execute_go.
                if (!iox_wdata[3] &&
                    ((w_lba > w_max_lba) ||
                     (w_cyl >= GEO_MAX_CYL) ||
                     ({8'd0, w_head} >= GEO_HEADS) ||
                     ({8'd0, w_sector} >= GEO_SPT))) begin
                  // ---- address mismatch ----
                  // nd100x execute_go: an illegal block address is also a seek
                  // error (seek condition b11, DISC-TEMA item 6), and the
                  // operation ends at once (handle_error + finish_operation).
                  // The unit does not go NOT READY (it used to here; nd100x
                  // sets only b8 and b12). The other mismatch, a sector whose
                  // address field is not the one asked for, is not modelled
                  // (no address-field table, see M5 below).
                  s_seek_err      <= 1'b1;
                  s_addr_mismatch <= 1'b1;
                  s_abnormal      <= 1'b1;
                  end_now(iox_wdata[0]);
                end else begin
                  // A transfer consumes the unit's outstanding seek (nd100x
                  // seekIssuedMask), so an M6 with no NEW seek times out
                  // (DISC-TEMA section 6).
                  if (iox_wdata[14:11] <= 4'd3)
                    s_seek_issued[iox_wdata[8:7]] <= 1'b0;
                  // A transfer's own time: the implied seek, the wait for the
                  // sector, one sector time per sector (nd100x
                  // smd_transfer_ticks), and the arm is left on the new
                  // cylinder. In test mode the data never touches the disc and
                  // nd100x gives a flat IODELAY_HDD_SMD; the arm stays.
                  if (iox_wdata[14:11] <= 4'd3) begin
                    if (iox_wdata[3]) begin
                      drive_flat;
                    end else begin
                      drive_xfer(w_arm_dist, w_sector, w_xfer_secs, 1'b0, w_rw_xfer);
                      s_arm[iox_wdata[8:7]] <= w_cyl;
                    end
                  end
                  case (iox_wdata[14:11])
                    4'd0: begin  // M0 read transfer (disk -> memory)
                      if (iox_wdata[3]) begin
                        // TEST MODE (ND-11.020.01 sec 4.4): the words come from
                        // the controller's own pattern generator, not the disc
                        // (nd100x smd_test_pattern_word: 052525, 125252, ...).
                        // The stream carries no valid check word, so the read
                        // ends with data error b9 (sec 4.4: status 041030).
                        if (w_words != 24'd0) begin
                          s_eng <= E_TEST_WR;
                        end else begin
                          s_crc_err   <= 1'b1;
                          s_delay_cnt <= END_DELAY;
                          s_eng       <= E_DELAY;
                        end
                      end else if (w_words != 24'd0) begin
                        disk_start <= 1'b1;
                        disk_req   <= 1'b1;
                        disk_wr    <= 1'b0;
                        s_chunk_q  <= (w_words > {13'd0, BUF_WORDS}) ?
                                      BUF_WORDS : w_words[10:0];
                        s_eng      <= E_DISK_RD;
                      end else begin
                        s_delay_cnt <= END_DELAY;
                        s_eng       <= E_DELAY;
                      end
                    end
                    4'd1: begin  // M1 write transfer (memory -> disk)
                      // Test mode makes no difference to M1 in nd100x: the
                      // words go to the disc.
                      if (w_words != 24'd0) begin
                        disk_start <= 1'b1;
                        s_chunk_q  <= (w_words > {13'd0, BUF_WORDS}) ?
                                      BUF_WORDS : w_words[10:0];
                        s_eng      <= E_MEM_RD;
                      end else begin
                        s_delay_cnt <= END_DELAY;
                        s_eng       <= E_DELAY;
                      end
                    end
                    4'd2: begin  // M2 read parity transfer
                      // ND-11.020.01 "M2: Read parity transfer": the data is
                      // read from the disk into the controller and checked,
                      // "No data transfer to the computer memory is
                      // performed". The card ends an M2 when the word counter
                      // reaches zero (sec 3.7.2: "M1,M2,M3 : SEC x WCZ x
                      // FIFOEMPTY"), so the words are COUNTED although none
                      // goes to memory. The counters are one Am2942 chain
                      // (card 3044 sheet 3, 14C/12C/12A) and the idle
                      // instruction is ENABLE COUNTERS, which steps the
                      // address counter up and the word counter down on the
                      // same clock; nothing on that sheet steps one without
                      // the other. So the memory address advances by the
                      // number of words counted, exactly as in an M0 - only
                      // the memory cycle is missing. Same disk read, same
                      // chunks and same completion as M0 (E_DISK_RD, then
                      // E_PARITY in place of E_MEM_WR), so a media fault still
                      // ends the command through the same error path. nd100x
                      // steps its counters the same way. Test mode makes no
                      // difference to M2 in nd100x.
                      if (w_words != 24'd0) begin
                        disk_start <= 1'b1;
                        disk_req   <= 1'b1;
                        disk_wr    <= 1'b0;
                        s_chunk_q  <= (w_words > {13'd0, BUF_WORDS}) ?
                                      BUF_WORDS : w_words[10:0];
                        s_eng      <= E_DISK_RD;
                      end else begin
                        s_delay_cnt <= END_DELAY;
                        s_eng       <= E_DELAY;
                      end
                    end
                    4'd3: begin  // M3 compare transfer
                      // ND-11.020.01 "M3: Compare transfer": "the controller
                      // compares the data read from the disk and the data from
                      // the computer memory bit by bit. A mismatch causes
                      // compare error to be set." Same disk read and chunking
                      // as M0; E_COMPARE then makes one memory READ per word
                      // (the counters step as a pair, as in M0/M2) and checks
                      // it against the disk word. Nothing is written to memory.
                      // In test mode the memory is compared with the pattern
                      // generator instead (E_TEST_CMP), and the compare ends
                      // with data error b9 like a test-mode read (sec 4.4).
                      if (iox_wdata[3]) begin
                        if (w_words != 24'd0) begin
                          s_eng <= E_TEST_CMP;
                        end else begin
                          s_crc_err   <= 1'b1;
                          s_delay_cnt <= END_DELAY;
                          s_eng       <= E_DELAY;
                        end
                      end else if (w_words != 24'd0) begin
                        disk_start <= 1'b1;
                        disk_req   <= 1'b1;
                        disk_wr    <= 1'b0;
                        s_chunk_q  <= (w_words > {13'd0, BUF_WORDS}) ?
                                      BUF_WORDS : w_words[10:0];
                        s_eng      <= E_DISK_RD;
                      end else begin
                        s_delay_cnt <= END_DELAY;
                        s_eng       <= E_DELAY;
                      end
                    end
                    4'd4: begin  // M4 initiate seek
                      // ND-11.020.01 "M4: Initiate seek": "As soon as this
                      // function is accepted by the disk, the operation will
                      // be completed." Normal End of Operation case 2 is "On
                      // cylinder is deactivated upon an initiate seek command"
                      // - the drive taking the command, not the heads
                      // arriving; arrival is reported later, through the
                      // seek-complete bits (+2 b0-3). So the CONTROLLER ends
                      // now. MEASURED: SINTRAN's driver polls status 64 times
                      // (about 17,000 cycles) after an M4 and then writes the
                      // next control word; holding ACTIVE for DELAY_TICKS
                      // (800,000 cycles in Verilator) turned that write into
                      // an illegal load (status 040064), every retry of the
                      // request failed, and start-up printed "TRANSFER ERROR".
                      // nd100x ends M4 at once too (finish_operation).
                      //
                      // The DRIVE then drops on-cylinder, moves its heads and
                      // raises on-cylinder and its seek-complete bit when they
                      // arrive (g_unit; nd100x smd_seek_end). The cylinder is
                      // checked even in test mode, where the address check
                      // above is skipped: a cylinder past the last one is a
                      // seek error (nd100x execute_go, DISC-TEMA section 7).
                      if (w_cyl >= GEO_MAX_CYL) begin
                        s_seek_err      <= 1'b1;
                        s_addr_mismatch <= 1'b1;
                        s_abnormal      <= 1'b1;
                      end else begin
                        s_seek_err  <= 1'b0;
                        s_on_cyl[iox_wdata[9:7]]      <= 1'b0;
                        s_seek_issued[iox_wdata[8:7]] <= 1'b1;
                        s_u_start   <= 4'd1 << iox_wdata[8:7];
                        s_u_dist    <= w_arm_dist;
                        s_u_rtz     <= 1'b0;
                        s_arm[iox_wdata[8:7]] <= w_cyl;
                      end
                      end_now(iox_wdata[0]);
                    end
                    4'd5: begin  // M5 write format
                      // nd100x execute_go, DEVICE_OP_WRITE_FORMAT. The word
                      // count is the format data the controller DMA-reads from
                      // memory: two address-field words per sector, a whole
                      // number of tracks. A count of zero, or one that is not a
                      // whole number of tracks, leaves the controller waiting
                      // for data that never lines up with the sector pulses:
                      // the 500 ms timeout, b6 (DISC-TEMA section 5 gives WC
                      // 30000B and wants "Bit 6b (timeout)"). nd100x ends that
                      // case at once.
                      if (w_words == 24'd0 || w_fmt_r != 24'd0) begin
                        s_time_out <= 1'b1;
                        s_abnormal <= 1'b1;
                        end_now(iox_wdata[0]);
                      end else begin
                        // The fields are read from memory, track after track,
                        // but NOT kept: this card has no address-field table,
                        // so a later transfer never finds a field different
                        // from the natural one (nd100x keeps one in memory,
                        // BUGS.md S4; Verilog/TODO.md). The registers are left
                        // as loaded, as in nd100x, which reads through a copy.
                        // The time: the implied seek, the wait for sector 0
                        // (the index), one revolution per track.
                        drive_xfer(w_arm_dist, 8'd0, w_fmt_q, 1'b1, w_rw_fmt);
                        s_arm[iox_wdata[8:7]] <= w_cyl;
                        if (FMT_FETCH) begin
                          s_eng <= E_FMT;
                        end else begin
                          s_delay_cnt <= END_DELAY;
                          s_eng       <= E_DELAY;
                        end
                      end
                    end
                    4'd6: begin  // M6 seek-complete search
                      // nd100x DEVICE_OP_SEEK_COMPLETE_SEARCH: the controller
                      // stays ACTIVE until a unit with a seek outstanding shows
                      // its seek-complete bit ("independent of the unit select
                      // code"), or the 500 ms timeout (b6). With no seek
                      // outstanding there is nothing to find and only the
                      // timeout ends it (DISC-TEMA section 6: "Seek Complete
                      // Search (with no previous seek), Status Bit 6b (timeout)
                      // is 0 !", and "Status Bit 2b (active) becomes 0
                      // immediately !!"). The seek error is cleared only when a
                      // seek is outstanding, as in nd100x.
                      if (s_seek_issued != 4'd0) s_seek_err <= 1'b0;
                      s_delay_cnt <= T_TIMEOUT;
                      s_eng       <= E_SEARCH;
                    end
                    4'd7: begin  // M7 return to zero (only op that clears seekErr)
                      // nd100x DEVICE_OP_RETURN_TO_ZERO_SEEK: the operation ends
                      // now (ND-11.020.01's fourth normal end, "RTZ * (not ON
                      // cyl)"); the drive drops on-cylinder, takes its seek
                      // time back to cylinder 0, and comes back on cylinder
                      // WITHOUT a seek-complete bit (nd100x smd_rtz_end;
                      // DISC-TEMA section 7 reads bits 0-7 zero after an RTZ).
                      s_seek_err  <= 1'b0;
                      s_on_cyl[iox_wdata[9:7]]      <= 1'b0;
                      s_seek_issued[iox_wdata[8:7]] <= 1'b1;
                      s_u_start   <= 4'd1 << iox_wdata[8:7];
                      s_u_dist    <= w_arm_now;
                      s_u_rtz     <= 1'b1;
                      s_arm[iox_wdata[8:7]] <= 16'd0;
                      end_now(iox_wdata[0]);
                    end
                    4'd8: begin  // M8 run ECC operation
                      // Not modelled in nd100x either ("TODO: Implement ECC
                      // operation"); it was activated, so it ends at once.
                      end_now(iox_wdata[0]);
                    end
                    4'd9: begin  // M9 select release
                      // nd100x: the selection is dropped and the operation
                      // ends at once. With no unit selected, status b13 reads 1
                      // and b14 0.
                      s_disk_selected <= 1'b0;
                      end_now(iox_wdata[0]);
                    end
                    default: begin
                      // Operation codes 10-15: nd100x sets active and nothing
                      // ever ends it (BUGS.md S10); only a device clear does.
                      // ND-11.020.01 does not say what the card does with them.
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
            // Off cylinder counts too, for both registers (w_load_illegal,
            // nd100x load_is_illegal).
            if (w_load_illegal) begin
              s_illegal <= 1'b1;
              s_abnormal <= 1'b1;
            end else begin
              s_boot_mode <= 1'b0;
              if (s_cwr) begin
                // Load ECC Control: ONE write loads it, on both cards (see the
                // note at s_ma_wc_ff; nd100x smd_write). Bit 0 resets the ECC
                // count, bit 1 forces the parity error (hardware error 2, b7,
                // as nd100x does it). Bit 2, LONG (a sector read or written
                // with its 64 ECC bits), and bits 3-6, the format bits, are
                // not modelled (Verilog/TODO.md).
                if (iox_wdata[0]) s_ecc_count <= 16'd0; // bit0: reset ECC
                if (iox_wdata[1]) s_hw_err2   <= 1'b1;  // bit1: force parity
              end else if (!HAS_WC_FLIPFLOP) begin
                // ECC / BIG-DISC: no flip-flop - one write loads the full 16 bits.
                s_word_cnt    <= iox_wdata;
                s_word_cnt_hi <= 8'd0;
              end else begin
                // 15 MHz card: the same flip-flop and the same load as the
                // memory address (s_ma_wc_ff) - the first access loads all 24
                // bits, the second bits 0-15. The mass-storage microcode's
                // single +7 write of 002000 therefore leaves 00 002000.
                if (!s_ma_wc_ff) s_word_cnt_hi <= iox_wdata[7:0];
                s_word_cnt <= iox_wdata;
                s_ma_wc_ff <= ~s_ma_wc_ff;
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
              s_eng     <= (s_op == 4'd2) ? E_PARITY :
                           (s_op == 4'd3) ? E_COMPARE : E_MEM_WR;
            end
          end
        end

        // M2: the chunk just read passes through the controller, one word per
        // clock, stepping the address and word counters as a pair (Am2942
        // ENABLE COUNTERS) but making NO memory cycle. The chunk bookkeeping
        // is the same as E_MEM_WR's, which is what M0 uses.
        E_PARITY: begin
          s_mem_addr   <= s_mem_addr   + 24'd1;
          s_words_left <= s_words_left - 24'd1;
          if (s_sec_idx + 11'd1 >= s_chunk_q || s_words_left == 24'd1) begin
            if (s_words_left == 24'd1) begin
              s_delay_cnt <= END_DELAY;
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

        // M3: for each word of the chunk read one word from ND memory and
        // compare it with the disk word s_buf_dout (the read port follows
        // s_sec_idx in this state). Chunk bookkeeping is E_MEM_WR's.
        // A mismatch ends the transfer AT THAT WORD with compare error b10
        // and abnormal completion b12, the counters left on the word that
        // differed: nd100x execute_go, DEVICE_OP_COMPARE_TRANSFER
        // (handle_error + finish_operation; BUGS.md S7 - ND-11.020.01 does not
        // list a compare error among the abnormal ends, so the card may well
        // run on). A failed memory read counts as a mismatch (BUGS.md S8).
        E_COMPARE: begin
          if (!s_dma_wait && !dma_busy && s_buf_valid) begin
            dma_issue(1'b0, s_mem_addr, 16'd0);
          end else if (s_dma_wait && dma_ack) begin
            s_dma_wait <= 1'b0;
            if (dma_err || dma_rdata != s_buf_dout) begin
              s_comparer_err <= 1'b1;
              s_abnormal     <= 1'b1;
              sync_regs;
              end_now(s_int_en);
            end else begin
              s_mem_addr   <= s_mem_addr   + 24'd1;
              s_words_left <= s_words_left - 24'd1;
              if (s_sec_idx + 11'd1 >= s_chunk_q || s_words_left == 24'd1) begin
                if (s_words_left == 24'd1) begin
                  s_delay_cnt <= END_DELAY;
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

        E_MEM_WR: begin
          // s_buf_valid: wait the one read-latency cycle after entering the
          // state / advancing s_sec_idx so s_buf_dout holds THIS word.
          if (!s_dma_wait && !dma_busy && s_buf_valid) begin
            dma_issue(1'b1, s_mem_addr, s_buf_dout);
          end else if (s_dma_wait && dma_ack) begin
            s_dma_wait <= 1'b0;
            // A failed memory write is not looked at: the word is lost, the
            // counters step on and nothing is reported (nd100x does not check
            // dev_dma_write, BUGS.md S8). It used to set b11 and end the
            // transfer with the unit NOT READY here.
            s_mem_addr   <= s_mem_addr   + 24'd1;
            s_words_left <= s_words_left - 24'd1;
            if (s_sec_idx + 11'd1 >= s_chunk_q || s_words_left == 24'd1) begin
              if (s_words_left == 24'd1) begin
                s_delay_cnt <= END_DELAY;
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

        E_MEM_RD: begin
          if (!s_dma_wait && !dma_busy) begin
            dma_issue(1'b0, s_mem_addr, 16'd0);
          end else if (s_dma_wait && dma_ack) begin
            s_dma_wait <= 1'b0;
            if (dma_err) begin
              // A failed memory read ends the write at once with abnormal
              // completion only, b12 (nd100x: handle_error(READ_ERROR) +
              // finish_operation; its b13 is lost on the status read,
              // BUGS.md S8 and S11). The counters stay on the failed word.
              // nd100x writes nothing to the disc in that case; this card
              // has already written the chunks before it (Verilog/TODO.md).
              s_abnormal <= 1'b1;
              sync_regs;
              end_now(s_int_en);
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
              s_delay_cnt <= END_DELAY;
              s_eng       <= E_DELAY;
            end else begin
              s_chunk_q <= (s_words_left > {13'd0, BUF_WORDS}) ?
                           BUF_WORDS : s_words_left[10:0];
              s_sec_idx <= 11'd0;
              s_eng     <= E_MEM_RD;
            end
          end
        end

        // Test-mode M0: the pattern generator's words go to memory, 052525
        // first, then 125252, alternating (nd100x smd_test_pattern_word,
        // measured with DISC-TEMA J02; s_sec_idx counts the words from 0). A
        // failed memory write is not looked at (BUGS.md S8). Ends with data
        // error b9 (ND-11.020.01 sec 4.4).
        E_TEST_WR: begin
          if (!s_dma_wait && !dma_busy) begin
            dma_issue(1'b1, s_mem_addr, s_sec_idx[0] ? 16'o125252 : 16'o052525);
          end else if (s_dma_wait && dma_ack) begin
            s_dma_wait   <= 1'b0;
            s_mem_addr   <= s_mem_addr   + 24'd1;
            s_words_left <= s_words_left - 24'd1;
            s_sec_idx    <= s_sec_idx + 11'd1;
            if (s_words_left == 24'd1) begin
              s_crc_err   <= 1'b1;
              s_delay_cnt <= END_DELAY;
              s_eng       <= E_DELAY;
            end
          end
        end

        // Test-mode M3: memory compared with the same pattern stream. A
        // mismatch, or a failed memory read, ends it at that word with compare
        // error b10, data error b9 and abnormal completion b12 (nd100x
        // execute_go, test-mode compare). A good compare ends with b9 alone.
        E_TEST_CMP: begin
          if (!s_dma_wait && !dma_busy) begin
            dma_issue(1'b0, s_mem_addr, 16'd0);
          end else if (s_dma_wait && dma_ack) begin
            s_dma_wait <= 1'b0;
            if (dma_err || dma_rdata != (s_sec_idx[0] ? 16'o125252 : 16'o052525)) begin
              s_comparer_err <= 1'b1;
              s_crc_err      <= 1'b1;
              s_abnormal     <= 1'b1;
              sync_regs;
              end_now(s_int_en);
            end else begin
              s_mem_addr   <= s_mem_addr   + 24'd1;
              s_words_left <= s_words_left - 24'd1;
              s_sec_idx    <= s_sec_idx + 11'd1;
              if (s_words_left == 24'd1) begin
                s_crc_err   <= 1'b1;
                s_delay_cnt <= END_DELAY;
                s_eng       <= E_DELAY;
              end
            end
          end
        end

        // M5: the address fields are read from memory, one word per DMA
        // cycle, and dropped (no address-field table, see the GO). A failed
        // read is taken as a zero word and the format goes on (nd100x,
        // BUGS.md S8). s_mem_addr and s_words_left run on a copy: the
        // registers are not changed by M5 (E_DELAY copies them back only for
        // M0-M3).
        E_FMT: begin
          if (!s_dma_wait && !dma_busy) begin
            dma_issue(1'b0, s_mem_addr, 16'd0);
          end else if (s_dma_wait && dma_ack) begin
            s_dma_wait   <= 1'b0;
            s_mem_addr   <= s_mem_addr   + 24'd1;
            s_words_left <= s_words_left - 24'd1;
            if (s_words_left == 24'd1) begin
              s_delay_cnt <= END_DELAY;
              s_eng       <= E_DELAY;
            end
          end
        end

        // M6: wait for a seek-complete bit of a unit with a seek outstanding
        // (nd100x smd_search_tick), else the 500 ms timeout (smd_timeout_end:
        // b6 and b12). Either way the operation then ends.
        E_SEARCH: begin
          if ((s_seek_complete[3:0] & s_seek_issued) != 4'd0) begin
            end_now(s_int_en);
          end else if (s_delay_cnt <= 32'd1) begin
            s_time_out <= 1'b1;
            s_abnormal <= 1'b1;
            end_now(s_int_en);
          end else begin
            s_delay_cnt <= s_delay_cnt - 32'd1;
          end
        end

        // Completion delay, then ReadEnd (oracle SMDReadEnd, nd100x
        // smd_read_end). It ends when the flat delay (FAST) and the drive time
        // (FAST = 0) are both over; in each mode the other one is 0. Boot
        // completions use the same delay slot but skip the register sync /
        // interrupt.
        E_DELAY: begin
          if (s_delay_cnt != 32'd0) begin
            s_delay_cnt <= s_delay_cnt - 32'd1;
          end else if (s_boot_mode) begin
            s_active <= 1'b0;
            s_rft    <= 1'b1;
            s_eng    <= E_IDLE;
          end else if (!w_drv_busy) begin
            // Only a transfer changes the address and word registers; M5
            // leaves them as loaded (nd100x reads its format data through a
            // copy). A completion never raises a seek-complete bit: those
            // belong to the drives (g_unit), and a finished transfer must
            // not set one (DISC-TEMA section 7 reads bits 0-7 zero "With no
            // previous Initiate-Seek").
            if (s_op <= 4'd3) sync_regs;
            end_now(s_int_en);
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
        $display("[SMD] cyc=%0d WR +%0d val=%o boot=%b cwr=%b mawcff=%b",
                 s_trace_cyc, s_reg, iox_wdata, s_boot_mode, s_cwr, s_ma_wc_ff);
      if (s_rd_here)
        $display("[SMD] cyc=%0d RD +%0d -> %o boot=%b active=%b rft=%b cwr=%b mawcff=%b",
                 s_trace_cyc, s_reg, iox_rdata, s_boot_mode, s_active, s_rft, s_cwr, s_ma_wc_ff);
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
