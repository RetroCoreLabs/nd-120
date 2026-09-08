# Nexys 4 DDR debug panel - every LED, switch, button and display digit

What each board indicator means on the ND-120 build, and how to use them in
a debugging session. Wiring lives in `nd120_nexys4ddr_top.v` (LED assigns,
RGB drives, `panel_value`); pin constraints in `nd120_nexys4ddr.xdc`.
Last verified: 25-AUG-2026.

## The 16 plain LEDs (LD0-LD15, left of the switches)

| LED | Signal | Meaning |
|-----|--------|---------|
| LD0 | storage block read (stretched) | flickers while the SD/FAT stack reads card blocks |
| LD1 | storage block write (stretched) | flickers while the stack writes card blocks |
| LD2 | SD wire activity (stretched) | any SD clock movement - card traffic of either kind |
| LD3 | `sys_rst_n` | reset released; OFF = board held in reset |
| LD4 | `~cpu_txd` | console output activity (flickers while the machine prints) |
| LD5 | heartbeat | slow blink = clocks alive; frozen = clocking dead |
| LD6 | `~s_run` | CPU RUN flip-flop - ON = machine executing (not in OPCOM stop) |
| LD7 | `~s_debug_lcs_n` | microcode loaded (WCS load completed) |
| LD8 | `s_debug_mr_n` | master-clear line released |
| LD9 | `calib_done` | DDR2 controller calibrated - must be ON before any boot |
| LD10 | `s_sd_status[0]` | SD stack status bit 0 (card mounted) |
| LD11-LD15 | `~s_debug_cc_term[4:0]` | microcode condition codes CC0-CC3 + TERM |

## The two tri-colour LEDs (LD16, LD17, left of LD15)

Dimmed to ~6% duty in the top - full-on RGB is blinding.

**LD16 - DDR2/arbiter health** (the watchdog's face):

| Colour | Signal | Meaning |
|--------|--------|---------|
| GREEN | `calib_done & ~stuck & ~orphan` | memory system healthy |
| RED | `dbg_stuck` (sticky) | the DDR2 port stopped answering mid-operation - watchdog fired |
| BLUE | `dbg_orphan` (sticky) | a DDR2 response arrived with no grant held |

**LD17 - memory traffic:**

| Colour | Signal | Meaning |
|--------|--------|---------|
| GREEN | `~s_run` | CPU executing |
| RED | MEM_HOLD activity (stretched) | DDR2 cache misses happening - the CPU is being frozen for refills |
| BLUE | storage grant (stretched) | the SD/storage client is using the DDR2 port |

Colours mix: LD17 solid yellow = running with heavy miss traffic; LD16
steady green is the normal state from calibration to power-off.

## The 8-digit 7-segment display

Driver: `SevenSegDebug8.v`. All digits hex. Digit 0 is rightmost.

**Right four digits (3..0)** - selected by switches, as before:

| sw15 sw14 | Shows |
|-----------|-------|
| 0 0 | sw0=0: CSA (microcode address, live) - sw0=1: LA (latched address bus) |
| 0 1 | {FDISK request count, FDISK done count} |
| 1 0 | {FDISK error count, first error code, last error code} |
| 1 1 | first FDISK logical sector requested |

**Left four digits (7..4)** - fixed live debug panel, new 25-AUG-2026:

| Digit | Value | Decode |
|-------|-------|--------|
| 7 | PIL | current interrupt level, one hex digit (B = the PIL-11 disc level) |
| 6 | {astate[2:0], MEM_HOLD} | DDR2 bridge state x2 + hold; even = astate with HOLD low, odd = the CPU is frozen right now |
| 5 | {last_hit, refill_pend, op_busy, have_data} | bridge detail bits |
| 4 | {0, ptw_overlap, dbg_orphan, dbg_stuck} | 0 = healthy; bit0 = DDR2 watchdog fired; bit1 = orphan response; bit2 = a page-table write strobe overlapped a MEM_HOLD freeze at least once (sticky; measured 0 across full boots - if it ever lights, capture s_ila_ptwhold_* with the ILA) |

Reading digit 6: the value is `astate*2 + MEM_HOLD`. astate: 0=A_IDLE,
1=A_COL (column on AA, lookup issued), 2=A_CHK (tag compare), 3=A_MISS
(frozen, waiting for the refill), 4=A_TAIL (access done, waiting out RAS)
- from `ddr2/MEM_RAM_49_DDR2.v`. A machine sitting at digit6=7 (astate 3,
HOLD 1) forever = a refill that never completes.

## Switches

All 16 slide switches, as wired in `nd120_nexys4ddr_top.v` (verified 30-AUG-2026).
Down = 0, up = 1. Every switch is read through two flops on its clock domain;
none has a debounce, none needs one.

| Switch | 0 (down) | 1 (up) | Needs |
|--------|----------|--------|-------|
| sw0 | right display shows CSA (microcode address) | shows LA *(always zero, see 7-segment section)* | only when sw15:14 = 00 |
| sw1 | US ANSI keyboard + font | Norwegian (NS 4551-1) keyboard + font - one bit drives both, so what you type is what you see | VGA console (default build) |
| sw2 | VGA 800x600 at 40 MHz pixel clock | 1920x1080 at 148.4 MHz - debounced 26 ms before it reaches the clock mux | VGA console |
| sw3 | operator panel hidden | operator panel drawn under the console text (PIL, hit rate, uptime ...) | VGA console |
| sw4 | **CPU cache ON** - the ND-100 console's SW1 (sheet 25 CON), the state every deployed image has run with | cache OFF - every access goes to main memory, the CSR reports the cache disabled; flip it at the OPCOM prompt or reboot, the cache is not flushed by the switch | cache compiled in (default; `nocache` removes it and the switch does nothing) |
| sw5 | keyboard debug off | 7-seg shows the last raw PS/2 scancode (extended/release + code), when sw6=0 and sw15:14=00 | debug |
| sw6 | keyboard debug off | 7-seg shows the DECODED keyboard byte the table hands on (e.g. F1 = 00B2), when sw15:14=00 | debug |
| sw7 | **console 115200 baud** (default) | **console 9600 baud** - drops BOTH the USB-serial line (SC2661) and the on-screen terminal to 9600, in lockstep, for software that cannot take 115200. No rebuild; the microcode baud thumbwheel stays at 9600 so boot is unaffected. Verified on hardware 06-SEP-2026 | - |
| sw8-sw13 | unused | unused | - |
| sw15:14 | right-display mode: 00 = sw0 picks CSA/LA, 01 = {FDISK request count, done count}, 10 = {FDISK error count, first error code, last error code}, 11 = first FDISK_LSECT requested (table above) | | - |

`sw1`-`sw3` exist only in the VGA-console build; without it (`novgaconsole`)
they are read by nothing. `sw4` reaches the CPU through `ND120_CORE.CACHE_SW`
-> `ND3202D.SW1_CONSOLE` -> `CPU_MMU_CACHE_25.CON`, so it is the real
machine's switch, not a debug override: SINTRAN sees the cache status change
exactly as it would on a 3202 board.

## Buttons

| Button | Function |
|--------|----------|
| CPU RESET (red, C12) | active low - held = ND-120 in reset, released = full boot restart |
| BTNC (centre) | second reset, OR'ed with CPU RESET |
| BTNU/BTND/BTNL/BTNR | unused |

## Using dbg_stuck in a debugging session

The scenario it exists for: the machine freezes silently - console dead,
no ERRFATAL, heartbeat still blinking. Before 25-AUG-2026 that state gave
no information at all (the stale-word hunt in `SINTRAN-BOOT-25AUG.md` cost
a full day partly for this reason). Now, in order:

1. **Look at LD16.** RED = the DDR2 port stopped answering: the fault is in
   the MIG/`nd_ddr2_port.v`/power domain - STOP hunting in the CPU,
   microcode, cache or SINTRAN. Not red = memory answered everything;
   the hang is elsewhere (CPU state, interrupt system, software).
2. **Look at digit 4** of the display: 1/3 confirms stuck, 2 says a
   response was mis-timed (arbiter/port protocol upset) even though
   nothing hangs yet.
3. **Look at digit 6.** Odd value = the CPU is frozen in MEM_HOLD right
   now; with LD16 red that is a dead refill. Even value with a dead
   console = the CPU is executing but not printing - a software spin, go
   to the ILA (`ila_ddr2hang.tcl` mode `snap`) and read CSA/PIL instead.
4. The same flags are ILA probes (`s_ila_arbflags`) for captures, and
   both are sticky until the next reset or reprogram, so a hang that
   happened hours ago still shows.

The watchdog itself is in `ddr2/nd_ddr2_arb.v` (2^16 ui_clk cycles =
874 us; nothing legitimate is remotely that slow). It deliberately takes
no action - releasing the grant or faking a completion mid-operation is
the corruption class `SINTRAN-BOOT-25AUG.md` documents. Unit test:
`make test-ddr2arb` in `CPU-BOARD-3202/circuit/sim/` (in the repo's
Verilog tree), including a dead-port test proving the flag rises and the
grant holds.
