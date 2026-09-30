//============================================================================
//! MEGA65 keyboard scan -> PS/2 set-2 key events for the shared terminal
//! decoder.
//!
//! Full path: Verilog/fpga/mega65/rtl/m65_keys_to_ps2.v
//!
//! WHAT THE FRAMEWORK GIVES US. MiSTer2MEGA65 hands the core a scan, not
//! events: `key_num` cycles 0..79 at 1 kHz (matrix_to_keynum.vhdl,
//! scan_frequency 1000 - each key is presented for clock/(72*1000) cycles,
//! ~555 clocks at 40 MHz) and `key_pressed_n` says, debounced and active
//! low, whether THAT key is down right now. The key numbers are the
//! MEGA65's own (CORE/vhdl/keyboard.vhd in the framework template lists all
//! 76 of them; 0 = INST/DEL ... 75 = RESTORE).
//!
//! WHAT THE TERMINAL WANTS. The shared decoder ps2_decoder_tdv.v takes PS/2
//! scancode-set-2 events: {code, release, extended}, and does everything
//! that is hard about a keyboard - shift, control, caps, Alt markers, the
//! TDV function/cursor keys, the ESC[nn_ family. None of that should exist
//! twice. So this module translates the MEGA65's keys INTO PS/2 events and
//! the decoder is reused unchanged, exactly as the MiSTer glue reuses it on
//! hps_io's events.
//!
//! THE ONE REAL PROBLEM: THE KEYCAPS. The MEGA65 keyboard is a C64 layout.
//! Its symbol pairs are not the PS/2 US pairs the decoder's table knows:
//! shift-2 is `"` (PS/2: `@`), shift-6 is `&` (PS/2: `^`), shift-7 is `'`,
//! shift-8 is `(`, shift-9 is `)`, and `:` `;` `@` `*` `+` `-` `=` are
//! keys of their own with `[` `]` on the shifted `:` `;`. A plain
//! key-to-code table would type what the PS/2 keycap says, not what the
//! MEGA65 keycap says, and the person testing this is looking at the
//! MEGA65 keycaps.
//!
//! So every key carries TWO targets, one per MEGA65 keycap legend
//! (unshifted / shifted), and each target says which PS/2 code produces
//! that character AND what the decoder's shift state must be while it does.
//! Where the decoder's shift state must differ from what the user is
//! physically holding, a synthetic LEFT-SHIFT press or release is sent
//! first, then the key, then the real state is restored. Example: the `:`
//! key unshifted must type `:`, which on PS/2 is shift+`;` (0x4C) - so
//! this sends SHIFT-down, 0x4C, SHIFT-up. Shift+`:` must type `[`, PS/2
//! 0x54 UNshifted - so with the user holding shift this sends SHIFT-up,
//! 0x54, SHIFT-down. Letters, digits with matching pairs, `,` `.` `/`
//! `1` `3` `4` `5` simply pass the user's shift state through, so caps lock
//! and shift behave inside the decoder as they always did.
//!
//! RELEASES. ps2_decoder_tdv acts on releases ONLY for the modifier keys
//! (shift, ctrl, alt); for every other key a release is ignored. So this
//! module sends releases for modifiers and nothing for the rest - fewer
//! events, and no per-key memory of which code was sent at press time.
//!
//! CAPS LOCK is a mechanically LATCHING key on the MEGA65: `key_pressed_n`
//! is low for as long as it is locked. The decoder TOGGLES its caps state
//! on every caps PRESS and ignores the release. So a press event is sent on
//! BOTH transitions of the key - lock and unlock each toggle once - and the
//! decoder's caps state tracks the physical latch.
//!
//! NOT DONE (02-SEP-2026): key repeat. PS/2 keyboards repeat by themselves
//! (typematic); the MEGA65 scan does not, so holding a key types it once.
//! Fine for a console; write it here if it is ever wanted.
//!
//! RUN/STOP is EXIT (04-SEP-2026, Ronny): the TDV2200's SLUTT key, ESC[48_,
//! the way out of a SINTRAN program - sent as the PC End key, which the
//! shared table already maps to SLUTT. The C64 keycap that means "stop this
//! program" is the right one for it; the framework only claims RUN/STOP
//! while its menu is open (m2m_keyb.vhd enable_core_i), and then the core
//! sees no keys at all. Alt+X reaches SLUTT too, through the decoder's Alt
//! map - proven on this path by the testbench.
//!
//! Keys with no terminal meaning (MEGA, NO SCROLL, RESTORE, F13,
//! shifted CLR/HOME) send nothing. Choices that are ours, not a standard,
//! are marked "(choice)" in the table.
//!
//! Written 02-SEP-2026.
//============================================================================

`default_nettype none

module m65_keys_to_ps2 (
    input wire clk,                  //! pixel clock, 40.000 MHz for 800x600@60 (from nd120_console_mega65.clk)
    input wire rst_n,  //! async reset, active low

    //! The framework's scan, in this clock domain.
    input wire [6:0] key_num,        //! 0..79
    input wire       key_pressed_n,  //! 0 = key `key_num` is down (debounced)

    //! To ps2_decoder_tdv. One event per clock at most.
    output reg       code_valid,     //! strobe, one clock (to ps2_decoder_tdv.code_valid)
    output reg [7:0] code_data,      //! the scancode itself (to ps2_decoder_tdv.code_data)
    output reg       code_release,   //! this was a key RELEASE (F0 seen) (to ps2_decoder_tdv.code_release)
    output reg       code_extended   //! this had the E0 prefix (to ps2_decoder_tdv.code_extended)
);

  //--------------------------------------------------------------------------
  // PS/2 set-2 codes the decoder recognises (ps2_decoder_tdv.v localparams)
  //--------------------------------------------------------------------------
  localparam [7:0] SC_LSHIFT = 8'h12;
  localparam [7:0] SC_CTRL   = 8'h14;
  localparam [7:0] SC_CAPS   = 8'h58;
  localparam [7:0] SC_ALT    = 8'h11;

  // MEGA65 key numbers that are modifiers here
  localparam [6:0] K_LSHIFT = 7'd15;
  localparam [6:0] K_RSHIFT = 7'd52;
  localparam [6:0] K_CTRL   = 7'd58;
  localparam [6:0] K_ALT    = 7'd66;
  localparam [6:0] K_CAPS   = 7'd72;

  // Shift requirement of a target: what the decoder's shift state must be
  // while the code is delivered.
  localparam [1:0] SH_OFF  = 2'b00;  // force the decoder's shift OFF
  localparam [1:0] SH_ON   = 2'b01;  // force it ON
  localparam [1:0] SH_PASS = 2'b10;  // whatever the user is holding

  //--------------------------------------------------------------------------
  // The keycap table. One entry per MEGA65 key, two targets each:
  //   {code[7:0], extended, shift_req[1:0]} for the unshifted legend,
  //   the same for the shifted legend. code 0x00 = this legend sends nothing.
  //--------------------------------------------------------------------------
  function [21:0] keymap;
    input [6:0] k;
    reg [10:0] u;  // unshifted target
    reg [10:0] s;  // shifted target
    begin
      u = {8'h00, 1'b0, SH_PASS};
      s = {8'h00, 1'b0, SH_PASS};
      case (k)
        // --- top row ---------------------------------------------------
        7'd57: begin u = {8'h4E, 1'b0, SH_ON};   s = u; end                       // left-arrow key -> '_' (choice)
        7'd56: begin u = {8'h16, 1'b0, SH_PASS}; s = u; end                       // 1 !
        7'd59: begin u = {8'h1E, 1'b0, SH_OFF};  s = {8'h52, 1'b0, SH_ON}; end    // 2 "
        7'd8:  begin u = {8'h26, 1'b0, SH_PASS}; s = u; end                       // 3 #
        7'd11: begin u = {8'h25, 1'b0, SH_PASS}; s = u; end                       // 4 $
        7'd16: begin u = {8'h2E, 1'b0, SH_PASS}; s = u; end                       // 5 %
        7'd19: begin u = {8'h36, 1'b0, SH_OFF};  s = {8'h3D, 1'b0, SH_ON}; end    // 6 &
        7'd24: begin u = {8'h3D, 1'b0, SH_OFF};  s = {8'h52, 1'b0, SH_OFF}; end   // 7 '
        7'd27: begin u = {8'h3E, 1'b0, SH_OFF};  s = {8'h46, 1'b0, SH_ON}; end    // 8 (
        7'd32: begin u = {8'h46, 1'b0, SH_OFF};  s = {8'h45, 1'b0, SH_ON}; end    // 9 )
        7'd35: begin u = {8'h45, 1'b0, SH_OFF};  s = u; end                       // 0 (shift-0 also 0)
        7'd40: begin u = {8'h55, 1'b0, SH_ON};   s = u; end                       // +
        7'd43: begin u = {8'h4E, 1'b0, SH_OFF};  s = u; end                       // -
        7'd48: begin u = {8'h5D, 1'b0, SH_OFF};  s = u; end                       // pound -> '\' (choice)
        7'd51: begin u = {8'h6C, 1'b1, SH_PASS}; s = {8'h00, 1'b0, SH_PASS}; end  // CLR/HOME: Home; CLR sends nothing
        7'd0:  begin u = {8'h66, 1'b0, SH_PASS}; s = {8'h70, 1'b1, SH_PASS}; end  // INST/DEL: Backspace(->DEL); shift = Insert
        // --- second row ------------------------------------------------
        7'd62: begin u = {8'h15, 1'b0, SH_PASS}; s = u; end  // q
        7'd9:  begin u = {8'h1D, 1'b0, SH_PASS}; s = u; end  // w
        7'd14: begin u = {8'h24, 1'b0, SH_PASS}; s = u; end  // e
        7'd17: begin u = {8'h2D, 1'b0, SH_PASS}; s = u; end  // r
        7'd22: begin u = {8'h2C, 1'b0, SH_PASS}; s = u; end  // t
        7'd25: begin u = {8'h35, 1'b0, SH_PASS}; s = u; end  // y
        7'd30: begin u = {8'h3C, 1'b0, SH_PASS}; s = u; end  // u
        7'd33: begin u = {8'h43, 1'b0, SH_PASS}; s = u; end  // i
        7'd38: begin u = {8'h44, 1'b0, SH_PASS}; s = u; end  // o
        7'd41: begin u = {8'h4D, 1'b0, SH_PASS}; s = u; end  // p
        7'd46: begin u = {8'h1E, 1'b0, SH_ON};   s = u; end  // @
        7'd49: begin u = {8'h3E, 1'b0, SH_ON};   s = u; end  // *
        7'd54: begin u = {8'h36, 1'b0, SH_ON};   s = u; end  // up-arrow key -> '^' (choice)
        // --- third row -------------------------------------------------
        7'd10: begin u = {8'h1C, 1'b0, SH_PASS}; s = u; end  // a
        7'd13: begin u = {8'h1B, 1'b0, SH_PASS}; s = u; end  // s
        7'd18: begin u = {8'h23, 1'b0, SH_PASS}; s = u; end  // d
        7'd21: begin u = {8'h2B, 1'b0, SH_PASS}; s = u; end  // f
        7'd26: begin u = {8'h34, 1'b0, SH_PASS}; s = u; end  // g
        7'd29: begin u = {8'h33, 1'b0, SH_PASS}; s = u; end  // h
        7'd34: begin u = {8'h3B, 1'b0, SH_PASS}; s = u; end  // j
        7'd37: begin u = {8'h42, 1'b0, SH_PASS}; s = u; end  // k
        7'd42: begin u = {8'h4B, 1'b0, SH_PASS}; s = u; end  // l
        7'd45: begin u = {8'h4C, 1'b0, SH_ON};   s = {8'h54, 1'b0, SH_OFF}; end  // : [
        7'd50: begin u = {8'h4C, 1'b0, SH_OFF};  s = {8'h5B, 1'b0, SH_OFF}; end  // ; ]
        7'd53: begin u = {8'h55, 1'b0, SH_OFF};  s = u; end                      // =
        7'd1:  begin u = {8'h5A, 1'b0, SH_PASS}; s = u; end                      // RETURN
        // --- bottom row ------------------------------------------------
        7'd12: begin u = {8'h1A, 1'b0, SH_PASS}; s = u; end  // z
        7'd23: begin u = {8'h22, 1'b0, SH_PASS}; s = u; end  // x
        7'd20: begin u = {8'h21, 1'b0, SH_PASS}; s = u; end  // c
        7'd31: begin u = {8'h2A, 1'b0, SH_PASS}; s = u; end  // v
        7'd28: begin u = {8'h32, 1'b0, SH_PASS}; s = u; end  // b
        7'd39: begin u = {8'h31, 1'b0, SH_PASS}; s = u; end  // n
        7'd36: begin u = {8'h3A, 1'b0, SH_PASS}; s = u; end  // m
        7'd47: begin u = {8'h41, 1'b0, SH_PASS}; s = u; end  // , <
        7'd44: begin u = {8'h49, 1'b0, SH_PASS}; s = u; end  // . >
        7'd55: begin u = {8'h4A, 1'b0, SH_PASS}; s = u; end  // / ?
        7'd60: begin u = {8'h29, 1'b0, SH_PASS}; s = u; end  // SPACE
        // --- cursor keys -----------------------------------------------
        7'd2:  begin u = {8'h74, 1'b1, SH_PASS}; s = {8'h6B, 1'b1, SH_PASS}; end  // C64 horizontal: Right, shift = Left
        7'd7:  begin u = {8'h72, 1'b1, SH_PASS}; s = {8'h75, 1'b1, SH_PASS}; end  // C64 vertical: Down, shift = Up
        7'd73: begin u = {8'h75, 1'b1, SH_PASS}; s = u; end                       // dedicated Up
        7'd74: begin u = {8'h6B, 1'b1, SH_PASS}; s = u; end                       // dedicated Left
        // --- function keys: the C64 pairs, shift = the even one --------
        // The decoder's own shift means "shifted F-key" (ESC[nn+1_), which
        // is not what the keycap says, so the decoder's shift is forced OFF
        // and the even key's own code is sent instead.
        7'd4:  begin u = {8'h05, 1'b0, SH_OFF}; s = {8'h06, 1'b0, SH_OFF}; end  // F1 / F2
        7'd5:  begin u = {8'h04, 1'b0, SH_OFF}; s = {8'h0C, 1'b0, SH_OFF}; end  // F3 / F4
        7'd6:  begin u = {8'h03, 1'b0, SH_OFF}; s = {8'h0B, 1'b0, SH_OFF}; end  // F5 / F6
        7'd3:  begin u = {8'h83, 1'b0, SH_OFF}; s = {8'h0A, 1'b0, SH_OFF}; end  // F7 / F8
        7'd68: begin u = {8'h01, 1'b0, SH_OFF}; s = {8'h09, 1'b0, SH_OFF}; end  // F9 / F10 -> HJELP / FUNK (the TDV table's F9/F10)
        7'd69: begin u = {8'h78, 1'b0, SH_OFF}; s = {8'h07, 1'b0, SH_OFF}; end  // F11 / F12 -> SKRIV / ANGRE
        7'd67: begin u = {8'h01, 1'b0, SH_OFF}; s = u; end                      // HELP -> HJELP, same as F9 (choice)
        // --- the MEGA65 extras -----------------------------------------
        7'd65: begin u = {8'h0D, 1'b0, SH_PASS}; s = u; end  // TAB
        7'd71: begin u = {8'h76, 1'b0, SH_PASS}; s = u; end  // ESC
        // RUN/STOP -> End (E0 69) -> SLUTT/EXIT ESC[48_. Shift forced OFF so
        // a held shift cannot turn it into the shifted variant ESC[49_.
        7'd63: begin u = {8'h69, 1'b1, SH_OFF};  s = u; end  // RUN/STOP -> EXIT (SLUTT)
        // 61 MEGA, 64 NO SCROLL, 70 F13/F14, 75 RESTORE: nothing.
        // 15/52 shift, 58 ctrl, 66 alt, 72 caps lock: modifiers, handled below.
        default: begin end
      endcase
      keymap = {u, s};
    end
  endfunction

  //--------------------------------------------------------------------------
  // Scan sampling: a key is looked at once per dwell, after `key_num` has
  // held still for 32 clocks, so the framework's own settling of
  // `key_pressed_n` behind `key_num` (a RAM read or two) never matters.
  //--------------------------------------------------------------------------
  reg  [6:0] s_num_d;
  reg  [5:0] s_stable;
  wire       s_sample = (s_stable == 6'd32);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s_num_d  <= 7'd0;
      s_stable <= 6'd0;
    end else begin
      s_num_d <= key_num;
      if (key_num != s_num_d)       s_stable <= 6'd0;
      else if (s_stable != 6'd63)   s_stable <= s_stable + 6'd1;
    end
  end

  //! Physical state of every key, 1 = down.
  reg [79:0] s_down;
  wire       s_pressed_now = ~key_pressed_n;
  wire       s_was_down    = s_down[key_num];
  wire       s_press_evt   = s_sample &&  s_pressed_now && !s_was_down;
  wire       s_release_evt = s_sample && !s_pressed_now &&  s_was_down;

  wire s_m65_shift = s_down[K_LSHIFT] | s_down[K_RSHIFT];

  //--------------------------------------------------------------------------
  // Event sequencer. At most three PS/2 events per MEGA65 event, one per
  // clock: [synthetic shift] key [restore shift]. The next key of the scan
  // is hundreds of clocks away, so no queue is needed.
  //--------------------------------------------------------------------------
  reg        s_dec_shift;   //! the shift state the DECODER currently believes

  reg [1:0]  s_step;        //! 0 idle, 1..3 = event slots
  reg [10:0] s_ev1, s_ev2, s_ev3;  //! {code, extended, release, valid} - see below
  // slot layout: [10:3] code, [2] extended, [1] release, [0] valid

  // The key's target for the legend the user is holding
  wire [21:0] s_map    = keymap(key_num);
  wire [10:0] s_target = s_m65_shift ? s_map[10:0] : s_map[21:11];
  wire [7:0]  s_t_code = s_target[10:3];
  wire        s_t_ext  = s_target[2];
  wire [1:0]  s_t_req  = s_target[1:0];
  wire        s_t_want = (s_t_req == SH_PASS) ? s_m65_shift : s_t_req[0];

  wire s_is_shift = (key_num == K_LSHIFT) || (key_num == K_RSHIFT);
  wire s_is_ctrl  = (key_num == K_CTRL);
  wire s_is_alt   = (key_num == K_ALT);
  wire s_is_caps  = (key_num == K_CAPS);

  //! Shift state the user will be holding AFTER this event is applied
  //! (needed for a shift key's own transition).
  wire s_m65_shift_next = s_is_shift ? ((s_press_evt) ? 1'b1
                                        : ((key_num == K_LSHIFT) ? s_down[K_RSHIFT] : s_down[K_LSHIFT]))
                                     : s_m65_shift;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s_down        <= 80'd0;
      s_dec_shift   <= 1'b0;
      s_step        <= 2'd0;
      s_ev1         <= 11'd0;
      s_ev2         <= 11'd0;
      s_ev3         <= 11'd0;
      code_valid    <= 1'b0;
      code_data     <= 8'h00;
      code_release  <= 1'b0;
      code_extended <= 1'b0;
    end else begin
      code_valid <= 1'b0;

      if (s_step != 2'd0) begin
        // deliver the queued slots in order, skipping empty ones
        case (s_step)
          2'd1: begin
            if (s_ev1[0]) begin
              code_valid <= 1'b1; code_data <= s_ev1[10:3]; code_extended <= s_ev1[2]; code_release <= s_ev1[1];
            end
            s_step <= 2'd2;
          end
          2'd2: begin
            if (s_ev2[0]) begin
              code_valid <= 1'b1; code_data <= s_ev2[10:3]; code_extended <= s_ev2[2]; code_release <= s_ev2[1];
            end
            s_step <= 2'd3;
          end
          default: begin
            if (s_ev3[0]) begin
              code_valid <= 1'b1; code_data <= s_ev3[10:3]; code_extended <= s_ev3[2]; code_release <= s_ev3[1];
            end
            s_step <= 2'd0;
          end
        endcase
      end else if (s_press_evt || s_release_evt) begin
        s_down[key_num] <= s_press_evt;
        s_ev1 <= 11'd0;
        s_ev2 <= 11'd0;
        s_ev3 <= 11'd0;

        if (s_is_shift) begin
          // Keep the decoder's shift equal to what the user holds. Two
          // shift keys: only the transition that changes the OR matters.
          if (s_dec_shift != s_m65_shift_next) begin
            s_ev1       <= {SC_LSHIFT, 1'b0, ~s_m65_shift_next, 1'b1};
            s_dec_shift <= s_m65_shift_next;
            s_step      <= 2'd1;
          end
        end else if (s_is_ctrl) begin
          s_ev1  <= {SC_CTRL, 1'b0, s_release_evt, 1'b1};
          s_step <= 2'd1;
        end else if (s_is_alt) begin
          s_ev1  <= {SC_ALT, 1'b0, s_release_evt, 1'b1};
          s_step <= 2'd1;
        end else if (s_is_caps) begin
          // latching key: every transition is one toggle for the decoder
          s_ev1  <= {SC_CAPS, 1'b0, 1'b0, 1'b1};
          s_step <= 2'd1;
        end else if (s_press_evt && s_t_code != 8'h00) begin
          // [set the decoder's shift for this legend] key [restore]
          if (s_dec_shift != s_t_want)
            s_ev1 <= {SC_LSHIFT, 1'b0, ~s_t_want, 1'b1};
          s_ev2 <= {s_t_code, s_t_ext, 1'b0, 1'b1};
          if (s_t_want != s_m65_shift)
            s_ev3 <= {SC_LSHIFT, 1'b0, ~s_m65_shift, 1'b1};
          s_dec_shift <= s_m65_shift;  // where it ends up after slot 3
          s_step      <= 2'd1;
        end
        // releases of ordinary keys: nothing to send
      end
    end
  end

endmodule

`default_nettype wire
