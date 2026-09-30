//============================================================================
//! Power-on message sender - walks term_banner_rom into the terminal.
//!
//! Part of the board-independent terminal core (Verilog/Terminals/).
//!
//! WHY A BANNER IS WORTH REAL GATES. It turns one useless symptom into two
//! useful ones. Without it a board that shows nothing could be a dead pixel
//! clock, a bad sync, an empty font ROM, a stuck character RAM, a keyboard
//! that never decodes, or a console seam that never delivers a byte. With it:
//!
//!   text appears           -> clock, sync, font, character RAM, scroll and
//!                             the whole write path are all working, and the
//!                             fault is downstream of them
//!   text appears, typing
//!   does nothing           -> the keyboard half alone
//!   nothing at all         -> the video half alone
//!
//! On a board on the desk that saves an hour. On a board belonging to a friend
//! in another country - which is how the MEGA65 will be tested, see
//! fpga/mega65/docs/00-plan.md - it is the difference between one round trip
//! and three, where each round trip is days.
//!
//! It sends ONCE per reset and then gets out of the way for good: `done` goes
//! high and `valid` never rises again, so the machine's own output cannot
//! collide with it.
//!
//! Written 28-AUG-2026.
//============================================================================

`default_nettype none

module term_banner (
    input wire clk,
    input wire rst_n,  //! async reset, active low

    //! Into the terminal's byte port. Same valid/ready contract.
    output wire       valid,
    output wire [7:0] data,
    input  wire       ready,  //! low while the previous byte is in flight (from terminal_top.byte_ready)

    output reg done  //! high once the whole message has been accepted
);

  reg [8:0] s_addr;

  wire [7:0] s_rom_data;

  term_banner_rom ROM (
      .addr(s_addr),
      .data(s_rom_data)
  );

  assign data = s_rom_data;

  //! The ROM returns 0x00 for every address past the end and the generator
  //! refuses to emit a NUL inside the message, so this is the terminator. No
  //! length constant exists anywhere in the design, and therefore none can go
  //! stale when the text is edited.
  wire s_at_end = (s_rom_data == 8'h00);

  //! COMBINATIONAL, deliberately. A registered `valid` is wrong here and the
  //! first version of this module had the bug: when the address steps onto the
  //! terminator the ROM immediately presents 0x00, but a registered valid is
  //! still high from the previous cycle - so if `ready` happened to be high
  //! that cycle the terminal would accept the NUL and print a stray glyph
  //! after the message. Deriving valid from the data the ROM is presenting
  //! RIGHT NOW means a terminator is never offered in the first place.
  assign valid = !done && !s_at_end;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s_addr <= 9'd0;
      done   <= 1'b0;
    end else if (!done) begin
      if (s_at_end) begin
        done <= 1'b1;   // reached the terminator: never speak again
      end else if (valid && ready) begin
        // Advance only when the terminal actually took the byte. `ready` is
        // low while the previous character is still crossing into the pixel
        // domain, and a clear-screen holds it low for a whole 1920-clock
        // sweep - so this handshake is not decorative.
        s_addr <= s_addr + 9'd1;
      end
    end
  end

endmodule

`default_nettype wire
