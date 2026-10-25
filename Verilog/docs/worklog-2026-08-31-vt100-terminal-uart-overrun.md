# Worklog 2026-08-31 - VT100 terminal, keyboard, and the SC2661 overrun bug

**Full path:** `Verilog/docs/worklog-2026-08-31-vt100-terminal-uart-overrun.md`

## What happened, in order

1. **Decision (Ronny, 30-AUG): the terminal is a plain VT100**, matching
   SINTRAN terminal type 6, not TDV2200. `Terminals/rtl/terminal_ctrl.v`
   rewritten from the earlier TDV C0 controller - full ESC/CSI parser,
   DECSTBM regions, DEC Special Graphics charset, 80x24. Committed `1c02698`.
2. **First Vivado synthesis** (via the CACHEFIX session's cache build 8)
   failed the 1080p pixel clock by -0.328 ns on the cursor-move paths.
   Fixed in two rounds - defer cursor moves into an apply state
   (`191bdee`), then latch their operands before use so no path runs from
   `s_par` to a cursor register at all (`e26f44b`). Closed at WNS +0.211 ns,
   all endpoints met. **Flashed to the Nexys and confirmed rendering good
   by Ronny.**
3. **Keyboard: the full DEC special-key set** - arrows, the six DEC editing
   keys (Home=FIND, End=SELECT, Insert, Delete, PgUp, PgDn), PF1-4, F5-F12,
   with the no-modifier-encoding rule (Shift/Ctrl on a special key send the
   base sequence; Alt sends nothing). Committed `cf9667b` + a dedicated
   `key_vt100_tb.v` sweep (`cf33df1`). Scancodes then cross-checked against
   two independent published set-2 references (`cd346bc`) - see
   `docs/SPEC-vt100-keys.md`.
4. **Live keyboard testing on real SINTRAN exposed two SEPARATE serial bugs**,
   found by comparing RetroTerm against TeraTerm on the same physical COM11
   link:
   - **RX: stray `0x3F` ('?') bytes inserted into text from the board.**
     Diagnosed as `.NET SerialPort.ParityReplace` (default '?') silently
     substituting any byte that fails the OS's parity check - reported to
     the RetroTerm-fixing session.
   - **TX: `PED\r` sent from RetroTerm arrived at the board as a single
     byte `(` (0x28)** - not any of P/E/D/CR. Traced to a genuine RTL
     defect in `Shared/support/SC2661_UART.v`'s receive state machine (see
     below) - **fixed in this session, uncommitted, untested** (WSL hung
     before the unit tests could run).
5. **Independently, Ronny found and fixed the actual root cause of the
   framing mismatch** (commit `773651f`, 00:40, parallel to this work):
   **`SC2661_UART.v` is hardwired 8N1 - 8 data bits, no parity, 1 stop
   bit - always.** The mode registers that would select 7-bit/parity are
   not implemented; the file has said "constant ... 8N1" in a comment
   since it was written. The `nexys-115200` RetroTerm connection had been
   set to **7E1** (on my advice, based on a stale claim in
   `Terminals/rtl/console_uart_rx.v`'s header comment about the real
   SC2661 chip's datasheet-level programmability, which this emulation
   does not implement) - so the PC was validating a "parity bit" that was
   actually the 8th data bit of 7-bit ASCII, explaining most of the `?`
   corruption. **Not fully explained even by Ronny's own measurement**:
   only 6 of 42 bytes came back wrong, clustered around echo/prompts, not
   the "nearly every odd-population byte" a clean framing-mismatch model
   predicts - see `HARDWARE.md` for the honest account.

## The SC2661_UART.v overrun fix (this session, uncommitted)

**Root cause**, read directly out of the RTL: `regReceiveHoldingRegister`
was used as BOTH the live shift-in register during a byte's arrival AND
the CPU-visible holding register, with no separate buffering. On a new
start bit, the code cleared this register **immediately** (`RX_STATE_IDLE`)
and then shifted the incoming byte's bits into it **live**, regardless of
whether the CPU had read the previous byte. Overrun was detected
(`regStatusRegister[4] <= 1`) but the RXRDY-clear needed to make that
meaningful was commented out with `-- SET OVERRUN?` - a TODO the original
author left unfinished. Net effect: if the CPU read the register while a
new byte was mid-shift, it got a torn, partially-assembled value matching
**neither** the old nor the new byte - exactly what a burst-sent `PED\r`
produced (`(` / 0x28, matching none of P/E/D/CR).

**Fix**: added `regRxShift` as a separate, CPU-invisible shift register.
`RX_STATE_READ` now shifts into `regRxShift`, not the holding register.
The ONLY write to `regReceiveHoldingRegister` on receive is now a single,
atomic transfer at the `RX_STATE_STOP_BIT -> RX_STATE_DONE` boundary -
exactly when a complete byte exists - and that is also where overrun is
now correctly checked and flagged (the true moment an unread byte would be
lost). The old byte stays valid and readable right up until that instant.

Matches the same "update only when a whole thing is done" pattern already
used correctly elsewhere in this codebase (`Terminals/rtl/console_uart_rx.v`,
`terminal_ctrl.v`'s `put_char`).

**NOT YET VERIFIED** - WSL hung (unresponsive to a trivial `echo`,
identical to an earlier hang this same session) before
`Shared/support/sim/`'s `test-uart`, `test-uart-txabort`, `test-uart-txint`
could run. Per this file's own convention (shared, heavily-used chip RTL),
the full `Verilog/tests/run_all_tests.sh` registry should also run before
this is trusted.

## Two RetroTerm issues reported to the RetroTerm-fixing session

Sent to `retroterm-45` then (after that session ended) `retroterm-dd`:

1. `SerialPort.ParityReplace` defaulting to `'?'` and silently corrupting
   any byte that fails a parity check - real regardless of the 7E1/8N1
   question above, since ANY genuine parity mismatch (even a harmless one
   from clock tolerance) would still trigger it whenever parity checking
   is enabled at all.
2. Feature request: a "Transmit Delay" Preferences tab (msec/char,
   msec/line, 0 = disabled) - useful independent of the SC2661 fix, since
   RetroTerm's TX path has no pacing at all today and other devices could
   hit similar limits.

## Status after the fact

The sections above are the log as written that night. Where they were later
overtaken:

- **Overrun fix: landed and tested.** `regRxShift` is in
  `Shared/support/SC2661_UART.v`, merged in `7c4d66d9`. `test-uart`,
  `test-uart-txabort`, `test-uart-txint` and `SC2661_RX_OVERRUN_tb.v` are in
  `tests/run_all_tests.sh`. The "uncommitted, untested, WSL hung" wording
  above describes that night only.
- **Framing advice above ("set the terminal to 8N1") is superseded.** The
  SC2661 model is a fixed 8-bit frame with no hardware parity, but SINTRAN
  puts software parity in bit 7 of some output, so the on-screen console
  receiver reads 7 data bits + parity (the same 8-bit frame) and the Nexys
  console is 7E1. See the header of `Terminals/rtl/console_uart_rx.v`. The
  release files use 115200 7E1.
- **Header comments of `console_uart_rx.v` / `console_uart_tx.v`:** corrected
  (they no longer claim the framing is programmable).
- **RetroTerm issues (ParityReplace, Transmit Delay tab):** reported to the
  RetroTerm session; their state is tracked there, not in this repository.

## Still open

- Whether PED sends a Device Attributes or Cursor Position query (`ESC[c`,
  `ESC[6n`) that our terminal never answers. `terminal_ctrl.v` has no reply
  path on purpose. Not measured; needs a TeraTerm log of a PED session on the
  board. Tracked in `Verilog/TODO.md`.
