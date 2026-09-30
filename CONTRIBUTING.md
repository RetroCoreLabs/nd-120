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
cd Code/Microcode && python3 gen_wcs_image.py && cd ../..   # the microcode images the tests load
make -C Verilog test                                         # every self-checking test bench
```

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
> a per-user location. The Vivado TCL scripts are the one known exception: they run on the
> Windows host and name its folders.

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
