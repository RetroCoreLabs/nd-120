# INSTRUCTION verifier (TPE Monitor, floppy) - run guide

**Date:** 2026-07-23, trimmed 28-SEP-2026.

The preferred CPU-correctness test to drive from the floppy-booted TPE
Monitor: it is fast, prints every instruction as it runs, and completes all
levels (it does not loop forever like the MEMORY test).

**Status.** The failures once logged in this file are solved; the
investigation log is in git history:
- Banner `INSTRUCTION` printed as `INST\x7f\x7fCTION` (word-index 2 read as
  all-ones): solved 26-JUL-2026 by the cache HIT-gate in
  `CPU-BOARD-3202/circuit/CPU_MMU_CACHE_25.v` (see the comment there).
- Cx instructions / MOVEW APT->APT: solved 31-JUL-2026, commit `727c23e`
  (`CGA_MAC_DECODE.v` GATES_5). On the Tang Nano 20K the full sweep then ran
  clean: level 1 all 15 areas "End of test", levels 2-9 clean, ending
  "The tests are now looping" (the verifier's normal full-pass behaviour).
- The known-good reference log this file started from showed
  `No interrupt generated on level 14` for the Page fault source on every
  level; that item is not open against our RTL.
- A sim-only RTC hazard in the init sweep is described in section 4; whether
  it still hits a default Verilator build has not been measured since
  24-JUL-2026.

> **BUILD TRAP (cost hours, 2026-07-24): the floppy-TPE boot needs FF mode.**
> A probe engine built **without** `-DFPGA_FF_MODE` (i.e. latch mode, the
> `USE_LATCHES=1` default) boots the microcode self-test fine but **never
> reaches the floppy `TPE>` prompt** - the console stops right after the
> `1560&` echo and produces no further output, at any tick count. This is
> silent: no crash, no error, just no boot. Confirmed by bisect: the engine
> `obj_dir_probe_dbg` (has `-DFPGA_FF_MODE`) boots to `TPE>` at ~44M ticks; an
> otherwise-identical build without it does not, at 122M+.
> - Verify a built engine's mode:
>   `grep -o FPGA_FF_MODE <objdir>/VND120_TOP__verFiles.dat` (empty = latch = will not floppy-boot).
> - The `Makefile` probe targets (`make probe-floppycore`) add `-DFPGA_FF_MODE`
>   automatically because the probe defaults to `USE_LATCHES=0`. **Hand-rolled
>   build scripts must add `-DFPGA_FF_MODE` explicitly** or the engine will not
>   boot the floppy (three helper scripts of July 2026 left it out, and every
>   run built on them silently failed to boot).

---

## 1. How to run it

1. Boot the real TPE Monitor: at the `#` prompt send **`1560&`** (floppy
   autoload, portable C core; image
   `Verilog/runSim/FLOPPY1.IMG`). Reaches `TPE>`
   in ~17-20 min at ~46k ticks/s. (Send-gap fix confirmed — boots real B01.)
2. At `TPE>` load the INSTRUCTION diagnostic: **`INSTRUCTION`** (`load inst` also works,
   as used on the Tang 31-JUL). Banner:
   `INSTRUCTION - Version: C03 - 1988-03-04`.
3. **Set parameters FIRST** (so each instruction name is printed and we can see
   which one runs and how it behaves):
   ```
   TPE>set-para,N,N,Y,N,Y
   ```
   5 comma-separated flags. Exact meaning of each flag is NOT yet confirmed
   (INFERRED: one Y enables per-instruction console echo; others select
   loop/stop-on-error/level range). Use this exact string until the flag
   semantics are documented. TODO: confirm each flag from the C03 test or the
   TPE-MON reference.
4. Run: `TPE>run`

The whole run (9 levels) is quick in wall-clock on real hardware (banner
timestamps span 15:36:08 -> 15:36:20, ~12 s). Ends with `=== End of run ===`
and returns to `TPE>`.

### TPE Monitor commands (learned while running the MEMORY test)

At the `TPE>` prompt commands are case-insensitive and abbreviations are
accepted:

| Command    | Effect |
|------------|--------|
| `HELP`     | lists all commands |
| `mem` / `MEMORY` | loads the **MEMORY** diagnostic (Version **D04**, 1988-02-01) |
| `run` / `RUN`    | runs the loaded test (for MEMORY: READ, WRITE/READ 7-pattern, walk, parity, ...) |

`config` is a dead end: in TPE B01 it is echoed but drives no test (paging
never turns on, no memory activity). It came from the stale
`SCRIPT_CMD_FBOOTCFG` string `"1560&config\rrun\r"` in `runSim/Run120.cpp`.
Use the test name and then `RUN`.

Expected MEMORY output (reference): `MEMORY - Version: D04 - 1988-02-01`,
`Total memory size....: 4.000 Mbytes`; `RUN` then prints one line per area
(`AREA TESTED`, READ TEST ON PROGRAM PART, ADDRESSES IN ADDRESSES,
WRITE/READ TEST (7 PATTERNS), RAPIDLY CHANGING ADDRESS BITS, PARITY ERROR
DETECTION, WALK TEST (34 PATTERNS)), each ending `=== END OF TEST ===`, then
`=== THE TESTS ARE NOW LOOPING ===`. MEMORY is very slow (huge loop counts),
which is why INSTRUCTION is the better first target.

---

## 2. CPU configuration banner (expected, from a known-good run)

```
    INSTRUCTION - Version: C03 - 1988-03-04

CPU type.............: ND-100/CX upgraded for 16 PITs
Floating format......: 48 bits
Memory management....: MMS-2
Cache................: Manually disabled
ALD register content.: 1560B
Cpu cycle............: Fast
```

NOTE the config says **Floating format: 48 bits** and the test includes a
`48 bits floating instructions` group (DNZ NLZ FMU FDV FAD FSB). Our PROM
microcode implements the **32-bit** float option
(`Verilog/docs/48bit-float-not-configured.md`),
so behaviour of that group may differ from this reference — track separately.

---

## 3. Test structure

The verifier runs **9 levels** (`=== Running Tests on Level 1 ===` ...
`Level 9`). Each level executes the SAME sequence of instruction groups, echoing
every instruction mnemonic as it is exercised. In Level 1 each group closes with
`=== End of test ===`; levels 2-9 print just the mnemonics then the
internal-interrupt section.

Instruction groups per level (in order), with the mnemonics printed:

| Group | Mnemonics |
|-------|-----------|
| Argument | SAA(x2) SAT(x2) SAB(x2) SAX(x2) AAA AAT AAB AAX |
| Memory reference | STZ STA STT STX LDA LDT LDX MIN(x2) LDF STF LDD STD SBYT LBYT ADD(x3) SUB(x3) AND(x2) ORA(x2) MPY(x2) |
| Sequencing | JMP JPL JAP JAN JAZ JAF JXN JPC JNC JXZ SKP |
| Register | RADD RSUB RAND(x2) RORA(x2) REXO(x2) SWAP COPY RMPY RDIV MIX EXR |
| Bit | BLDA(x2) BSTA BSTC BLDC BANC(x2) BORC(x2) BAND(x2) BORA(x2) BSKP(x3) BSET(x4) |
| Shift | SHA(x9) SHT(x9) SHD(x9) SAD(x9) |
| 48 bits floating | DNZ NLZ FMU FDV FAD FSB |
| Privileged | LOAD/STORE REGISTER BLOCK ; TRA/TRR PID/PIE |
| Byte | BFILL MOVB MOVBF |
| Physical memory | SEX EXAM LDATX LDXTX LDDTX LDBTX STATX STZTX STDTX |
| Binary coded decimal | ADDD SUBD COMD SHDE PACK UPACK |
| Cx | TSET RDUS MOVEW {PT,APT,PHYS} => {PT,APT,PHYS} (9 combos) |
| Stack | INIT LEAVE |
| Segment | SETPT CLEPT CLNREENT CHREENTPAGES CLEPU |
| Internal interrupts | (see below) |

### Internal interrupts group (walks each internal-interrupt source)

Sources printed, in order:
```
Not assigned / IOX-error / Not assigned / Privileged instr. / Not assigned /
Error indicator (z) / Not assigned / Illegal instruction / Not assigned /
Page fault / Not assigned / Protect violation / Not assigned / Monitor call /
Not assigned
```

---

## 4. Sim-only hazard: RTC fires inside the masked init sweep (24-JUL-2026)

Seen in Verilator only, before the fixes listed at the top; not re-measured
since. On `run`, our sim printed
`*** TPE initialization error *** Impossible to clear ... IDENT interrupt on level`.

- Mechanism (traced): the init sweep masks interrupts while it clears the 16
  request latches. The RTC fires, the RTC trap-handler microcode sets IOC bit 3
  (level 13 source; bit 3 has no hardware set or clear, `IO_REG_41.v`), and
  while masked nothing clears it - so the level-13 verify fails. At the sim
  RTC default (8192 sysclk) a fire lands in almost every masked window; on real
  hardware (20 ms) it almost never does.
- Rate alone is not a full fix: even a 2,000,000-tick period (near the 21-bit
  `s_rtc_cnt` ceiling) still failed once. A real fix would have to stop the RTC
  firing while interrupts are masked, or widen the counter.
- Knobs (both sim-only, default-preserving):
  - build time `-DRTC_SIM_20MS=<cycles>` (see `build-defines.md`). Boot is
    RTC-paced, so a large value slows the boot by the same factor.
  - run time: probe command `rtc [20ms [5ms]]` / `Probe.rtc(cycles)`, needs the
    engine built with `-DND120_RTC_RUNTIME` (`sim/nd120_probe.cpp`; RTL vars
    `s_rtc_20ms_var`/`s_rtc_5ms_var` in `DECODE_DGA_POW.v`). Boot fast at 8192,
    then poke a slow period only for the test.
- OPCOM input is also RTC-paced (one typed character per RTC tick). Type every
  command (`INSTRUCTION`, `set-para`, `run`) at the fast default, and only poke
  the RTC slow after `run` has been received. `-DRTC_REAL_PERIOD` on its own
  never reached `TPE>` because the harness typed faster than MOPC could read
  (`ND120_SEND_GAP` must scale with the RTC period).
- Trap when reading probe CSVs: multi-bit values print in **octal**; `RTC_CNT`
  tops out at `20000` = 8192 decimal.

---

## 5. Why this test, not MEMORY

- MEMORY (D04) runs enormous loops and is very slow; poor for iteration.
- INSTRUCTION (C03) is fast, prints every instruction and completes. It is the
  right harness for CPU-instruction/interrupt debugging from the floppy-booted
  monitor.
```
