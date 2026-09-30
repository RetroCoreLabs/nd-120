//============================================================================
//! Terminal control - TDV2200 (terminal type 93, Tandberg TDV-2200/9S
//! ND-NOTIS)
//!
//! Part of the board-independent terminal core (Verilog/Terminals/).
//! Sibling of terminal_ctrl.v (VT100, type 6) - same engine (clear/scroll/
//! copy/apply state machines, cursor-move arithmetic, address functions are
//! IDENTICAL, terminal-type-agnostic screen mechanics), different PARSER:
//! a TDV does not speak ECMA-48 C0 meanings or DEC CSI cursor letters for
//! input, and neither does SINTRAN when it thinks it is talking to one.
//!
//! GROUND TRUTH (see ps2_ascii_table_tdv.v's header for the full source
//! list) and the REAL CAPTURED PED-at-type-93 startup this parser is built
//! to survive byte-exact (Verilog/Terminals/docs/SPEC-tdv2200.md has the
//! full account):
//!   ESC Q                          exit/enable EC switch - swallowed
//!   ESC[30;7;80l  ESC[62;62h       mode set/reset, UNMARKED (no '?'),
//!                                  function unknown - swallowed generically
//!   ESC P L10 ESC\  (x4)           DCS soft-key programming - SKIPPED AS A
//!                                  UNIT, never rendered (matches RetroTerm's
//!                                  own TDV2200Emulator, which does not
//!                                  implement DCS soft-key programming either)
//!   ESC[001;001H                   CUP, ZERO-PADDED parameters
//!   ESC[2J                         ED, standard
//!
//! C0 CONTROL CODES have TDV-native meanings, not ASCII/ECMA-48 ones - this
//! is the single biggest difference from terminal_ctrl.v. Cursor movement is
//! C0 bytes (BS=left, VT=down, CAN=right, FS=up, GS=home), NOT escape
//! sequences - confirmed on real hardware (FINDINGS-2026-08-20.md: SENDKEY
//! HOME transmitted GS 0x1D, cursor landed on the PED: line, "exactly the
//! documented behaviour").
//!
//! DLE (0x10) starts 2-byte BINARY cursor addressing: row byte masked to 5
//! bits (0-24), column byte masked to 7 bits (0-79) - 7, not 5: 5 bits
//! cannot address column 79, and the RetroTerm source code comment disputes
//! the 5-bit claim some docs make on exactly this basis. The same masking
//! is tolerant of BOTH a raw 0-based encoding and SINTRAN's 0x7F+n 1-based
//! biased encoding - masking off the low 5/7 bits collapses both cases to
//! the same result, so no mode flag is needed to pick which one arrived.
//!
//! CHARACTER SETS: "ESC <digit>" (NDSS1-9, e.g. "ESC 6" for Box) - a bare
//! TWO-byte designation, NOT VT100's three-byte "ESC ( <final>". Only NDSS6
//! (Box, font page 3 - see font/make_font.py) actually renders differently;
//! every other digit falls back to plain ASCII (page 0), same conservative
//! choice terminal_ctrl.v makes for any VT100 charset it does not implement.
//! Found missing and fixed 31-AUG-2026 against a live SCONF capture: cell
//! 0x60 printed as a literal backtick instead of a top-left corner, because
//! this parser only recognised VT100's ESC( form, which a TDV never sends.
//!
//! DEFERRED, NOT IMPLEMENTED (no evidence PED/LED use them; add only if a
//! live capture shows otherwise): ND private rectangle ops (z { } u v ~ | p
//! q s t), Tektronix/ND graphics, DCS soft-key/PUSH-key PROGRAMMING (only
//! skip-and-discard is implemented), 132-column mode (no TDV terminal type
//! supports it), NDSS1-5/7-9 (Graphics I/II, Math, Greek, Diacritics, NIX,
//! T, ND private) and the ISO 646 national-variant switch (ESC %).
//!
//! CELL LAYOUT, clock domain, blink: identical to terminal_ctrl.v - see
//! that file's header.
//!
//! Written 31-AUG-2026.
//============================================================================

`default_nettype none

module terminal_ctrl_tdv #(
    parameter integer COLS     = 80,
    //! 80x25 is TDV2200 geometry - one more row than VT100's 80x24, the
    //! 25th row PED's status line uses (confirmed: FINDINGS-2026-08-20.md,
    //! "PED as a TDV gets one more text line... Line: 1-21... 25th row").
    parameter integer ROWS     = 25,
    parameter integer AWIDTH   = 11,
    parameter integer TAB_STOP = 8,
    parameter integer BLINK_FRAMES = 30
) (
    input wire clk,  //! pixel clock (from nd120_console_mega65.clk and others)
    input wire rst_n,  //! async reset, active low (from nd120_console_mega65.rst_n and others)

    input  wire       byte_valid,
    input  wire [7:0] byte_data,
    output wire       ready,

    output reg               ram_we,
    output reg  [AWIDTH-1:0] ram_waddr,
    output reg  [      15:0] ram_wdata,
    output wire [AWIDTH-1:0] ram_raddr2,
    input  wire [      15:0] ram_rdata2,

    output reg  [7:0] top_row,  //! which stored row is displayed at the top (to text_screen.top_row)
    output reg  [7:0] cursor_col,
    output reg  [7:0] cursor_row,  //! cursor position in SCREEN coordinates (to text_screen.cursor_row)
    output wire       cursor_enable,  //! draw the cursor at all (to text_screen.cursor_enable)
    output reg        rev_screen,
    output wire       blink_on,

    input  wire frame_end,  //! one pulse per frame, un-delayed (for blink) (from text_screen.frame_end)
    output reg  bell,  //! one pix_clk per BEL received (to terminal_top.bell)
    output reg  [3:0] leds,  //! DECLL (CSI Ps q) - the VT100 keyboard lamps L1-L4 (to terminal_top.leds)

    //! Box-charset debug taps (01-SEP-2026): live s_g0_gfx state, and a
    //! STICKY latch set the first time ESC 6 (NDSS6/Box) is ever received
    //! and never cleared by anything but rst_n - directly answers "has
    //! SINTRAN ever sent the box designation at all" without racing a
    //! live snapshot against a designation that toggles back off.
    output wire dbg_box_mode,
    output reg  dbg_saw_esc6
);
  assign dbg_box_mode = s_g0_gfx;

  localparam [15:0] BLANK_CELL = {8'h00, 8'h20};

  //--------------------------------------------------------------------------
  // Engine states - identical shape to terminal_ctrl.v (terminal-type-
  // agnostic screen mechanics).
  //--------------------------------------------------------------------------
  localparam [2:0] ST_RUN     = 3'd0;
  localparam [2:0] ST_CLEAR   = 3'd1;
  localparam [2:0] ST_COPY_RD = 3'd2;
  localparam [2:0] ST_COPY_WR = 3'd3;
  localparam [2:0] ST_APPLY   = 3'd4;

  reg [2:0] s_state;

  //--------------------------------------------------------------------------
  // Parser states. P_DLE1/P_DLE2 (binary cursor addressing) and P_DCS/
  // P_DCS_ESC (skip a soft-key programming block) are new; P_ESC/P_ESCINT/
  // P_CSI carry the same shape as terminal_ctrl.v, dispatching different
  // finals.
  //--------------------------------------------------------------------------
  localparam [2:0] P_GROUND  = 3'd0;
  localparam [2:0] P_ESC     = 3'd1;
  localparam [2:0] P_ESCINT  = 3'd2;
  localparam [2:0] P_CSI     = 3'd3;
  localparam [2:0] P_DLE1    = 3'd4;  //! DLE seen, awaiting the row byte
  localparam [2:0] P_DLE2    = 3'd5;  //! row byte seen, awaiting the column byte
  localparam [2:0] P_DCS     = 3'd6;  //! inside ESC P ... - discard until ESC \
  localparam [2:0] P_DCS_ESC = 3'd7;  //! saw ESC while skipping a DCS block

  reg [2:0] p_state;
  reg [7:0] s_par  [0:3];
  reg [2:0] s_npar;
  reg       s_priv;
  reg       s_ign;
  reg [7:0] s_escint;
  reg [4:0] s_dle_row;  //! latched between P_DLE1 and P_DLE2

  //--------------------------------------------------------------------------
  // Terminal modes and rendition state - the subset TDV mode actually uses.
  // No DECOM/DECAWM/DECSTBM/LNM: not confirmed in any TDV capture, and an
  // unimplemented mode already swallows safely (see dispatch_csi).
  //--------------------------------------------------------------------------
  reg s_cursor_vis;

  reg s_at_rev, s_at_bold, s_at_ul, s_at_blink;
  reg s_shift;    //! SO/SI: 0 = G0 active, 1 = G1 active
  reg s_g0_gfx;   //! G0 designated NDSS6/Box (ESC 6) - cell bit 12, font
                  //! page 3 (TDV2200 character set 2). SCONF draws with it
                  //! (live capture 31-AUG-2026). A locking designation.
  reg s_g1_gfx;   //! G1's own designation - never set (no NDSS G1 form
                  //! implemented yet), so G1 always reads as plain ASCII

  //! SS2 (ESC N) - single-shift the NEXT character only through the
  //! TDV2200's CHARACTER SET 2 (cell bit 12, font page 3 - the SAME set the
  //! ESC 6 Box designation selects; on a real TDV2200 they are one alphabet,
  //! and RetroCore maps both to bank 2). This is the mechanism PED's
  //! box-drawing (frame/fullbar in PLANC-SCREEN-H, per NDInsight's
  //! VTM-TERMINAL-INTERFACES.md) actually uses: RetroTerm's own
  //! TDVEmulatorBase.cs hardwires G2 to set 2 PERMANENTLY (no designation
  //! escape at all - see _g2CharacterSet's initializer), so ESC N + a data
  //! byte is the box-drawing character right there, not a delayed G0 mode
  //! change. Confirmed against a live capture 01-SEP-2026: PED repeats
  //! `ESC N <char>` once per graphics cell (e.g. the position ruler), never
  //! a lasting SO. One-shot: cleared the instant put_char consumes it.
  //!
  //! Set 2 is NOT the VT100 DEC Special Graphics alphabet. Measured on the
  //! Nexys 01-SEP-2026: with SS2 pointed at the DEC page, PED's frames came
  //! out as DIAMONDS, because in set 2 code 0x60 is the horizontal line
  //! (DEC: diamond) and the corners/tees sit at 0x61-0x6A. Page 3 carries
  //! the real TDV2200 character ROM as dumped in RetroCore's FontTDV2200.cs
  //! (font/tdv2200_set2_from_retrocore.py).
  reg s_ss2_armed;

  reg s_pending;  //! last-column flag - same VT100-derived autowrap behavior;
                  //! a TDV wraps too, and nothing in the captures says otherwise.

  reg [7:0] s_cl_row, s_cl_col, s_cl_erow, s_cl_ecol;

  reg [7:0] s_cp_dst;
  reg [7:0] s_cp_col;
  reg       s_cp_down;

  //! Deferred cursor-move commit - same two-phase reasoning as
  //! terminal_ctrl.v (latch operands one cycle, commit the next) to keep
  //! the combinational cone off the cursor registers short. TDV has no
  //! scroll region, so there is no floor/ceiling clamp to register
  //! separately - every move clamps straight to the screen edges.
  //!
  //! CUU/CUD/CUF/CUB exist because SINTRAN's own cursor-move ECHO for an
  //! arrow keypress is standard VT100 CSI (ESC[A/B/C/D), not another bare
  //! TDV byte - measured on real hardware (RetroCore trace, 31-AUG-2026):
  //! sending TDV-native FS (cursor up) got ESC[A back, sending BS (cursor
  //! left) got ESC[D back, and so on for all four. Found missing here:
  //! this parser only handled H/f (CUP) - A/B/C/D fell through the
  //! `default: ;` and never moved the cursor, which is why arrows looked
  //! completely dead in PED even though the keyboard side was correct all
  //! along and SINTRAN was receiving and processing every keypress.
  localparam [3:0] AP_CUP = 4'd0;
  localparam [3:0] AP_CUU = 4'd1;
  localparam [3:0] AP_CUD = 4'd2;
  localparam [3:0] AP_CUF = 4'd3;
  localparam [3:0] AP_CUB = 4'd4;
  //! CHA (col-absolute) and VPA (row-absolute) - ported from terminal_ctrl.v
  //! along with the cursor moves above: SINTRAN's type-93 line speaks the
  //! same base ECMA-48 CSI set VT100 does (RetroTerm's own class hierarchy
  //! has TDV2200Emulator derive from the identical core VT100Emulator
  //! uses, adding ND extensions on top - not a separate protocol), so this
  //! parser should carry the same base set terminal_ctrl.v already proved,
  //! not reinvent a narrower one.
  localparam [3:0] AP_CHA = 4'd5;
  localparam [3:0] AP_VPA = 4'd6;
  //! SGR walks s_par like AP_MODE/AP_LED do in terminal_ctrl.v - one
  //! parameter per clock via s_ap_idx, not the two-phase latch above.
  localparam [3:0] AP_SGR = 4'd7;
  reg [3:0] s_ap_kind;
  reg       s_ap_phase;
  reg [7:0] s_ap_row_q;  //! CUP/VPA's row operand, or CUU/CUD/CUF/CUB/CHA's count/column
  reg [7:0] s_ap_col_q;  //! CUP's column operand only
  reg [2:0] s_ap_idx;    //! SGR parameter walk index

  assign ready = (s_state == ST_RUN) && !s_wr_hold;

  reg       s_wr_hold;
  reg [7:0] s_wr_char;

  //--------------------------------------------------------------------------
  // Address arithmetic - identical to terminal_ctrl.v.
  //--------------------------------------------------------------------------

  function automatic [7:0] stored_row;
    input [7:0] top;
    input [7:0] screen;
    reg [8:0] sum;
    begin
      sum = {1'b0, top} + {1'b0, screen};
      stored_row = (sum >= ROWS) ? (sum[7:0] - ROWS[7:0]) : sum[7:0];
    end
  endfunction

  function automatic [AWIDTH-1:0] cell_addr;
    input [7:0] row;
    input [7:0] col;
    begin
      cell_addr = {row, 6'b0} + {row, 4'b0} + col;
    end
  endfunction

  //! A CSI parameter with its default: 0 or absent means `dflt` (ECMA-48).
  function automatic [7:0] par_or;
    input [7:0] value;
    input [7:0] dflt;
    begin
      par_or = (value == 8'd0) ? dflt : value;
    end
  endfunction

  function automatic [7:0] dig_acc;
    input [7:0] cur;
    input [7:0] digit;
    reg [11:0] wide;
    begin
      wide = {4'd0, cur} * 12'd10 + {8'd0, digit[3:0]};
      dig_acc = (wide > 12'd255) ? 8'd255 : wide[7:0];
    end
  endfunction

  wire [7:0] s_cp_src = s_cp_down ? (s_cp_dst - 8'd1) : (s_cp_dst + 8'd1);
  assign ram_raddr2 = cell_addr(stored_row(top_row, s_cp_src), s_cp_col);

  //--------------------------------------------------------------------------
  // Cursor / attribute blink - identical to terminal_ctrl.v.
  //--------------------------------------------------------------------------

  reg [7:0] s_blink_count;
  reg       s_blink_on;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s_blink_count <= 8'd0;
      s_blink_on    <= 1'b1;
    end else if (frame_end) begin
      if (s_blink_count == BLINK_FRAMES - 1) begin
        s_blink_count <= 8'd0;
        s_blink_on    <= ~s_blink_on;
      end else begin
        s_blink_count <= s_blink_count + 8'd1;
      end
    end
  end

  assign cursor_enable = s_blink_on && s_cursor_vis;
  assign blink_on      = s_blink_on;

  //--------------------------------------------------------------------------
  // Screen movers - identical mechanics to terminal_ctrl.v, no DECSTBM
  // region (a TDV capture has never shown one; the ring always covers the
  // whole screen, which is the same code path terminal_ctrl.v uses for its
  // no-region case).
  //--------------------------------------------------------------------------

  task automatic start_clear;
    input [7:0] r1; input [7:0] c1;
    input [7:0] r2; input [7:0] c2;
    begin
      s_cl_row  <= r1;
      s_cl_col  <= c1;
      s_cl_erow <= r2;
      s_cl_ecol <= c2;
      s_state   <= ST_CLEAR;
    end
  endtask

  task automatic scroll_up;
    begin
      top_row <= (top_row == ROWS - 1) ? 8'd0 : (top_row + 8'd1);
      start_clear(ROWS[7:0] - 8'd1, 8'd0, ROWS[7:0] - 8'd1, COLS[7:0] - 8'd1);
    end
  endtask

  task automatic scroll_down;
    begin
      top_row <= (top_row == 8'd0) ? (ROWS[7:0] - 8'd1) : (top_row - 8'd1);
      start_clear(8'd0, 8'd0, 8'd0, COLS[7:0] - 8'd1);
    end
  endtask

  //! Cursor down (VT/LF); scrolls at the bottom row.
  task automatic do_index;
    begin
      if (cursor_row == ROWS - 1) scroll_up;
      else cursor_row <= cursor_row + 8'd1;
    end
  endtask

  //! Cursor up (FS); scrolls at the top row.
  task automatic do_rev_index;
    begin
      if (cursor_row == 8'd0) scroll_down;
      else cursor_row <= cursor_row - 8'd1;
    end
  endtask

  task automatic put_char;
    input [7:0] ch;
    begin
      ram_we    <= 1'b1;
      ram_waddr <= cell_addr(stored_row(top_row, cursor_row), cursor_col);
      // ONE graphics bit (cell bit 12 -> font page 3, the TDV2200 character
      // set 2). It is set by EITHER of the two things that select that set on
      // a real TDV2200, which are the same alphabet:
      //   - SS2 (ESC N): a single shift, so s_ss2_armed is true for exactly
      //     THIS character, whatever G0/G1 is invoked; and
      //   - the invoked set being NDSS6/Box (ESC 6): s_g0_gfx / s_g1_gfx, a
      //     locking designation that stays until the program changes it.
      // s_ss2_armed wins and is cleared here, unconditionally, the instant
      // this character is consumed - true single-shift semantics (one
      // character only). Bits 15:13 are spare.
      //
      // This is the build-24 structure, which synthesised and rendered
      // correctly on the Nexys; a two-bit / five-page variant (SS2 on its own
      // page) was dropped by Vivado's optimiser and aliased to page 0 - see
      // font_rom.v's header.
      ram_wdata <= {3'b000, (s_ss2_armed ? 1'b1 : (s_shift ? s_g1_gfx : s_g0_gfx)),
                    s_at_blink, s_at_ul, s_at_bold, s_at_rev, ch};
      s_ss2_armed <= 1'b0;
      if (cursor_col == COLS - 1) begin
        s_pending <= 1'b1;
      end else begin
        cursor_col <= cursor_col + 8'd1;
      end
    end
  endtask

  task automatic reset_modes;
    begin
      top_row      <= 8'd0;
      cursor_col   <= 8'd0;
      cursor_row   <= 8'd0;
      s_cursor_vis <= 1'b1;
      rev_screen   <= 1'b0;
      s_at_rev     <= 1'b0;
      s_at_bold    <= 1'b0;
      s_at_ul      <= 1'b0;
      s_at_blink   <= 1'b0;
      s_shift      <= 1'b0;
      s_g0_gfx     <= 1'b0;
      s_g1_gfx     <= 1'b0;
      s_ss2_armed  <= 1'b0;
      s_pending    <= 1'b0;
      leds         <= 4'b0000;
      p_state      <= P_GROUND;
    end
  endtask

  //--------------------------------------------------------------------------
  // CSI final dispatch. A/B/C/D (cursor moves), G/d (CHA/VPA), H/f (CUP),
  // J (ED), K (EL) and m (SGR) are the base ECMA-48/VT100 set, ported from
  // terminal_ctrl.v - see the AP_CHA/AP_VPA declaration above for why: a
  // type-93 line speaks this same base set, confirmed on real hardware
  // for A/B/C/D (SINTRAN's cursor-move ECHO for a TDV keypress) and for m
  // (the captured PED startup's own "ESC[2;7m" dim-reverse status line).
  // Every other final, INCLUDING every h/l mode set/reset (mode 62 among
  // them, "function unknown" per the real TDV2200 termcap's own init
  // string) is the existing `default: ;` - swallowed, never printed,
  // never corrupts parser state. That is deliberate: it is what lets an
  // unknown mode number arrive safely instead of needing to be enumerated
  // first, and it is also why DECSTBM/scroll-region CSI (`r`) and the DEC
  // private modes stay out - no capture has shown TDV mode using them.
  //--------------------------------------------------------------------------

  task automatic dispatch_csi;
    input [7:0] fin;
    begin
      case (fin)
        "A": begin s_pending<=1'b0; s_ap_kind<=AP_CUU; s_ap_phase<=1'b0; s_state<=ST_APPLY; end
        "B": begin s_pending<=1'b0; s_ap_kind<=AP_CUD; s_ap_phase<=1'b0; s_state<=ST_APPLY; end
        "C": begin s_pending<=1'b0; s_ap_kind<=AP_CUF; s_ap_phase<=1'b0; s_state<=ST_APPLY; end
        "D": begin s_pending<=1'b0; s_ap_kind<=AP_CUB; s_ap_phase<=1'b0; s_state<=ST_APPLY; end
        "G": begin s_pending<=1'b0; s_ap_kind<=AP_CHA; s_ap_phase<=1'b0; s_state<=ST_APPLY; end
        "d": begin s_pending<=1'b0; s_ap_kind<=AP_VPA; s_ap_phase<=1'b0; s_state<=ST_APPLY; end

        "H", "f": begin
          s_pending  <= 1'b0;
          s_ap_kind  <= AP_CUP;
          s_ap_phase <= 1'b0;
          s_state    <= ST_APPLY;
        end

        "m": begin  // SGR - walk the parameter list, one per clock
          s_ap_kind <= AP_SGR;
          s_ap_idx  <= 3'd0;
          if (s_npar == 3'd0) s_npar <= 3'd1;  // no params = SGR 0 (reset)
          s_state   <= ST_APPLY;
        end

        "J": begin
          s_pending <= 1'b0;
          case (s_par[0])
            8'd1: start_clear(8'd0, 8'd0, cursor_row, cursor_col);
            8'd2: start_clear(8'd0, 8'd0, ROWS[7:0] - 8'd1, COLS[7:0] - 8'd1);
            default: start_clear(cursor_row, cursor_col,
                                 ROWS[7:0] - 8'd1, COLS[7:0] - 8'd1);
          endcase
        end

        "K": begin
          s_pending <= 1'b0;
          case (s_par[0])
            8'd1: start_clear(cursor_row, 8'd0, cursor_row, cursor_col);
            8'd2: start_clear(cursor_row, 8'd0, cursor_row, COLS[7:0] - 8'd1);
            default: start_clear(cursor_row, cursor_col,
                                 cursor_row, COLS[7:0] - 8'd1);
          endcase
        end

        default: ;  // every h/l mode, every ND-private final: swallowed

      endcase
    end
  endtask

  //--------------------------------------------------------------------------
  // Main sequencer
  //--------------------------------------------------------------------------

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s_state   <= ST_CLEAR;
      s_cl_row  <= 8'd0;
      s_cl_col  <= 8'd0;
      s_cl_erow <= ROWS[7:0] - 8'd1;
      s_cl_ecol <= COLS[7:0] - 8'd1;
      ram_we    <= 1'b0;
      ram_waddr <= {AWIDTH{1'b0}};
      ram_wdata <= BLANK_CELL;
      bell      <= 1'b0;
      s_wr_hold <= 1'b0;
      s_wr_char <= 8'd0;
      s_npar    <= 3'd0;
      s_priv    <= 1'b0;
      s_ign     <= 1'b0;
      s_escint  <= 8'd0;
      s_dle_row <= 5'd0;
      s_par[0]  <= 8'd0; s_par[1] <= 8'd0; s_par[2] <= 8'd0; s_par[3] <= 8'd0;
      s_cp_dst  <= 8'd0; s_cp_col <= 8'd0; s_cp_down <= 1'b0;
      s_ap_kind <= AP_CUP; s_ap_phase <= 1'b0; s_ap_idx <= 3'd0;
      s_ap_row_q <= 8'd0; s_ap_col_q <= 8'd0;
      dbg_saw_esc6 <= 1'b0;
      reset_modes;
    end else begin
      ram_we <= 1'b0;
      bell   <= 1'b0;

      case (s_state)

        //----------------------------------------------------------------
        ST_CLEAR: begin
          ram_we    <= 1'b1;
          ram_waddr <= cell_addr(stored_row(top_row, s_cl_row), s_cl_col);
          ram_wdata <= BLANK_CELL;

          if (s_cl_row == s_cl_erow && s_cl_col == s_cl_ecol) begin
            s_state <= ST_RUN;
          end else if (s_cl_col == COLS - 1) begin
            s_cl_col <= 8'd0;
            s_cl_row <= s_cl_row + 8'd1;
          end else begin
            s_cl_col <= s_cl_col + 8'd1;
          end
        end

        //----------------------------------------------------------------
        ST_COPY_RD: begin
          s_state <= ST_COPY_WR;
        end

        ST_COPY_WR: begin
          ram_we    <= 1'b1;
          ram_waddr <= cell_addr(stored_row(top_row, s_cp_dst), s_cp_col);
          ram_wdata <= ram_rdata2;

          if (s_cp_col != COLS - 1) begin
            s_cp_col <= s_cp_col + 8'd1;
            s_state  <= ST_COPY_RD;
          end else begin
            s_cp_col <= 8'd0;
            s_cp_dst <= s_cp_dst + 8'd1;
            s_state  <= ST_COPY_RD;
          end
        end

        //----------------------------------------------------------------
        // Deferred cursor-move commit for AP_CUP/CUU/CUD/CUF/CUB/CHA/VPA
        // (two-phase, see the declaration above for why), OR the SGR
        // parameter walk for AP_SGR (one param per clock, same shape as
        // terminal_ctrl.v's AP_SGR/AP_MODE/AP_LED).
        //----------------------------------------------------------------
        ST_APPLY: begin : apply
          reg [8:0] ap_sum;

          if (s_ap_kind != AP_SGR) begin
            if (!s_ap_phase) begin
              s_ap_row_q <= par_or(s_par[0], 8'd1);
              s_ap_col_q <= par_or(s_par[1], 8'd1);
              s_ap_phase <= 1'b1;
            end else begin
              s_state <= ST_RUN;
              case (s_ap_kind)
                AP_CUP: begin
                  cursor_row <= (s_ap_row_q == 8'd0) ? 8'd0
                              : (s_ap_row_q >= ROWS) ? (ROWS[7:0] - 8'd1)
                              : (s_ap_row_q - 8'd1);
                  cursor_col <= (s_ap_col_q == 8'd0) ? 8'd0
                              : (s_ap_col_q >= COLS) ? (COLS[7:0] - 8'd1)
                              : (s_ap_col_q - 8'd1);
                end
                AP_CUU: cursor_row <=
                    ({1'b0, cursor_row} > {1'b0, s_ap_row_q})
                    ? (cursor_row - s_ap_row_q) : 8'd0;
                AP_CUD: begin
                  ap_sum = {1'b0, cursor_row} + {1'b0, s_ap_row_q};
                  cursor_row <= (ap_sum < ROWS) ? ap_sum[7:0] : (ROWS[7:0] - 8'd1);
                end
                AP_CUF: begin
                  ap_sum = {1'b0, cursor_col} + {1'b0, s_ap_row_q};
                  cursor_col <= (ap_sum < COLS - 1) ? ap_sum[7:0] : (COLS[7:0] - 8'd1);
                end
                AP_CUB: cursor_col <=
                    ({1'b0, cursor_col} > {1'b0, s_ap_row_q})
                    ? (cursor_col - s_ap_row_q) : 8'd0;
                AP_CHA: cursor_col <=
                    (s_ap_row_q <= COLS) ? (s_ap_row_q - 8'd1) : (COLS[7:0] - 8'd1);
                AP_VPA: cursor_row <=
                    (s_ap_row_q <= ROWS) ? (s_ap_row_q - 8'd1) : (ROWS[7:0] - 8'd1);
                default: ;
              endcase
            end
          end else if (s_ap_idx >= s_npar) begin
            s_state <= ST_RUN;
          end else begin
            s_ap_idx <= s_ap_idx + 3'd1;
            case (s_par[s_ap_idx[1:0]])
              8'd0: begin
                s_at_rev <= 1'b0; s_at_bold <= 1'b0;
                s_at_ul  <= 1'b0; s_at_blink <= 1'b0;
              end
              8'd1:  s_at_bold  <= 1'b1;
              8'd4:  s_at_ul    <= 1'b1;
              8'd5:  s_at_blink <= 1'b1;
              8'd7:  s_at_rev   <= 1'b1;
              8'd22: s_at_bold  <= 1'b0;
              8'd24: s_at_ul    <= 1'b0;
              8'd25: s_at_blink <= 1'b0;
              8'd27: s_at_rev   <= 1'b0;
              default: ;  // 2 (dim), colours, the rest: swallowed
            endcase
          end
        end

        //----------------------------------------------------------------
        ST_RUN: begin
          if (s_wr_hold) begin
            s_wr_hold <= 1'b0;
            put_char(s_wr_char);
          end else if (byte_valid) begin

            //--------------------------------------------------------------
            // RAW-BYTE-CAPTURE states first: P_DLE1/P_DLE2 (the two binary
            // cursor-addressing bytes) and P_DCS (the soft-key programming
            // payload) must see EVERY byte value literally, including ones
            // below 0x20 - a row/column byte or a payload byte is routinely
            // < 0x20 and must NOT be reinterpreted as a C0 control. This is
            // checked before the general C0 dispatch below, which otherwise
            // would steal those bytes (found by the testbench: DLE's own
            // row/col bytes, and the DCS terminator's own ESC, were both
            // being caught here first).
            //--------------------------------------------------------------
            if (p_state == P_DLE1) begin
              s_dle_row <= byte_data[4:0];
              p_state   <= P_DLE2;
            end else if (p_state == P_DLE2) begin
              p_state    <= P_GROUND;
              s_pending  <= 1'b0;
              cursor_row <= (s_dle_row >= ROWS[4:0]) ? (ROWS[7:0]-8'd1) : {3'b000, s_dle_row};
              cursor_col <= (byte_data[6:0] >= COLS[6:0]) ? (COLS[7:0]-8'd1) : {1'b0, byte_data[6:0]};
            end else if (p_state == P_DCS) begin
              if (byte_data == 8'h1B) p_state <= P_DCS_ESC;
              // else: still inside the DCS payload, discard the byte.
            end else if (p_state == P_DCS_ESC) begin
              if (byte_data == 8'h5C) p_state <= P_GROUND;  // ST - done (0x5C = backslash; 8'hXX not "\\", which Quartus' lexer rejects)
              else p_state <= P_DCS;  // not the terminator, keep skipping

            //--------------------------------------------------------------
            // C0 controls - TDV-NATIVE meanings, not ASCII ones. This block
            // is the core difference from terminal_ctrl.v. DLE and ESC hand
            // off to their own parser states; everything else executes
            // immediately without disturbing whatever state p_state is in
            // (matching terminal_ctrl.v's "an executable C0 arriving inside
            // a sequence executes without abandoning it" rule - real hosts
            // do this, and nothing here has evidence it does NOT apply to
            // a TDV too).
            //--------------------------------------------------------------
            end else if (byte_data < 8'h20) begin
              case (byte_data)
                8'h02, 8'h03: ;                                          // STX/ETX video off/on - not modeled
                8'h04: start_clear(cursor_row, 8'd0, cursor_row, COLS[7:0]-8'd1);  // EOT erase line
                8'h05: leds[0] <= 1'b1;                                  // ENQ LED1 on
                8'h06: leds[1] <= 1'b1;                                  // ACK LED2 on
                8'h07: bell <= 1'b1;                                     // BEL
                8'h08: begin s_pending <= 1'b0; if (cursor_col != 0) cursor_col <= cursor_col - 8'd1; end  // BS cursor left
                8'h09: begin                                             // HT
                  s_pending <= 1'b0;
                  if (((cursor_col / TAB_STOP) + 8'd1) * TAB_STOP >= COLS)
                    cursor_col <= COLS[7:0] - 8'd1;
                  else
                    cursor_col <= ((cursor_col / TAB_STOP) + 8'd1) * TAB_STOP;
                end
                8'h0A: begin s_pending <= 1'b0; do_index; end            // LF cursor down
                8'h0B: begin s_pending <= 1'b0; do_index; end            // VT cursor down
                8'h0C: begin s_pending <= 1'b0; do_rev_index; end        // FF roll up (scroll back)
                8'h0D: begin s_pending <= 1'b0; cursor_col <= 8'd0; end  // CR
                8'h0E: s_shift <= 1'b1;                                  // SO -> G1
                8'h0F: s_shift <= 1'b0;                                  // SI -> G0
                8'h10: p_state <= P_DLE1;                                // DLE - binary cursor addressing
                8'h15: leds[2] <= 1'b1;                                  // NAK LED3 on
                8'h16: leds <= 4'b0000;                                  // SYN all lamps off
                8'h17: begin s_pending <= 1'b0; do_index; end            // ETB roll down (scroll forward)
                8'h18: begin s_pending <= 1'b0; if (cursor_col != COLS-1) cursor_col <= cursor_col + 8'd1; end  // CAN cursor right
                8'h19: start_clear(8'd0, 8'd0, ROWS[7:0]-8'd1, COLS[7:0]-8'd1);  // EM erase page
                8'h1B: begin                                             // ESC
                  p_state <= P_ESC;
                  s_npar  <= 3'd0;
                  s_priv  <= 1'b0;
                  s_ign   <= 1'b0;
                  s_par[0] <= 8'd0; s_par[1] <= 8'd0;
                  s_par[2] <= 8'd0; s_par[3] <= 8'd0;
                end
                8'h1C: begin s_pending <= 1'b0; do_rev_index; end        // FS cursor up
                8'h1D: begin                                             // GS cursor home
                  s_pending  <= 1'b0;
                  cursor_row <= 8'd0;
                  cursor_col <= 8'd0;
                end
                default: ;  // NUL and anything else: dropped
              endcase

            end else begin
              case (p_state)

                //--------------------------------------------------------
                P_GROUND: begin
                  if (byte_data < 8'h7F) begin
                    if (s_pending) begin
                      s_pending  <= 1'b0;
                      cursor_col <= 8'd0;
                      s_wr_hold  <= 1'b1;
                      s_wr_char  <= byte_data;
                      do_index;
                    end else begin
                      put_char(byte_data);
                    end
                  end
                  // 0x7F DEL as a display byte, and 0x80-0xFF: dropped.
                end

                // P_DLE1/P_DLE2/P_DCS/P_DCS_ESC are handled in the
                // raw-byte-capture branch above, before this switch is
                // ever reached - they cannot appear here.

                //--------------------------------------------------------
                P_ESC: begin
                  p_state <= P_GROUND;
                  case (byte_data)
                    "[": p_state <= P_CSI;
                    "P": p_state <= P_DCS;             // DCS - see above
                    8'h20, "#", "(", ")", "*", "+", "%": begin
                      s_escint <= byte_data;
                      p_state  <= P_ESCINT;
                    end
                    "c": begin                          // RIS-equivalent full reset
                      reset_modes;
                      start_clear(8'd0, 8'd0, ROWS[7:0] - 8'd1, COLS[7:0] - 8'd1);
                    end
                    // NDSS1-9: bare "ESC <digit>" character-set designation
                    // (Verilog/Terminals/docs/SPEC-tdv2200.md) - NOT VT100's
                    // three-byte "ESC ( <final>". Only NDSS6 (Box) actually
                    // renders differently (font page 3, confirmed against a
                    // live SCONF capture 31-AUG-2026: cell 0x60 printed as a
                    // literal backtick instead of a top-left corner before
                    // this was implemented). Any other designation - incl.
                    // "1" back to plain ASCII - falls back to page 0, same
                    // conservative choice as an unimplemented VT100 charset.
                    "1", "2", "3", "4", "5", "6", "7", "8", "9": begin
                      s_g0_gfx <= (byte_data == "6");
                      if (byte_data == "6") dbg_saw_esc6 <= 1'b1;
                    end
                    // SS2 (ESC N): single-shift the NEXT character only
                    // through the graphics font - see s_ss2_armed's
                    // declaration for why this, not NDSS6, is PED's real
                    // box-drawing mechanism. SS3 (ESC O) would shift to
                    // G3/GraphicsII (circles/shapes) - no font page built
                    // for it yet, swallowed same as before (default arm).
                    "N": s_ss2_armed <= 1'b1;
                    // "Q" (exit/enable EC switch) and anything else
                    // unrecognised: swallowed.
                    default: ;
                  endcase
                end

                //--------------------------------------------------------
                // ESC + intermediate: "#" (double-height/width lines) and
                // "%" (ISO 646 national variant) are parsed and dropped -
                // deferred, no live capture has shown them used yet. "(" ")"
                // "*" "+" (VT100's G0-G3 designation prefixes) are consumed
                // the same way in case anything ever sends them, but they
                // are not how a TDV designates its own character sets (see
                // the NDSS digit case in P_ESC above) - a byte here never
                // leaks as garbage text either way.
                //--------------------------------------------------------
                P_ESCINT: begin
                  if (byte_data >= 8'h20 && byte_data <= 8'h2F) begin
                    s_escint <= byte_data;
                  end else begin
                    p_state <= P_GROUND;  // final byte consumed, nothing acted on
                  end
                end

                //--------------------------------------------------------
                P_CSI: begin
                  if (byte_data >= "0" && byte_data <= "9") begin
                    if (s_npar == 3'd0) begin
                      s_npar   <= 3'd1;
                      s_par[0] <= dig_acc(s_par[0], byte_data);
                    end else if (s_npar <= 3'd4) begin
                      s_par[s_npar[1:0] - 2'd1]
                        <= dig_acc(s_par[s_npar[1:0] - 2'd1], byte_data);
                    end
                  end else if (byte_data == ";") begin
                    if (s_npar == 3'd0) s_npar <= 3'd2;
                    else if (s_npar < 3'd4) s_npar <= s_npar + 3'd1;
                    else s_ign <= 1'b1;
                  end else if (byte_data >= 8'h3C && byte_data <= 8'h3F) begin
                    s_priv <= 1'b1;
                  end else if (byte_data >= 8'h20 && byte_data <= 8'h2F) begin
                    s_ign <= 1'b1;
                  end else if (byte_data >= 8'h40 && byte_data <= 8'h7E) begin
                    p_state <= P_GROUND;
                    if (!s_ign) dispatch_csi(byte_data);
                  end else begin
                    p_state <= P_GROUND;
                  end
                end

                default: p_state <= P_GROUND;

              endcase
            end
          end
        end

        //----------------------------------------------------------------
        default: s_state <= ST_RUN;

      endcase
    end
  end

endmodule

`default_nettype wire
