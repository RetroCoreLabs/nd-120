# RetroTermWeb TDV2200 - facts read from the code, 01-SEP-2026

Source: `src/` of the RetroTermWeb repository.

Ronny's instruction, 01-SEP-2026: the board's TDV2200 terminal must behave like
the RetroCore / RetroTermWeb emulation. These three reports were produced by
reading that TypeScript, every claim with a file:line. Read from the code, not
run in a browser. Compare `rtl/terminal_ctrl_tdv.v`, `rtl/ps2_ascii_table_tdv.v`
and `font/make_font.py` against them; where they differ, the emulation wins
unless a live capture says otherwise.

---

## Fonts and character sets

**1. Glyph bitmaps**
- `src/fonts/FontTDV2200.ts:35-1054` - one `Uint16Array GLYPHS`, 1018 glyphs, one glyph per source line, 16 uint16 rows per glyph (lines 36..1053). Only the low 8 bits of each row are used: `width = 8`, `height = 16`, `heightToUse = 14`, `stretchY = 1` (`FontTDV2200.ts:1059-1063`). MSB is the leftmost pixel (`BitmapFontRenderer.ts:184-186`).
- Bank offsets: `fontNumOffset = [0, 0, 128, 256, 384]` (`FontTDV2200.ts:1064`). `FontBase.getFontBits` (`FontBase.ts:35-69`) computes `glyphIndex = fontValue + fontNumOffset[fontNum]` (only when `fontNum > 0`, line 43-48), then `startPos = glyphIndex * 16`. Set 0 and 1 share offset 0; set 2 at 128; set 3 at 256; set 4 at 384. Glyphs 512-513 are hand-made German section sign and sharp s (`FontTDV2200.ts:27-32`). Space (0x20) is remapped to glyph 0 via `mapSpaceChar = 0` (`FontBase.ts:37-39`, `FontTDV2200.ts:1065`).
- Rendering transformation (`BitmapFontRenderer.ts:135-179`): only rows 0..13 are drawn (`heightToUse`); each bit is scaled to the cell with `pixelWidth = cellWidth/8`, `pixelHeight = cellHeight/14`, times 2 for double-width/height attributes; `yOffset` is 0 except `-cellHeight` for double-height-bottom (line 166). No other x/y offset. Bold draws a second offset copy (line 195-200), italic applies a shear (line 170-171).

**2. Bank selection mechanisms** (TDV2200 emulator)
- State: `_g0.._g3CharacterSet` (defaults USASCII, USASCII, GraphicsI, GraphicsII) and `_invokedCharacterSet` (0..3) at `TDVEmulatorBase.ts:26-30`, reset at `TDV2200Emulator.ts:66-70`.
- **SO (0x0E)** -> `_invokedCharacterSet = 1` (G1); **SI (0x0F)** -> 0 (G0). Locking, persists. `TDV2200Emulator.ts:96-103`.
- **ESC N (0x4E)** -> `activateSS2()`; **ESC O (0x4F)** -> `activateSS3()`. One character only: flag cleared in `processSingleShift2/3` (`TDVCharacterSetManager.ts:37-50`). `TDV2200Emulator.ts:119-124`.
- **ESC n (0x6E)** -> `_invokedCharacterSet = 2` (LS2); **ESC o (0x6F)** -> 3 (LS3). Locking. `TDV2200Emulator.ts:125-130`.
- **ESC ( <0-9>** designates G0, **ESC ) <0-9>** designates G1, with `type = final - 0x30` (`TDVEmulatorBase.ts:354-364`). There is NO TDV designation for G2/G3 (`*`/`+` only reach the VT100 base handler, `TerminalEmulatorBase.ts:262-289`, which sets the separate VT100 `characterSets[]` array, not the TDV G-sets). `ESC ( B/A/0` also fall to that VT100 path.
- **ESC % I/N/S/G** - ISO 646 variant (`TDV2200Emulator.ts:134-139`, `TDVISO646VariantHandler.ts:22-44`). Persists; makes fontNumber 5/6/7 for cells that would otherwise be font 0 (`TDV2200Emulator.ts:235-246`).
- **No "ESC 6" / NDSS handler exists.** grep for `NDSS` and bare `0x36` in `src/emulators/tdv/` finds only `ESC # 6` double-width (`TDVEmulatorBase.ts:382`).
- Bank chosen per character in `handleCharacter` (`TDV2200Emulator.ts:206-232`): SS2 -> `CHARSET_TYPE_TO_FONTNUM[G2type]`, SS3 -> same with G3, else `CHARSET_TYPE_TO_FONTNUM[activeGtype]` (0 for USASCII). The table (`TDVCharacterSets.ts:32-42`): types GraphicsI(1)/Math(3)/Greek(4)/Box(6)/T(8) -> bank 2; GraphicsII(2) -> bank 3; ND(9) -> bank 4; Diacritics(5)/NIX(7) -> bank 0. Type enum at `TDVCharacterSets.ts:15-26`. So with defaults, SS2 draws from bank 2 (offset 128) and SS3 from bank 3 (offset 256). Result stored in `cell.fontNumber` (`TDV2200Emulator.ts:278`).

**3. Remap table in the render path?**
- TDV path: `applyCharacterSetMapping` is overridden to return the codepoint unchanged (`TDVEmulatorBase.ts:429-432`), and `processSingleShift2/3` return `mappedChar: c` unchanged. So the raw 7-bit code is the bank index: `getFontBits(code, fontNumber)` (`BitmapFontRenderer.ts:125`).
- Exceptions inside `BitmapFontRenderer.drawCharacter` (`:107-130`): if `cell.characterSet === 2` (VT100 DEC Special Graphics designated via `ESC ( 0` in the VT100 base array) codes 0x60-0x7E become ROM 0x00-0x1E (line 111-113); if the codepoint is > 0x7F it is reverse-mapped through `UNICODE_TO_VT100_ROM` (line 28-50, 117-122); if the glyph is null and fontNumber != 0, it falls back to bank 0 (line 128-130). `TDV2200Emulator.ts:249-253` also invokes the DEC mapping when `characterSets[active] === 2` and fontNumber is 0. Fonts 5-7 redirect only the 10 national positions to ROM 0-31 (`FontTDV2200.ts:1075-1090`).
- Canvas call: `CanvasRenderer.ts:233-237` (and 352-356) passes `cell.codepoint, cell.fontNumber, ..., cell.characterSet`. Font chosen at `CanvasRenderer.ts:411-412` for emulator type `tdv2200`; there is no system-font fallback (line 405-407).

**4. Set 2 (bank 2, offset 128) glyphs 0x60-0x6A** = glyph indices 224-234 = `FontTDV2200.ts:260-270`. Decoded (column 4 of 8 = 0x08; row 7 is the joint row; rows 0-13 drawn):
- 0x60 (l.260): horizontal line, row 7 full width (`0xFF`)
- 0x61 (l.261): bottom-left corner (vertical rows 0-6, row 7 right half `0x0F`)
- 0x62 (l.262): bottom tee
- 0x63 (l.263): bottom-right corner (row 7 left half `0xF8`)
- 0x64 (l.264): left tee
- 0x65 (l.265): cross
- 0x66 (l.266): right tee
- 0x67 (l.267): top-left corner
- 0x68 (l.268): top tee
- 0x69 (l.269): top-right corner
- 0x6A (l.270): vertical line (rows 0-13 `0x08`)

**5. 7-bit vs 8-bit**
- Bit 7 is NOT stripped and is NOT used as a set selector. `EscapeSequenceParser.ts:177-198`: 0x20-0x7E -> `onCharacter`; 0x9B -> C1 CSI; any other byte >= 0x80 is treated as the start of a UTF-8 sequence (`:483-520`), invalid starts emit U+FFFD. So an 8-bit ND byte such as 0xE0 would be parsed as a UTF-8 lead byte, not as "set 2 + 0x60". Nothing in the TDV files masks with `& 0x7F`.

---

## ESC and CSI sequences (host to terminal)

Path shorthand used in the table:

- **T2200** = `emulators/tdv/TDV2200Emulator.ts`
- **TBase** = `emulators/tdv/TDVEmulatorBase.ts`
- **Base** = `emulators/TerminalEmulatorBase.ts`
- **C2115** = `emulators/tdv/components/TDV2115CompatibilityHandler.ts`
- **Parser** = `parser/EscapeSequenceParser.ts`
- **Rect** = `emulators/tdv/components/TDVRectangleOperations.ts`

Dispatch order for a CSI in TDV2200 (T2200:146-174): 1) DA/DSR/DECRQM queries, 2) `?40 h/l`, 3) TDV2200 finals (`< > p q s t`), 4) ND finals (`z { } | ~ u v`, `"q`, `?66-69`), 5) VT100 base. Order matters (see notes).

### C0 controls (normal mode)

| Bytes | Name | Effect | Where |
|---|---|---|---|
| 0x07 BEL | bell | fires onBell | Base:186 |
| 0x08 BS | backspace | col-1, clamps at 0, no reverse wrap | Base:189, CursorState.ts:86 |
| 0x09 HT | tab | next stop (every 8 cols by default), else last column | Base:192, 713 |
| 0x0A LF, 0x0B VT, 0x0C FF | line feed | all three identical: row+1, scroll up at scrollBottom | Base:195-198, 782 |
| 0x0D CR | | col 0; plus LF if LNM (mode 20) set | Base:200 |
| 0x0E SO | shift out | TDV: invokedCharacterSet=1 (G1) | T2200:97 |
| 0x0F SI | shift in | TDV: invokedCharacterSet=0 (G0) | T2200:100 |
| 0x00, 0x10 DLE, 0x18 CAN, 0x19 EM, 0x1A SUB, 0x1C FS, 0x1D GS, 0x1E RS, 0x1F US, 0x7F DEL, all others | | **swallowed** (no case in switch) | Base:184-213; Parser:178-196 routes 0x7F to onExecute |

### C0 controls in 2115 compatibility mode (after `CSI ?40 h` / `CSI ?66 h`)

Checked first (T2200:89-93), before the table above.

| Byte | Effect | Where |
|---|---|---|
| 0x02 STX / 0x03 ETX | videoOn=false / true (flag only) | C2115:57-58 |
| 0x04 EOT | erase cursor to end of line | C2115:59, TBase:491 |
| 0x19 EM | erase whole page (cursor unchanged) | C2115:60, TBase:495 |
| 0x05 ENQ / 0x06 ACK / 0x15 NAK | LED 1/2/3 on | C2115:61-63 |
| 0x16 SYN | all 3 LEDs off | C2115:64 |
| 0x0D CR | col 0 (never LF) | C2115:65 |
| 0x1D GS | home (0,0) | C2115:66 |
| 0x08 BS / 0x18 CAN | cursor left / right, clamped | C2115:67-76 |
| 0x1C FS | cursor up, clamped at 0 | C2115:77 |
| 0x0A LF / 0x0B VT | down; at last row scroll up | C2115:82 |
| 0x0C FF | scroll up (roll up) | C2115:89 |
| 0x17 ETB | scroll down (roll down) | C2115:90 |
| 0x10 DLE | arm binary cursor addressing | C2115:91 |
| 0x07, 0x09, rest | fall to normal table | C2115:95-96 |

**DLE encoding** (C2115:101-113): byte 1 `row = b & 0x1F` (5-bit, 0-based, no bias), byte 2 `col = b & 0x7F` (7-bit, 0-based, no bias). Applied only if `row < height && col < width`, else silently dropped; DLE mode then clears. **Caveat from code:** DLE bytes only reach `handleDLEByte` via `handleExecute` (T2200:83), which the parser calls only for bytes < 0x20 (Parser:193-195). Any row/col byte >= 0x20 is delivered to `handleCharacter` and **printed as text** while DLE stays armed. The `TDVInputProcessor` that would fix this (`components/TDVInputProcessor.ts:49-60`) is constructed (T2200:35) but `processInput` is never called outside unit tests; `Terminal.ts:236-238` calls `processData` directly.

### ESC sequences

| Bytes | Name | Effect | Where |
|---|---|---|---|
| ESC Q | exit 2115 mode | | T2200:116 |
| ESC N / ESC O | SS2 / SS3 | next char from TDV G2 / G3 (fontNumber via CHARSET_TYPE_TO_FONTNUM) | T2200:119-124, TDVCharacterSetManager.ts:27-50 |
| ESC n / ESC o | LS2 / LS3 | invokedCharacterSet=2 / 3 | T2200:125-130 |
| ESC % I/N/S/G | ISO 646 variant | International/Norwegian/Swedish/German; other final leaves flag armed but harmless | T2200:134-139, TDVISO646VariantHandler.ts:22-44 |
| ESC Z | identify | sends `CSI ?220;0c` (`?115;0c` in 2115 mode) | TBase:327, T2200:353 |
| ESC # 3/4/5/6 | DECDHL top/bottom, DECSWL, DECDWL | sets per-cell doubleWidth/Height flags on whole cursor row | TBase:336, 371-386 |
| ESC ( d / ESC ) d, d=0..9 | TDV charset to G0/G1 | 0 USASCII,1 GraphicsI,2 GraphicsII,3 Math,4 Greek,5 Diacritics,6 Box,7 NIX,8 T,9 ND | TBase:357-363, TDVCharacterSets.ts:15-42 |
| ESC ( B/A, ESC ) B/A, ESC * x, ESC + x | VT100 designation | writes base `characterSets[]` only (not the TDV G-sets) | Base:262-290 |
| ESC D / E / M | IND / NEL / RI | | Base:227-236 |
| ESC H | HTS | | Base:237 |
| ESC 7 / ESC 8 | DECSC / DECRC | row, col, style only (no attributes) | Base:242-247, CursorState.ts:138-148 |
| ESC c | RIS | full reset + home | Base:248 |
| ESC = / ESC > | DECKPAM / DECKPNM | | Base:252-257 |
| ESC 6, any other final | | **swallowed** | Base:226-258 |

### CSI sequences

| Bytes | Name | Effect / defaults | Where |
|---|---|---|---|
| CSI c, CSI >c | DA1 / DA2 | `CSI ?220;0c` (`?115;0c` in 2115) / `CSI >220;0;0c` | TBase:134-149, T2200:342-351 |
| CSI 5n / 6n | DSR / CPR | `CSI 0n` / `CSI r;cR` (1-based); other Pn ignored | TBase:151-167 |
| CSI ? Ps $ p (or $ y) | DECRQM | reply `CSI ?Ps;st$y`, st=1/2 for 1,40,67,68,69; else 0 | TBase:170-176, T2200:368-374 |
| CSI ?40 h/l, CSI ?66 h/l | 2115 compat on/off | | T2200:154-164, TBase:244 |
| CSI ?67 / ?68 / ?69 h/l | smooth scroll / blink / enhanced blink | flags only, nothing else reads them | TBase:245-247 |
| CSI ?1/?5/?6/?7/?25/?47/?1047/?1048/?1049 h/l | DECCKM, DECSCNM, DECOM (homes cursor), DECAWM, DECTCEM, alt screen, save/restore | ?12 is a no-op | Base:435-489 |
| CSI 4 h/l, CSI 20 h/l | IRM, LNM | | Base:740-753 |
| CSI Pn A/B/C/D | CUU/CUD/CUF/CUB, default 1, clamped to screen (ignore margins) | Base:305-316 |
| CSI Pn E/F | CNL/CPL | Base:317-324 |
| CSI Pn G / d | CHA / VPA | Base:325, 357 |
| CSI Pr;Pc H / f | CUP/HVP, defaults 1;1, origin mode adds scrollTop | Base:328-338 |
| CSI Ps J | ED 0/1/2/3 (3 = + scrollback) | Base:339, 613-635 |
| CSI Ps K | EL 0/1/2 | Base:342, 637-649 |
| CSI Pn L / M | IL / DL from cursor row **to screen bottom, ignores DECSTBM** | Base:345-350, TerminalBuffer.ts:155-166 |
| CSI Pn P / X / @ | DCH / ECH / ICH | Base:351-355, 383 |
| CSI Pn S / T | SU / SD within scroll region | Base:386-401 |
| CSI Ps g | TBC 0 / 3 | Base:402 |
| CSI Pt;Pb r | DECSTBM; 0;0 or none = full; needs t<b; homes cursor | Base:366-376, 818-838 |
| CSI Ps m | SGR: 0,1,2,3,4,5,7,8,9,22-25,27-29,30-37,38;5;n,38;2;r;g;b,39,40-47,48;...,49,90-97,100-107 | Base:493-609 |
| **CSI Pn s** | **NDICHE** = insert Pn chars at cursor (default 1). Base SCOSC unreachable | T2200:191-196 |
| **CSI Pn t** | NDDCHE = delete Pn chars (default 1) | T2200:197 |
| **CSI Pn p** | NDLIWA: insert Pn lines from cursor row to work-area bottom | T2200:185, 312-319 |
| **CSI Pn q** | NDDLWA: delete Pn lines from cursor row to work-area bottom. Catches **every** `q` without `?` marker, so `CSI SP q` (DECSCUSR) and `CSI 1"q`/`2"q` (SPA/EPA at TBase:187-199) never reach their handlers in TDV2200 | T2200:188 |
| CSI attr;x1;y1;x2;y2 z / { / } | NDSAR / NDAAR (same as SAR) / NDRAR: set/clear one attribute in rectangle; attr 1 bold,2 dim,4 underline,5 blink,7 reverse,8 hidden; coords are 0-based col,row, clamped, order-normalised; need 5 params | TBase:256-282, Rect:12-68 |
| CSI ch;x1;y1;x2;y2 \| | NDFC: fill rectangle with codepoint `ch` (decimal) | TBase:284, Rect:117-124 |
| CSI x1;y1;x2;y2 ~ | NDDWA: define work area; fewer than 4 params = clear it | TBase:293-302, TDVWorkAreas.ts:25-31 |
| CSI x1;y1;x2;y2 u | NDSREC save rectangle (needs 4 params; base SCORC unreachable) | TBase:224-229, 304-311 |
| CSI x;y v | NDRREC restore most recently saved rectangle at x,y (default 0,0) | TBase:313-317, Rect:88-114 |
| CSI Ps < | NDVIDEO: 1 = graphics extension flag on, 0 off | T2200:179, 291-299 |
| CSI Ps > | 0/1 graphics flag off/on, 2/3 Tektronix flag on/off - flags only | T2200:182, 301-310 |
| anything else | | **swallowed** | Base:304-430 |

### DCS, OSC, other strings

- `ESC P ... ESC \` / `0x9C`: parser accumulates params and data (Parser:408-481) but TDV2200 never assigns `onDcsHook/onDcsPut/onDcsUnhook`, so the whole DCS is **discarded**. `TDVDCSHandler` (PUSH/UDC/SOFT/LED prefixes, `components/TDVDCSHandler.ts:53-74`) is constructed only to be reset (T2200:74); it returns description strings and performs no action. The PUSH/PROGRAM key programmer (`components/TDVDCSHandlerFeature.ts`) is 2215-only and `handleDCSSequence` has no callers anywhere.
- OSC 0/2 `;text` (BEL or ST terminated) sets title; other OSC ignored (Base:666-699). APC/PM/SOS consumed to ST (Parser:166-173).

### Parameter parsing

- Digits accumulate `*10 + d` (Parser:346-353), so `001` = 1. `getParam(i, def)` returns `def` when the param is missing **or zero** (Parser:65-69) - `CSI 0;0H` = `CSI 1;1H`. Rectangle/mode handlers use `getRawParam` (Parser:72), where 0 stays 0.
- Max 32 params, 2 intermediates; private markers `? > ! =`; a C0 control inside a CSI is executed and the CSI continues (Parser:379-381); ESC anywhere restarts the sequence (Parser:117-131).

### Departures from the VT100/ECMA-48 base

1. SO/SI switch the TDV `invokedCharacterSet`, not the base `activeCharacterSet` (T2200:96-103), so base `ESC ( 0` line-drawing mapping (T2200:248-254) is effectively dead: TDV `ESC ( 0` means USASCII (TBase:359).
2. `s`, `u`, `q`, `p`, `t` are all ND private in TDV2200 (see table), hiding SCOSC/SCORC/DECSCUSR/DECSCA/SPA/EPA.
3. `?h/l` with an ND mode returns on the first matching param (T2200:161, TBase:244-247), so remaining modes in the same list are dropped.
4. Character cells carry a `fontNumber` (0 ASCII, 2 Greek/Math, 3 sub/super, 4 control-display, 5/6/7 ISO646 NO/SE/DE) instead of Unicode mapping (T2200:212-246, `components/TDVCharacterSets.ts:32-42`).

---

## Keyboard (terminal to host)

All paths below are relative to the root of the RetroTermWeb repository.

### How a physical PC key becomes bytes

1. `src/terminal/Terminal.ts:605-620` `mapKeyToSequence`: in TDV2200/2215 mode, `domKeyToVK(ev.key)` (`src/keyboard/KeyboardMapper.ts:137-169`) maps only non-text keys to a VK code; letters/digits/punctuation return 0 and skip the TDV mapper entirely.
2. `src/keyboard/TDVKeyboardMapper.ts:77-124` `mapKey`: Alt bindings -> (dead TDV2115 branch) -> registry lookup by VK -> Backspace fallback -> null.
3. `src/keyboard/TDV2200KeyRegistry.ts:664-697` `getSequence`: `alwaysSameCode` keys ignore Shift/Ctrl (line 679); else numpad-func (682), Ctrl variant if defined (685), Shift variant if defined (688), else normal. `extendedControlMode` is `true` and `numericPadFuncMode` is `false` at `TDVKeyboardMapper.ts:69,72` and nothing in `src/` ever changes them (verified by grep), so the "Simple ASCII" column is unreachable from the PC keyboard.
4. Anything the TDV mapper returns null for falls through to the VT100 table at `Terminal.ts:623-665`.
5. Printable characters come via `keypress` (`Terminal.ts:509-519`), pass through `remapCharacter`, and are fired as a JS string via `onKey`; the byte encoding is the host app's job (`demo/demo.js:33-36` just dumps `charCodeAt`).

### Table (Extended Control Mode, the only mode reachable)

| PC key | Plain | Shift | Ctrl | Registry row | Notes |
|---|---|---|---|---|---|
| Up | `1C` (FS) | `1C` | `1C` | C48 UP, `TDV2200KeyRegistry.ts:223` | AlwaysSameCode |
| Down | `0B` (VT) | `0B` | `0B` | A48 DOWN, `:263` | |
| Left | `08` (BS) | `08` | `08` | B47 LEFT, `:248` | |
| Right | `18` (CAN) | `18` | `18` | B49 RIGHT, `:250` | |
| Home | `1D` (GS) | `1D` | `1D` | B48 HOME, `:249` | simple-ASCII col would be `10` |
| End | `1B 5B 34 38 5F` ESC[48_ | ESC[49_ | ESC[48_ | G54 SLUTT (EXIT), `:137` | vk 35 |
| Insert | ESC[82_ | ESC[83_ | ESC[82_ | D99 INNS, `:177` | sends only; toggles NOTHING locally (`insertMode` is set only by host DECSET, `TerminalEmulatorBase.ts:746`) |
| Delete | ESC[10_ | ESC[11_ | ESC[10_ | G47 STRYK, `:129` | The TDV `DEL` key E14 (`7F`, `:163`) has vk 0 and is not reachable from a PC key |
| Backspace | `08` | `08` | `08` | none; `TDVKeyboardMapper.ts:120` fallback | never `7F` in TDV mode. NEWPARA E13 (ESC[86_/87_, `:162`) is vk 192 and unreachable |
| Enter | `0D` | `0D` | `0D` | C13 RETURN, `:219` | CR only, no LF. Numpad Enter also `0D` (vk 13 collides, first-registered C13 wins, `:92`) |
| Tab | ESC[16_ | ESC[17_ | ESC[16_ | F47 TAB, `:140` | vk 9 goes to F47 (the "TAB -/+" key), not the A49 arrow-tab (ESC[40_) |
| Escape | `1B` | `1B` | `1B` | G0, `:114` | |
| PageUp | ESC[32_ | ESC[33_ | ESC[32_ | D49 ROLLDN, `:196` | |
| PageDown | ESC[28_ | ESC[29_ | ESC[28_ | D47 ROLLUP, `:194` | |
| F1 | ESC[50_ | ESC[51_ | ESC[50_ | F51, `:143` | no ctrl variant -> normal |
| F2 | ESC[52_ | ESC[53_ | **ESC[54_** | F52, `:144` | |
| F3 | ESC[55_ | ESC[56_ | **ESC[57_** | F53, `:145` | |
| F4 | ESC[58_ | ESC[59_ | ESC[58_ | F54, `:146` | |
| F5 | ESC[60_ | ESC[61_ | ESC[60_ | E51, `:171` | |
| F6 | ESC[62_ | ESC[63_ | ESC[62_ | E52, `:172` | |
| F7 | ESC[64_ | ESC[65_ | ESC[64_ | E53, `:173` | |
| F8 | ESC[66_ | ESC[67_ | ESC[66_ | E54, `:174` | |
| F9..F12 | ESC[20~ / [21~ / [23~ / [24~ | same | same | not in registry; VT100 fallback `Terminal.ts:657-660` | xterm codes leak through |
| Ctrl+Shift+F1..F8 | = Shift variant | | | `TDV2200KeyRegistry.ts:685-688` (ctrl null, shift wins) | |
| Ctrl+letter | letter & 0x1F | | | `Terminal.ts:623-630` | Ctrl+Shift+C/V/F are eaten (copy/paste/search, `Terminal.ts:469-496`) |
| Alt+letter / Alt+digit | **nothing** | | | `Terminal.ts:607-608` (`domKeyToVK` returns 0), keypress ignores altKey `:511` | The Alt table (`TDV2200KeyRegistry.ts:575-615`, Alt+H=HJELP etc.) is only reachable via the exported `mapAltKeyToSequence` (`AltKeyMapper.ts:40`) or `mapKey` called directly; `Terminal.ts` never gets there for letters |
| Alt+Delete | ESC[10_ | ESC[11_ (Shift) | | `:612` -> G47 | works, because Delete has a VK |
| Alt+PageUp | ESC[32_ | | | `:613` -> D49 ROLLDN | |
| Alt+PageDown | ESC[28_ | | | `:614` -> D47 ROLLUP | |
| Alt+Backspace | ESC[30_ | ESC[31_ | | `:580` -> D48 ANGRE (CANCEL) | |
| Alt+F1..F8 | **nothing** | | | `:590-598` map to PUSH keys G1-G8; `TDVKeyboardMapper.ts:86-89` returns null for programmable keys and nothing else picks them up | |
| Numpad 0-9 . - | digits as text | | | `:199-268`; `numericPadFuncMode` never true, so ESC[68_..80_ never sent | |
| PrintScreen | nothing | | | G52 SKRIV vk 44 but `domKeyToVK` has no PrintScreen | |

### TDV keys with no PC key (only via VirtualKeyboard or Alt API)

MERK ESC[00_/01_ `:121`; FELT 02/03 `:122`; AVSH 04/05 `:123`; SETN 06/07 `:124`; ORD 08/09 `:125`; KOPI 12/13 `:130`; FLYTT 14/15 `:131`; SEARCH 18/19 `:141`; REPLACE(DO) 20/21 `:142`; GUILLEMETS 22/23 `:166`; JUST(ER) 24/25 `:167`; SINGLEGUILLEMETS 26/27 `:168`; ANGRE 30/31 `:195`; FIELDLEFT 34/35 `:222`; FIELDRIGHT 36/37 `:224`; TABLEFT 38/39 `:262`; TABRIGHT 40/41 `:264`; FUNK 42/43 `:134`; SKRIV 44/45 `:135`; HJELP 46/47 `:136`; MODE 84/85 `:205`; LF `0A` `:191`. Pattern: plain n is even, Shift is n+1; Ctrl exists only for F2/F3. The on-screen VirtualKeyboard sends the same registry sequences (`src/keyboard/VirtualKeyboard.ts:700-703`) with sticky Shift/Ctrl reset after each key (`:735-737`), and injects them by firing `_onKey` directly (`:743`).

### Norwegian layout

`TDVKeyboardMapper.ts:25-34` and `remapCharacter` `:130-141`, applied on keypress at `Terminal.ts:516`; language defaults to `'no'` (`TDVKeyboardMapper.ts:75`), set via `Terminal.setKeyboardLanguage` (`Terminal.ts:350-352`). Whatever key the OS layout makes produce these characters:

| Char | Sent |
|---|---|
| ae (small) | `7B` `{` |
| oe (small) | `7C` `\|` |
| aa (small) | `7D` `}` |
| AE | `5B` `[` |
| OE | `5C` `\` |
| AA | `5D` `]` |

Any other code >= 0x80 is passed through as the raw JS char (`:139`). ASCII `{|}[\]` typed on a US layout are sent unchanged (`:133`), so they collide with the national letters on the wire. Tables also exist for dk/sv/fi/de/ch/fr (`:35-64`).

### Other behaviour

- Local echo: none in the library. `demo/demo.js:273-275` has an opt-in "Echo mode" that writes `ev.key` back to the screen.
- Key repeat: no handling; `ev.repeat` is never read (grep of `src/` empty), so OS auto-repeat produces repeated sends.
- Windows/GUI key: `metaKey` is only used to *suppress* - keypress with Meta ignored (`Terminal.ts:511`), Ctrl-char and plain-char paths require `!metaKey` (`:623, :663`). Meta is folded into `KeyModifiers.Meta` (`KeyboardMapper.ts:179`) but the TDV mapper never tests it.
- AltGr: no `getModifierState('AltGraph')` anywhere. On Windows, AltGr arrives as Ctrl+Alt; the keypress path drops it (`:511`, `ctrlKey`/`altKey`), and keydown falls through to null (`:623` requires `!altKey`). So AltGr characters (e.g. `@` on a Norwegian layout) are **not sent** by keydown/keypress. Read from the code only, not run in a browser.
- The `TDV2115Mode` C0 branch at `TDVKeyboardMapper.ts:96-106` is dead: `Terminal.ts:610-612` only passes `TDV2200Mode` or `TDV2215Mode`.
- PUSH keys: `src/emulators/tdv/components/TDVPushKeys.ts` stores programmed strings (1-24), but no code path in `Terminal.ts` or `VirtualKeyboard.ts` looks up a programmed string on a G1-G8 press; `getSequence` returns null for them (`TDV2200KeyRegistry.ts:675`).
