# ND-120 generic sim PROBE — build, protocol, driver API, examples

**Full path:** `Verilog/sim/PROBE-README.md`

A ONE reusable, scriptable Verilator harness for the whole ND-120 CPU
(`VND120_TOP`) that you point at *any* signal and *any* trigger **at runtime**,
driven from Python the way nd100x is driven by `tools/nd100x_expect.py`. It
replaces the recompile-per-signal pattern of `latch_ff_compare.cpp` and the
hardcoded post-trigger window of `test_nd120.cpp`.

**REPORT-ONLY**: no RTL is edited — the probe is a NEW harness
(`nd120_probe.cpp`) built with the non-invasive flags `--public-flat-rw --vpi`.

**Why it exists** (from the retired design note, folded in here
28-SEP-2026): before it, `test_nd120.cpp` dumped the full FST with one
hard-coded post-trigger window (`logwin=60` on CSA 06000..06003 ->
`mic_trace.csv`), and `latch_ff_compare.cpp` wrote a per-cycle CSV of a
hard-coded signal list through `top->rootp->ND120_TOP__DOT__...` root paths.
Changing a signal meant editing C++ and a ~12 min Verilator rebuild, and there
was no runtime trigger and no pre-trigger history - exactly what a
store-routing bug needs. The probe fixes all three: signal list, trigger and a
pre/post ring buffer are chosen at run time.

```
  Python example scripts  (examples/mmu_177777_probe.py, ...)   <- the investigation
        |  import
  nd120_probe.py   (pexpect-style driver; mirrors nd100x_expect.py; stdlib only)
        |  spawn + line protocol over stdin/stdout (unbuffered)
  obj_dir_probe/VND120_TOP   built from nd120_probe.cpp  (the ENGINE)
        |  Verilator --vpi --public-flat-rw
  VND120_TOP  (whole ND-120, report-only RTL - never edited)
```

Files:
- `Verilog/sim/nd120_probe.cpp` — the engine.
- `Verilog/sim/nd120_probe.py` — the Python driver.
- `Verilog/sim/examples/mmu_177777_probe.py` — worked MMU example.
- `Makefile` target `probe`, and this README.

---

## 1. Build (WSL ONLY)

Everything Verilator/make/run happens inside WSL, working in the repo checkout
as WSL sees it. NEVER run a Verilator/Windows exe from Windows/MINGW.

```bash
wsl.exe -e bash -lc 'cd Verilog/sim && make probe USE_LATCHES=0'
```

- `USE_LATCHES=0` selects FF mode (the shipped FPGA path) — the default for
  investigations. The engine binary lands at `obj_dir_probe/VND120_TOP`.
- The `probe` target is **additive**: it does not touch `test_nd120` or the
  `compare_*` targets, and only adds files to `sim/`.

Underlying command the target runs:

```
verilator --trace-fst --vpi -Wall --cc ../ND120_TOP.v $(SUPPRESS_FLAGS) \
  -DVERILATOR_SIM -DFPGA_FF_MODE --public-flat-rw $(VERILATOR_DIRS) \
  --exe nd120_probe.cpp ../simDevices/NDDevices.cpp ../simDevices/NDBus.cpp \
  --Mdir obj_dir_probe
```

---

## 2. Line protocol (stdin → engine; engine → stdout)

The engine prints `OK probe ready ...` on startup, then one reply per command.
All replies are unbuffered (`fflush`). Emulated-terminal (UART) output goes to
**stderr** so it never corrupts the stdout protocol.

| Command | Meaning |
|---|---|
| `load <bpun-path>` | backdoor-load a BPUN into RAM |
| `deposit <octal-addr> <octal-val>` | backdoor word write (+parity) |
| `examine <octal-addr>` | → `VAL <addr> <val>` (octal) |
| `get <signal>` | one-shot read → `VAL <name> <val>` (octal) |
| `watch add <signal>` | sample a signal into the CSV ring |
| `watch group <MMU\|STORE\|BUS\|MIC>` | add a whole group |
| `watch clear` | clear the watch set |
| `set pre <N>` / `set post <N>` | ring depth / post-window |
| `capture csv <path>` / `open <path>` | select the compact CSV sink |
| `capture fst <path>` | select the windowed full-hierarchy FST sink |
| `capture off` | disable sinks |
| `rule add <name> [level] when "<expr>" do <acts>` | reactive rule |
| `rule clear <name\|all>` | remove rule(s) |
| `run <ticks>` | step N full sysclk cycles; emits EVENT/LOG as rules fire |
| `runto "<expr>" [maxticks]` | run until expr fires (one-shot rule + stop) |
| `reset` | pulse `sys_rst_n` low for 100 ticks |
| `send <text>` | queue chars to UART TX (`\r` = CR) |
| `signals` / `groups` | list registry names / group names |
| `quit` | exit |

**Reply verbs:** `OK …`, `ERR …`, `VAL …`, `EVENT …`, `LOG …`.
Event line example: `EVENT id=3 trig=top_shadow tick=812345 wrote=csv#rows=128`.

### Rule condition grammar (boolean over ANY signals)

```
or   := and ('||' and)*
and  := cmp ('&&' cmp)*
cmp  := unary (('=='|'!='|'<='|'>='|'<'|'>') unary)?
unary:= '!' unary | primary
prim := number | signal | '(' or ')'
signal := IDENT ['[' hi ':' lo ']']       # bit-select
number := o<octal> | 0x<hex> | <decimal>
```

Example: `MMU.s_wmap_n==0 && MMU.s_lshadow==1 && CSA_12_0 >= o6000`.
Rules are **rising-edge** by default (fire on false→true); add `level` to fire
every tick the condition holds.

### Rule actions (comma-separated)

- `log[:"msg"]` — emit a `LOG` line with the rule's referenced signal values.
- `fst_on` / `fst_off` — gate the windowed FST dump on a signal combination.
- `csv` — flush the PRE ring + arm the POST window into the CSV.
- `event` — emit a machine-parseable `EVENT` (default if no action given).
- `mark:"tag"` — labelled marker (into CSV + an EVENT line).
- `stop` — end the current `run`/`runto`.

---

## 3. Signal access — registry floor + VPI

Two-tier resolution (see `readSignal()` in the engine):

1. **Registry floor (guaranteed):** a curated `{name → root-path reader}` table
   using the proven `top->rootp->ND120_TOP__DOT__…` member pattern from
   `latch_ff_compare.cpp`. Always available. Covers groups:
   - `MIC`   = `CSA_12_0`, `XMIC_DBG_15_0` (top ports)
   - `MMU`   = `MMU.s_wmap_n`, `MMU.s_la_20_10`, `MMU.s_cyd` (+ VPI: `s_lshadow`, `s_epmap_n`, `s_ept_n`, `PON`)
   - `STORE` = `s_maclk`, `CBWRITE`, `CMWRITE`, `DISB`, `TST`, `BLOCKL`, `EBADR_n`, `BDRY`, …
   - `BUS`   = `DAP`, `BLOCK`, `RERR`, `BDRY`, `BACT`, `EBADR_n`, `EMD`, `CBWRITE`, `CMWRITE`, `s_term_n`
2. **VPI (arbitrary names):** any dotted signal name is resolved with
   `vpi_handle_by_name(...)` and cached. This is what lets a script name a signal
   the registry never listed. If the VPI layer cannot see a name, `get` returns
   `ERR … unresolved` and `watch group` reports `unresolved=N` — **honestly**,
   never a fake value.

**Verified hierarchy fact:** the MMU instance path is
`ND120_TOP.CORE.CPU_BOARD.CPU.MMU` (there is an extra `CPU` level vs the design
doc); `s_cyd`/`s_maclk`/`s_term_n` sit at `…CPU_BOARD.…`; `s_poni` at
`…CPU_BOARD.CPU.s_poni`.

---

## 4. Python driver API (`nd120_probe.Probe`)

Stdlib only; mirrors `nd100x_expect.py`. On Windows it auto-wraps the launch in
`wsl.exe -e bash -lc` (pass `wsl=False` on Linux). Methods:

```python
from nd120_probe import Probe
with Probe(bpun="INSTRUCTION-B.BPUN") as p:      # FF-mode binary
    p.load("INSTRUCTION-B.BPUN")                 # backdoor load
    p.deposit(0o1000, 0o123456); p.examine(0o1000)
    p.watch_group("MMU"); p.watch("CSA_12_0")
    p.set(pre=64, post=64); p.open("run.csv"); p.capture(fst="win.fst")
    p.rule("shadow", "MMU.s_wmap_n==0", ["log", "csv", "fst_on"])
    p.run(200000)
    ev = p.runto("CSA_12_0 == o6000", maxticks=1_000_000)   # -> Event or None
    print(p.get("MMU.s_wmap_n"), p.examine(0o177777))
    for e in p.events(): print(e.raw)
```

`expect_event(trig, timeout)` blocks for a specific EVENT; `wait_console(regex)`
matches emulated-terminal output (the driver can double as a TPE driver).

---

## 5. Worked example A — MMU 177777 store routing

`examples/mmu_177777_probe.py` investigates whether a paged store to logical
`177777` routes to MAIN or SHADOW. It instruments the shadow-write strobe
(`s_wmap_n==0`), adds a **control** normal-paged-store detector so a harness that
never issues a paged store can't masquerade as a bug, gates the FST on the
top-page window, and prints an HONEST verdict. Run:

```bash
wsl.exe -e bash -lc 'cd Verilog/sim && python3 examples/mmu_177777_probe.py'
```

Outputs: `mmu_177777.csv` (compact PRE/POST window) and `mmu_177777_win.fst`
(full-hierarchy, windowed).

## 6. Worked example B — gate the FST on a signal combo

Generic pattern: record a full-hierarchy FST **only** while a condition holds,
then read it with the existing tools. No script file needed:

```bash
wsl.exe -e bash -lc 'cd Verilog/sim && \
  printf "%s\n" \
    "load INSTRUCTION-B.BPUN" \
    "capture fst combo_win.fst" \
    "rule add win when \"CSA_12_0>=o6000 && CSA_12_0<=o6003\" do fst_on,mark:\"str2\"" \
    "rule add off when \"CSA_12_0==o145\" do fst_off" \
    "run 300000" \
    "quit" | ./obj_dir_probe/VND120_TOP'
# then read the windowed FST with the EXISTING tools:
wsl.exe -e bash -lc 'cd Verilog/sim && python3 vcd_extract.py combo_win.fst --list | head'
```

The windowed `combo_win.fst` is read by `fst.py::open_wave` (pipes through
`fst2vcd`) and `vcd_extract.py` (`-s NAME…`, `-p PATTERN`, `--gtkw`, `--tstart/
--tend`, `--json`, `--list`), and opens in GTKWave with `top_3202d.gtkw`.

---

## 7. Notes / honesty

- The RAM backdoor (`deposit`/`examine`) reads **MAIN** memory only (`b0_*`
  arrays). The MMU SHADOW array is a separate memory not exposed by the backdoor;
  "landed in shadow" is inferred from the shadow-write strobe, not read back.
- If a signal doesn't resolve (registry miss + VPI miss), the tools say so — no
  fabricated values.
- `send` paces characters: MOPC has no receive FIFO, so back-to-back characters
  are lost (a `1560&` once arrived as just `&`, which autoloaded the papertape
  instead of the floppy). The gap between characters is `ND120_SEND_GAP` sysclk
  ticks, default 300000 (`nd120_probe.cpp`); `runSim/Run120.cpp` has the same
  guard as `ND120_STDIN_GAP`.
- Other probe builds in `sim/Makefile`: `probe-floppy` (Verilog floppy),
  `probe-floppycore` (the portable C floppy core), `probe-wd` and `probe-wd-sd` (Winchester).
