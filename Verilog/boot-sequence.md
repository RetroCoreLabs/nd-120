# ND-120 FPGA Boot Sequence

Complete documentation of the ND-120 CPU boot sequence, covering hardware reset, microcode loading, CPU self-test, and transition to OPCOM. Covers both FPGA and Verilator simulation paths.

---

## 1. Reset Entry Point

### FPGA

`sys_rst_n` is driven by `btn1` on the Basys3 board, routed through a 256-cycle power-on-reset (POR) counter in `ND120_TOP.v`. The POR counter holds `sys_rst_n=0` for 256 sysclk cycles after `btn1` goes high, ensuring stable power rails before the CPU starts.

```
btn1 pressed → POR counter (256 cycles) → sys_rst_n=1 → boot begins
```

### Verilator Simulation

`sys_rst_n` maps directly to `btn1` with no POR delay. In `test_nd120.cpp`, `btn1=false` for the first 100 ticks, then `true`. This gives a 100-cycle reset window.

```cpp
// test_nd120.cpp
top->btn1 = (tickCount < 100) ? false : true;
```

### Clock

In simulation mode (`ifdef VERILATOR_SIM`), `clk1 = sysclk` (no clock divider). In FPGA mode, `oc_select = 2'b11` selects full-speed XTAL1. All timing below assumes `sysclk` = the CPU master clock.

---

## 2. Power-On Clear and CLEAR_n Pulse

### DECODE_DGA_POW.v — CLEAR_n

The powerfail circuit (A596, A602, A591–A605) has been removed. In its place, `CLEAR_n` is derived directly from `sys_rst_n`:

```verilog
// DECODE_DGA_POW.v
assign s_clear_n = sys_rst_n;
```

While `sys_rst_n=0` (during the reset window), `s_clear_n=0` → CLEAR fires.

CLEAR propagates into the CPU board as:

```verilog
// IO_DCD_38.v → ND3202D.v
assign s_mcl = ~(s_emcl_n & s_clear_n);   // MCL = Master Clear
```

MCL=1 during reset, initializing all downstream modules (register files, bus state, interrupt controller, etc.).

### regPowerOnClear (IO_DCD_38.v)

A synchronous 4-bit counter in `IO_DCD_38.v` generates `s_power_on_zener` (the "power on clear" signal for the oscillator circuit):

```verilog
// IO_DCD_38.v — regPowerOnClear
always @(posedge sysclk) begin
    if (!sys_rst_n)
        regPowerOnClear <= 4'b0;
    else if (regPowerOnClear != 4'hF)
        regPowerOnClear <= regPowerOnClear + 1;
end
assign s_power_on_zener = (regPowerOnClear == 4'hF);
```

`s_power_on_zener` goes high after ~11 cycles post-reset, enabling the oscillator section (`s_closc = ~(OSCCL_n & s_power_on_zener)`).

---

## 3. MR_n Generation via Sync Pipeline

CLEAR_n going low (during reset) propagates through a synchronous 2-stage pipeline into the BIF (Bus Interface) section:

```
s_clear_n=0 → BIF_BCTL_SYNC_8 CHIP_3D → CHIP_4D → MR_n=0
```

The pipeline introduces a 2-cycle latency. MR_n is the "Master Reset" signal that triggers microcode loading.

Key files:
- `CPU_PROC_CGA_33.v` / `CPU_PROC_32.v` — BIF sync pipeline stages
- `CPU_CS_PROM_19.v` — consumes MR_n

MR_n stays low for approximately the same duration as the CLEAR_n pulse (the reset window), long enough for the microcode load state machine to latch onto it.

---

## 4. Microcode Load — LCS_n and the PROM→WCS Copy

### Trigger: MR_n → LCS=1

The PAL `PAL_44403C` (component `CYC_36`) implements the microcode load state machine. Its core logic:

```
if (MR | (LCS & BSTP_n & WCA12_n)) then LCS=1
else LCS=0
```

Where:
- `MR` = Master Reset (= ~MR_n). LCS is forced high when MR fires.
- `LCS` = Load Control Strobe — stays high while loading
- `BSTP_n` = Bus Stop (must be inactive)
- `WCA12_n` = bit 12 of the WCS address counter (LUA12). Goes low when the counter reaches address 4096 and wraps at 8192.

**Translation**: Loading starts when MR fires. Loading continues until `LUA12` (bit 12 of the WCS address counter) asserts. This happens after 8192 addresses (0x0000–0x1FFF) have been written.

### LCS_n = ~LCS

While `LCS_n=0` (loading active):
- `BLCS_n=0` is asserted to the PROM address MUX and WCS write enable
- The PROM (CPU_CS_PROM_19) outputs microcode data at each MCLK cycle
- Data flows: PROM → TCV (bus transceiver) → WCS data input
- The WCS address counter (`LUA12:0`) auto-increments

### Address Sweep

The WCS address counter sweeps from 0 to 8191:
- At address 8192, bit 12 (`LUA12`) flips → hold condition fails → `LCS=0` → `LCS_n=1`
- Loading complete

### Timing (Simulation)

From `boot_analysis.md`:
- `LCS_n=0` asserted: tick ~7
- `LCS_n=1` (load complete): tick ~573,437
- Load duration: ~573,430 sysclk cycles for 8192 microcode words

This gives ~70 cycles per word (MCLK rate, bus transactions, pipeline stalls).

---

## 5. CPU Starts Executing

At `LCS_n=1` (load complete):
- WCS is fully loaded with microcode
- The microcode program counter starts at address `o02001` (octal, the reset/start vector)
- The CPU begins fetching and executing microcode instructions

**Important**: Microcode loading is **not** triggered by the `MACL` microcode instruction. It is a pure hardware sequence driven by `MR_n`. The WCS does not contain valid microcode until the PROM copy is complete — executing MACL before this would have no valid code to run.

---

## 6. STP Latch and Run Control

### F595 A571 — The STP Latch

The `STP` latch in `DECODE_DGA_POW.v` controls whether the CPU runs or stops:

```verilog
F595 A571 (
    .sysclk(sysclk),
    .sys_rst_n(sys_rst_n),   // Forces Q=0 (running) during reset
    .H01_S (a580_nand_out),  // SET = stop the CPU
    .H02_R (s_start),        // RESET = start (release stop)
    .H03_G (s_zz1),          // Gate enable
    .N01_Q (s_stp),          // STP = 1 → CPU stopped
    .N02_QB(s_stp_n)
);
```

`sys_rst_n=0` forces `s_stp=0` (CPU allowed to run). At reset release, the latch is in the idle (run) state.

### SET condition for STP

```verilog
assign a580_nand_out = ~(s_sstop_n & s_clear_n & s_stop_n);
```

A SET (stop CPU) fires when any of:
- `SSTOPN=0` — software stop command via COMM register
- `s_clear_n=0` — during CLEAR pulse (would hold, but sys_rst_n already forces Q=0)
- `STOP_n=0` — external front panel STOP button (tied HIGH in simulation)

### SSTOPN at Boot

`SSTOPN` (s_sstop_n) is the Q1 output of F924 A181 in `DECODE_DGA_COMM.v`. It is clocked by `CLK3` (≈ sysclk rate):

```verilog
// DECODE_DGA_COMM.v
// D1 = s_isstop_n = NAND(CSCOMM bits)
// At boot: CSCOMM[3]=0 → s_isstop_n=1 → SSTOPN=1 within first CLK3 cycle
```

With `CSCOMM[3]=0` at boot, `s_isstop_n=1` → `SSTOPN=1` within the reset window. This ensures `a580_nand_out=0` after reset, so the STP latch stays clear (CPU runs).

### RUN_n

```verilog
// ND3202D.v
assign s_run_n = s_stp;   // RUN_n=0 when STP=0 (CPU running)
```

---

## 7. RTC Timer and Panel Interrupt

### RTOSC Generation

The real-time oscillator is generated by a two-stage F714 binary counter chain in `IO_DCD_38.v`:

```
sysclk → CHIP_13C_1 (÷16, QD=s_div_16) → CHIP_13C_2 (÷16, QD=s_XRTOSC=RTOSC)
```

RTOSC frequency = sysclk / 256 ≈ 390.6 kHz (at 100 MHz sysclk).

### RTC Interrupt Period

The RTC interrupt chain in `DECODE_DGA_POW.v`:

```
RTOSC → A624 (÷2) → A616/A618/A617 (JK counter ÷8) → A577 (÷2) → RTC interrupt
```

Total divisor: 2 × 8 × 2 = 32

RTC period = RTOSC period × 32 = (sysclk/256) × 32 = sysclk × 8192

At 100 MHz: 8192 × 10 ns = 81.92 µs per RTC interrupt (simulation).
On real hardware (10 MHz clock): 8192 × 100 ns = 819.2 µs ≈ 1.2 kHz interrupt rate.

### Simulation Parameter

```verilog
// DECODE_DGA_POW.v (shortened - read the file for the full set)
`ifdef RTC_REAL_PERIOD                 // real period even in Verilator
    localparam RTC_20MS = (`BOARD_CLK_FREQ / 50) - 1;    // 20 ms
`elsif VERILATOR_SIM
    localparam RTC_20MS = 21'd8192;    // TESTE=1 baseline (RTC_SIM_20MS overrides)
    localparam RTC_5MS  = 21'd2048;
`else                                  // every FPGA build
    localparam RTC_20MS = (`BOARD_CLK_FREQ / 50) - 1;    // 20 ms of the real board clock
    localparam RTC_5MS  = (`BOARD_CLK_FREQ / 200) - 1;   // 5 ms
`endif
```

The FPGA period used to be a fixed 1_999_999 (20 ms at 100 MHz); on a board
whose CPU clock is slower that stretched the tick (16.67 MHz on the Basys3 gave
~120 ms), so it is now derived from `BOARD_CLK_FREQ`.

**Note**: If RTC is set too fast (e.g., 256 cycles), RTC interrupts (~3906 per million ticks) starve the CPU of execution time and instruction verify hangs. 8192 cycles is the correct calibration.

### Panel Interrupt Path

RTC fires → trap `o016` (octal) → `PANVC[5]` → microcode CONT with `COMM,CLRTC` → clears the RTC flag.

---

## 8. CPU Self-Test (SELFT / MACL2)

After the WCS loads and the CPU starts at `o02001`, it runs the built-in self-test sequence:

### Phase 1: MACL (Microcode All Loaded)

The microcode writes to `COMM,SIOC` with value `30120` (octal):

```
COMM,SIOC ← 30120
```

This write sets:
- Bit 5 (red LED) = 1 → Master Clear / MACL in progress indicator
- Other control bits for the I/O controller

Simultaneously, the `AB,MACL` microcode scratch location is set non-zero at vector 0 and cleared at `STOP2` when it is safe to leave that phase.

### Phase 2: SELFT (Self-Test)

The CPU runs the hardware self-test (SELFT sequence). Tests:
- ALU operations
- Register file
- Memory reference (via simulated RAM)
- I/O decode

In Verilator simulation (from `boot_analysis.md`):
- ALU countdown loop: tick 573,799 to 754,018 (~180K ticks, 16,384 iterations)

If self-test fails → `STERR` branch → halt (does **not** reach MACL2).

### Phase 3: MACL2 (Self-Test Complete)

If all self-tests pass, the microcode writes:

```
COMM,SIOC ← 30140
```

This sets:
- Bit 4 (green LED) = 1 → Initialization complete
- Bit 5 (red LED) = 1 → Master Clear remains set

Then `AB,STATUS` is written with the current SIOC value (30140), recording the post-MACL2 I/O controller state.

OPCOM becomes available after MACL2 completes.

### Timing (Simulation)

- `LCS_n=1` (load complete): tick ~573,437
- OPCOM reachable: tick ~739,217
- OPCOM to MACL2 gap: ~166K ticks of self-test execution

---

## 9. Microcode Scratchpad Semantics

Three ND-120-specific scratchpad locations are used during boot. **Note**: `AB,NOISE` is ND-120 specific and does not exist in the ND-110 RASK.

### AB,MACL

- **Set**: At microcode vector 0 (start) — non-zero value
- **Cleared**: At `STOP2` when the system is safely past the MACL phase
- **Purpose**: Gate — while non-zero, the system is in "just finished MACL, stand-by not OK" state. Used to prevent premature STOP/load operations during microcode load and initial self-test.

### AB,STATUS

- **Set**: At MACL2 — receives the current `SIOC` register value (30140 octal)
- **Purpose**: Preserves the I/O controller state after a successful self-test. Only written if self-test passes (no `STERR`). Useful for diagnostic reads after boot.

### AB,NOISE

- **Set**: At MACL entry
- **Reset**: At STOP
- **Purpose**: ND-120 specific. Inhibits microcode load after MACL completes. Prevents spurious re-loads if the load sequence is accidentally re-triggered. Not present in the ND-110 RASK.

---

## 10. SIOC LED Signals

The `COMM,SIOC` register controls I/O controller state and maps to physical LEDs on the operator panel:

| Bit | Value (octal) | Color | Meaning |
|-----|--------------|-------|---------|
| 4   | 000020       | Green | Initialization complete (set at MACL2) |
| 5   | 000040       | Red   | Master Clear / MACL in progress |

### Write sequence

| Phase | SIOC value | Green (bit 4) | Red (bit 5) |
|-------|-----------|--------------|------------|
| MACL  | 30120     | 0            | 1          |
| MACL2 | 30140     | 1            | 1          |

Both LEDs lit after MACL2 = normal post-boot state. Only red during MACL = self-test running.

---

## 11. OPCOM and Post-Boot State

OPCOM (Operator Communication) is the ND-120 console interface, implemented via the SC2661 UART. After MACL2:

- UART is initialized and ready
- OPCOM prints the ND-120 banner / prompt
- The system awaits operator commands (e.g., `INSTRUCTION-VERIFY`, `LOAD`, `START`)

From `boot_analysis.md`, simulation timing:
- OPCOM prompt appears at tick ~739,217
- `INSTRUCTION-VERIFY` test can then be run interactively

After OPCOM is active, the boot sequence is complete. The CPU is in the `STOP` state (STP latch set by the `MACL2` sequence's final STOP instruction), waiting for operator input.

---

## 12. Simulation vs FPGA Timing

| Parameter | Verilator Simulation | FPGA (Basys3, 100 MHz) |
|-----------|---------------------|----------------------|
| sys_rst_n source | btn1 direct (no POR) | btn1 + 256-cycle POR counter |
| Reset window | 100 ticks | 256 cycles |
| Clock | sysclk = 100 MHz (simulated) | 100 MHz actual |
| RTOSC | sysclk/256 = 390.6 kHz | sysclk/256 = 390.6 kHz |
| RTC period | 8192 sysclk cycles | `BOARD_CLK_FREQ / 50` sysclk cycles (20 ms real time) |
| Microcode load | ~573K ticks (8192 words × ~70 cycles/word) | Same (hardware-dependent) |
| OPCOM ready | tick ~739,217 | Similar wall-clock time |

The `VERILATOR_SIM` macro is injected by the Makefile (`-DVERILATOR_SIM`). Besides the `RTC_20MS`/`RTC_5MS` period it also enables the bus ports, the fast UART and the large simulation RAM (`MEM_RAM_49.v`), so simulation and FPGA builds are NOT otherwise identical. The full list of defines is in `docs/build-defines.md`.

This table was written for the Basys3 at a 100 MHz sysclk; the boards now run other clocks (per-board figures in `fpga/README.md`).

### Running Simulation (WSL required)

The oss-cad-suite Verilator in Git Bash has a broken Perl environment (missing `Pod::Usage`). Always use WSL:

```bash
# inside WSL, from the repo checkout
cd Verilog/sim && make compile && make run
```

For the full CPU simulation (with UART/OPCOM):

```bash
cd Verilog/runSim && make compile && make run
```

---

## 13. Signal Reference

### Reset Chain

| Signal | Source | Description |
|--------|--------|-------------|
| `btn1` | Basys3 button | Physical reset button |
| `sys_rst_n` | `ND120_TOP.v` | Active-low system reset (btn1 + POR in FPGA) |
| `s_clear_n` | `DECODE_DGA_POW.v` | `= sys_rst_n`. CLEAR pulse during reset window |
| `s_mcl` | `IO_DCD_38.v` | Master Clear: `~(s_emcl_n & s_clear_n)` |
| `s_power_on_zener` | `IO_DCD_38.v` | High after ~11 cycles post-reset |

### Microcode Load

| Signal | Source | Description |
|--------|--------|-------------|
| `MR_n` | BIF sync pipeline | Master Reset, triggers LCS |
| `LCS_n` | `PAL_44403C` (CYC_36) | Low during microcode load |
| `BLCS_n` | derived | Load Control Strobe to PROM/WCS |
| `LUA12` | WCS address counter | High when address ≥ 4096; wraps at 8192 |

### Run Control

| Signal | Source | Description |
|--------|--------|-------------|
| `s_stp` / `STP` | F595 A571 (DGA_POW) | 1 = CPU stopped |
| `s_run_n` | `ND3202D.v` (`= s_stp`) | Active-low run enable |
| `SSTOPN` | F924 A181 (DGA_COMM) | Software stop request from CSCOMM |
| `s_start` | F924 (DGA_COMM) | Start command from CSCOMM |
| `a580_nand_out` | DGA_POW | NAND(SSTOPN, clear_n, stop_n) — SET for STP |

### RTC / Oscillator

| Signal | Source | Description |
|--------|--------|-------------|
| `XTAL1` | `ND120_TOP.v` | Master clock input (= sysclk in sim) |
| `s_div_16` | CHIP_13C_1 (IO_DCD_38) | sysclk ÷ 16 |
| `s_XRTOSC` / `RTOSC` | CHIP_13C_2 (IO_DCD_38) | sysclk ÷ 256 ≈ 390 kHz |
| RTC interrupt | DGA_POW counter | RTOSC × 8192 period |

### SIOC / LEDs

| Signal | Description |
|--------|-------------|
| `COMM,SIOC` | I/O controller register, written by microcode |
| Bit 4 (green) | Initialization complete — set at MACL2 |
| Bit 5 (red) | Master Clear / MACL in progress — set at MACL |

---

## Boot Sequence Summary (Timeline)

```
tick 0        sys_rst_n=0 (reset asserted)
              s_clear_n=0, MCL=1
              F595 latches forced to idle state (sys_rst_n)
              F924 A181/A183 clock SSTOPN=1, s_start_n=1 within reset window

tick ~7       MR_n goes low (via BIF sync pipeline from CLEAR_n)
              PAL_44403C: MR=1 → LCS=1 → LCS_n=0
              PROM→WCS copy begins (8192 addresses)

tick 100      sys_rst_n=1 (reset released)
              s_clear_n=1, MCL=0
              STP latch: H01_S=0, H02_R=0 → holds Q=0 (CPU runs)

tick ~573,437 LUA12 wraps → LCS=0 → LCS_n=1
              Microcode load complete
              CPU begins executing at o02001

tick ~573,437 MACL phase:
              AB,MACL set non-zero
              AB,NOISE set
              COMM,SIOC ← 30120 (red LED on)

tick ~573,799 ALU self-test countdown loop begins (16,384 iterations)

tick ~754,018 ALU self-test complete

tick ~739,217 MACL2 phase (if all tests pass):
              COMM,SIOC ← 30140 (green LED on)
              AB,STATUS ← 30140
              AB,NOISE cleared at STOP
              AB,MACL cleared at STOP2

              OPCOM banner printed, system ready for operator
```

---

*Generated from source analysis of the ND-120 Verilog implementation.*
*Primary sources: `DECODE_DGA_POW.v`, `IO_DCD_38.v`, `DECODE_DGA_COMM.v`, `ND3202D.v`, `ND120_TOP.v`, `CPU_CS_PROM_19.v`, `boot_analysis.md`, `test_nd120.cpp`.*
