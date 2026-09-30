# Contributing to nd-120

Thanks for looking. This file says how to get a build running, what the code is expected to look
like, and what will get a change sent back.

---

## Getting a build

The work is done on **Linux or WSL2 with bash**. The simulators and the test suite run there; the
FPGA vendor tools (Vivado, Gowin, Quartus) run on the Windows host and are only needed to build a
bitstream. Ready-built bitstreams are on the releases page, so most changes need no vendor tool at
all.

| # | Requirement | How to check |
|---|---|---|
| 1 | Icarus Verilog - the unit test benches (`*_tb.v`) | `iverilog -V \| head -1` |
| 2 | Verilator 5.x - the whole-machine simulation (`test_*.cpp`) | `verilator --version` |
| 3 | Python 3, `dosfstools`, `mtools`, `yosys` - test helpers and the Tang netlist checks | `python3 --version` |

The CI job installs exactly these on Ubuntu:

```bash
sudo apt-get install -y iverilog verilator dosfstools mtools python3 yosys
```

Every tool, its version on the development machine and what uses it is in
[Verilog/docs/PREREQUISITES.md](Verilog/docs/PREREQUISITES.md). Every build option is in
[Verilog/docs/build-defines.md](Verilog/docs/build-defines.md).

```bash
# from the repository root
python3 configure.py                 # once per clone: tools, submodules, microcode images, local.mk
make -C Verilog test                 # every self-checking test bench
```

`make test` itself needs no local setting (the CI runs it on a clean clone with only
`cd Code/Microcode && python3 gen_wcs_image.py` before it); `configure.py` is what makes the
microcode images on your machine and what every board build reads - see
[Local settings](#local-settings).

`make test` runs every registered test bench, **fail-fast**: the first failure stops the run with
exit 1. `make test-instr` runs the INSTRUCTION-B trace gate, and `make test-full` adds the heavy
system gates. [BUILDING.md](BUILDING.md) has the simulator and board build steps.

### The rule that will stop you first: every test bench is registered

A test bench lives in a `sim/` folder **next to the module it tests** - there is no central test
tree. And **every test bench must be added to the registry** in
[Verilog/tests/run_all_tests.sh](Verilog/tests/run_all_tests.sh), with a strict pass pattern
(`TB_RESULT: PASS` is the convention). A test bench that is not registered never runs, and the
suite's own first check (`test-tb-catalog`) fails when it finds one.

Every test bench must print a verdict a machine can check. A test that can pass silently can fail
silently.

---

## What the code is expected to look like

 - **Keep the Logisim structure.** Most of the Verilog was first made from the Logisim-Evolution
   schematics; it is now kept by hand, so a fix to the logic belongs in both places.
 - **Names:** internal signals use the `s_` prefix; buses are `BUSNAME_BITS` (`CD_15_0`); active-low
   signals end in `_n`.
 - **No `z` inside the FPGA.** A "3-state" buffer drives `0` when disabled, not `z`.
 - **Flip-flops on silicon, latches only in simulation.** The FPGA builds run in flip-flop mode;
   `test-no-latches` enforces it. `make compare` in `Verilog/sim/` proves a change leaves the
   latch and flip-flop traces identical.
 - **Octal.** The ND-120 is an octal machine; addresses and data values are written in octal.
 - **Test benches only.** Never add a standalone program that prints something and exits - it
   cannot fail a build.
 - **Keep the comments, and add more.** A comment that records a design-document page, a datasheet
   reference, or the reason a thing is NOT done the obvious way is the most valuable line in the
   file. Never delete one because a style guide prefers less; replace one only when it has become
   factually wrong.
 - **Plain words.** In code, comments, commit messages and documentation alike. No jargon where a
   normal word works.

### Naming

The organisation is **RetroCoreLabs**; the old name `HackerCorpLabs` is retired and must not
appear in anything new.

---

## Documentation changes

There are two documentation checkers. Both must pass.

```bash
# from the repository root
python3 eng/check-docs.py                # the RetroCore Labs house standard
make -C Verilog/tests test-docs-check    # this repository's dead-link gate (runs in CI)
```

- **`eng/check-docs.py`** is the house-standard checker, shared by every RetroCore Labs
  repository. It fails on a relative link that does not resolve or leaves the repository root, a
  machine-specific absolute path, a hand-written contents list, a Mermaid diagram that is malformed
  or breaks `MERMAID_COLOR_STANDARDS.md`, and a README that does not follow the template. Waivers,
  each with its reason, are in `eng/check-docs.json`.
- **`Verilog/tests/check_md_links.py`** is this repository's own gate. It resolves every relative
  link in every tracked `.md` file and is part of `make test`, so a dead link fails the CI run.

> [!WARNING]
> **Never put an absolute path in anything committed here.** A drive letter or a home directory is
> correct on exactly one machine, and this repository is public. A path inside the repository goes
> repo-relative; a sibling ND repository is written `$ND_REPOS/<repo>/...`; anything outside is
> described. A variable such as `%USERPROFILE%` or `~` is fine - that is the portable way to name
> a per-user location. There are no exceptions: the build scripts read tool and folder locations
> from `local.mk` at the repository root (written by `configure.py`, see
> [Local settings](#local-settings)) or the environment, and `make test` fails on any machine path
> in a tracked file.

### Paths in scripts and build files

No script, Makefile, GTKWave save file or comment names a folder on one particular machine.
`make -C Verilog/tests test-no-machine-paths` (part of `make test`) fails on any tracked file
that does.

- **A path inside the repository** is worked out at run time from the script's own location
  (Python `os.path.dirname(os.path.abspath(__file__))`, sh `$(cd "$(dirname "$0")" && pwd)`,
  make `$(dir $(abspath $(lastword $(MAKEFILE_LIST))))`, Tcl `[file dirname [file normalize
  [info script]]]`, PowerShell `$PSScriptRoot`). In comments and documents it is written
  repo-relative. A GTKWave `.gtkw` file stores its dump and save paths relative to its own folder.
- **A path outside the repository** is one of the named settings in [Local settings](#local-settings):
  kept in `local.mk`, or set in the environment. When a script needs one that is not set, it stops
  with a message naming it and the command that sets it.

---

## Local settings

Everything that differs between machines - where the tools are installed, where builds go, where
the other ND repositories are - is a named setting. They live in **`local.mk` at the repository
root**: machine-local, gitignored, never committed, written by **`configure.py`**.

```bash
python3 configure.py                          # set up a clone: asks for what it cannot find
py configure.py                               # the same from a Windows shell (cmd / PowerShell)
python3 configure.py --check                  # every setting, where it came from, what is missing
python3 configure.py --set ND120_BUILD_DIR=<folder>   # change one (NAME= removes it)
python3 configure.py --non-interactive        # no questions: --set values, the environment, the tool search
make check-config                             # the same as --check, from any Makefile folder
```

What `configure.py` does: finds `vivado`, `gw_sh` (Gowin), `quartus_sh`, oss-cad-suite and
w64devkit on the `PATH` and in the usual install folders (from WSL it also looks on the Windows
drives), reports `verilator`, `iverilog`, `yosys`, `python3`, `make` and `git`; asks only for what
it could not find, plus the build folder and `ND_REPOS`; writes `local.mk`; runs
`git submodule update --init`; makes the microcode preload images (`Code/Microcode/gen_wcs_image.py`
for the boards, `--sim` for the simulators); creates the build folder. Running it again keeps the
answers as defaults. It is Python 3 standard library only and runs the same on Linux, WSL and
Windows. A Windows program (`vivado.bat`, `gw_sh.exe`) is always stored as a Windows path, since
it is started through `powershell.exe` from WSL; every reader converts `X:\...` and `/mnt/x/...`
for its own side.

**Which value wins**, the same rule in every reader: a value in the **environment** wins over
`local.mk`, and under make a value on the command line (`make NAME=value`) wins over both.

**Who reads `local.mk`:** every Makefile that needs a setting, through `paths.mk` at the repository
root; the PowerShell scripts through `Verilog/fpga/paths.ps1`; the Vivado and Gowin Tcl scripts
through `Verilog/fpga/paths.tcl` (so `vivado -source build.tcl` from a Windows shell works too);
the Python and shell helpers through `configure.py` (`configure.setting()`, `--get`).

**Checks come first.** Each target checks the settings IT needs before doing any work and stops
with one message: which variable, what it is for, whether `local.mk` is missing or only lacks the
value, or that a tool path does not exist, and the command that fixes it. `make test` and the
simulator targets need none of them.

| Setting | What it is | Read by | Required |
|---|---|---|---|
| `ND120_BUILD_DIR` | where builds go: every board writes everything to `<this>/<board>/` | every board Makefile, `build.tcl`, the `.ps1` wrappers | **yes**, for any board build |
| `ND120_VIVADO` | the Vivado program (`vivado.bat` / `vivado`); `make VIVADO=...` overrides it | Basys3, Cmod A7, Nexys 4 DDR, QMTECH, MEGA65 | for those builds |
| `ND120_VIVADO_LICENSE` | Vivado licence file list, handed on as `XILINXD_LICENSE_FILE` | `paths.mk`, `run_tool.ps1`, the Vivado `.ps1` wrappers | no |
| `ND120_GOWIN` | the Gowin `gw_sh` program | Tang Nano 20K `make gowin`, `gowin_build.ps1` | for the Gowin build |
| `ND120_QUARTUS` | the Quartus `bin` folder | nothing yet (the MiSTer build runs Quartus in Docker) | no |
| `ND120_OSS_CAD_SUITE` | the oss-cad-suite folder | Tang Makefile (OSS flow), `Verilog/ND-120-Yosys/synh.bat`, BUS-IF gate example | no (else the tools from `PATH`) |
| `ND120_W64DEVKIT` | the w64devkit folder | BUS-IF gate Windows example | no |
| `ND_REPOS` | the folder holding the sibling ND checkouts (`ND110Compile`, `RetroTerm`, `NDDeviceCore`, ...) | `Verilog/tests/instruction-verify/` (golden traces, listings), `Verilog/sim/compare_boot.py` | for `make test-instr` |
| `ND120_ILA_CSV` | an ILA capture exported from Vivado as CSV (`iladata.csv`) | `Verilog/sim/analyze_ila.py`, `compare_boot.py` | for those scripts |
| `ND120_ORACLE_DIR` | where long trace captures are kept (too big to commit) | Tang capture scripts, `Verilog/sim/Makefile` | no |
| `ND120_SIM_WSLDIR` | the `Verilog/sim` folder as WSL sees it; by default worked out from the script's own location | `Verilog/sim/nd120_probe.py` | no |
| `ND120_FRESH_DIR` | an empty folder for `make fresh-build` (usually given on the command line) | `make fresh-build` in every board folder | for `make fresh-build` |

`ND120_BASYS3_PROJECT` (the old Basys3 Vivado project folder) is read by nothing since the Basys3
build became a non-project flow; `configure.py` keeps it only if you set it.

**`make fresh-build ND120_FRESH_DIR=<empty folder>`**, in any board folder, clones the current
commit into that folder, runs `configure.py --non-interactive` there with the same tool settings
but a build folder inside the clone, and runs the board's build target in the clone. It proves the
build needs nothing outside the repository. It never runs by itself.

---

## Submitting a change

 1. Branch off `main`. Do not commit to `main` directly.
 2. One logical change per commit. A commit message says **what changed and why**, in plain
    words - the subject line in the imperative, then a blank line, then the reasoning. If you
    measured something, put the number in the message.
 3. `make -C Verilog test` passes before you open the pull request.
 4. Say in the pull request what you verified and how. "Tests pass" on its own is not useful;
    "the SC2661 transmit bench now checks the bytes it sends, is registered, and `make test` is
    green end to end" is.
    If you ran it on a board, say which board, which clock and which build.
 5. If something is still broken or unfinished, say so plainly. A known gap that is written down
    is fine. One that is hidden is not.

---

## Licence

By contributing you agree your work is licensed under the MIT licence in [LICENSE](LICENSE).
