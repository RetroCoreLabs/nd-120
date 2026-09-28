# HANDOFF — floppy PIO (3027) controller: C and C# defects

**For:** whoever owns the nd100x C emulator and/or the RetroCore C# emulator.
**Subject:** the OLDER **PIO** (programmed-I/O) floppy controller "3027" — device
octal 1560/1570, ident 021/022, interrupt level 11. This is a *different* device
from the 3112 DMA controller (whose nd100x fixes landed as nd100x commit
efed8ae; spec in `floppy-3112-register-spec-ND-11.021.md`).

**Files:**
- C: the nd100x repository, `src/devices/floppy/deviceFloppyPIO.c` + `.h`
- C#: the RetroCore repository, `Emulated.HW/ND/CPU/NDBUS/NDBusFloppyPIO.cs`

**Manual:** there is **no dedicated 3027 / ND-11.015 / ND-11.012 PIO manual** in
NDInsight (confirmed). The authoritative register spec used here is **§B.4
"ND-100 Floppy Disk Programming Specification" in
`Reference-Manuals/ND-06.015.02 ND-100 Functional Description.md` in the
NDInsight repository** (lines ~9747-9990). Line numbers below are approximate — the
implementer should confirm each against current source before editing.

**Rule:** no guessing. Every defect is grounded in a manual line or a
cross-model divergence. Items that cannot be verified (autoload bit 2) are
labelled UNVERIFIABLE, not "fixed."

**What is already correct (do NOT touch):** IOX register map (+0..+7), RSR1/RSR2
core bit layouts, WCWD command bits, WDAD/WSCT decode, sector geometry
(fmt0/1=128B/26sec, fmt2=256B/15sec, fmt3=512B/8sec), and the READ_DATA /
READ_ID / SEEK / RECALIBRATE paths — all faithful to §B.4 and matching between
the two models.

---

## C-side defects (`deviceFloppyPIO.c`) — real, unique to C

### C-PIO-1 [write-broken + wrong-error] Image opened read-only; write-protect guard is dead code
- Constructor opens the image `fopen(floppyName, "r")` (≈ `:229`) — **read-only**.
- `ExecuteGo` forces `RSR2.bits.writeProtect = false` (≈ `:351`), so the
  write-protect guards in WRITE / WRITE_DELETED / FORMAT_TRACK (≈ `:390/435/480`)
  can never fire.
- Result: every write actually fails at the C library level, surfacing as
  drive-not-ready (*inferred*), and the manual's real **write-protect = RSR2 bit
  9** (manual ≈9868-9870) is never reported.
- RetroCore C# does this correctly (honors real read-only via `IsDeviceReadOnly`,
  reports `WriteProtect`), so this is both a divergence-from-C# and a
  manual-violation.
- **Fix:** open the image read/write (`"rb+"`), track the real read-only state,
  and set `RSR2.writeProtect` (bit 9) when a write is attempted on RO media —
  instead of forcing it false. Only fall back to drive-not-ready for genuine
  seek/IO failures.

### C-PIO-2 [data-corruption] FORMAT_TRACK start position off-by-one
- FORMAT_TRACK computes `position = (1 * bytes_pr_sector) + track*bytes*sectors`
  (≈ `:396-397`) — it starts **one sector into** the track.
- Effect: it overruns the end of the track and leaves sector 1 unformatted.
- C# uses per-sector `(s-1)*bytes` starting at 0 (≈ `:825`), which is the correct
  track layout.
- **Fix:** start at the track base (`position = track*bytes_pr_sector*sectors`)
  and format sectors 1..sectors_pr_track from offset 0.

---

## C#-side defects (`NDBusFloppyPIO.cs`) — real, unique to C#

### CS-PIO-1 [breaks command in debug builds] `Debug.Assert(false)` landmines
- `Debug.Assert(false)` sits in FORMAT_TRACK (≈ `:820`, `:845`) and CONTROL_RESET
  (≈ `:1030`). In any debug build these commands **abort** — FORMAT_TRACK is
  effectively unimplemented.
- C runs both commands (however imperfectly — see C-PIO-2).
- **Fix:** either implement FORMAT_TRACK / CONTROL_RESET properly or remove the
  asserts and let them complete; do not leave an assert that aborts a legal
  driver command.

### CS-PIO cosmetics (low priority, note only)
- Deleted-sector map `DeletedSector[sector, track]` is unbounded and index-swapped
  vs C's bounds-checked `[track][sector-1]` (≈ `:1060`). Works in-range; would
  throw if indices exceeded 99.
- `IDENT` clears `InterruptEnabled` unconditionally (≈ `:1105`) even when this
  device did not raise the level. C acts only if it owns the pending interrupt.
- `Reset` does not clear `selectedDrive` / RSR2 (≈ `:420-425`); C resets
  `selectedDrive=-1` and `interruptBits=0`.
- Dead duplicate `SetBit911` (≈ `:734-756`).
- Drive-select decoded as 2 bits (`(value>>8)&0b11`, ≈ `:647`) vs the manual's
  3-bit unit field (b8-10); harmless for units 0-2 only.

---

## Shared deviations from §B.4 (both models agree with each other, both wrong vs the spec)

### SH-PIO-1 [wrong-status] CONTROL_RESET (control bit 15) leaves RFT=0 and generates busy
- `ExecuteGo` clears `ReadyForTransfer` on entry (C ≈ `:346`, C# ≈ `:770`). A lone
  control-reset word (0x8000) passes the `0xFF00` command mask, so it enters
  dispatch, transiently sets busy, and CONTROL_RESET then clears only busy —
  queuing no completion, leaving **RFT=0 with no interrupt**.
- Manual ≈9840: bit 15 (control reset) must NOT generate device-busy and gives no
  interrupt. **Fix:** route control-reset outside the busy/command path; do not
  clear RFT for it.

### SH-PIO-2 [wrong-status] Device-clear + command in one WCWD forces drive-not-ready
- WCWD processing order is device-clear(b4) → clear-buffer(b5) → command dispatch
  (C ≈ `:169-203`, C# ≈ `:561-629`). A word combining device-clear **and** a
  command deselects the drive (`selectedDrive=-1`) *then* runs the command →
  guaranteed drive-not-ready (C ≈ `:184/368`, C# ≈ `:591/792`). Drivers do
  combine bits in one IOX. **Fix:** decide ordering deliberately (a real
  controller latches the command against the drive selected at that write).

### SH-PIO-3 [wrong-status] Sector auto-increment steps one past the last sector
- Both use `if (sector <= sectors_pr_track) sector++` (C ≈ `:284`, C# ≈ `:1077`).
  Manual ≈9983: auto-increment is "not valid past the last sector." At the last
  sector this increments one beyond range. **Fix:** use `<` (stop at the last
  sector).

### SH-PIO-4 [UNVERIFIABLE] Autoload on control bit 2
- Both use control **bit 2 = Activate Autoload** (C ≈ `.h:82`, C# ≈ `:182`), and
  both implement the 388-byte `floppy_boot` blob one byte per 16-bit word
  (byte-per-word matches the `FLOPPY-FU-1986F` "Expected 000261"=0xB1 evidence).
- §B.4 line ≈9833 lists bit 2 as **"Not used"** — but the real autoload spec is
  in the unavailable ND-11.015 3027 manual. The two models AGREE, so leave as-is;
  mark as **unverifiable** until the 3027 manual surfaces. Do not "correct" it to
  the §B.4 "not used" reading.

### SH-PIO-5 [cosmetic] "Magic" RSR1 bits 9-11 and never-asserted diagnostics
- Both inject RSR1 bits 9/10/11 from `bufferPointer` (C ≈ `:104-110`, C# ≈
  `:461-463`) — not in §B.4, both label it a `FLOPPY-FU-1986F` test hack.
  Identical in both; leave (removing it breaks that test program).
- Diagnostic status bits the manual defines but neither model ever raises:
  timeout (RSR1 b8), CRC/overrun (RSR2), and — for C — write-protect (dead per
  C-PIO-1). Note only.

---

## Priority summary

| Sev | Model | Item |
|-----|-------|------|
| write-broken | C | C-PIO-1 read-only image + dead WP guard |
| data-corruption | C | C-PIO-2 FORMAT_TRACK off-by-one |
| breaks-in-debug | C# | CS-PIO-1 `Debug.Assert(false)` in FORMAT_TRACK / CONTROL_RESET |
| wrong-status | both | SH-PIO-1 control-reset RFT/busy |
| wrong-status | both | SH-PIO-2 device-clear+command ordering |
| wrong-status | both | SH-PIO-3 auto-increment boundary |
| unverifiable | both | SH-PIO-4 autoload bit 2 (needs ND-11.015) |
| cosmetic | both/C# | magic bits, deleted-map, IDENT, reset, dead code |

## How to validate
- The `FLOPPY-FU-1986F` floppy function test program is the real acceptance gate
  (the C model already tunes the magic RSR1 bits to it). Run it against each
  model before/after.
- Cross-check register/command behavior against §B.4 in
  `ND-06.015.02 ND-100 Functional Description.md` (lines ~9747-9990).
- If/when the ND-11.015 3027 manual is located, re-verify SH-PIO-4 (autoload
  bit 2) and the diagnostic status bits against it.
