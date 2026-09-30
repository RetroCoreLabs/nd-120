# Basys3 (Xilinx Artix-7) FPGA target

**Full path:** `Verilog/fpga/basys3/`

Vivado build/flash flow for the Digilent **Basys3** board. This was the first
FPGA target. OPCOM booted on hardware on 07-JUL-2026 (tag
fpga-opcom-working-basys3, commit f5821fe); the 21-AUG build failed timing
(WNS -29.8 ns at 16.667 MHz) and no build since has been tried on the board -
see [Status](#status).

## Main-memory ceiling

24K words at most, measured on the Cmod (same die); the Basys3's own free tile
count is UNMEASURED. Full table and reasoning:
[../cmod-a7-35t/README.md](../cmod-a7-35t/README.md#main-memory-ceiling---measured-07-sep-2026).
Neither board can ever run SINTRAN.

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

**Vivado, on the Windows host.** Scripts are run from this folder. Since
30-SEP-2026 this is a **non-project flow** like the other Vivado boards:
everything the build needs is in this folder - the source list
[`nd120_basys3_sources.txt`](nd120_basys3_sources.txt) (the 267 files of the
old Vivado project, in its order) and the pin map
[`nd120_basys3.xdc`](nd120_basys3.xdc) (the old project's constraint set,
copied byte for byte) - and everything it writes goes to
`$ND120_BUILD_DIR/basys3/`: `ND120_TOP.bit` (+ `.ltx` for ILA probes), the
reports, `post_synth.dcp` and `ND120_TOP_routed.dcp`, the copied microcode,
and `logs/` (Vivado log, ILA CSVs). The old project (`ND3202D.xpr`, outside
the repo) is no longer read; the header of `vivado_build.tcl` lists what it
held and where each piece went.

### Local settings

No machine path is written in these scripts. Run `python3 configure.py` at
the repository root once; it writes `local.mk` there (see
[CONTRIBUTING.md - Local settings](../../../CONTRIBUTING.md#local-settings)):

| Variable | What | If unset |
|----------|------|----------|
| `ND120_BUILD_DIR` | where builds go (this board: `<it>/basys3/`) | the scripts stop with a message naming it |
| `ND120_VIVADO` | `vivado.bat` | the scripts stop with a message naming it (`-VivadoPath` overrides it) |
| `ND120_VIVADO_LICENSE` | licence file list, passed as `XILINXD_LICENSE_FILE` | the user/machine `XILINXD_LICENSE_FILE` |

`make` passes them on; the `.ps1` wrappers (via `../paths.ps1`) and the Tcl
scripts (via `paths.tcl`, which every script here sources first) also read
`local.mk` themselves, so running a script by hand from PowerShell or the
Vivado Tcl console needs nothing extra. A value already in the environment
wins over `local.mk`.

## Files

| File | Purpose |
|------|---------|
| `vivado_build.tcl` | Non-project synthesis + implementation + bitstream. Header lists flags: `full_synth` (force ~1h re-synth; default reuses `post_synth.dcp` from the build folder), `skip_program`, `backup_bit`, `enable_ila`, `lint` (`no_reset_synth` is accepted and ignored). Also sets up the ILA (probe0..26). |
| `nd120_basys3_sources.txt` | The source list, in the old project's order; `-` marks the 8 files the project had disabled. |
| `nd120_basys3.xdc` | The pin map and board constraints (read after synthesis, then `nd120_timing.xdc`). |
| `vivado_build.ps1` | PowerShell wrapper: checks the settings, runs `vivado_build.tcl` in the build folder, logs to `<build>/logs/`. Finds the tcl via its own folder. |
| `paths.tcl` | Sourced first by every Tcl script here: derives the repo paths from its own location and the build folder from `ND120_BUILD_DIR` (see [Local settings](#local-settings)). |
| `vivado_lint.tcl` | Lint-only run (`vivado_build.tcl` with `lint`). |
| `vivado_impl_only.tcl` | Implementation on the last synthesized design (skip synthesis), then program. |
| `flash.tcl` / `flash.ps1` | Program the FPGA. `.\flash.ps1 -Quick` = JTAG only (volatile, fast); `.\flash.ps1` = JTAG + SPI flash (persistent). Loads `ND120_TOP.ltx` so ILA probes appear in Hardware Manager. |
| `list_flash.tcl` | List available SPI flash parts matching the board. |
| `check_rom.tcl` | Sanity-check the microcode ROM contents. |
| `find_nets.tcl` | Locate nets by name (probe/debug helper). |
| `constraints_tie_unused.xdc` | An old XDC tying off unused pins. It was in neither of the old project's constraint sets and the build does not read it. The clock constraint is in `nd120_basys3.xdc`. |

Mem-test gotcha: the standalone mem-test (`mem-test/`) holds reset while
btn1 = SW0 (pin V17) is UP (`basys3_mem_test_top.v:21,48`), the opposite of the
CPU build's "SW0 UP = run". Set SW0 DOWN to run it.

## Build & flash (Windows PowerShell)

```powershell
cd Verilog/fpga/basys3

# Full synth (needed after any logic change; ~1h). Default ps1 does full_synth.
.\vivado_build.ps1
#   -> runs vivado_build.tcl in <build>\basys3, writes ND120_TOP.bit + .ltx there

# Flash:
.\flash.ps1 -Quick     # JTAG only, volatile - fast iteration
.\flash.ps1            # JTAG + SPI flash - survives power cycle
```

The microcode preload images (`Code/Microcode/wcs/`, made by
`configure.py`) must exist or the ROM is empty; `vivado_build.tcl` copies them
into the build folder and stops if one is missing.

## On-chip debug (ILA)

Probes are declared in `vivado_build.tcl` (probe0..26) via `mark_debug` on wires
plus `connect_probe`. After capturing in Hardware Manager, export CSV:

```tcl
source paths.tcl   ;# sets b3_logdir = <ND120_BUILD_DIR>/basys3/logs/
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
- Timing history: `../../docs/fpga-debug-methodology.md` (section 3.2).

## Debug LEDs, switches, 7-segment and ILA (reference)

UNVERIFIED against the current Basys3 top: nobody has re-checked this map
against it. Moved here 28-SEP-2026 from
`Verilog/doc/basys3-debug-reference.md`.

### LED Layout (LD15 left to LD0 right)

```
+------+------+------+------+------+------+------+------+------+------+------+------+------+------+------+------+
| LD15 | LD14 | LD13 | LD12 | LD11 | LD10 | LD9  | LD8  | LD7  | LD6  | LD5  | LD4  | LD3  | LD2  | LD1  | LD0  |
+------+------+------+------+------+------+------+------+------+------+------+------+------+------+------+------+
| TERM | CC3  | CC2  | CC1  | CC0  |  -   |  -   |  -   | LCS  | MCLK | BEAT | UART | RST  | RUN  | GRN  | RED  |
+------+------+------+------+------+------+------+------+------+------+------+------+------+------+------+------+
  ^                                                        ^             ^                                    ^
  |                                                        |             |                                    |
  Cycle state machine (ON = active)                    Microcode     Heartbeat                           CPU Error
                                                       loaded       ~1.5 Hz
```

### LED Descriptions

| LED   | Signal               | ON means                                      | OFF means                    |
|-------|----------------------|-----------------------------------------------|------------------------------|
| LD0   | CPU RED              | CPU error/halt                                | Normal                       |
| LD1   | CPU GREEN            | CPU in normal operation                       | Not running                  |
| LD2   | RUN                  | CPU executing microcode                       | OPCOM mode (halted)          |
| LD3   | RESET (sys_rst_n)    | Reset released (SW0 UP)                       | CPU held in reset            |
| LD4   | UART TX              | UART transmitting (blinks)                    | No serial output             |
| LD5   | Heartbeat            | Blinks ~1.5 Hz if clock running               | FPGA not clocked             |
| LD6   | MCLK                 | Memory clock active                           | No memory clock              |
| LD7   | LCS (loaded)         | Microcode ROM loaded (~5.7ms after reset)     | Still loading microcode      |
| LD8   | (spare)              | -                                             | -                            |
| LD9   | (spare)              | -                                             | -                            |
| LD10  | (spare)              | -                                             | -                            |
| LD11  | CC0                  | Cycle counter bit 0 active                    | -                            |
| LD12  | CC1                  | Cycle counter bit 1 active                    | -                            |
| LD13  | CC2                  | Cycle counter bit 2 active                    | -                            |
| LD14  | CC3                  | Cycle counter bit 3 active                    | -                            |
| LD15  | TERM                 | Cycle termination active                      | -                            |

### Switch Layout

```
+------+------+
| SW1  | SW0  |    (leftmost switches on Basys3)
+------+------+
| 7seg | RST  |
| sel  | ctrl |
+------+------+
```

| Switch | Signal      | UP (1)                        | DOWN (0)                      |
|--------|-------------|-------------------------------|-------------------------------|
| SW0    | sys_rst_n   | Reset released (CPU runs)     | CPU held in reset             |
| SW1    | Display sel | 7-seg shows MAC address       | 7-seg shows MIC address       |

### 7-Segment Display

```
+--------+--------+--------+--------+
| Digit3 | Digit2 | Digit1 | Digit0 |    4 hex digits
+--------+--------+--------+--------+
```

| SW1 State | Display Content         | Format   | Example  |
|-----------|-------------------------|----------|----------|
| DOWN (0)  | MIC address (CSA_12_0)  | 0000-1FFF | 0E40    |
| UP (1)    | MAC address (LA_23_10)  | 0000-3FFF | 01A0    |

**If display shows changing values** = CPU is fetching/executing
**If display shows 0000 or stuck** = CPU is not running

### UART

| Parameter | Value            |
|-----------|------------------|
| Baud rate | 115200           |
| Data bits | 8                |
| Parity    | None             |
| Stop bits | 1                |
| Flow ctrl | None             |
| TX pin    | A17 (FPGA to PC) |
| RX pin    | A18 (PC to FPGA) |

### Boot Sequence (expected)

1. Program FPGA bitstream
2. LD5 starts blinking (clock running)
3. Slide SW0 UP (release reset)
4. LD3 turns ON (reset released)
5. LD15-LD11 start cycling (cycle state machine)
6. LD7 turns ON after ~6ms (microcode loaded, LCS_n=1)
7. LD2 turns ON (CPU running)
8. 7-seg shows changing MIC addresses
9. Serial terminal shows `#` prompt (OPCOM ready)

### Vivado ILA Debug Signals

These signals have `mark_debug` attributes for Vivado ILA probing:

#### Top Level (ND120_TOP)

| Signal              | Width | Description                              |
|---------------------|-------|------------------------------------------|
| s_run               | 1     | CPU run state (0=running, active low)    |
| s_debug_csa[12:0]   | 13    | MIC address (microcode fetch address)    |
| s_debug_uartTx      | 1     | UART TX line                             |
| s_debug_uartRx      | 1     | UART RX line                             |
| s_debug_cpu_led[6:0] | 7    | CPU status LEDs                          |
| s_debug_la_23_10[13:0] | 14 | MAC address upper (logical address)      |
| s_debug_ca_9_0[9:0] | 10    | MAC address lower (cache address)        |
| s_debug_cc_term[4:0] | 5    | {TERM_n, CC3_n, CC2_n, CC1_n, CC0_n}    |
| s_debug_mclk        | 1     | Memory clock                             |
| s_debug_lcs_n       | 1     | LCS_n (0=loading, 1=microcode loaded)    |

#### Signals to add for deeper debug (inside hierarchy)

| Signal Path                                    | Width | Description                    |
|------------------------------------------------|-------|--------------------------------|
| CPU_BOARD.s_term_n                             | 1     | TERM_n at board level          |
| CPU_BOARD.CPU.PROC.CGA.DELILAH.s_FIDBO_15_0   | 16    | CGA internal data bus output   |
| CPU_BOARD.CPU.PROC.CGA.DELILAH.s_FIDBI_15_0   | 16    | CGA internal data bus input    |
| CPU_BOARD.CPU.CS.s_csbits[63:0]               | 64    | TOPCSB - full microcode word   |
| CPU_BOARD.CPU.PROC.s_idb_erf_out[15:0]        | 16    | Register file output to IDB    |
| CPU_BOARD.MEM.RAM.CHIP_15H.sdram[addr]        | 8     | Main RAM content               |
| CPU_BOARD.IO.UART.CHIP_32H.txState            | 3     | UART TX state machine          |
| CPU_BOARD.IO.UART.CHIP_32H.rxState            | 3     | UART RX state machine          |

#### Pin Mapping Reference (Basys3 xc7a35tcpg236-1)

| Port      | Pin  | Function          |
|-----------|------|-------------------|
| sysclk    | W5   | 100 MHz clock     |
| btn1/SW0  | V17  | Reset control     |
| btn2/SW1  | V16  | Display select    |
| uartTx    | A17  | Serial TX         |
| uartRx    | A18  | Serial RX         |
| led[0]    | U16  | LD0 - CPU RED     |
| led[1]    | E19  | LD1 - CPU GREEN   |
| led[2]    | U19  | LD2 - RUN         |
| led[3]    | V19  | LD3 - RESET       |
| led[4]    | W18  | LD4 - UART TX     |
| led[5]    | U15  | LD5 - Heartbeat   |
| led[6]    | U14  | LD6 - MCLK        |
| led[7]    | V14  | LD7 - LCS loaded  |
| led[11]   | U3   | LD11 - CC0        |
| led[12]   | P3   | LD12 - CC1        |
| led[13]   | N3   | LD13 - CC2        |
| led[14]   | P1   | LD14 - CC3        |
| led[15]   | L1   | LD15 - TERM       |
| seg[0-6]  | W7,W6,U8,V8,U5,V5,U7 | 7-seg segments |
| an[0-3]   | U2,U1,T1,R2          | 7-seg anodes   |

## Related docs

- `../../docs/fpga-debug-methodology.md` - the Verilator-vs-FPGA debug workflow.
- `../../docs/boot-golden-spec.md` - expected microcode boot sequence.
- `../../docs/build-defines.md` - compile-time defines (`VERILATOR_SIM`,
  `FPGA_FF_MODE`, `SKIP_WCS_LOAD`, ...).
- `../../sim/FPGA_DEBUG_RUNBOOK.md` - Verilator-vs-board comparison method (incl. the golden-model and ILA capture notes).
