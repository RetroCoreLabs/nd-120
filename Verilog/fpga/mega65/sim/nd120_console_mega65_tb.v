//============================================================================
//! Self-checking testbench for nd120_console_mega65.v - the MEGA65 glue
//!
//! Full path: Verilog/fpga/mega65/sim/nd120_console_mega65_tb.v
//!
//! The terminal core is tested in Verilog/Terminals/sim/, the keyboard
//! translator in m65_keys_to_ps2_tb.v. What is tested HERE is the glue that
//! joins them to the MiSTer2MEGA65 framework's contract, because every line
//! of it fails in a way that looks plausible on a screen:
//!
//!   * the scan-to-screen path end to end: a MEGA65 key number pressed the
//!     framework's way must put its character on the screen (local echo)
//!     and on the machine seam, and a release must do nothing;
//!   * the banner/seam priority (the seam is shut while the banner owns the
//!     screen, opens promptly after);
//!   * the VIDEO SHAPE the framework consumes: hblank and vblank must be
//!     the two halves of de (de == !(hblank|vblank)) over a whole frame,
//!     and RGB must be black outside de - the framework's analog path
//!     rebuilds de from the blanks, so a blank that disagrees with de
//!     shows up as a shifted or torn picture on VGA only, which a friend
//!     with an HDMI monitor would never see.
//!
//! The screen is inspected by reading the character RAM directly through
//! the hierarchy - the terminal's actual state.
//!
//! Prints "TB_RESULT: PASS" or "TB_RESULT: FAIL".
//!
//! Written 02-SEP-2026.
//============================================================================

`timescale 1ns / 1ps
`default_nettype none

module nd120_console_mega65_tb;

  localparam integer COLS  = 80;
  localparam integer DWELL = 64;   //! clocks per key in the modelled scan

  reg clk = 1'b0;
  reg rst_n = 1'b0;
  always #19.84 clk = ~clk;   // 25.197 MHz: the console clock = the pixel clock (clk.vhd CLKOUT0)

  reg [6:0]  key_num = 7'd0;
  reg        key_pressed_n = 1'b1;
  reg [79:0] down = 80'd0;

  wire       cpu_ready;
  wire       kbd_valid;
  wire [7:0] kbd_data;
  wire [7:0] video_r, video_g, video_b;
  wire       hsync, vsync, hblank, vblank, de, bell;

  //! Console UART TX ready, modelled as in the MiSTer tb: idle high, busy
  //! for 40 clocks after accepting a byte.
  reg  [7:0] s_kbd_busy = 8'd0;
  wire       kbd_ready = (s_kbd_busy == 8'd0);
  always @(posedge clk) begin
    if (s_kbd_busy != 8'd0)   s_kbd_busy <= s_kbd_busy - 8'd1;
    else if (kbd_valid)       s_kbd_busy <= 8'd40;
  end

  nd120_console_mega65 #(
      .FONT_FILE ("../../../Terminals/font/font8x16.hex"),
      .LOCAL_ECHO(1)
  ) DUT (
      .clk  (clk),
      .rst_n(rst_n),

      .key_num      (key_num),
      .key_pressed_n(key_pressed_n),
      .text_colour  (2'd0),

      .cpu_byte_valid(1'b0),
      .cpu_byte_data (8'h00),
      .cpu_byte_ready(cpu_ready),

      .panel_enable      (1'b0),
      .panel_pil         (4'd0),
      .panel_actlv       (16'd0),
      .panel_mips        (16'd0),
      .panel_cpu_red     (1'b0),
      .panel_cpu_green   (1'b0),
      .panel_lev0        (1'b0),
      .panel_hit         (1'b0),
      .panel_ring        (2'd0),
      .panel_paging_on   (1'b0),
      .panel_interrupt_on(1'b0),
      .panel_running     (1'b0),
      .panel_hdd_rd      (1'b0),
      .panel_hdd_wr      (1'b0),
      .panel_flp_rd      (1'b0),
      .panel_flp_wr      (1'b0),

      .kbd_ready(kbd_ready),
      .kbd_valid(kbd_valid),
      .kbd_data (kbd_data),

      .video_r(video_r),
      .video_g(video_g),
      .video_b(video_b),
      .hsync  (hsync),
      .vsync  (vsync),
      .hblank (hblank),
      .vblank (vblank),
      .de     (de),
      .bell   (bell)
  );

  integer errors = 0;
  integer i;
  reg [7:0] got;

  //! Every byte the machine seam receives, for the multi-byte key checks.
  reg [7:0] seam [0:15];
  integer   nseam = 0;
  always @(posedge clk) begin
    if (kbd_valid && kbd_ready) begin
      if (nseam < 16) seam[nseam] <= kbd_data;
      nseam <= nseam + 1;
    end
  end

  //! Expect exactly ESC [ 4 8 _ (the TDV2200's SLUTT/EXIT key) since the
  //! last clear of the seam log.
  task expect_exit;
    input [8*40-1:0] what;
    begin
      if (nseam != 5 || seam[0] !== 8'h1B || seam[1] !== "[" ||
          seam[2] !== "4" || seam[3] !== "8" || seam[4] !== "_") begin
        $display("FAIL: %0s: expected ESC [ 4 8 _ on the machine seam, got %0d byte(s): %02x %02x %02x %02x %02x",
                 what, nseam, seam[0], seam[1], seam[2], seam[3], seam[4]);
        errors = errors + 1;
      end else begin
        $display("-- %0s -> ESC [ 4 8 _ (SLUTT/EXIT)", what);
      end
      nseam = 0;
    end
  endtask

  //! One sweep of the keyboard, the framework's way.
  task sweep;
    integer k;
    begin
      for (k = 0; k < 80; k = k + 1) begin
        @(negedge clk);
        key_num       = k[6:0];
        key_pressed_n = ~down[k];
        repeat (DWELL - 1) @(negedge clk);
      end
    end
  endtask

  function [7:0] screen_char;
    input integer c;
    begin
      screen_char = DUT.TERMINAL.CHARRAM.s_cells[c][7:0];
    end
  endfunction

  //--------------------------------------------------------------------------
  // Video shape checks, running all the time
  //--------------------------------------------------------------------------
  integer  v_samples = 0;
  integer  v_de_shape_errs = 0;
  integer  v_rgb_errs = 0;
  integer  v_de_count = 0;
  integer  v_green_count = 0;

  always @(posedge clk) begin
    if (rst_n) begin
      v_samples <= v_samples + 1;
      if (de !== ~(hblank | vblank)) v_de_shape_errs <= v_de_shape_errs + 1;
      if (!de && (video_r !== 8'h00 || video_g !== 8'h00 || video_b !== 8'h00))
        v_rgb_errs <= v_rgb_errs + 1;
      if (de) v_de_count <= v_de_count + 1;
      if (de && video_g == 8'hFF && video_r == 8'h00 && video_b == 8'h00)
        v_green_count <= v_green_count + 1;
    end
  end

  initial begin
    $dumpfile("nd120_console_mega65_tb.vcd");
    $dumpvars(1, nd120_console_mega65_tb);

    repeat (4) @(posedge clk);
    rst_n = 1'b1;

    //------------------------------------------------------------------
    // 1. The machine seam is shut while the banner owns the screen.
    //------------------------------------------------------------------
    @(negedge clk);
    if (cpu_ready !== 1'b0) begin
      $display("FAIL: cpu_byte_ready is high during the banner");
      errors = errors + 1;
    end else begin
      $display("-- machine seam held closed while the banner runs");
    end

    //------------------------------------------------------------------
    // 2. Let the banner finish, check it is intact.
    //------------------------------------------------------------------
    i = 0;
    while (!DUT.FEED.BANNER.done && i < 200000) begin
      @(posedge clk);
      i = i + 1;
    end
    if (!DUT.FEED.BANNER.done) begin
      $display("FAIL: the banner never finished");
      errors = errors + 1;
    end
    if (screen_char(0) !== "N" || screen_char(1) !== "D" ||
        screen_char(2) !== "-" || screen_char(3) !== "1") begin
      $display("FAIL: row 0 starts %c%c%c%c, expected ND-1",
               screen_char(0), screen_char(1), screen_char(2), screen_char(3));
      errors = errors + 1;
    end else begin
      $display("-- banner intact on screen");
    end

    //------------------------------------------------------------------
    // 3. The seam opens promptly after the banner.
    //------------------------------------------------------------------
    i = 0;
    while (!cpu_ready && i < 100) begin
      @(posedge clk);
      i = i + 1;
    end
    if (!cpu_ready) begin
      $display("FAIL: cpu_byte_ready still low 100 clocks after the banner");
      errors = errors + 1;
    end else begin
      $display("-- machine seam open %0d clocks after the banner finished", i);
    end

    //------------------------------------------------------------------
    // 4. A key pressed the framework's way reaches the machine seam once.
    //    'q' (key 62), because the banner contains no 'q'.
    //------------------------------------------------------------------
    got = 8'h00;
    fork
      begin : catch_press
        @(posedge clk);
        while (!kbd_valid) @(posedge clk);
        got = kbd_data;
      end
      begin
        down[62] = 1'b1;
        sweep();
        disable catch_press;
      end
    join
    if (got !== "q") begin
      $display("FAIL: pressing MEGA65 key 62 gave 0x%02X to the machine, expected 'q'", got);
      errors = errors + 1;
    end else begin
      $display("-- a key PRESS produces its character on the machine seam");
    end

    //------------------------------------------------------------------
    // 5. Its release produces nothing.
    //------------------------------------------------------------------
    got = 8'hFF;
    fork
      begin : catch_release
        @(posedge clk);
        while (!kbd_valid) @(posedge clk);
        got = kbd_data;
      end
      begin
        down[62] = 1'b0;
        sweep();
        disable catch_release;
      end
    join
    if (got !== 8'hFF) begin
      $display("FAIL: a key RELEASE produced 0x%02X - releases must be silent", got);
      errors = errors + 1;
    end else begin
      $display("-- a key RELEASE produces nothing");
    end

    //------------------------------------------------------------------
    // 6. Local echo reached the screen: search for the 'q'.
    //------------------------------------------------------------------
    repeat (200) @(posedge clk);
    begin : find_q
      integer r, c;
      reg found;
      found = 1'b0;
      for (r = 0; r < 25 && !found; r = r + 1)
        for (c = 0; c < COLS && !found; c = c + 1)
          if (DUT.TERMINAL.CHARRAM.s_cells[r*COLS + c][7:0] === "q") begin
            found = 1'b1;
            $display("-- local echo: 'q' found on screen at row %0d col %0d", r, c);
          end
      if (!found) begin
        $display("FAIL: the typed 'q' never reached the screen - local echo is broken");
        errors = errors + 1;
      end
    end

    //------------------------------------------------------------------
    // 7. A shifted C64 legend through the whole glue: shift + ':' = '['.
    //------------------------------------------------------------------
    got = 8'h00;
    down[15] = 1'b1;    // left shift
    sweep();
    fork
      begin : catch_bracket
        @(posedge clk);
        while (!kbd_valid) @(posedge clk);
        got = kbd_data;
      end
      begin
        down[45] = 1'b1;   // ':' key
        sweep();
        disable catch_bracket;
      end
    join
    down[45] = 1'b0; down[15] = 1'b0;
    sweep();
    if (got !== "[") begin
      $display("FAIL: shift + colon key gave 0x%02X, expected '[' (the MEGA65 keycap)", got);
      errors = errors + 1;
    end else begin
      $display("-- shift + colon key types '[' as the keycap says");
    end

    //------------------------------------------------------------------
    // 7b. EXIT (SLUTT) end to end, both ways (04-SEP-2026): RUN/STOP, and
    //     Alt+X. The machine must see the TDV2200's ESC [ 4 8 _, five
    //     bytes, once per press, and nothing on release. The seam's own
    //     40-clock busy per byte (kbd_ready above) is in the path, so this
    //     also proves the expander waits for it.
    //------------------------------------------------------------------
    nseam = 0;
    down[63] = 1'b1;   // RUN/STOP
    sweep();
    down[63] = 1'b0;
    sweep();
    repeat (400) @(posedge clk);
    expect_exit("RUN/STOP");

    down[66] = 1'b1;   // ALT
    sweep();
    down[23] = 1'b1;   // X
    sweep();
    down[23] = 1'b0;
    sweep();
    down[66] = 1'b0;
    sweep();
    repeat (400) @(posedge clk);
    expect_exit("Alt+X");

    //------------------------------------------------------------------
    // 8. Video shape over more than one full frame (800 x 525 pixel clocks:
    //    640x480@60 on this board, see nd120_console_mega65.v).
    //------------------------------------------------------------------
    // Zero the counters on a NEGEDGE: the sampling block above increments
    // them with non-blocking assignments on the posedge, and a blocking
    // clear issued in the same posedge time step loses to that increment
    // (found 04-SEP-2026 when step 7b left this block parked on a posedge -
    // de_count came out as the whole run's total, 526548).
    @(negedge clk);
    v_samples = 0; v_de_shape_errs = 0; v_rgb_errs = 0; v_de_count = 0; v_green_count = 0;
    repeat (800 * 525 + 2000) @(posedge clk);
    if (v_de_shape_errs != 0) begin
      $display("FAIL: de != !(hblank|vblank) on %0d of %0d clocks", v_de_shape_errs, v_samples);
      errors = errors + 1;
    end else begin
      $display("-- hblank/vblank are the two halves of de over %0d clocks", v_samples);
    end
    if (v_rgb_errs != 0) begin
      $display("FAIL: RGB not black outside de on %0d clocks", v_rgb_errs);
      errors = errors + 1;
    end else begin
      $display("-- RGB black outside de");
    end
    // 640x480 visible of 800x525 total: de should be high ~73% of the time.
    // 307200 per frame, plus the 2000-clock tail's share of the next one.
    if (v_de_count < 300000 || v_de_count > 316000) begin
      $display("FAIL: de high on %0d clocks per frame-ish, expected ~307200 (640x480)", v_de_count);
      errors = errors + 1;
    end else begin
      $display("-- de covers %0d clocks, consistent with 640x480", v_de_count);
    end
    if (v_green_count == 0) begin
      $display("FAIL: no green text pixels at all - palette or ink path dead");
      errors = errors + 1;
    end else begin
      $display("-- %0d green text pixels seen", v_green_count);
    end

    if (errors == 0) $display("TB_RESULT: PASS (MEGA65 console glue)");
    else             $display("TB_RESULT: FAIL (%0d errors)", errors);
    $finish;
  end

  initial begin
    #100_000_000;
    $display("FAIL: timeout");
    $display("TB_RESULT: FAIL (timeout)");
    $finish;
  end

endmodule

`default_nettype wire
