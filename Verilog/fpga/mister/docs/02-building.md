# Building the Core (project structure, Quartus, Docker)

How the `nd120.rbf` is built: the project layout, the pinned Quartus version, and
the Docker compile loop. The project already contains `ND3202D` and boots on
hardware; this doc is the reference for the structure and the build. All links
verified 2026-07-08.

## 1. Quartus version: 17.0.2, non-negotiable

- Official compile docs: https://mister-devel.github.io/MkDocs_MiSTer/developer/mistercompile/
  — "The vast majority of MiSTer FPGA cores currently use Quartus 17.0.2".
- Template README (https://github.com/MiSTer-devel/Template_MiSTer) repeats it:
  v17.0.x, 17.0.2 recommended; **newer versions introduce project incompatibilities**
  and give no benefit on this FPGA.
- FPGA part: Cyclone V SE **5CSEBA6U23I7**.

## 2. Anatomy of a core project (from Template_MiSTer)

Source: https://github.com/MiSTer-devel/Template_MiSTer

```
rtl/              your core RTL + the core PLL (pll.v, pll.qip, pll/)
sys/              framework - NEVER EDIT ("Framework updates may erase any
                  customization in this folder"; all cores must include sys/ as-is)
Template.qpf      Quartus project        \
Template.qsf      Quartus settings        \  rename ALL of these to nd120.*
Template.sdc      timing constraints      /  and set PROJECT_REVISION = "nd120"
Template.srf      warning suppressions   /   in the .qpf
Template.sv       the emu module (rename to nd120.sv)
files.qip         YOUR source file list - edited BY HAND (Quartus can't modify it)
```

Steps to create ours:

1. Clone https://github.com/MiSTer-devel/Template_MiSTer (or copy its contents into
   `Verilog/fpga/mister/`).
2. Rename `Template.{qpf,qsf,sdc,srf,sv}` to `nd120.*`; edit `nd120.qpf` so
   `PROJECT_REVISION = "nd120"`.
3. List every ND-120 source file in `files.qip` (paths can point at
   `../../CPU-BOARD-3202/...` etc. — one `set_global_assignment -name VERILOG_FILE
   <path>` style line per file, matching the existing entries in the file).
4. Add the `FPGA_FF_MODE` define (and NOT `VERILATOR_SIM`) as a Verilog macro in
   `nd120.qsf` — same requirement as the Vivado build. **[project-specific, not from
   MiSTer docs]**

### The emu module

Official page: https://mister-devel.github.io/MkDocs_MiSTer/developer/emu/

You do not own the FPGA top level — `sys/sys_top.v` does. You implement `module emu`;
its port list is framework-owned, included from `sys/emu_ports.vh`
(https://raw.githubusercontent.com/MiSTer-devel/Template_MiSTer/master/sys/emu_ports.vh).
Ports that matter to us:

- `input CLK_50M` — the board clock; feed your PLL from it.
- `input RESET` — async reset from the framework.
- `inout [45:0] HPS_BUS` — opaque; wire straight to the `hps_io` instance.
- `output LED_USER`, `LED_POWER[1:0]`, `LED_DISK[1:0]` — debug gold (see 06).
- `input UART_RXD, UART_CTS, UART_DSR` / `output UART_TXD, UART_RTS, UART_DTR` —
  the framework UART, routed to the Linux side → OPCOM console.
- `DDRAM_*` — 64-bit Avalon-style window into HPS DDR3 (main-memory option A).
- `SDRAM_*` — raw pins of the SDRAM add-on board (main-memory option B).
- Video: `CLK_VIDEO`, `CE_PIXEL`, `VGA_R/G/B/HS/VS/DE` + aspect — needed even for a
  skeleton core (drive black + valid syncs, or use the Template's example pattern).
- Audio: `AUDIO_L/R/S` — tie off to zero.

### The PLL

The framework expects the core PLL in `rtl/` (`pll.qip`, generated `pll/` folder).
Template instantiation, verbatim:

```verilog
pll pll
(
    .refclk(CLK_50M),
    .rst(0),
    .outclk_0(clk_sys)
);
```

Regenerate the "PLL Intel FPGA IP" in the Quartus GUI to set the CPU/bus domain
clock (the shipping build runs the CPU at 20 MHz off the board's 50 MHz; add more
outclk taps as needed). For odd sub-frequencies,
prefer clock **enables** off one PLL clock — the official snippets page has a
power-of-2 divider and a fractional clock-enable generator:
https://mister-devel.github.io/MkDocs_MiSTer/developer/snippets/
(This matches the clock-enable refactor style already used in this repo.)

Porting-guide rules worth knowing early
(https://mister-devel.github.io/MkDocs_MiSTer/developer/porting/):

- `CLK_VIDEO` = a base video clock, `CE_PIXEL` pulsed only on real pixel ticks.
- `VGA_DE` must be `~(VBlank | HBlank)` — the HDMI scaler measures resolution from it.
- Sync polarities positive.
- DDR3 needs careful reset handling "or hard hangs".
- hps_io supports up to 4 simultaneously mounted disk images.

## 3. Building with Docker (the everyday loop)

Image: `raetro/quartus:17.0` (contains Quartus v17.0.2.602). Sources:
https://github.com/raetro/sdk-docker-fpga and https://hub.docker.com/r/raetro/quartus

```bash
cd Verilog/fpga/mister
docker run -it --rm -v "$(pwd)":/build raetro/quartus:17.0 \
    quartus_sh --flow compile nd120.qpf
```

- Your cwd is mounted at `/build`, the container's workdir, where Quartus finds the
  `.qpf`.
- Output: `output_files/nd120.rbf` (plus a `.sof` used for JTAG/SignalTap).
- Release naming convention (Template README): `nd120_YYYYMMDD.rbf`.
- A Docker build takes about 25 minutes. Never edit a source file while
  Quartus is reading it - two builds (v42, v43) were thrown away for exactly
  that.
- Run the container from WSL, not Git Bash: Git Bash rewrites the working
  directory to a Windows path and the run dies before Quartus starts.

### CI

The raetro repo ships a GitHub Actions example — `container: raetro/quartus:17.1`
with a `quartus_sh --flow compile my_project.qpf` step; full examples in its
`/examples` directory (use the `17.0` tag for MiSTer). So the ND-120 core can get a
build check on every push once it lives in a repo.

## 4. Native/GUI builds

Needed for PLL IP generation and SignalTap. Install per
[01-getting-started.md](01-getting-started.md) §5, open `nd120.qpf`, press the
compile (play) button — that is the entire official flow
(https://mister-devel.github.io/MkDocs_MiSTer/developer/mistercompile/).

## Build check

- [ ] `docker run ... quartus_sh --flow compile nd120.qpf` (or `make build`)
      produces `output_files/nd120.rbf` with zero errors.
- [ ] `files.qip` lists the ND-120 RTL and the full design passes Quartus synthesis
      and fitting (watch the resource report: ~110K LE available).
- [ ] The core loads on the MiSTer and comes up at the `#` MOPC monitor.
