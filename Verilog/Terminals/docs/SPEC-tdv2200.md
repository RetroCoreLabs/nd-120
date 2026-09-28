# TDV 2200 - the specification the 31-AUG-2026 build was built against

> **IMPLEMENTED 31-AUG-2026, and now the DEFAULT terminal again.** The
> 30-AUG-2026 VT100 rewrite (below, superseded) was tried first and works
> perfectly for DISPLAY OUTPUT - but live testing that same night proved
> SINTRAN's screen editors (PED, confirmed on real hardware; LED by its own
> manual) are built around the Tandberg keyboard's key set, not VT100 CSI
> input, on TWO independent implementations (our FPGA and RetroCore's
> software emulation) - ruling out a hardware bug. VT100 input was never
> going to drive PED's cursor.
>
> Built as `Verilog/Terminals/rtl/terminal_ctrl_tdv.v` +
> `ps2_ascii_table_tdv.v` + `ps2_decoder_tdv.v` + `ps2_keyboard_tdv.v` +
> `key_tdv2200.v` - genuinely SEPARATE modules from the VT100 ones, kept
> (not replaced), selected at COMPILE TIME via
> `` `ifdef ND120_TERMINAL_VT100 `` (default = TDV2200; build with
> `-VT100Terminal` on the Nexys for the VT100 variant instead). See
> `Verilog/docs/build-defines.md`.
>
> **The exact target is terminal type 93** ("Tandberg TDV-2200/9S
> ND-NOTIS"), NOT type 53 ("Tandberg TDV 2200/9", no S) that most of this
> document's original research (below) was measured against - these are
> different real hardware models. Type 93 was independently re-confirmed
> end to end against a real ND-100 host (RetroTerm
> `docs/manual-tests/FINDINGS-2026-08-20.md`, "the TDV key registry checked
> end to end against a real ND host", 13/13 exact matches) and by a
> **directly captured PED-at-type-93 startup sequence**, replayed byte-exact
> as `terminal_ctrl_tdv_tb.v`'s primary test:
> ```
> ESC Q
> ESC[30;7;80l  ESC[62;62h        (mode set/reset, unmarked, mode 62 unknown)
> ESC P L10 ESC\  (x4, L10/L20/L30/L40)   (DCS soft-key programming - skipped
>                                          as a unit, matches what RetroTerm's
>                                          own TDV2200Emulator does)
> ESC[001;001H                    (CUP, zero-padded parameters)
> ESC[2J
> ```
> Also reconfirmed on real hardware: Home really is bare `GS 0x1D` - PED's
> own guide says "HOME - Move to command line (PED:)", and `SENDKEY HOME`
> transmitted `GS 0x1D` with the cursor landing exactly there.
> V1 scope is deliberately narrow - C0 table, DLE addressing (7-bit column,
> confirmed below), the CUP/ED/EL trio, generic mode/DCS swallow, character-
> set designation bytes consumed but not all 9 sets rendered. Deferred until
> a live capture shows they are actually used: ND private rectangle ops,
> Tektronix/ND graphics, DCS soft-key *programming* (skip-only is
> implemented), 132-column mode (no TDV terminal type supports it).
>
> **REAL-HARDWARE FOLLOW-UP, same day.** Testing the flashed build on the
> Nexys surfaced two more real bugs, both fixed and tested:
> - **Character sets were never actually implemented, only swallowed.**
>   TDV designates a character set with a bare TWO-byte `ESC <digit>`
>   (NDSS1-9 - e.g. `ESC 6` for Box), not VT100's three-byte `ESC ( <final>`
>   this parser only recognised at first. SCONF's box-drawing screen showed
>   the bug directly: cell `0x60` rendered as a literal backtick instead of
>   a top-left corner. Fixed: `ESC <digit>` is now recognised, NDSS6 (Box)
>   sets the graphics attribute and renders from a new font page 3
>   (`font/make_font.py`'s `tdv_box_page()`, light/heavy/double strokes
>   synthesized the same way page 2's DEC graphics are); every other digit
>   falls back to plain ASCII. `terminal_ctrl_tdv_tb.v` has the regression
>   test.
> - **PED's box-drawing is SS2 into character set 2 (01-SEP-2026, measured
>   on the Nexys).** PED draws every frame cell with SS2 (`ESC N <char>`), a
>   single shift through G2, which on a TDV2200 is permanently **character
>   set 2** of the terminal's own ROM (confirmed against a live serial trace:
>   repeated `1B 4E` then one data byte per cell). Set 2 is the SAME alphabet
>   the `ESC 6` Box designation selects - on a real TDV2200 they are one set
>   (RetroCore maps both Box and G2 to bank 2) - so both use the ONE graphics
>   bit (cell bit 12 -> font **page 3**). Set 2 is NOT the VT100 DEC Special
>   Graphics alphabet: it has the horizontal line at `0x60` where DEC has a
>   diamond, and the corners/tees at `0x61-0x6A`. Page 3's glyphs are the
>   real ROM's, copied glyph for glyph from RetroCore's dump
>   (`font/tdv2200_set2_from_retrocore.py` -> `font/tdv2200_set2.py`), with
>   the eleven line glyphs re-drawn at full cell height so they join between
>   cells.
>   - **The Nexys detour that cost the evening:** a first cut pointed SS2 at
>     the DEC page (page 2), and PED's frames rendered as rows of DIAMONDS.
>     A second cut gave SS2 its OWN font page (page 4) and a second cell bit
>     (bit 13); that fifth page pushed the font ROM past a block-RAM boundary
>     and **Vivado, proving the page-4 address was never asserted, dropped it
>     and aliased page 4 back onto page 0** - so PED's frames came out as
>     backticks (`0x60`) and the odd `e` (`0x65`), exactly page 0 of the
>     set-2 codes. The RTL and both testbenches were correct; the bug was
>     synthesis-only and invisible in Verilator. Fix: Box and SS2 share one
>     page, the ROM stays at four pages / 8192 bytes, and it synthesises as
>     it did on the working build 24. Do not split them onto separate pages
>     again without checking the font ROM actually grew in the BRAM report.
> - **Backspace was wired to `BS` (0x08), which is wrong.** `BS` is pure
>   cursor-left on a TDV, with no delete at all - it is the exact same byte
>   Left arrow sends. A destructive backward-delete needs `DEL` (0x7F),
>   same as the PC Delete key. Fixed in `ps2_ascii_table_tdv.v`.
>
> **ALT+KEY APPLICATION SHORTCUTS, same day** (user-requested, not a PC
> keyboard or TDV standard - most of these functions have no PC key at
> all): `ps2_decoder_tdv.v` now tracks Alt as a modifier (scancode 0x11,
> both Left and Right), and a held Alt over a bound key sends a DEDICATED
> marker instead of the plain character - a key with NO Alt binding sends
> NOTHING while Alt is held, never falling through to the plain letter.
> Markers live at `0xE0`-`0xF8` in `ps2_ascii_table_tdv.v` (`ALTM_*`),
> chosen with headroom above the highest ESC[nn_ marker actually in use
> (Insert's own marker is `0x80|82=0xD2` - NOT capped at n=67 the way an
> earlier cut of this file assumed, which is exactly the bug that first
> revealed the need for headroom: that earlier cut used `0xC4` and it
> landed on top of Insert's marker). Two trust levels, kept distinct in the
> source comments and here:
> - **Registry-trusted** (same `TDV2200KeyRegistry.cs` as the F-key table):
>   Alt+H=HELP(HJELP,46) Alt+U=FUNC(FUNK,42) Alt+X=EXIT(SLUTT,48)
>   Alt+C=CANCEL(ANGRE,30) Alt+K=COPY(KOPI,12) Alt+V=MOVE(FLYTT,14)
>   Alt+J=JUST(24) Alt+A=MARK(MERK,00) Alt+L=FIELD(FELT,02)
>   Alt+P=PARA(AVSH,04) Alt+E=SENT(SETN,06) Alt+W=WORD(ORD,08).
> - **User-specified, NOT in the registry - unconfirmed against real
>   hardware or the registry, no other source exists for these**:
>   Alt+D=DO (`ESC[29~`), Alt+M=COMMAND (`ESC[26~`), Alt+F=FIND
>   (`ESC[1;2R`), Alt+S=SELECT (`ESC[4;2~`), Alt+1..Alt+8=PUSH1-8
>   (`ESC P N<1-8> ESC \`) - the registry says PUSH keys are
>   host-programmable with **no fixed sequence at all**, so this is a
>   guess dressed as a sequence, not a fact; treat it as such until a real
>   TDV or a live capture settles it. Alt+I=INSERT HERE is an
>   approximate match (mapped to D99 INNS/EXPS, `ESC[82_`, the TDV's own
>   Insert-mode toggle - the closest real function, not a confirmed match
>   for "insert at cursor"). `key_tdv2200.v` expands each marker into its
>   own fixed byte sequence (up to 6 bytes total, PUSH/FIND/SELECT run
>   longest - the queue grew from 4 lookahead bytes to 5 for this).
>
> **Arrow keys: found and fixed, same day.** The keyboard side (traced
> above as clean end to end) was never the problem. A RetroCore protocol
> trace, captured live while navigating PED with terminal type 93 active,
> showed the real mechanism: SINTRAN's own cursor-move ECHO for a TDV
> keypress is STANDARD VT100 CSI, not another bare TDV byte -
>
> ```
> TX 08 BS   (TDV: cursor left)   -> RX ESC[D  CUB
> TX 0B VT   (TDV: cursor down)   -> RX ESC[B  CUD
> TX 1C FS   (TDV: cursor up)     -> RX ESC[A  CUU
> TX 18 CAN  (TDV: cursor right)  -> RX ESC[C  CUF
> ```
>
> So SINTRAN was receiving and correctly processing every keypress all
> along - the DISPLAY side just never implemented CSI `A`/`B`/`C`/`D` at
> all (only `H`/`f`/`J`/`K` existed), so the echoed cursor move was
> silently swallowed and the cursor never visibly moved. This matches
> RetroTerm's own class hierarchy exactly (`TDV2200Emulator` derives from
> the same ECMA-48 core `VT100Emulator` uses, adding ND extensions on top
> - not a separate protocol) - `terminal_ctrl_tdv.v` needed the SAME base
> CSI set `terminal_ctrl.v` already has, not a narrower one. Ported over
> (same arithmetic, no scroll-region floor/ceiling since TDV has none):
> `A`/`B`/`C`/`D` (CUU/CUD/CUF/CUB), `G` (CHA), `d` (VPA), and `m` (SGR -
> also independently confirmed needed, the captured PED startup's own
> `ESC[2;7m` dim-reverse status line was being swallowed too before this).
> `terminal_ctrl_tdv_tb.v` replays the exact RetroCore trace shape as its
> regression test.
>
> Everything below this point is the ORIGINAL 27-AUG-2026 research this was
> built from - still the best TDV 2200 reference in this repo, and mostly
> unchanged by the type-93-specific confirmation above. Read it for the
> traps list and the keyboard rules; the geometry/keyboard/C0 facts below
> all held up.

**Full path:** `Verilog/Terminals/docs/SPEC-tdv2200.md`
Answered 27-AUG-2026 by `retroterm-09`, read out of RetroTerm's source rather
than the OCR documents. RetroTerm is MIT and Ronny's own, so this is a clean
source with no licence question. Where something was a guess, it says so.

Companion to [PLAN-vt100-terminal-core.md](PLAN-vt100-terminal-core.md).

## CORRECTION, 27-AUG-2026: the C0 codes are not the ASCII ones

Ronny pointed out that the escape sequences are documented in RetroTerm's own
`docs/` folder and in its code - which they are, in detail. Reading them
changed the design, and two of the corrections were things a live trace would
have shown only after a wasted build.

**Source:** `docs/TDV-COMPLETE-ESCAPE-SEQUENCE-REFERENCE.md` in the RetroTerm repository
and `TDV-COMPREHENSIVE-REFERENCE.md`, cross-checked against each other, plus
`TDV-DLE-CURSOR-BUG-FIX.md`.

### The TDV C0 set (implemented in terminal_ctrl_tdv.v)

| Byte | Name | TDV meaning | What ANSI would have done |
|---|---|---|---|
| 0x02 | STX | video OFF (screen kept) | - |
| 0x03 | ETX | video ON | - |
| 0x04 | EOT | **erase line** | - |
| 0x05/06/15 | ENQ/ACK/NAK | LED 1/2/3 on | - |
| 0x07 | BEL | bell | same |
| 0x08 | BS | cursor left | same |
| 0x09 | HT | tab | same |
| 0x0A/0B | LF/VT | cursor down | same |
| **0x0C** | **FF** | **ROLL UP (scroll)** | **clear the screen** |
| 0x0D | CR | column 0 | same |
| 0x0E/0F | SO/SI | **disputed - see below** | - |
| **0x10** | **DLE** | **cursor addressing, 2 bytes follow** | - |
| 0x16 | SYN | all lamps off | - |
| 0x17 | ETB | ROLL DOWN | - |
| 0x18 | CAN | cursor right | - |
| **0x19** | **EM** | **ERASE PAGE** | - |
| 0x1C | FS | cursor up | - |
| 0x1D | GS | cursor home | - |

**The expensive one: FF is a scroll, not a clear.** An ANSI reading wipes the
screen every time SINTRAN rolls the page. EM is the clear. Both were wrong in
our first cut and are now right, with a testbench that fails if they are
swapped back.

### DLE - cursor addressing with no escape sequence at all

`DLE row col` - three bytes. Row is the next byte masked `0b0001_1111`,
column the byte after masked `0b0111_1111`, both 0-based.

**SINTRAN positions the cursor this way** - confirmed by a live RX capture of
terminal type 53 (`TDV-DLE-CURSOR-BUG-FIX.md`). That is the single most useful
fact in this whole document: full-screen cursor addressing costs a three-state
machine and **no escape parser**, so a lot of what looked like Stage B is
already reachable in Stage A.

**Doc defect, confirmed by RetroTerm's own bug report:**
`TDV-COMPLETE-ESCAPE-SEQUENCE-REFERENCE.md` says the COLUMN mask is 5 bits,
which cannot express the documented range 0-79. The code uses 7 bits and the
bug-fix report calls the 5-bit figure a doc defect. **We use 7 bits**, and the
testbench specifically addresses column 79 so a regression to 5 bits fails.

### SO (0x0E) and SI (0x0F) - RESOLVED, and the answer was "both"

Both documents are correct. They describe different **modes**, and neither
names the mode it applies in - which is why they read as a contradiction.
RetroTerm implements both (confirmed by retroterm-09, 27-AUG-2026):

| Mode | SO (0x0E) | SI (0x0F) | Where |
|---|---|---|---|
| native TDV2200/2215 | invoke G1 | invoke G0 | `TDV2200Emulator.cs:303-306` |
| 2115 compatibility | underline ON | underline OFF | `TDV2115CompatibilityHandler.cs:218-234` |

2115 mode is entered by ND private mode 66 - **the same mode that swaps the
whole keyboard encoding** from `ESC[nn_` to single C0 bytes (rule C above). So
the two meanings travel together: implement 2115 mode and SO/SI change meaning
along with the keyboard.

**We do not implement 2115 mode**, so the G1/G0 reading is correct for every
case our terminal can reach. `terminal_ctrl.v` tracks it on a `charset`
output. Nothing renders differently yet - there is one font page - but the
state is carried rather than dropped, so a second font page is only a wiring
job.

The comment in RetroTerm's own 2115 handler is worth keeping, because whoever
wrote it hit this exact question:

> "0x0E SO / 0x0F SI. Here they mean Underline / Normal, a 2115 attribute
> feature. Outside 2115 mode they are Shift Out / Shift In - G1/G0 invocation -
> which the emulator already handles. Routing them here would silently break
> character-set switching."

**The doc defect is real but is not "one of them is stale".** Both are
INCOMPLETE in the same way - each states its meaning without naming the mode.
That is worse than a wrong entry, because both readers come away confident.

## Stage A is enough for a login - and this is MEASURED, not assumed

retroterm-09 logged into a live SINTRAN III VSX/500 console (RetroCore
emulated ND-100, port 9010): ESC, login as SYSTEM, `@WHO-IS-ON`. The whole
exchange - banner, ENTER/PASSWORD prompts, the `@` prompt, the terminal
listing - was **plain text with CR/LF**. RetroTerm's "what did I receive and
not act on" report came back **nothing unhandled**, and nothing on screen
needed cursor addressing.

So a glass TTY - printable ASCII, CR, LF, BS, BEL - genuinely gets a SINTRAN
login and the `@`-command loop. **That is Stage A, and it is now backed by
evidence rather than by our hope.**

What the full-screen tools need (the LED editor, QED, the ND-500 monitor
screens) is **largely answered by the documents above, not by a trace**: the
TDV C0 set plus DLE cursor addressing is what they position with, and DLE is
confirmed against a live SINTRAN capture. If a gap turns up later, the next
place to look is RetroTerm's `docs/` folder and its emulator code - not a new
measurement. That was Ronny's point, and it was right.

## Geometry - 80 x 25, NOT 80 x 24

From RetroTerm's `EmulatorFactory` (line ~200): TDV 2200 and TDV 2215 are
**80 columns by 25 rows**. Our first cut said 24; corrected in the RTL on
27-AUG-2026. A whole row is a whole row of BRAM and a scroll region off by one.

## The grammar - why a VT100 parser is not enough

TDV extended control keys use **`ESC [ nn _`** - CSI, two DECIMAL digits,
terminator **underscore (0x5F)**. 0x5F is **outside the ANSI final-byte range
0x40-0x7E**, so an ECMA-48 parser never terminates on it. The CSI state needs
`_` added as a final, or its own state.

ND-specific CSI finals (`TDVEmulatorBase.IsNDSpecificFinal`):

| Final | Name | What it does |
|---|---|---|
| `z` | NDSAR | set attribute over a RECTANGLE |
| `u` | NDSREC | save rectangle |
| `v` | NDRREC | restore rectangle |
| `~` | NDDWA | define work area |
| `<` | NDVIDEO | alpha/graphics toggle |

A VT100 parser silently swallows all five. ND private modes (`CSI ? n h/l`)
include **66** (2115 compatibility), **67** NDSSM smooth scroll, **68** NDBLWM
blink, **69** enhanced blink.

## The keyboard - the rules matter more than the table

Source of truth:
`src\RetroTerm.Core\Terminal\Emulators\TDV\TDV2200KeyRegistry.cs` (1303 lines).
Each key is one `Reg(gridPosition, name, colour, flags, vk, extNormal,
extShift, extCtrl, simpleAscii, numPadFunc)` - **five possible encodings per
key**. That, not the byte values, is what will cost time.

### Rule A - shifted is unshifted PLUS ONE

Holds across the whole table. Store one base number per key and add the shift
bit; do not build 60 separate constants.

| Key | Base | Key | Base |
|---|---|---|---|
| MERK | 00 | STRYK | 10 |
| FELT | 02 | KOPI | 12 |
| AVSH | 04 | FLYTT | 14 |
| SETN | 06 | TAB | 16 |
| ORD | 08 | SEARCH | 18 |
| REPLACE | 20 | FUNK | 42 |
| SKRIV | 44 | HJELP | 46 |
| SLUTT | 48 | F1 | 50 |
| F2 | 52 | F3 | 55 |
| F4 | 58 | NEWPARA | 86 |

Only F2 and F3 have a ctrl variant, at base+2.

### Rule B - arrows and HOME are NEVER escape sequences

**Checked against the code, because a doc said otherwise.**
`docs\TDV-KEYBOARD-COMPLETE-REFERENCE.md` has a table claiming the arrows send
`ESC [ A/B/C/D` in "TDV2200 Extended" mode and C0 codes only in 2115 mode.
`TDV2200KeyRegistry.cs` disagrees, and the registry is the source of truth:

```csharp
Reg("C48","UP",   ...AlwaysSameCode, 38, "","",null,"",null);
Reg("A48","DOWN", ...AlwaysSameCode, 40, "","",null,"",null);
Reg("B47","LEFT", ...AlwaysSameCode, 37, "","",null,"",null);
Reg("B49","RIGHT",...AlwaysSameCode, 39, "","",null,"",null);
Reg("B48","HOME", ...AlwaysSameCode, 36, "","",null,"",null);
```

Same C0 byte in the normal, shift AND simple-ASCII columns, with the flag
`AlwaysSameCode`. **So the C0 codes are right and that doc table is wrong** -
a third document in this family that turned out to be a claim rather than a
fact. HOME is the exception the registry itself shows: 0x1D native, 0x10 in
Simple ASCII, exactly as stated below.

Implemented in `ps2_ascii_table_tdv.v`, with the registry lines quoted in the
source, so the next person does not have to re-do this.

#### The whole table was wrong, not just that row (retroterm-09, 27-AUG-2026)

Reported back, and retroterm-09 checked every row against the registry: the
"Navigation Keys" table **was a VT220 table wearing a TDV label**. Fixed on
its side in commit `d993a14` with a regression test. What the keys actually
are - this matters for Stage C, because two of them are not what a PC keyboard
would suggest:

| Grid | The doc said | **Reality (registry)** |
|---|---|---|
| arrows | `ESC[A/B/C/D` natively | **C0 bytes in EVERY mode**, AlwaysSameCode |
| HOME | `ESC[H` native / 0x1D in 2115 | **INVERTED**: 0x1D native, 0x10 in 2115 |
| D47 | "Page Down", `ESC[6~` | **ROLLUP** - `ESC[28_` / shift `ESC[29_` / 2115 0x06 |
| D49 | "Page Up", `ESC[5~` | **ROLLDN** - `ESC[32_` / shift `ESC[33_` / 2115 0x05 |
| C49 | "Insert", `ESC[2~` | **FIELDRIGHT** - `ESC[36_` |
| G47 | "Delete", `ESC[3~` | **STRYK** - `ESC[10_` |
| END | `ESC[F` | **there is no END key on a TDV** - returns null |
| F1-F12 | `ESC[11~` for F1 | **F1 = `ESC[50_`** (rule A base 50) |
| PUSH P1-P8 | `ESC[?n~` | **no fixed sequence exists at all** |

**Consequence for our Stage C key mapping:** a PC Page Up / Page Down should
map to **ROLLDN / ROLLUP**, not to any VT-style page sequence - and there is
nothing for a PC END key to send. Our Stage A behaviour (extended keys with no
TDV equivalent send NOTHING) is already right and stays right.

There is no VT220-ish TDV mode that would have made the doc true: DECCKM does
rewrite `ESC[A` into `ESC O A`, but only in the VT100/VT220 mapper classes,
which are never in the path for a TDV. The document had simply been written
from VT knowledge.


Bare C0 bytes, identical in every mode (flag `AlwaysSameCode`):

| Key | Byte | Key | Byte |
|---|---|---|---|
| UP | 0x1C | DOWN | 0x0B |
| LEFT | 0x08 | RIGHT | 0x18 |
| HOME | 0x1D | RETURN | 0x0D |
| DEL | 0x7F | | |

A real difference from VT100 - **no `ESC [ A`**. Emit VT100 arrows and the
SINTRAN full-screen tools will not see cursor keys at all. Note LEFT = 0x08 =
backspace, and HOME = 0x1D (0x10 in Simple ASCII mode - the one key whose code
changes between modes).

### Rule C - Simple ASCII mode (2115 compatibility, ND private mode 66)

Replaces the escape sequences with single C0 bytes: FELT 0x02, AVSH 0x01,
SETN 0x03, TAB 0x09, SEARCH 0x11, REPLACE 0x14, F1 0x1E, F2 0x1F, F3 0x18,
FIELDLEFT 0x0C, FIELDRIGHT 0x17, TABLEFT 0x15, TABRIGHT 0x09, NEWPARA 0x08.

So the key encoder needs a mode bit choosing rule A or rule C.

### Rule D - the numeric pad has a third encoding

Used only in numeric-pad-function mode: KP1 `ESC[69_`, KP2 `ESC[70_`,
KP3 `ESC[71_`, and so on. KPENTER is 0x0D always.

### What is awkward from a PS/2 or MEGA65 keyboard

- **PUSH keys G1-G8 are PROGRAMMABLE with no fixed sequence at all** (flag
  `IsProgrammable`, every sequence null). There is nothing to emit until the
  host defines them. Decide early whether Stage C supports them; ignoring them
  breaks nothing, they simply do nothing.
- **13 Norwegian legends with no PC equivalent** - MERK, FELT, AVSH, SETN,
  ORD, STRYK, KOPI, FLYTT, JUST, SKRIV, HJELP, SLUTT, FUNK - plus shifted
  variants. Needs a modifier layer or a mode key. RetroTerm's answer was a
  user-editable binding table, too much for RTL; **a fixed Alt+letter layer is
  the cheap version.**
- LOKAL (G14) and CAPS (E0) are local toggles that send nothing.
- **The keyboard is addressed by GRID POSITION** (G0, F51, C13, B48...), not
  by legend, because the same physical position carries different legends per
  national variant. Hardcode legends and it has to be redone for every
  national keyboard.

## Attributes - per cell, but the wire protocol is per region

The cell carries a `CharacterAttributes` ushort
(`src\RetroTerm.Core\Terminal\Buffer\CharacterAttributes.cs`): Bold, Dim,
Italic, Underline, Blink, RapidBlink, Reverse, Hidden, Strikethrough,
DoubleWidth, DoubleHeightTop, DoubleHeightBottom, and more above bit 11.

**The interaction that matters for BRAM:** NDSAR (`CSI ... z`) sets an
attribute over a RECTANGLE, and NDSREC/NDRREC save and restore rectangles - so
the wire protocol is region-oriented while the storage is per-cell. Store per
cell and NDSAR is a fill loop; try to store per region to save BRAM and you
fight every other sequence.

First cut per cell: 8 bits character + reverse + underline + blink + dim.
Reverse and underline are what the ND full-screen tools lean on. **Which
attributes SINTRAN actually uses is not measured** - same caveat as Stage A.

Our `char_ram.v` already carries a 16-bit cell (8 character + 8 attribute,
only reverse used so far), so this needs no width change.

## Traps, collected

1. **80x25, not 80x24.**
2. The `_` terminator is outside the ANSI final range - tell the CSI state
   machine, or it never terminates.
3. Shifted = base+1 across the whole key table.
4. Arrows are C0 bytes, not escape sequences.
5. HOME is the only key whose code changes between modes (0x1D vs 0x10).
6. **Two mapper classes that must not be conflated:**
   `Terminal\Input\KeyboardMapper.cs` holds `TDV2200KeyboardMapper`, keyed by
   **VK code** - the one the factory builds;
   `Emulators\TDV\TDVKeyboardMapper.cs` is keyed by key **name**. That
   confusion has cost time in RetroTerm and a memory note there was wrong
   about it for weeks.
7. **No VT100 fallback, deliberately.** A key with no TDV equivalent returns
   null and sends nothing rather than degrading to a VT100 sequence. Add a
   fallback and you send bytes a real TDV never sent.
8. **Escape sequences ARRIVE SPLIT ACROSS READS.** Not theoretical -
   RetroTerm's `InputParser.cs` is a state machine with a 100 ms timeout for
   exactly this reason. Over a UART the same happens, with ESC in one
   byte-time and `[` in the next. **Never write a matcher that needs the whole
   sequence in one buffer.** (A hardware state machine gets this right for
   free - but this is why it must stay a state machine.)
9. If any of this is ever turned into C or C# tables: `"\x1ba"` is ONE
   character, not ESC followed by `a` - the hex escape is greedy and takes as
   many hex digits as it can. Verilog is safe; a generator script is not.
10. Treat the OCR documents and derived guides as **claims**. Three of
    RetroTerm's own documents turned out wrong and two would have hidden a
    real defect. Our own `TDV-Keys.md` misread was the same shape: its §1 is
    about the TDV **1200**, not the 2200.

## Reading order (from retroterm-09)

1. `Terminal\Emulators\TDV\TDV2200KeyRegistry.cs` - the key table, START HERE
2. `Terminal\Emulators\TDV\TDVEmulatorBase.cs` - ND finals, private modes
3. `Terminal\Input\KeyboardMapper.cs` - the VK-keyed mapper the factory builds
4. `Terminal\Buffer\CharacterAttributes.cs` - the attribute bits
5. `Configuration\EmulatorFactory.cs` - geometry per terminal type (line ~200)
6. `Terminal\Parsing\EscapeSequenceParser.cs` - the split-across-reads machine
7. `Protocols.TelnetServer\Parsing\InputParser.cs` - a smaller worked example

**Not** `TerminalEmulatorBase.cs` - it is the enormous ECMA-48 core, and it is
not the TDV story.
