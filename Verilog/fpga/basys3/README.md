# Basys3 (Xilinx Artix-7) FPGA target

**Full path:** `Verilog/fpga/basys3/`

Vivado build/flash flow for the Digilent **Basys3** board. This was the first
FPGA target; synthesis works but the design did not boot on hardware at the
last test. NOTE (24-AUG-2026): not re-tested since the bus bank-decode fix in
`ND3202D.v:533` - shared board logic that made SINTRAN III boot on the Tang.
Whether it helps here is UNKNOWN and untested.
timing-closure problem, see [Status](#status)).

## Board / device

| Item | Value |
|------|-------|
| Board | Digilent Basys3 |
| FPGA | Xilinx Artix-7 **`xc7a35tcpg236-1`** |
| Logic | 33,280 LUT6, 41,600 FF |
| Block RAM | ~1,800 Kbit (50 RAMB36 / 100 RAMB18) |
| Big RAM | none on-board (no DRAM) |
| Clock | 100 MHz oscillator; CPU clock via `MMCME2_BASE` (`../../ND120_TOP.v`) |
| Programmer | Digilent USB-JTAG |

## Toolchain

**Vivado, on the Windows host.** Scripts are run from this folder. The Vivado
project itself lives **outside the repo**, in the folder named by
`ND120_BASYS3_PROJECT` (it holds `ND3202D.xpr`); the bitstream lands at
`<ND120_BASYS3_PROJECT>/output/ND120_TOP.bit` (+ `.ltx` for ILA probes).

### Local paths

No machine path is written in these scripts. Copy
`Verilog/fpga/local.mk.example` to `Verilog/fpga/local.mk` (untracked) and set:

| Variable | What | If unset |
|----------|------|----------|
| `ND120_BASYS3_PROJECT` | folder holding `ND3202D.xpr` | the scripts stop with an error |
| `ND120_VIVADO` | `vivado.bat` | `vivado.bat` on PATH (`-VivadoPath` overrides both) |
| `ND120_VIVADO_LICENSE` | licence file list, passed as `XILINXD_LICENSE_FILE` | the user/machine `XILINXD_LICENSE_FILE` |

`make` passes them on; the `.ps1` wrappers (via `../paths.ps1`) and the Tcl
scripts (via `paths.tcl`, which every script here sources first) also read
`local.mk` themselves, so running a script by hand from PowerShell or the
Vivado Tcl console needs nothing extra. A value already in the environment
wins over `local.mk`. Logs and ILA CSVs go to `logs/` in this folder.

## Files

| File | Purpose |
|------|---------|
| `vivado_build.tcl` | Synthesis + implementation + bitstream. Header lists flags: `full_synth` (force ~1h re-synth; default reuses the `synth_1` checkpoint), `skip_program`, `no_reset_synth`, `backup_bit`. Also sets up the ILA (probe0..26). |
| `vivado_build.ps1` | PowerShell wrapper: copies microcode hex into the project dir, then runs `vivado_build.tcl`. Finds the tcl via its own folder. |
| `paths.tcl` | Sourced first by every Tcl script here: derives the repo paths from its own location and reads `ND120_BASYS3_PROJECT` (see [Local paths](#local-paths)). |
| `vivado_lint.tcl` | Lint-only run. |
| `vivado_impl_only.tcl` | Re-run implementation on the existing synth checkpoint (skip synthesis). |
| `flash.tcl` / `flash.ps1` | Program the FPGA. `.\flash.ps1 -Quick` = JTAG only (volatile, fast); `.\flash.ps1` = JTAG + SPI flash (persistent). Loads `ND120_TOP.ltx` so ILA probes appear in Hardware Manager. |
| `list_flash.tcl` | List available SPI flash parts matching the board. |
| `check_rom.tcl` | Sanity-check the microcode ROM contents. |
| `find_nets.tcl` | Locate nets by name (probe/debug helper). |
| `constraints_tie_unused.xdc` | Repo XDC tying off unused pins. NOTE: the CPU **clock constraint** lives in the Vivado-managed project XDC (`ND3202D.srcs/constrs_2/new/constraints.xdc`), not here. |

## Build & flash (Windows PowerShell)

```powershell
cd Verilog/fpga/basys3

# Full synth (needed after any logic change; ~1h). Default ps1 does full_synth.
.\vivado_build.ps1
#   -> copies microcode hex, runs vivado_build.tcl, writes output\ND120_TOP.bit + .ltx

# Flash:
.\flash.ps1 -Quick     # JTAG only, volatile - fast iteration
.\flash.ps1            # JTAG + SPI flash - survives power cycle
```

Microcode `AM27256_4513{2,3}L.hex` must be present in the project dir (the ps1
copies it from `Code/Microcode/`) or the ROM is empty.

## On-chip debug (ILA)

Probes are declared in `vivado_build.tcl` (probe0..26) via `mark_debug` on wires
plus `connect_probe`. After capturing in Hardware Manager, export CSV:

```tcl
source paths.tcl   ;# sets b3_logdir = this folder's logs/
write_hw_ila_data -csv_file -force [file join $b3_logdir ila_capture.csv] [upload_hw_ila_data hw_ila_1]
```

Then compare against the Verilator golden trace - see
`../../docs/fpga-debug-methodology.md` and `../../docs/boot-golden-spec.md`.

## Status

- **Synthesis:** passes. Utilization ~9,302 LUT primitives, ~1,044 Kbit BRAM
  (dominated by the duplicated microcode PROM + WCS).
- **Implementation:** **FAILS TIMING**, so the CPU does not boot on hardware.
  Measured 21-AUG-2026, Vivado 2026.1, from `logs/timing_impl.rpt`:

  | clock | period | WNS | TNS | failing endpoints |
  |---|---|---|---|---|
  | `sys_clk` | 10.000 ns (100 MHz) | **+7.475** MET | 0.000 | 0 of 44 |
  | `clk_cpu_pre` | 60.000 ns (16.667 MHz) | **-29.778** | -44293.688 | 1714 of 44510 |

  Hold is clean (WHS +0.035 ns, 0 failing of 44,593). A bitstream IS produced.
  Implied Fmax as routed is about **11.1 MHz** against the 16.667 MHz target.
  (This supersedes an older "WNS approx -100 ns / TNS approx -50,000 ns" claim.
  Do not read -100 -> -29.8 as an improvement from any one change: the design
  also changed substantially in between and the attribution is unmeasured.)
- **What the timing report actually says:** the **Inter Clock Table is EMPTY** -
  the `set_clock_groups -asynchronous` works, no cross-domain path is timed, so
  every remaining violation is INSIDE the CPU clock domain and is real logic
  depth. Do not go looking for a constraint fix. The worst path (-29.778 ns,
  89.336 ns of data path against a 60 ns budget, **156 logic levels**) runs from
  a WCS microcode BRAM output combinationally into a write-register-file clock
  enable in a single cycle:

      source: CORE/CPU_BOARD/CPU/CS/WCS/CHIP_22D/idt_memory_array_reg/CLKARDCLK
      dest  : CORE/CPU_BOARD/CPU/PROC/CGA/DELILAH/WRF/RBLOCK/R2_REG_10/regFF_reg[15]/CE

- **Derived clocks:** the clock-enable refactor is PARTIAL, not finished. The
  base primitives are converted (`LATCH`, `L4`, `L8`, the `*_EN` variants all
  clock on `sysclk`), but **22 derived-clock `always` blocks remain**, mostly in
  `Verilog/PAL/`. That is still worth finishing, but note it is no longer the
  measured explanation for the -29.778 ns: that path is logic depth in one
  domain.
- Full analysis + fix plan: `../../docs/fpga-debug-methodology.md` (section 3.2).

## Related docs

- `../../docs/fpga-debug-methodology.md` - the Verilator-vs-FPGA debug workflow.
- `../../docs/boot-golden-spec.md` - expected microcode boot sequence.
- `../../docs/build-defines.md` - compile-time defines (`VERILATOR_SIM`,
  `FPGA_FF_MODE`, `SKIP_WCS_LOAD`, ...).
- `../../FPGA-BRINGUP-PLAN.md` - overall bring-up plan.
