# Plan - an in-repo VT-style terminal core (screen + keyboard console)

> **DECIDED 30-AUG-2026 (Ronny): the terminal is a plain VT100** - SINTRAN's
> console line is set to terminal type 6 (DEC-VT100), so the TDV stages below
> are history, not plan. Stage B is built (`rtl/terminal_ctrl.v`, rewritten
> 30-AUG); Stage A's TDV C0 controller was removed by that rewrite; Stage C is
> not planned. Geometry is the VT100's 80x24. Current state: ../README.md.

**Full path:** `Verilog/Terminals/docs/PLAN-vt100-terminal-core.md`
Written 27-AUG-2026. Serves two boards that both want the console on the
machine's own screen and keyboard instead of a USB serial cable:
**MiSTer** (`Verilog/fpga/mister/`) and **MEGA65** (`Verilog/fpga/mega65/`).

## The problem

Today every ND-120 FPGA target puts the OPCOM/SINTRAN console on a UART and
you attach a PC terminal program to it. On a MiSTer or a MEGA65 that is the
wrong shape: both machines already own an HDMI/VGA output and a keyboard.
What is missing is the piece in between - a terminal: character generator,
screen buffer, escape-sequence handling, key-to-ASCII mapping.

## The licensing finding (checked 27-AUG-2026, this is measured, not assumed)

Ronny asked about reusing the VT100 emulator inside PDP2011:
<https://github.com/MiSTer-Enhanced/PDP2011_MiSTer>. Two separate licences
are in play there and only one of them is the repo's `LICENSE`:

- The repo `LICENSE` file is **GPL-2.0** (that is the MiSTer framework's
  licence, carried by every core that vendors `sys/`).
- The terminal source files themselves - `rtl/vt.vhd`, `rtl/vga.vhd`,
  `rtl/vgacr.vhd`, `rtl/ps2.vhd` - carry a **different, non-free header**:
  *"Copyright (c) 2008-2021 Sytse van Slooten ... granted ... to use these
  materials solely for personal, non-commercial purposes."*

That non-commercial clause is a field-of-use restriction. It is the same
class of problem the MEGA65 plan already rejected for Grant Searle's
SBCTextDisplayRGB (`fpga/mega65/docs/00-plan.md`, "the one license fork"),
and it cannot be mixed into an MIT repo. **So the files cannot be vendored.**

**Decision (Ronny, 27-AUG-2026): re-implement, keep MIT.**

### What "clean room" has to mean here, or it is not worth doing

Reading `vt.vhd` and then writing our version is *not* a clean-room
re-implementation - it is a derivative work with extra steps. The good news
is that we do not need that file as the specification at all, because the
specification is public:

- **DEC VT100 User Guide** - the terminal's own documented behaviour.
- **ANSI X3.64 / ECMA-48** - the escape-sequence standard, freely published.
- Our own machine's need: what SINTRAN III actually sends to a console.

So the rule for this work: **implement from the public VT100/ECMA-48
documents.** PDP2011 is used only as a *feature checklist* - "a working
minicomputer console needs at least these behaviours" - never as source to
translate. No side-by-side porting, no structure copied.

### One more reason not to copy it

`vt.vhd` is not a small character generator. It implements the terminal the
way DEC did - as a **microcoded CPU running terminal firmware** (the entity
even exports `vga_debug ... "debug output from microcode"`). 43 KB of VHDL.
Re-creating that is a project of its own, and it is far more terminal than a
SINTRAN login needs. The MEGA65 plan's estimate stands: **~300-500 lines of
Verilog** for VGA timing + a 2 KB character RAM + a font ROM + CR/LF/BS/scroll.

## The better spec source: RetroTerm (Ronny, 27-AUG-2026)

The RetroTerm repository is **MIT, Copyright (c) 2025-2026 Ronny Hansen** -
his own code - and it already implements VT100, VT52, ECMA-48, TDV and
Tektronix. There is no licence question and no clean-room dance: it can be
read, quoted and translated freely. It is a better specification than the
public documents alone because it also encodes *what a real SINTRAN session
needs*, which no standard document says.

Where to read (verified paths, 27-AUG-2026):

- `src/RetroTerm.Core/Terminal/Emulators/` - `VT100Emulator.cs`,
  `Vt52Emulator.cs`, `Ecma48Emulator.cs`, `TDV/`, `Tektronix/`.
  `TerminalEmulatorBase.cs` is 360 KB and is the ECMA-48 core - useful for the
  parser, useless for the TDV story. Do not start there.
- Keyboard: `src/RetroTerm.Core/Terminal/Input/KeyboardMapper.cs`
  (`TDV2200KeyboardMapper`, keyed by VK code - the one the factory builds) and
  `src/RetroTerm.Core/Terminal/Emulators/TDV/TDVKeyboardMapper.cs` (keyed by key
  name - a DIFFERENT class; conflating them has already cost time). Both
  resolve through `TDV2200KeyRegistry`.
- `spec/TDV2200/OCR/*.md` - OCR'ed Tandberg/ND manuals;
  `spec/TDV2200/DOC TDV2200/` - keyboard docs + ROM disassembly;
  `spec/TDV2200/Term and keyboard info/TDV-Keys.md` - a derived guide.
  **Treat all of that as claims until it agrees with the ROM disassembly or
  with RetroTerm's behaviour** (retroterm-09's warning: three documents in that
  repo turned out wrong, two of them hiding a real defect).

PDP2011 drops to a distant third source - and stays reference-only, never
vendored, for the licence reason above.

## Feature checklist (scope, smallest useful first)

Stage A - glass TTY, enough to log in to SINTRAN:
- **80x25** character screen buffer in BRAM (TDV 2200 geometry - see SPEC-tdv2200.md; it is NOT 80x24).
- Font ROM 8x16, from a public-domain IBM-clone font or OFL Terminus.
- VGA/HDMI timing generator; `DE = ~(HBlank | VBlank)` for the MiSTer scaler.
- Control characters: CR, LF, BS, TAB, BEL (ignore), FF/clear.
- Bottom-line scroll, block cursor.

Stage B - what a real ND session wants:
- ANSI/VT100 CSI subset: cursor addressing (`CUP`), erase in line/display
  (`EL`/`ED`), cursor up/down/left/right, save/restore.
- Reverse video attribute (one attribute bit per cell).

Stage C - only if something needs it: 132-column mode, double-height lines,
smooth scroll, the full VT100 answerback. Probably never.

> **The full TDV 2200 specification now lives in
> [SPEC-tdv2200.md](SPEC-tdv2200.md)** - grammar, the key-encoding rules,
> geometry, attributes and the traps, all sourced from RetroTerm on
> 27-AUG-2026. Read that before writing any Stage C code. Two headlines:
> **Stage A is confirmed sufficient for a SINTRAN login by an actual live
> session**, and the screen is **80x25, not 80x24**.

**Answered 27-AUG-2026 by `retroterm-09` (the session that owns RetroTerm):**
SINTRAN and ND software drive Tandberg TDV terminals, and **TDV 2200 is not
ANSI-with-extras** - it is a different grammar. Keys come back as TDV grid
positions such as `ESC [ 4 6 _`, with an **underscore terminator** that is not
in the ANSI final-byte set; RetroTerm resolves keys through a TDV registry with
no VT100 fallback at all. A plain VT100 pointed at SINTRAN will not do.
Consequence for this plan: Stage A/B (VT100/ECMA-48) is still the right first
build, but Stage C is a **second parser**, not a delta.

## Where it plugs in - the seam is the same on both boards

The ND-120 console UART is `IO_UART_42` inside the board; the top level
brings out serial pins (`ND120_TOP.v:890` `.TXD(uartTx)`; boards wire that to
`cpu_txd` / `RXD`). Two byte FIFOs at that seam, as the MEGA65 plan already
specified:

- **TX:** tap the console byte *before* 7E2 serialization, push into the
  terminal core - so baud rate and framing quirks never reach the screen.
- **RX:** keyboard ASCII is injected as if it had been received.

That glue is ~100-200 lines plus clock-domain crossing, and is identical for
MiSTer and MEGA65. **Only the two ends differ:**

| | MiSTer (Cyclone V) | MEGA65 (Artix-7) |
|---|---|---|
| Keyboard | `hps_io` gives `ps2_key[10:0]` free - USB keyboard handled by Linux | vendor the four mega65-core files (`mega65kbd_to_matrix`, `kb_matrix_ram`, `matrix_to_ascii`, `mk2_to_mk1`), LGPLv3, isolated dir |
| Video out | `CLK_VIDEO` + `CE_PIXEL` + `VGA_*` into the framework's `video_mixer`/scaler, HDMI for free | VGA timing straight to the board's VDAC (VGA-first, per the 27-AUG research) |
| Console source switch | an OSD status bit picks on-screen terminal vs framework UART - exactly what PDP2011 exposes as `serial_console (status[2])` | a config switch or just build-time |

## Language note

Write it in **Verilog**, not VHDL. The Tang Nano OSS flow (yosys) has no
usable VHDL path, and keeping one language means the core can be reused on
the Nexys/Tang later if it ever earns a screen there.

## Location - decided

`Verilog/Terminals/` (Ronny, 27-AUG-2026): `rtl/`, `sim/`, `font/`, `docs/`.
Board-independent - it knows nothing about MiSTer or MEGA65; each board folder
owns its own keyboard source and video sink. Testbenches go in
`Verilog/Terminals/sim/` and get registered in `Verilog/tests/run_all_tests.sh`
with a strict pass pattern, like everything else. See
[../README.md](../README.md).
