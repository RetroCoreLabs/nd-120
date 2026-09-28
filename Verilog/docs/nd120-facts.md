# ND-120 machine facts - the invariants that keep getting re-derived

Last verified: 24-AUG-2026. Board table, panel, interrupt sources and
software notes updated 28-SEP-2026. Every entry is measured or drawing-verified in
this repo's campaigns; each names its source. Add new facts WITH their
evidence; correct wrong ones rather than appending contradictions.

## Address spaces

- **Logical space: 64K words (16-bit word address) - per bank.** Any main-
  memory backend smaller than this WRAPS silently and corrupts software
  state (the 24-AUG LIST-FILE-NAMES runaway: `ND120_BLOCKRAM_ADDR_BITS=15`).
  Enforced by `test-blockram-space`.
- Physical: 24-bit; the 3202D board decodes banks BANK0/1/2. The Nexys
  BLOCKRAM carries 3 x 64K words (384 KB); the Tang SDRAM carries 4 MB =
  2M words in banks BANK0 (phys 0-1M) + BANK2 (phys 1M-2M) - address
  order BANK0, BANK2, BANK1, silicon-validated (MEM_RAM_49_SDRAM.v).
- DRAM protocol (sheet 49): AA carries the ROW at the RAS rising edge,
  the COLUMN one clock later; write data valid BEFORE CAS rises;
  window = RAS & CAS & bank. `lin = {row, col}` - the 2024 `{col,row}`
  reversal aliased everything (the 400& junk bug).

## Console terminal (internal device, IOX 0o300-0o307)

- Register map: 300 read data, 302 read input status, 303 write input
  control, 305 write data, 306 read output status, 307 write output
  control (nd100x `deviceTerminal.h`, verified against behavior).
- Input status bits: 0 = interrupt enabled, 2 = device activated (a soft
  latch from control-word bit 2), 3 = data available, 4-7 error bits,
  11 carrier missing.
- FILSYS's control word is 0o044004 (activate, 7-bit, parity).
- The IOX 30x service is MICROCODE (TRM2x at CSA 0o0520-0o0545): result =
  hardware IOR word OR scratch register R6 (the soft activated/interrupt
  state). The IOR word (CHIP_33G capture in `IO_UART_42.v`) is
  `{TBMT_n, DA_n, EAUTO_n, LOCK_n, CONSOLE_n, 1, BAUD[3:0]}`.
- Console interrupts (IO_REG_41.v): BINT10 = IOC bit2 & TBMT (output),
  BINT12 = IOC bit1 & DA (input), BINT13 = IOC bit3 & bit0 (RTC).
  Measured 24-AUG: TPE never sets IOC bit 1 - TPE input is POLLED (RTC
  tick), not interrupt-driven.
- The SC2661: TxEN=0 must NOT abort a character in flight (real chip
  finishes it) - fixed 24-AUG, guarded by `test-uart-txabort`.

## Interrupt sources (RTC and MOR)

- The RTC timebase is FREE-RUNNING from master clear: `s_rtc_cnt` in
  `DECODE_DGA_POW.v` has no start input; it counts every sysclk and is
  zeroed only by power-on reset (`s_rescl`) or the microcode re-arm
  (`COMM,CLRTC` -> `s_clrti`). IOC bit 3 (`IO_REG_41.v`, `s_ioc_3`) has no
  hardware set or clear - only software writes it: the 20 ms RTC
  trap-handler microcode (`MS20`, o2333) sets it via `WSIOC`. Level 13 also
  needs the OS to set IOC bit 0 (`BINT13 = IOC bit3 & bit0`, above).
  Open: IOC bit 7 ("Reset real time clock", `s_reset` in `IO_REG_41.v`) is
  captured but not wired to the DGA RTC; whether the real board used it
  needs the DELILAH schematic.
- MOR (Memory Out of Range) is a BUS-TIMEOUT interrupt on level 12. Chain:
  `DECODE_DGA_POW.v` A631 watchdog, re-armed by every BDRY, gives
  `s_tout = ~(s_a631_q | s_rfclk)` -> `BIF_BCTL_BDRV_7.v:251-252` splits it:
  timeout on an I/O reference = IOXERR (level 10), on a memory reference =
  MOR -> `BIF_BCTL_6` -> `BIF_5` -> `ND3202D` -> `CPU_PROC_CGA_33` `.XMORN`
  -> `CGA.v` -> `CGA_INTR.v:125` (`assign s_mor_n = MORN`; the old tie-off
  survives only behind `ND120_MOR_TIED_OFF`) -> `CGA_INTR_IRSRC.v`
  GATES_21 -> IREQ bit 12. Wired 15-JUL-2026, commit `3acef36`.
- On-board memory is decoded as 4 MB by PAL: `PAL_44445B.v:85` (CLRQ,
  PPN23..21 = 0) and `PAL_44446B.v:85` (`AOK = ~(BMEM_n|BD23|BD22|BD21|MOFF)`).
  Below 4 MB `PAL_44310D` always returns BDRY, so MOR can only fire for an
  address >= 4 MB that no ND-bus device answers.

## CPU registers

- WRF register file (`CGA_WRF_RBLOCK.v`): regs 0-7 = Z, D, P, B, L, A,
  T, X; reg 8 = STS; regs 9-15 = microcode scratch R1-R7 (so microcode
  field "A,R6" = physical reg 14).
- BSKP 0o1752xx: op field (bits 10:7), bit number (bits 6:3), register
  (bits 2:0, 5=A). `BSKP ONE 30 DA` (0o175235) = skip if A bit 3 set.
- ND-100 P-relative addressing: 8-bit SIGNED displacement, EA = own
  address + disp (0o203 = -125, not +131).

## Microcode

- WCS: 8192 x 64-bit microwords; the loaded listing ends at LUA 0o012513.
  CSA values above that are bus transients, never real states.
- The word layout: bits [15:0] = PROM RF=0 group ... [63:48] = RF=3;
  PROM byte index = LUA*4 + RF (see `Code/Microcode/gen_wcs_image.py`).
- TWO variants of word 0o2002 (MACL+1) exist historically: raw PROM
  (0x...60e0) and the 07-DEC-2024 run-simulator patch (0x...00e0,
  commit 895f360). Decoded 02-SEP-2026: the patch changes the A-operand
  field (RF0 bits 15:12) from `A,6` to `A,0`; the word is
  `A,6 B,R1 ALUF,PASSD ALUD,B IDBS,BMG`, so R1 <- 1<<A is the outer count
  of the master-clear wait loop (listing 001777-002003, "% WAITING LOOP
  0.5 - 1 SECOND", 64 x 65536 steps). Patched: 1 pass - a 64x shorter
  power-on wait, a simulator speed-up, not a bug fix (the old "clears the
  COND/F,JMP bits" wording here was wrong; those are bits 7:0, untouched).
  BOTH pass everything (measured 24-AUG: rig raw PASS, rig patched PASS,
  Tang raw PASS; MiSTer boots SINTRAN raw). **DECIDED 02-SEP-2026
  (Ronny): raw on the boards, patched in the simulators.** That decision
  covers word 0o2002 only - see 0o2003 below.
  `gen_wcs_image.py` writes `Code/Microcode/wcs/` (raw - Nexys, Tang,
  Basys3, MEGA65 and `Shared/support` for the MiSTer) and, with `--sim`,
  `wcs-sim/` (patched, for SKIP_WCS sim runs; equal to the sims' patched
  `AM27256_45133L.hex`). `test-microcode-sync` checks every copy of both
  the PROM images and the 33 WCS images against the variant its directory
  must hold. Builds made 24-AUG..02-SEP from `Code/Microcode/wcs` (Nexys
  builds since 24-AUG, the MEGA65 02-SEP cores, the MiSTer 18:42 02-SEP
  .rbf) carry the PATCHED word; they boot, and the only visible effect is
  the shorter power-on wait.
- A second patch, word 0o2003 (MACL3, the last word of the same wait loop):
  `Code/Microcode/AM27256_45132L.hex` byte 4109 (= LUA 0o2003 x 4 + RF 1) is
  0x01 where the PROM dump `AM27256_45132L.bin` has 0x81 - commit d6799aa
  (07-DEC-2024, "Patched microcode address 002003 to disable waiting
  loop"). `gen_wcs_image.py` reads that `.hex`, so the board WCS preloads
  (`Code/Microcode/wcs/`, `Shared/support/wcs_*.hex`) carry this patch too;
  the `CPU-BOARD-3202/circuit/BIF_BCTL_SYNC_8/sim/AM27256_45132L.hex` fixture
  is the copy that holds the raw byte. Measured 28-SEP-2026. Whether the
  boards should get the raw byte is an open owner decision.

## Boards - intended configuration differences (Tang vs Nexys)

| item | Tang Nano 20K | Nexys 4 DDR |
|---|---|---|
| main memory | SDRAM 4 MB, PACK16 | DDR2 behind a BRAM cache (`MAIN_RAM_DDR2`, default since 25-AUG; `-tclargs bramram` = old 64K-words/bank BRAM, aliases) |
| CPU cache | `ND120_NO_CACHE` (the cache does not fit) | compiled in by default (`-tclargs nocache` removes it); all 8 cache tests pass on the board (31-AUG, `CACHE-STATUS.md`) |
| CPU clock | `slow` 6.75 MHz is the build default; `fast20` 20.25 MHz is the timing-clean fast variant | build default `clk 16` (16.67 MHz); deployed build runs `clk 33` (33.333 MHz) |
| WCS | preload (SKIP_WCS_LOAD) | preload (SKIP_WCS_LOAD; `-promload` for runtime) |
| storage | SD via nd_storage, discs uncached | SD + DDR2 region, Winchester cached |
| console | 115200 (`UART_BAUD_RATE`, every variant since 27-AUG) | 115200 by default (`baud=9600` still accepted) |

The microcode still believes the console runs 9600 (thumbwheel BAUDV 8);
the physical rate is the `UART_BAUD_RATE` build constant alone
(`fpga/tang-nano-20k/src/tang20k_defines.v`, `fpga/nexys4ddr/build.tcl`).

Shadow RAM (TMM2018D page tables): IDENTICAL on both boards - sync-read
model, `TMM_ASYNC_READ` defined by no build (verified 24-AUG).

Board-parity sim builds: `make rig-nexys` / `make rig-tang` in
`Verilog/dmaSim/`.

## Panel processor

- Accessed via TRA PANS / TRR PANC (message protocol with a calendar
  clock, see nd100x `src/devices/panel/`). The MC68705/MM58274 clock is
  emulated by `CPU-BOARD-3202/circuit/PANCAL_68705_CLOCK.v`, opt-in via
  `ND120_PANEL_CLOCK` (ON by default in the Nexys `build.tcl` and the Tang
  `gowin_build.ps1`; sims need `PANEL_CLOCK=1`). See `panel-clock-68705.md`.
- Without `ND120_PANEL_CLOCK` the panel is a stub: TPE prints
  `==TPE42=> The clock is not updated (display panel wrong or unexisting)`,
  which a real panel-less machine also prints.

## Known software behaviors (for expect scripts)

- FILSYS: bare CR to "User no." = list user 0; letters at numeric
  prompts are silently swallowed; unknown device name prints the legal-
  answers list; prompts sit silent indefinitely (no timeout reprint).
- TPE: `HELP` is interactive (prompts `Command:`); an unknown command
  returns straight to `TPE>`. Golden dialogs: `Verilog/tests/golden-console/`.
- TPE loading: only the FIRST program is loaded by its bare name; every
  later one needs `LOAD <name>` (a bare name then answers
  `*** No such command ***`). After a load, wait for ONE new `TPE>` in the
  text written since the command before sending `RUN`; watch for
  `NO SUCH FILE NAME` too. Floppy names: `CONFIGURATIO-D05:TEST`,
  `INSTRUCTION-C03:TEST`, `PAGING-C02:TEST`, `MEMORY-D04:TEST`,
  `CACHE-1X0-A00:TEST` (`CONFIGURE` is rejected). CONFIGURATION ends with
  `=== END OF INVESTIGATION ===`, not "END OF TEST".
- `400$` BPUN load: `?` after it is a BPUN checksum error, and the machine
  is right (microcode: nd120uc repository,
  `source/nd-120-delilah-L-from-K.uc:6212`). A BPUN with `execute = 000000`
  loads and does not start; start it with `20!`.
- OPCOM output is sent one character at a time by the microcode routine
  MOPC. On the boards, `IO_37.v` pulses STAT3 when the UART transmit
  register drains, so MOPC runs at character rate; without that kick it
  would send one character per 20 ms RTC tick.

## SINTRAN crash decode

Recorded in August 2026 while chasing the Nexys/Tang disc hangs (retired
floppy-DMA handoff, git `c4896a4`; retired page-fault plans, git `043c460`).
The addresses are for the SINTRAN image booted then; not re-checked since.

- `ERRFA` = 004356 is ERRFATAL itself. It saves X -> 004347, T -> 004350,
  A -> 004351, D -> 004352, L -> 004353. Its A is IRETR (the retry-limit
  constant, -5) and carries no information.
- Winchester driver wait loop 042510-042514: `042512 JPL I -104` calls WISTA
  (runtime 077132), `042513 JPL I 7` = CALL ERRFATAL (the error return),
  `042514 JMP -2` = the busy return. WD datafield base B = 042346 (SSTAT
  042244, SVLCA 042312, SVLWC 042313).
- Disc-operation latency (the sim's SD pace, or the old 362 ms FAT walk)
  makes SINTRAN's driver time out -> ERRFATAL / DILLC / MEMER.
- `IOXT` is opcode 150415 (not 143700).
- FILSYS command `OPCOM` drops to `#` with memory intact; `<` dumps stop on
  any input character; OPCOM prints about 1.3 lines/s.
- Page-fault anchors: Perror = P of the interrupted level
  (`MP-P2-2.NPL:396`); the IPAGFAULT ND-500-window branch is at
  `MP-P2-2.NPL:283`; `WNDN5 = 000760` = page table 7 (DPIT) page 60;
  `IP-P2-SEGADM.NPL:503` `0=:IWDN5 % CLEAR ND500 WINDOW` (watchpoint hit at
  PC=034747).

## Testbench lessons

- Read the FIRST error, not the loudest cluster - a random soak repeats one
  mismatch thousands of times after the real first failure (bank-map tb,
  04-AUG-2026).
