> # SOLVED 24-AUG-2026 - this document is a HISTORICAL RECORD
>
> The ERRFATAL page-fault investigation this file belongs to is **closed**.
> Root cause: the memory bank was decoded from the wrong side of the bus
> transceiver (`ND3202D.v:533`). On an incoming DMA write the board drives
> nothing and that net idles all-ones, so every transfer decoded to BANK0 -
> disc data landed at the right ROW in the wrong BANK, the CPU fetched zeros
> from a page nothing had written, executed them as STZ and halted in
> ERRFATAL after exactly 143 s on every boot.
>
> **SINTRAN III now boots on the Tang Nano 20K.**
>
> Anything below describing the fault as open, or naming a suspect, is
> superseded. The measured trail and the theories that were REFUTED are in
> `PLAN-pf-campaign-prio.md`; the regression guard is `make test-bdbank`.

# Comparing the oracle against the Tang - what is actually affordable

**Full path:** `Verilog/fpga/tang-nano-20k/PLAN-oracle-vs-tang-tracing.md`
**Date:** 21-AUG-2026

Written after measuring the real numbers rather than estimating them.

---

## 0. What already exists - do not rebuild it

`F:\tmp\verilog` (= `/mnt/f/tmp/verilog`) already holds a working
oracle-vs-ND-120 comparison rig from earlier sessions:

| file | what it is |
|---|---|
| `oracle_make.sh` | builds an ND120CX oracle trace from nd100x; FULL ~104 B/line, COMPACT ~63 B/line |
| `lockstep.py` | timing-tolerant lockstep comparison, ND-120 trace vs oracle |
| `boot_compare.py` | compares an ND-120 RTL trace against the ND120CX oracle |
| `ctxdiff.py`, `ctxdiff_tight.py` | context-matched divergence hunt (first differing opcode/next-PC for the same context) |
| `oracle_full.trc` (2.35 GB), `oracle_1m.trc`, `nd120_*.trc` | previously captured traces, same column format |

Both sides emit the same columns:
`PIL PC OPCODE A D T X B L STS PIE PID IIE IID PGS MMU INT SEX`

**The ND-120 side of that rig has always been VERILATOR, never the Tang.**
That is the crux of the whole question below.

---

## 1. The hard numbers

### Oracle (nd100x)

- `--cputype=ND120CX` exists and works.
- Untraced speed: **2.9 M instructions/second**.
- Boot to `SINTRAN III RUNNING`: **between 10M and 20M instructions**.
- Trace cost: `-t` gives **190 B/instruction** raw; `oracle_make.sh` FULL is
  ~104 B/line, COMPACT ~63 B/line.
- **Full boot trace: roughly 1.3-3.8 GB.** Fine on F: (52 GB free).
- Also has `--watch=[phys:]ADDR[:r|w|rw]` (32 max) and `-B ADDR`. Octal needs a
  LEADING ZERO: `--watch=0175740:w`, not `175740`.

### Tang - the bandwidth ceiling

- **Console UART is fixed at 9600** and cannot be raised: the CPU board's baud
  thumbwheel is a hardware constant (BAUDV, microcode page 158) and
  `UART_BAUD_RATE` in `src/tang20k_defines.v:516` must match it. 960 B/s.
- **The debug dumper is a SEPARATE transmitter** and its baud is ours:
  `uart_tx #(.DELAY_FRAMES(1406))` on `clk2x` (13.5 MHz) in
  `src/ND120_TANG20K_TOP.v:1075`. `DELAY_FRAMES = 13.5e6 / baud`:

  | baud | DELAY_FRAMES | throughput |
  |---|---|---|
  | 9600 (today) | 1406 | 0.96 kB/s |
  | 115200 | 117 | 11.5 kB/s |
  | 460800 | 29 | 46 kB/s |
  | **921600** | **15** | **92 kB/s** |

  FT2232 handles 921600 comfortably. **That is a 96x improvement for one
  parameter**, and it costs nothing.
- Ring buffer today: **512 entries x 20 bits** of distributed RAM
  (`CAP_AW = 9`). Deeper costs logic cells the design does not have - 512 deep
  already overflowed the part once (see the comment at `:230`).
- SDRAM: 8 MB on the board, ND-120 populates 2 banks (~2 MB). Spare exists but
  it shares the controller with the CPU's own traffic.

### The arithmetic that kills full tracing on the Tang

A 20M-instruction boot, even at a minimal **5 bytes per record** (PC + opcode):

```
20M x 5 B = 100 MB
  at   9600 baud -> 29 hours
  at 921600 baud -> 18 minutes   (but needs 100 MB of buffering it does not have)
```

**There is no configuration in which the Tang streams a full instruction trace.**
The board has no storage for it and the link cannot carry it live.

---

## 2. The options, ranked by value per hour

### A. Keep the ND-120 side in VERILATOR - already built, still the best tool
Full traces, any depth, existing comparison scripts, no bandwidth limit.
**Cost:** hours of sim, no board.
**Risk, and it is real:** sim and silicon are already known to fail
differently, so a Verilator run may simply not reproduce the Tang's ERRFATAL.
Verify that it reproduces BEFORE investing in a long trace.

### B. Raise the dump baud - do this regardless
One parameter, `DELAY_FRAMES` 1406 -> 15. Every existing capture dumps 96x
faster: the 512-entry ring goes from 3.2 s to 33 ms. No downside; the console
is dead during a dump anyway.

### C. Landmark tracing on the Tang, not instruction tracing  ** RECOMMENDED **
Do not record instructions. Record only events that can be compared against a
filtered oracle log:
  - every level-14 entry (PIL 0->14) with P and IIC
  - every page-fault vector with LA and PT
  - every access whose page is one of the window pages 0o757/0o760/0o761
  - every page-table WRITE with index and data
A whole boot yields hundreds to a few thousand such records - **kilobytes**,
seconds to dump even at 9600. The oracle side is a grep over the existing
`.trc` files, or `--watch` for the memory events.

### D. Landmark COUNTING before landmark tracing
Cheapest possible comparison: both sides report only COUNTS - level-14 entries,
page faults, disc operations, page-table writes. Find the first count that
diverges, then aim C at that window. The ND120_PF_CAPTURE census already does
this on the Tang (`n_faults`, `last_la`).

### E. SDRAM-backed windowed trace
~1-2M records in spare SDRAM, dumped afterwards at 921600 (2M x 5 B = 10 MB =
~2 minutes). Gives a deep window, not a whole boot. **Only worth building if C
and D fail**, because it contends with the CPU's own SDRAM traffic and is the
most invasive option here.

### F. GAO
Documented (`GAO-HOWTO.md`) but wrong for this: needs a trigger armed for a
rare event, eats BSRAM the design has none of, and gives a microsecond window.

---

## 3. The concrete next step for the CURRENT question

The question is now narrow: **why does our machine access the ND-500 window
page (software `DPIT` page 60) when the oracle never does?**

Measured facts:
- The entry is deliberately unmapped on BOTH machines - SINTRAN writes zero to
  it (`IP-P2-SEGADM.NPL:503`, `0=:IWDN5  % CLEAR ND500 WINDOW`), confirmed on
  the oracle by a watchpoint hit at `PC=034747`.
- So this is NOT a missing mapping. It is a **spurious access**.
- SINTRAN reports the faulting instruction as `Perror` ~ `0644xx`
  (064406 / 064470 / 064544 across runs).

Cheapest decisive experiment, needs no board:

```
nd100x --cputype=ND120CX --boot=wd0 --wd0=<a COPY> -B 064406 -t
```

Stop the oracle at the same PC the Tang faults on and read what address that
code computes. If the oracle computes a different address there, the divergence
is in address generation and the trace comparison can be aimed at that exact
instruction instead of at 20M of them.

---

## 4. Two cautions

**Booting an image MODIFIES it.** `WD0-M.IMG` changed from `0af10921840e` to
`8b4785767949` after emulator boots - SINTRAN writes to the disc. Always boot a
COPY, or the image stops matching the SD card.

**There are now FOUR WD images**, all 78,643,200 bytes:
`WD0.IMG` (92b1b0be26b7), `WD0-M.IMG` (was 0af1…, the SD-card one),
`WD0-sim.IMG` (8072df07b29d), and `F:\tmp\verilog\TANG_WD0.IMG` (67a6a6119e2c).
Check which one is under test before drawing any conclusion - a full day was
spent on the assumption that the analysed image and the booting image were the
same file.

---

## 5. TANG_PC_HISTORY - built 21-AUG-2026, not yet run on the board

The instrument that follows from section 3, implemented and statically
validated. **No board run yet.**

### What it does

Records `{PIL[3:0], P[15:0]}` - 20 bits, the native width of the Tang's
existing capture ring - into that ring, and freezes it on an ACCESS to the
ND-500 window page. The oracle never makes such an access AFTER SINTRAN clears the ND-500 window
PIT entry, so the first one identifies itself and the ring holds the trail.

Be precise about why, because the obvious version of this argument is wrong:
the emulator updates PGS ONLY ON A FAULT (all four UpdatePGS call sites in
nd100x `src/cpu/cpu_mms.c` are error paths), unlike real ND-120 hardware where
PGS follows every VACC-qualified access. So "zero PGS occurrences" means "never
faulted there". It becomes "never accessed there" only because SINTRAN clears
that PIT entry, an access to an unmapped page must fault, and every fault
updates PGS. **Scope limit: this says nothing about the window before the
clear**, so the probe can fire legitimately during early initialisation - which
is one more reason the ~40 s arming delay matters.

### Where the code is

| file | change |
|---|---|
| `Verilog/DELILAH-CPU/CGA/circuit/CGA.v` | new `TANG_PC_HISTORY` block drives `XMIC_DBG_15_0` with `s_pr_15_0` (the P register). Guarded `ifndef TANG_PF_CAPTURE`. |
| `Verilog/fpga/tang-nano-20k/src/ND120_TANG20K_TOP.v` | new `TANG_PC_HISTORY` variant (`s_cap_src`/`stb`/`arm`/`event`, `CAP_POST=16`), a `pc_prev` register for change detection, and a TX-mux branch |

It reuses the existing generic capture framework - ring, freeze logic and hex
dumper are all shared and already proven on silicon. An earlier standalone
`ND120_PC_RING.v` was written and then deleted on finding that framework.

### Two constraints that shaped it

- **One debug port.** `XMIC_DBG_15_0` is the only 16-bit path out of the CGA
  and every probe wants it. `TANG_PF_CAPTURE` and `TANG_PC_HISTORY` are
  therefore mutually exclusive (defining both gave two drivers - the Gowin
  EX2000 failure - now guarded). A PC-history build has no page-fault readout,
  which is why the trigger is formed from `LA` at the top instead.
- **The trigger is EDGE-detected, and only partly qualified.** LA_23_10 holds
  its last value between accesses, so a bare `== 0o1360` would keep matching
  long after the access; firing on LA BECOMING that value pins the freeze to
  the access. The proper qualifier is VACC - which is what ND120_PF_CAPTURE
  gates its identical comparison on - but VACC is not routed out of the CGA and
  getting it to the top needs a port through ND3202D and ND120_CORE as well.
  That plumbing was attempted and backed out. Residual risk: a genuine
  transient where LA settles on 0o1360 at a clk2x edge with no translated
  access. It is detectable after the fact - the decoded trail would not end
  near the ERRFATAL - and the run can be repeated.
- **RAW vs SOFTWARE PNUMB.** The trigger compares
  `s_debug_la_23_10[9:0] == 10'o1360`. SINTRAN's WNDN5 is the SOFTWARE value
  0o760; the hardware index has its top two table bits complemented, so the RAW
  value is 0o1360. Matching 0o760 here would silently watch software page
  0o360 and never fire.

### Validation done

- preprocessor directive balance checked in both files
- exactly ONE driver of `XMIC_DBG_15_0` in every define combination, including
  the pathological both-probes case
- exactly one definition each of `s_cap_src` / `s_cap_stb` / `s_cap_arm` /
  `s_cap_event` / `CAP_POST` / `uart_txp` in the new mode
- **every existing build mode is CODE-IDENTICAL** to before the change
  (preprocessed output compared with blank lines and `line` directives
  stripped): default, `TANG_PF_CAPTURE`, `TANG_GRANT_CAPTURE`,
  `TANG_WD_TRACE_DUMP`, `FPGA_FF_MODE`, `USE_LATCHES`, `ND_WD_TRACE_TVEC_CSA`
- `verilator --lint-only` over all 289 Verilog sources: the new mode produces
  **the same single error as the default build** (the Gowin `rPLL` primitive,
  unavailable outside the vendor toolchain). No new errors.

### The decoder - built and validated 21-AUG-2026

`Verilog/fpga/tang-nano-20k/pc_history_decode.py`

```
pc_history_decode.py DUMPFILE --hist ORACLE_PC_HISTOGRAM
pc_history_decode.py --selftest
```

Reads the captured serial log, ignores the console output mixed into it,
decodes each 5-character entry (one PIL nibble + four hex digits of P) and
prints the trail oldest-first, annotating every address with how many times the
oracle executes it - so the addresses a healthy system NEVER runs stand out.

The histogram lives outside the repo, so it is an argument or the
`ND120_ORACLE_HIST` environment variable; no machine-specific path is baked in.

Validated without a board: `--selftest` passes 9 checks, and an end-to-end run
on a synthetic trail against the real
`oracle_pc_histogram.txt` correctly flagged 5 of 16 addresses as never executed
by the oracle and marked the scheduler dispatch at 032037 (17,560 oracle
executions).

**The self-test earned its place immediately** - it caught the author writing
the test data as "PIL followed by a 6-digit octal address" when an entry is
five characters: a PIL nibble plus FOUR hex digits of P. That mistake would
otherwise have surfaced only after a 35-minute board run.

### Still to do

1. build with `-PcHistory` (the switch is in `gowin_build.ps1`; it refuses to
   run together with `-PfCapture`) and flash
2. a board run to the ERRFATAL, then decode the trail

### BLOCKER FOUND 21-AUG-2026 - TANG_PF_CAPTURE does not build

Unrelated to this probe, but it will bite whoever tries that mode next:
`CGA.v:1133` connects `.c_pgs_at_read()` on the ND120_PF_CAPTURE instance, and
**no such port is declared** in
`Verilog/DELILAH-CPU/CGA/circuit/ND120_PF_CAPTURE.v` - the name appears only in
its comments. Verilator stops with `PINNOTFOUND`, and Gowin will too, so a
`-PfCapture` build cannot elaborate today. It predates this work (present in
commit 4f6feda). Either declare the output or drop the connection.

`TANG_PC_HISTORY` is unaffected - it does not instantiate that module.

### Reading the result

Feed the recovered PC trail to `$ND120_ORACLE_DIR/nd100x_disdrv.c` for
disassembly, and check each address against
`$ND120_ORACLE_DIR/oracle_pc_histogram.txt` to see whether the oracle ever
executes it. Addresses the oracle never executes are the interesting ones.


---

## 6. Run 1 failed, and what it taught (22-AUG-2026)

**Result: the ERRFATAL reproduced (Perror 064406, IIC 3) but NO dump arrived** -
zero bytes at 9600, 115200 and 921600, so the line was idle rather than
garbled. The console stopped mid-word at `PEA   `, where a healthy halt prints
`PEA   : 000000#`.

Two causes could not be separated from outside: the dumper took the pin and
sent nothing, or the trigger never fired and the CPU simply stopped printing.
`cap_post` decrements every clk2x cycle once `cap_trig` sets - it is NOT gated
on the sample strobe - so "a halted CPU stalled cap_done" is already excluded.

### THE TRIGGER CONSTANT IS ON WEAKER GROUND THAN IT LOOKED

`ND120_PF_CAPTURE` has `MATCH_PAGE_ONLY = 1` by default and **CGA.v does not
override it**. So the proven capture matched the PAGE FIELD ONLY
(`la_pnumb[5:0] == 6'o60`), in any page table - and the `MATCH_LA_19_10(10'o760)`
argument it passes is never evaluated. Its census counted 57 faults on page
0o60 spread across tables.

Our probe demands the FULL raw value 0o1360. **If the fatal access is on page
0o60 in a different table, this trigger cannot fire.** That is a live
explanation for run 1's silence.

### Run 2 changes - one build, self-diagnosing

- **fallback trigger**: if the LA match has not fired by ~199 s after reset
  (39.8 s arming + 159.1 s counting at 13.5 MHz), trigger anyway. A dump now
  happens either way. A trail ending in 0644xx means the LA match won; a trail
  ending elsewhere means it did not, and the ring/dumper chain is nonetheless
  proven.
- **`led[2]` shows `dbg_dumping`** under TANG_PC_HISTORY (guarded, so other
  builds keep the tape indicator). The board previously gave no clue whether
  the dumper ever started.

`hold_cnt` was deliberately left alone: at ~10 s after `cap_done` it was never
the constraint, and it is shared with every other capture mode.

### If run 2 dumps but the trail does not end at the fault

Loosen the trigger to page-only, exactly as the proven capture does:
`s_debug_la_23_10[5:0] == 6'o60`. It will fire earlier and more often, so pair
it with a larger `CAP_POST` or accept that the first occurrence is captured.
Change ONE thing at a time. A build is only about 6 minutes (measured
00:24:16 -> 00:30:20, 22-AUG-2026), so iterating is cheap - but a wrong guess
still costs a boot run, and mixing two changes still muddies the result.
