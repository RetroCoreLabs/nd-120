# Lessons from the 300$ / JMP0-3 hunt - I/O capture, clocking, microcode hygiene

11-JUL-2026, trimmed 28-SEP-2026. The dispatch story itself lives in
`serial-binload-300.md`: 300$ is PARKED by owner decision (11-JUL-2026). A
one-word microcode patch (`COMM,LDIRV` at o500) made the JMP0-3 dispatch work
in sim, but it was not kept - the committed PROM images carry no o500 change
(the `test-microcode-sync` gate allows no difference except the deliberate
0o2002 sim patch). This file collects the findings that generalize to other
code.

Removed in the trim (history is in git): the July strobed-I/O read problem
(resolved 12-JUL-2026, not reproducible), and the "PROM copies have drifted"
section - superseded by the 02-SEP-2026 raw-vs-sim decision in
`nd120-facts.md` and the `test-microcode-sync` gate (`tests/microcode_sync.py`),
which now checks every PROM copy.

## 1. The SC2661 model answers reads one clock late (the real chip does not)

Shared/support/SC2661_UART.v registers its read response: regDataOut updates on
the UART's clock edge AFTER chip-enable + read go active, and the pins show
regDataOut during the strobe (re-checked 28-SEP-2026: still true, the read
assignment near line 421 and `D_OUT` near line 280). The real SCN2661 drives
data combinationally within its access time once CE/read are asserted. The
registered response adds artificial latency on top of a strobed-read race and
makes the model harder to read correctly in sim. (That race was a
strobed-I/O read problem seen in July 2026; it stopped reproducing on
12-JUL-2026 after the UART sysclk-edge fix and the clock-enable conversions -
see git history of this file.) If the read path is ever reworked, make the read
response combinational
(the microcode even grants extra time: the status read at TRMVC runs under
COMM,XSLOW, a 425 ns cycle on the real machine).

For the record, the model's flag semantics were AUDITED AND ARE CORRECT:
reading the data register clears the data-available flag; reading the status
register does not touch it. That was not the bug.

## 2. Clocking and pipeline confirmations (good news for the clock-enable work)

- **The FF-mode MIC pipeline is cycle-accurate through heavy stress.** The
  dispatch test exercised 412,987 vectored jumps in FF mode (USE_LATCHES=0)
  through the microcode sequencer's full pipeline - operand-address register
  lagging one MCLK by design, condition set/enable pairs spanning words, jump
  target assembly - with zero mislandings. The P2-converted MIC clock domain
  holds up under real workload, not just boot.
- **Delay slots appear in CSA traces.** After a TAKEN conditional jump, the
  next sequential word shows up in the trace before the jump target (measured
  at o503 -> o504 -> o511, and o2312 -> o2313 -> o2310). Trace tooling and
  golden compares must not count a delay-slot visit as "the flow went there";
  visit counts of a delay-slot address roughly equal the loop count of the
  jump above it. (Whether the slot's side effects also execute was not
  established - treat that as unknown until measured.)
- **Strobe-class signals: prefer architectural fixes over new RTL clocking.**
  LDIRV (the microcode instruction-register load strobe) is decoded from the
  microword and gated to the MCLK-low half-cycle - exactly the signal class
  the latch->FF refactor keeps tripping over. The 300$ fix deliberately added
  NO new RTL: one word of microcode (COMM,LDIRV at o500) made the existing,
  already-converted strobe fire where it was needed (a sim experiment, not kept;
  see the top of this file). When a fix can live in
  microcode or configuration instead of a new clock-domain crossing, take it.

## 3. Toolchain recipe: microcode source -> PROM hex (now proven end to end)

Full pipeline used for the o500 patch, reusable for any future microcode work:

1. Edit the .uc source ($ND_REPOS/ND110Compile/ND110Compile/uCode/,
   version-L files; CRLF line endings - patch with line-targeted sed).
2. Build the assembler in WSL: `dotnet build -c Release` in
   $ND_REPOS/ND110Compile/ND110Compile/, then run with
   `DOTNET_ROLL_FORWARD=LatestMajor dotnet ./bin/Release/net8.0/ND110Compile.dll`
   (WSL has .NET 9; the project targets 8). Program.cs selects input files by
   File.Exists - Linux-path entries run only under Linux, Windows-path entries
   only on Windows, which keeps the two environments from double-compiling.
3. Extract compiled words from the .DETAILS.TXT output: lines matching
   `uC: <octal-addr> : 0x<16 hex digits> =>`. Diff against EPROM truth before
   trusting anything.
4. PROM byte mapping (verified in Code/Microcode/gen_wcs_image.py): byte index
   = address*4 + chunk, chunk 0..3 = word bits 15:0 .. 63:48; 45132L holds the
   low byte of each 16-bit chunk, 45133L the high byte.
5. The sim loads runSim's copies via $readmemh in
   CPU-BOARD-3202/circuit/CPU_CS_PROM_19.v. Back up before patching
   (*.orig-unpatched convention).

Also proven: the assembler's token values are bit-exact ND semantics - e.g.
COMM,LDIRV = 0x00000C1000200000 including the delay bit, matching all ten
EPROM occurrences. When in doubt about a microword field, trust the token
table (nd120uc scripts/nd120_tokens.json) and verify against the EPROM.

## 4. Console harness note

Run120.cpp's console injector sends OPCOM characters in a 7-bit frame
(matching the 7-data-bit, even-parity, 2-stop mode the boot microcode programs
into the UART at o002010). Binary streams need all 8 bits, so the injector now
switches to 8-data-1-stop when an ND120_BINLOAD_FILE stream opens (tx8n1 in
Run120.cpp). The SC2661 model samples a fixed 8 data bits regardless of its
mode register, so this pairing works in sim and on our FPGA implementation.
How the REAL machine carried 8-bit binary over a console programmed 7E2 is an
open historical question (candidates: the panel processor, or terminal-control
reprogramming we have not traced) - only relevant if 300$ is ever attempted
against a real SC2661.

Note (28-SEP-2026): the SC2661 model ignores its mode register and is 8N1 only
(`Shared/support/SC2661_UART.v` header). The 7-data/even/2-stop reading of the
boot microcode's mode word above dates from 11-JUL-2026 and was not re-checked.
