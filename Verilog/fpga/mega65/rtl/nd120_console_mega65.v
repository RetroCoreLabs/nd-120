//============================================================================
//! MEGA65 glue for the board-independent terminal core.
//!
//! Full path: Verilog/fpga/mega65/rtl/nd120_console_mega65.v
//!
//! The MEGA65 counterpart of fpga/mister/rtl/nd120_console_mister.v: the
//! terminal core in Verilog/Terminals/ is shared and unchanged, and this
//! file is the two ends that differ per board - where keystrokes come from
//! and where pixels go - plus the palette, because colour depth is a board
//! property.
//!
//! THE KEYBOARD END. MiSTer2MEGA65 gives the core a 1 kHz SCAN of the
//! MEGA65's 80 key numbers (key_num + key_pressed_n), not events, and the
//! keys are a C64 layout. m65_keys_to_ps2 turns that into PS/2 set-2
//! events whose codes type what the MEGA65 KEYCAPS say, so the shared
//! ps2_decoder_tdv (modifiers, caps, ctrl, Alt markers, the TDV
//! function/cursor keys) is reused as-is - the same decoder the MiSTer and
//! Nexys builds use. Then key_tdv2200 expands the TDV markers into their
//! ESC[nn_ sequences, exactly as on the other two boards.
//!
//! THE VIDEO END. The framework wants a pixel clock, a pixel enable, RGB
//! 8:8:8, syncs and SEPARATE hblank/vblank in the video clock domain, and
//! scales whatever it is given for HDMI while passing it straight out on
//! VGA. We hand it the terminal core at 640x480@60, one pixel per clock
//! (25.197 MHz, ce = 1). The WHOLE console - terminal, keyboard decoder,
//! UART bridge - runs on that one clock, exactly as on the other boards:
//! the terminal core carries its cursor/scroll state from its byte side to
//! its pixel side without a synchroniser, which is right only while the two
//! are one clock. The framework's key scan arrives from its 40 MHz domain;
//! m65_keys_to_ps2 samples a key only after 32 stable clocks, so that
//! crossing needs nothing else. hblank/vblank come from the terminal core.
//!
//! WHY 640x480 AND NOT THE 800x600 THE NEXYS AND MiSTer USE. The MEGA65 is
//! the one board whose HDMI goes through a frame-buffer rescaler in a slow
//! external memory: the framework's ascal stores every input pixel in the
//! 8-bit 100 MHz HyperRAM (~75 clocks per 128-byte burst) and reads it back
//! for the HDMI mode from the same chip. The rescaler's input buffer is two
//! 128-byte halves with no back-pressure, so a half must be drained within
//! ~151 clocks or the input overwrites it and that chunk is lost. 800x600 at
//! 40 Mpx/s x 24 bpp filled a half every 107 clocks: chunks were lost
//! whenever the output side was reading, which in 720p is nearly always -
//! the torn, colour-rotated picture the R6 tester filmed. 640x480 at
//! 25.2 Mpx/s with the rescaler storing 16 bpp (CORE/vhdl/framework-
//! overrides/digital_pipeline.vhd) fills a half every 254 clocks and loads
//! the chip ~45% in 720p60. Numbers and the comparison with the other M2M
//! cores: CORE/vhdl/clk.vhd and docs/00-plan.md.
//!
//! The 80x24 text (640x384) plus one blank row and the 5-row operator panel
//! (80 lines) is 480 lines exactly, so the grid starts on line 0 (ORIGIN_Y
//! 0 below); terminal_top's own centring would push the panel off the
//! bottom. Nothing in the shared terminal core changes - these are its
//! parameters.
//!
//! B1 (02-SEP-2026) has no ND-120 in it. `cpu_*` is wired but nothing
//! drives it: the banner prints, then the keyboard echoes locally. That
//! proves the framework flow, the clock, the video timing, the font, the
//! character RAM and the keyboard on a MEGA65 with NOTHING of the CPU able
//! to be blamed - and the MEGA65 is tested by friends, days per round
//! trip, so one thing at a time matters more here than anywhere.
//!
//! Written 02-SEP-2026.
//============================================================================

`default_nettype none

module nd120_console_mega65 #(
    //! Ignored since 02-SEP-2026: font_rom.v has the glyphs EMBEDDED
    //! (commit 4eb3220) - nothing is read from disk at synthesis. Kept so
    //! this glue instantiates terminal_top the same way the other boards do.
    parameter FONT_FILE = "embedded",

    //! B1: echo keystrokes to the screen so the console is testable with no
    //! machine behind it. B3 sets this to 0 - the ND-120 echoes, and doing
    //! both shows every character twice.
    parameter LOCAL_ECHO = 1
) (
    input wire clk,    //! the console clock = the pixel clock, 25.197 MHz for 640x480@60 (clk.vhd)
    input wire rst_n,  //! async reset, active low, release synchronised to clk

    //! The framework's keyboard scan (main_kb_key_num_i / _pressed_n_i)
    input wire [6:0] key_num,
    input wire       key_pressed_n,

    //! Console text colour, 0 green / 1 amber / 2 white / 3 cyan - an OSD
    //! option later; B1 ties it to green.
    input wire [1:0] text_colour,

    //! The machine seam. Bytes from the ND-120's console UART come in here;
    //! keystrokes go back out. Unused in B1.
    input  wire       cpu_byte_valid,  //! one clock per received byte (from console_uart_rx.byte_valid)
    input  wire [7:0] cpu_byte_data,
    output wire       cpu_byte_ready,

    //! Operator panel, threaded straight to terminal_top (see
    //! nd120_console_mister.v for the field meanings). B1: all constant 0.
    input wire        panel_enable,
    input wire [ 3:0] panel_pil,  //! Processor interrupt level (for debug capture) (from ND120_CORE.PIL)
    input wire [15:0] panel_actlv,  //! ACTIVE LEVEL word from the panel processor (from ND120_CORE.PANEL_ACTLV)
    input wire [15:0] panel_mips,
    input wire        panel_cpu_red,
    input wire        panel_cpu_green,
    input wire        panel_lev0,
    input wire        panel_hit,
    input wire [ 1:0] panel_ring,
    input wire        panel_paging_on,
    input wire        panel_interrupt_on,
    input wire        panel_running,
    input wire        panel_hdd_rd,
    input wire        panel_hdd_wr,
    input wire        panel_flp_rd,
    input wire        panel_flp_wr,

    //! Keystrokes to the machine, after the key_tdv2200 expander. kbd_ready
    //! is the console UART TX's idle flag; B1 ties it high.
    input  wire       kbd_ready,  //! high when idle (from console_uart_tx.ready)
    output wire       kbd_valid,  //! one clock; ignored unless ready (to console_uart_tx.byte_valid)
    output wire [7:0] kbd_data,

    //! Video, in the framework's shape. `de` is kept for testbenches.
    output wire [7:0] video_r,
    output wire [7:0] video_g,
    output wire [7:0] video_b,
    output wire       hsync,
    output wire       vsync,
    output wire       hblank,
    output wire       vblank,
    output wire       de,

    output wire bell
);

  //--------------------------------------------------------------------------
  // Keyboard: scan -> PS/2 events -> the shared decoder -> the TDV expander
  //--------------------------------------------------------------------------

  wire       s_code_valid;
  wire [7:0] s_code_data;
  wire       s_code_release;
  wire       s_code_extended;

  m65_keys_to_ps2 KEYS (
      .clk          (clk),
      .rst_n        (rst_n),
      .key_num      (key_num),
      .key_pressed_n(key_pressed_n),
      .code_valid   (s_code_valid),
      .code_data    (s_code_data),
      .code_release (s_code_release),
      .code_extended(s_code_extended)
  );

  wire       s_kbd_ascii_valid;
  wire [7:0] s_kbd_ascii_data;

  ps2_decoder_tdv DECODER (
      .clk  (clk),
      .rst_n(rst_n),

      .code_valid   (s_code_valid),
      .code_data    (s_code_data),
      .code_release (s_code_release),
      .code_extended(s_code_extended),

      //! US table, always: m65_keys_to_ps2 chooses its codes against the
      //! US column, and the MEGA65 keycaps are what they are regardless of
      //! the terminal's national font page.
      .layout_no(1'b0),

      .ascii_valid(s_kbd_ascii_valid),
      .ascii_data (s_kbd_ascii_data),

      .shift_active(),
      .ctrl_active (),
      .caps_active (),
      .alt_active  ()
  );

  key_tdv2200 KEYEXP (
      .clk      (clk),
      .rst_n    (rst_n),
      .key_valid(s_kbd_ascii_valid),
      .key_data (s_kbd_ascii_data),
      .out_valid(kbd_valid),
      .out_data (kbd_data),
      .out_ready(kbd_ready)
  );

  //--------------------------------------------------------------------------
  // What the screen is told to display: banner, then machine, then echo -
  // the priority lives in the shared term_console_feed.
  //--------------------------------------------------------------------------

  wire       s_term_ready;
  wire       s_src_valid;
  wire [7:0] s_src_data;

  term_console_feed FEED (
      .clk  (clk),
      .rst_n(rst_n),

      .cpu_valid(cpu_byte_valid),
      .cpu_data (cpu_byte_data),
      .cpu_ready(cpu_byte_ready),

      .echo_valid((LOCAL_ECHO != 0) && s_kbd_ascii_valid),
      .echo_data (s_kbd_ascii_data),

      .term_valid(s_src_valid),
      .term_data (s_src_data),
      .term_ready(s_term_ready),

      .banner_done()
  );

  //--------------------------------------------------------------------------
  // The shared terminal core
  //--------------------------------------------------------------------------

  wire [2:0] s_colour;

  terminal_top #(
      .FONT_FILE    (FONT_FILE),
      //! 640x480@60: 800 x 525 total, VESA 25.175 MHz (ours 25.197). The
      //! syncs stay POSITIVE (vga_timing's default): the framework's
      //! rescaler and video mixer want them so (m2m/doc/temp/
      //! VS-HS-Polarity.md); the HDMI mode's own polarity is made by the
      //! framework on the way out.
      .H_VISIBLE    (640),
      .H_FRONT_PORCH(16),
      .H_SYNC       (96),
      .H_BACK_PORCH (48),
      .V_VISIBLE    (480),
      .V_FRONT_PORCH(10),
      .V_SYNC       (2),
      .V_BACK_PORCH (33),
      //! 24 rows x 16 = 384 text lines, one blank row, then the 5-row panel
      //! (term_panel's origin is ORIGIN_Y + ROWS*CELL_H + CELL_H = 400) = 480.
      .ORIGIN_X     (0),
      .ORIGIN_Y     (0)
  ) TERMINAL (
      .byte_clk  (clk),
      .byte_rst_n(rst_n),
      .byte_valid(s_src_valid),
      .byte_data (s_src_data),
      .byte_ready(s_term_ready),

      .national (1'b0),
      .mode     (1'b0),

      .panel_enable      (panel_enable),
      .panel_pil         (panel_pil),
      .panel_actlv       (panel_actlv),
      .panel_mips        (panel_mips),
      .panel_cpu_red     (panel_cpu_red),
      .panel_cpu_green   (panel_cpu_green),
      .panel_lev0        (panel_lev0),
      .panel_hit         (panel_hit),
      .panel_ring        (panel_ring),
      .panel_paging_on   (panel_paging_on),
      .panel_interrupt_on(panel_interrupt_on),
      .panel_running     (panel_running),
      .panel_hdd_rd      (panel_hdd_rd),
      .panel_hdd_wr      (panel_hdd_wr),
      .panel_flp_rd      (panel_flp_rd),
      .panel_flp_wr      (panel_flp_wr),

      .colour   (s_colour),

      .pix_clk  (clk),
      .pix_rst_n(rst_n),
      .pixel    (),        // `colour` already says ink/paper - see the palette
      .hsync    (hsync),
      .vsync    (vsync),
      .de       (de),
      .hblank   (hblank),
      .vblank   (vblank),

      .bell(bell),
      .leds(),
      .dbg_box_mode(),
      .dbg_saw_esc6()
  );

  //--------------------------------------------------------------------------
  // Palette: the core says WHICH of eight things a pixel is; the board picks
  // the colour. Same values as the MiSTer build (nd120.sv), whose panel
  // colours were sampled from a photograph of the real folio panel.
  //--------------------------------------------------------------------------

  reg [23:0] s_text_rgb;
  always @(*) begin
    case (text_colour)
      2'd0:    s_text_rgb = 24'h00FF00;  // green - the Tandberg default
      2'd1:    s_text_rgb = 24'hFFBF00;  // amber
      2'd2:    s_text_rgb = 24'hFFFFFF;  // white
      default: s_text_rgb = 24'h00FFFF;  // cyan
    endcase
  end

  reg [23:0] s_rgb;
  always @(*) begin
    case (s_colour)
      3'd0:    s_rgb = 24'h000000;   // black
      3'd1:    s_rgb = s_text_rgb;   // console text
      3'd2:    s_rgb = 24'h191b19;   // panel fascia
      3'd3:    s_rgb = 24'hd6d9d2;   // silkscreen
      3'd4:    s_rgb = 24'hb6c2a4;   // LCD ground
      3'd5:    s_rgb = 24'h2a3226;   // LCD segment
      3'd6:    s_rgb = 24'he04a63;   // lit legend
      default: s_rgb = 24'h444444;   // unlit legend
    endcase
  end

  assign video_r = de ? s_rgb[23:16] : 8'h00;
  assign video_g = de ? s_rgb[15:8]  : 8'h00;
  assign video_b = de ? s_rgb[7:0]   : 8'h00;

endmodule

`default_nettype wire
