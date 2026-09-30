# Prerequisites: every tool this repo needs, how to install it, how it is used

**Full path:** `Verilog/docs/PREREQUISITES.md`
**Last verified:** 20-AUG-2026 — every version below was read off this machine
with the command shown next to it, not copied from documentation.
**Corrected 28-SEP-2026:** the open-source Tang flow, the MiSTer and the
MEGA65 entries (§3.1-§3.3).

This document is written so that a person **or an LLM** can bring a fresh
machine to a working state without guessing. Every section gives:

1. **What it is and why this repo needs it**
2. **Install** — copy-paste commands, including the prerequisites of the prerequisite
3. **Validate** — a command that proves it works, with the expected output
4. **How this repo uses it** — the actual files and targets that call it

> **Path convention.** Vendor tools live outside the repo, so they are referred
> to through **environment variables** (`VIVADO_BIN`, `GOWIN_BIN`). Set them
> once in your shell profile. Example values for this machine are given in
> [Section 9](#9-this-machines-configuration), clearly marked as machine-specific —
> never hard-code them into scripts that get committed.

---

## 1. Host environment

The work is driven from **Linux / WSL2 with bash**. The vendor FPGA tools run
on the **Windows host** and are invoked from WSL through `cmd.exe` or
`powershell.exe` — which works because the repo lives on a Windows drive.

| Component | Version here | How to check |
|---|---|---|
| WSL2 | Ubuntu 22.04 | `lsb_release -d` |
| Kernel | 6.18.33.2-microsoft-standard-WSL2 | `uname -r` |
| GNU Make | 4.3 | `make --version \| head -1` |
| gcc | 11.4.0 | `gcc --version \| head -1` |
| Python | 3.10.12 | `python3 --version` |
| Node.js | v22.18.0 | `node --version` |
| npm | 11.5.2 | `npm --version` |

**Install the base:**

```bash
sudo apt-get update
sudo apt-get install -y build-essential git make python3 python3-pip
```

**Validate:**

```bash
make --version | head -1 && gcc --version | head -1 && python3 --version
# expect: GNU Make 4.x / gcc (Ubuntu 11.x) / Python 3.10.x
```

---

## 2. Simulation and lint (the daily tools)

These four do the actual engineering work. Everything else is convenience.

### 2.1 Verilator — the working reference simulator

**Why:** the Verilator simulation is the project's reference implementation;
the FPGA is validated *against* it. Also used as a **linter**, which is how
several structural RTL bugs were found (`UNOPTFLAT`, `MULTIDRIVEN`, `UNDRIVEN`).

```bash
sudo apt-get install -y verilator          # distro build, usually older
# or from source for a current version:
sudo apt-get install -y git perl python3 make autoconf g++ flex bison \
     ccache libgoogle-perftools-dev numactl perl-doc libfl2 libfl-dev zlib1g zlib1g-dev
git clone https://github.com/verilator/verilator
cd verilator && git checkout stable && autoconf && ./configure && make -j$(nproc) && sudo make install
```

**Validate:**

```bash
verilator --version
# expect: Verilator 5.x
```

**How this repo uses it:**

| Use | Where |
|---|---|
| Reference simulation of the whole machine | `Verilog/runSim/` (owner's harness), `Verilog/sim/` |
| Lint gate on individual modules | ad-hoc: `verilator --lint-only -Wall <file>.v` |
| Structural bug detection | `UNOPTFLAT` finds combinational loops; `MULTIDRIVEN` finds a wire driven twice |

```bash
# the lint invocation that finds bus-modelling bugs, with the repo's library paths
V=Verilog
verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-VARHIDDEN -Wno-PINCONNECTEMPTY \
  -DFPGA_FF_MODE -DMAIN_RAM_BLOCKRAM \
  -y $V/CPU-BOARD-3202/circuit -y $V/Shared/support -y $V/Shared/ndlib \
  -y $V/DELILAH-CPU/CGA/circuit -y $V/PAL \
  $V/CPU-BOARD-3202/circuit/CPU_15.v 2>&1 | grep -E "UNOPTFLAT|MULTIDRIVEN|UNDRIVEN"
```

### 2.2 Icarus Verilog (iverilog) — unit testbenches

**Why:** every `*_tb.v` unit testbench compiles and runs under iverilog. It is
far faster to iterate than Verilator for small modules.

```bash
sudo apt-get install -y iverilog
```

**Validate:**

```bash
iverilog -V | head -1
# expect: Icarus Verilog version 11.0 (stable)
```

**How this repo uses it:** every `sim/Makefile` in the tree. The convention is
`iverilog -g2005` (or `-g2012`) to build, `vvp` to run, and the testbench
prints a machine-checkable verdict line `TB_RESULT: PASS`.

### 2.3 Yosys — synthesis-side checks and schematic generation

**Why:** used here for **module schematics** (see §5.2). Also useful as a
second opinion on synthesisability.

```bash
sudo apt-get install -y yosys
```

**Validate:**

```bash
yosys -V
# expect: Yosys 0.9 or newer
```

### 2.4 GTKWave — waveform viewing

```bash
sudo apt-get install -y gtkwave
```

**Validate:** `gtkwave --version` → `GTKWave Analyzer v3.3.x`

**How this repo uses it:** `Verilog/sim/` writes `waveform.fst` and ships
GTKWave save-files (`top_3202d.gtkw`, `DELILAH-CPU/CGA/sim/cga.gtkw`) that
pre-select the interesting signals. `make all` in `sim/` opens it directly.

---

## 3. FPGA vendor toolchains, per board

Per-board build instructions live **with the board** in
`Verilog/fpga/<board>/README.md`. This section covers only what must be
*installed* and how the repo reaches it.

### 3.1 Xilinx / AMD Artix-7 boards — Vivado

**Boards:** Nexys 4 DDR (`xc7a100tcsg324-1`), Basys3 (`xc7a35tcpg236-1`),
Cmod A7-35T, QMTECH XC7A35T, MEGA65 (the MEGA65 build is recorded as working
on **Vivado 2026.1**, `Verilog/fpga/mega65/README.md`; its toolchain traps
are in `Verilog/fpga/mega65/docs/00-plan.md`).

**Version here: Vivado 2025.2.1 (64-bit)** — read from a build log
(`****** Vivado v2025.2.1`).

**Install:** download the AMD Unified Installer for Windows from
<https://www.amd.com/en/support/download/fpga-development-tools.html>.
A free account is required. Select **Vivado ML Standard** (free, no licence)
and at minimum the **Artix-7** device family. Install **on the Windows host**,
not inside WSL.

Disk: budget ~50 GB for a Vivado install with one device family.

**Configure:** point the repo at it with an environment variable:

```bash
# add to ~/.bashrc
export VIVADO_BIN='<your Vivado install>\bin\vivado.bat'   # a Windows path
```

**Validate from WSL:**

```bash
cmd.exe /c "$VIVADO_BIN" -version 2>&1 | head -2
# expect: ****** Vivado v2025.2.1 (64-bit)
```

**How this repo uses it:** each board folder has a `build.tcl` run in batch
mode. The Makefiles delegate through `cmd.exe`:

```bash
cd Verilog/fpga/nexys4ddr && make build      # bitstream only
cd Verilog/fpga/nexys4ddr && make            # build + JTAG program
```

**MIG (Memory Interface Generator)** ships inside Vivado; no separate install.
It generates the DDR2 controller from Digilent's project file — see
`Verilog/fpga/nexys4ddr/ddr2-test/gen_mig.tcl`.

### 3.2 Gowin GW2AR-18 — Tang Nano 20K

**Version here: Gowin V1.9.10.02 (x64)**

**Install:** download Gowin EDA from <https://www.gowinsemi.com/en/support/home/>
(account required). Install on the **Windows host**. The Education edition
needs a free licence file tied to your NIC MAC address.

```bash
# add to ~/.bashrc
export GOWIN_BIN='<your Gowin install>\IDE\bin\gw_sh.exe'   # a Windows path
export GOWIN_LICENSE='<path to>\gowin_<your-id>.lic'
```

**Validate:**

```bash
ls "$(wslpath "$GOWIN_BIN")" && echo "gw_sh present"
```

**Open-source flow (second option).** The Tang can also be built with the
oss-cad-suite (yosys + nextpnr-himbaechel + gowin_pack), from WSL, with
`make` in `Verilog/fpga/tang-nano-20k/`. It covers the `slow`, `crawl` and
`full` variants only; the deployed `fast20` variant needs Gowin EDA. The
full CPU no longer fits with this flow (107-109% LUT4, measured
28-SEP-2026), so bitstreams come from Gowin EDA. Install
instructions (one prebuilt tarball, no sudo) are in
`Verilog/fpga/tang-nano-20k/README.md`, section "Toolchain". That flow needs
the oss-cad-suite yosys (0.4x+), not the distro 0.9 of §2.3.

**How this repo uses it:** `Verilog/fpga/tang-nano-20k/gowin_build.ps1` and
`gowin_build.tcl`; `make` / `make load` in that folder.

### 3.3 Intel Cyclone V — MiSTer (DE10-Nano)

**Quartus Prime Lite 17.0.2** exactly — free, no licence. MiSTer standardizes
on that version. Nothing needs installing on the host: the community Docker
image `raetro/quartus:17.0` carries it. The core boots SINTRAN on the board
(02-SEP-2026). Build and deploy: `Verilog/fpga/mister/README.md` and
`Verilog/fpga/mister/docs/02-building.md`.

---

## 4. Programming and serial access

### 4.1 JTAG programming

Xilinx boards use Vivado's own Hardware Manager over the board's built-in
USB-JTAG — **no separate programmer or driver is needed**, and there is a
`program.tcl` in each board folder that programs an existing bitstream without
rebuilding (about one minute instead of ten).

```bash
cd Verilog/fpga/nexys4ddr
cmd.exe /c "$VIVADO_BIN" -mode batch -source program.tcl
# expect: End of startup status: HIGH   and   PROGRAMMED: ...bit
```

### 4.2 Serial console

Two routes. **Which one you can use depends on who owns the USB device.**

**From Windows** (leaves JTAG available to Vivado):

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass \
  -File Verilog/fpga/nexys4ddr/console.ps1 -Seconds 60
```

**From WSL** via usbipd — the device is forwarded into Linux and appears as
`/dev/ttyUSB*`:

```bash
sudo apt-get install -y picocom          # or screen
# one-time, from an ELEVATED Windows prompt:
#   usbipd bind --busid <id>
cd Verilog/fpga/nexys4ddr && ./usb-attach.sh
picocom -b 9600 /dev/ttyUSBn             # exit: Ctrl-A Ctrl-Q
./usb-attach.sh --detach                 # give it back to Windows
```

**usbipd-win** installs on the Windows host:
<https://github.com/dorssel/usbipd-win/releases>. Validate with
`usbipd.exe list` from WSL.

> **Trap worth knowing.** The FT2232 on these boards carries **both** USB-JTAG
> and USB-UART on one device. While it is attached to WSL, Windows cannot see
> it and Vivado cannot program the board. Also, the Tang Nano 20K and the Nexys
> both enumerate as `0403:6010`, so a VID:PID match grabs the wrong board when
> both are plugged in — `Verilog/fpga/nexys4ddr/usb-attach.sh` selects by FTDI
> **serial number** for exactly this reason.

---

## 5. Documentation and diagram generation

**This repo does not use Doxygen.** See §7.1 for the analysis of why, and what
replaces it.

### 5.1 Module symbol + README from the `//!` comments

**Tool:** `Verilog/tests/module_doc.py` (in this repo).
**Needs:** Python 3 + Pillow. Nothing else.

```bash
python3 -m pip install --user pillow
```

**Validate:**

```bash
python3 -c "import PIL; print('Pillow', PIL.__version__)"
# expect: Pillow 12.x (or any 9.0+)
```

**Use:**

```bash
cd Verilog
python3 tests/module_doc.py Shared/support/TTL_74245.v -o Shared/support/doc \
    --note "TB_RESULT: PASS - 524292 checks (exhaustive)"
# writes doc/TTL_74245.png (block symbol) and doc/TTL_74245.md (port table)
```

It reads the header banner, `//! @title` / `//! @author`, and the `//!` comment
on each port. It understands the repo's conventions: `_n` suffix draws an
inversion bubble, `NAME_23_0` and `[15:0]` become bus width labels, `inout`
draws a bidirectional arrow.

### 5.2 Module schematic from the synthesised netlist

**Tool:** yosys + graphviz.

```bash
sudo apt-get install -y yosys graphviz
```

**Validate:**

```bash
dot -V                 # expect: dot - graphviz version 2.4x
yosys -V               # expect: Yosys 0.9+
```

**Use:**

```bash
yosys -p "read_verilog Verilog/Shared/support/TTL_74245.v; \
          prep -top TTL_74245; show -format png -prefix /tmp/ttl245 -notitle"
```

This draws the **synthesised gate structure**, which is a different and
complementary picture to §5.1's port symbol — it is what caught the shared-node
bug in the 74245: the fixed version shows two independent mux paths with no
common node.

### 5.3 Waveform / truth-table PNG from a testbench VCD

**Tool:** `Verilog/tests/wave2png.py` (in this repo).
**Needs:** Python 3 + `vcdvcd` + Pillow.

```bash
python3 -m pip install --user vcdvcd pillow
```

**Validate:**

```bash
python3 -c "import vcdvcd, PIL; print('ok')"
```

**Use:**

```bash
cd Verilog/CPU-BOARD-3202/circuit/sim
make CYC_36_enables_tb && ./CYC_36_enables_tb        # writes CYC_36_enables_tb.vcd
python3 ../../../tests/wave2png.py CYC_36_enables_tb.vcd /tmp/cyc36.png \
    --signals clk,clk_en,mclk,mclk_en --title "CYC_36 clock enables" \
    --note "TB_RESULT: PASS - 18990 checks"
```

61 of the 210 testbenches already call `$dumpfile`, so the raw material exists
without touching the RTL.

> **Use judgement about which testbenches get a waveform.** For an exhaustive
> sweep (the 74245 walks 262,144 combinations) a waveform is noise — use
> `--table` for a value table instead. Reserve waveforms for testbenches where
> **timing is the contract**: `CPU_CS_ACAL_17_tb` (zero-latency transparency),
> the SDRAM protocol replay, the clock-domain handshakes.

> **Committing PNGs:** they are binary and cannot be diffed. Regenerate only
> when the RTL or the testbench changes, not on every run. The authoritative
> record stays the `TB_RESULT: PASS` line and the check count — the images are
> documentation for a human, not evidence for the suite.

---

## 6. Test execution

No extra tools beyond iverilog, Verilator and make.

```bash
cd Verilog
make test          # every self-checking unit testbench, fail-fast
make test-full     # adds the heavy system gates (golden traces, boot)
make test-instr    # all 13 instruction-verify areas vs the ND-110 golden trace (~1.5h)
make test-instr-ARGUMENT   # one area (~minutes)
```

**How it works:** `Verilog/tests/run_all_tests.sh` holds a registry of
`directory :: make-target :: expected-pass-pattern`. Every testbench must be
reachable from its own `sim/Makefile` **and** registered there — the catalogue
tool `Verilog/tests/tb_catalog.py` fails the suite if a testbench exists that
nothing runs. The convention is that a testbench prints `TB_RESULT: PASS`.

The rationale, worth preserving: **a test that can pass silently can fail
silently.**

---

## 7. Optional tools, and the honest case for skipping them

### 7.1 Doxygen — NOT USED, and not recommended

The RTL is annotated in Doxygen style (`//!`, `//! @title`, `//! @author`), so
running Doxygen looks like the obvious move. It is not, for a concrete reason:

**Doxygen cannot draw a Verilog module symbol.** Its graphviz output produces
call, include and inheritance graphs, which are meaningless for Verilog. There
is no Doxygen feature that renders a box with inputs on the left and outputs on
the right. Verilog support also requires a third-party filter and emits HTML
that is awkward to commit and review.

`Verilog/tests/module_doc.py` (§5.1) reads the **same comments** and produces
the block symbol plus a diffable Markdown port table, with no dependency beyond
Pillow — which is already needed for the waveform tool. **Recommendation: do
not install Doxygen.**

If it is ever wanted anyway: `sudo apt-get install -y doxygen graphviz`, then a
`Doxyfile` with `FILE_PATTERNS = *.v` and `EXTENSION_MAPPING = v=C++`.

### 7.2 netlistsvg — optional upgrade to §5.2

Prettier schematics with proper digital-logic symbols, versus graphviz boxes.

```bash
npm install -g netlistsvg
yosys -p "read_verilog X.v; prep -top X; write_json /tmp/x.json"
netlistsvg /tmp/x.json -o /tmp/x.svg
inkscape /tmp/x.svg -o /tmp/x.png     # or: magick /tmp/x.svg /tmp/x.png
```

**Not installed here.** `yosys show` already produces usable schematics with
zero install. Add netlistsvg when aesthetics start mattering more than
coverage.

### 7.3 vcd2wavedrom + wavedrom-cli — optional alternative to §5.3

Produces the clean textbook-style timing diagram.

```bash
python3 -m pip install --user vcd2wavedrom
npm install -g wavedrom-cli
vcd2wavedrom -i x.vcd -o x.json && wavedrom-cli -i x.json -p x.png
```

**Not installed here.** `wave2png.py` covers the same ground with no network
install, and `puppeteer` (already present globally via npm) can render WaveDrom
headlessly if that route is preferred later.

---

## 8. One-shot setup script

Everything needed for **simulation, lint, test and documentation** on a fresh
Ubuntu/WSL2 machine. The FPGA vendor tools (§3) install on Windows separately.

```bash
#!/usr/bin/env bash
set -euo pipefail

sudo apt-get update
sudo apt-get install -y \
    build-essential git make python3 python3-pip \
    verilator iverilog yosys gtkwave graphviz \
    picocom imagemagick

python3 -m pip install --user vcdvcd pillow pyserial

echo "--- validating ---"
verilator --version
iverilog -V | head -1
yosys -V
dot -V
gtkwave --version 2>&1 | head -1
python3 -c "import vcdvcd, PIL, serial; print('python modules ok')"
echo "--- all present ---"
```

**Then validate against the repo itself** — this is the real proof, because it
exercises the actual flow:

```bash
cd Verilog/Shared/support/sim && make test-74245
# expect: TB_RESULT: PASS   (524292 checks)

cd ../../../CPU-BOARD-3202/circuit/sim && make test-acal
# expect: TB_RESULT: PASS  (CPU_CS_ACAL_17 LUA is a zero-latency transparent latch)
```

---

## 9. This machine's configuration

Machine-specific. Recorded so a discrepancy can be spotted, **not** to be
hard-coded into committed scripts.

| Tool | Version | Location |
|---|---|---|
| Verilator | 5.025 devel rev v5.024-9-g1315aa31e | WSL, `/usr/local/bin` |
| Icarus Verilog | 11.0 (stable) | WSL |
| Yosys | 0.9 (git sha1 1979e0b) | WSL |
| GTKWave | 3.3.104 | WSL |
| graphviz (dot) | 2.43.0 | WSL |
| ImageMagick | 7 (`magick`; `convert` deprecated) | WSL |
| Inkscape | 1.1.2 | WSL |
| Python | 3.10.12 | WSL |
| vcdvcd | 2.6.0 | pip --user |
| Pillow | 12.1.1 | pip --user |
| pyserial | 3.5 | pip --user |
| pyDigitalWaveTools | 1.2 | pip --user |
| Node.js / npm | 22.18.0 / 11.5.2 | WSL (nvm) |
| puppeteer | 24.40.0 | npm global |
| **Vivado** | **2025.2.1** | Windows host |
| **Gowin EDA** | **V1.9.10.02 x64** | Windows host |
| usbipd-win | present | Windows host |
| Quartus | 17.0.2 through Docker (`raetro/quartus:17.0`) | see §3.3 |
| Doxygen | **not installed — deliberately, see §7.1** | — |
| netlistsvg / vcd2wavedrom / wavedrom-cli | not installed — optional, see §7.2, §7.3 | — |

**Serial ports on this machine:** the Nexys 4 DDR console is `COM11` from
Windows (FTDI serial `210292A4BE00B`, usbipd busid `2-1`). The Tang Nano 20K is
a second `0403:6010` device — see the trap noted in §4.2.

**Regenerating this table:**

```bash
verilator --version; iverilog -V | head -1; yosys -V; dot -V
gtkwave --version 2>&1 | head -1; python3 --version; node --version
python3 -c "import importlib.metadata as m; \
  [print(x, m.version(x)) for x in ['vcdvcd','Pillow','pyserial']]"
```

---

## Related documents

- `Verilog/fpga/README.md` — the FPGA target directory and the shared board build API
- `Verilog/fpga/<board>/README.md` — per-board build, pins and status
- `Verilog/readme.md` — Verilog implementation status
- `DEVELOPMENT.md` (repo root) — architecture, coding rules and conventions
- `Verilog/docs/build-defines.md` — the compile-time defines
