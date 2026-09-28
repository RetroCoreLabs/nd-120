# MC68705U3 — ND-120 Front Panel Controller
## Complete Firmware Analysis

**File:** `Code/68705/MC68705U3_35C.BIN` (disassembly: `Code/68705/U3/U3-Dissassembly.pdf`; C port: `Code/68705/U3/u3_code/u3.c`)  
**Ghidra Project:** `ND-120-68705-U3` in the RetroGhidra project (a separate repository)  
**Architecture:** Motorola MC68705U3 (6805 family), 4KB ROM (0x0000–0x0FFF), 128-byte RAM (page 0)  
**Crystal:** 4 MHz  
**Analysis date:** 2026-04-06
**Corrected:** 2026-08-28 - every pin/strobe statement below was re-checked against the ROM bytes with a fresh disassembly (see section 17, "Corrections 28-AUG-2026"). The clock path is now emulated in `Verilog/CPU-BOARD-3202/circuit/PANCAL_68705_CLOCK.v` (doc: `Verilog/docs/panel-clock-68705.md`).

---

## Table of Contents

1. [Hardware Overview](#1-hardware-overview)
2. [Port Assignment Summary](#2-port-assignment-summary)
3. [Boot Sequence](#3-boot-sequence)
4. [Timer ISR (400 Hz)](#4-timer-isr-400-hz)
5. [Main Loop — FIFO Command Processing](#5-main-loop--fifo-command-processing)
6. [PANC Command Protocol — Receiving Commands](#6-panc-command-protocol--receiving-commands)
7. [PANC Text Protocol — Writing Text to the Panel](#7-panc-text-protocol--writing-text-to-the-panel)
8. [PANC Response Protocol — Sending Data to ND-120](#8-panc-response-protocol--sending-data-to-nd-120)
9. [Display Update — From Characters to Shift Register](#9-display-update--from-characters-to-shift-register)
10. [MM58274 RTC Interface](#10-mm58274-rtc-interface)
11. [Software RTC (Timer-Driven)](#11-software-rtc-timer-driven)
12. [CPU Performance Monitoring (Port D)](#12-cpu-performance-monitoring-port-d)
13. [PRES / MIPANS / IDB:15 Hardware Path](#13-pres--mipans--idb15-hardware-path)
14. [RAM Layout](#14-ram-layout)
15. [ROM Data Tables](#15-rom-data-tables)
16. [Interrupt Vectors](#16-interrupt-vectors)
17. [Corrections to Existing Analysis Documents](#17-corrections-to-existing-analysis-documents)

---

## 1. Hardware Overview

The MC68705U3 (chip 44A) is the dedicated front-panel controller for the ND-120 minicomputer. It sits between the Delilah DGA (Gate Array) CPU and the 3202D CBP (Control Board Panel), performing:

- Reception and dispatch of PANC commands from the ND-120 CPU via the IDB FIFO
- Display update: 4-character text output to 5 × 7-segment digits via Port C serial shift register chain
- Software real-time clock (seconds → minutes → hours → days → months → years)
- MM58274 hardware RTC: read at boot and at every clock READ from the CPU, written after every clock WRITE (section 10)
- CPU performance monitoring: samples Port D 400 times/second (section 4), builds utilization histograms

```
┌──────────────────────────────────────────────────────────────────┐
│                        ND-120 SYSTEM                             │
│                                                                  │
│  ┌──────────────┐   IDB[15:0]   ┌──────────────────────────┐   │
│  │  Delilah DGA │◄─────────────►│  3202D CBP Board         │   │
│  │  (CPU)       │               │  ┌────────────────────┐   │   │
│  └──────────────┘               │  │ 74LS374 (32B) Latch │   │   │
│          │ /EMP (FIFO rdy)      │  │ IDB[7:0] ↔ PA[7:0] │   │   │
│          │ IDBS.MIPANS (20ms)   │  └────────────────────┘   │   │
│          │                      │                            │   │
│          │                      │  ┌────────────────────┐   │   │
│          ▼                      │  │  MC68705U3 (44A)   │   │   │
│       IDB Bus                   │  │  Panel Controller  │   │   │
│          │                      │  └────────────────────┘   │   │
│          │                      └──────────────────────────┘   │
│          │                                                       │
│       74LS244                                                    │
│       IDB:15 ← PRES ← 74F04 inv ← PB7 (always 0)               │
└──────────────────────────────────────────────────────────────────┘
```

---

## 2. Port Assignment Summary

### Port A — IDB Data Bus (Bidirectional)

| Mode | DDRA | PA[7:0] Function |
|------|------|-----------------|
| Normal (command rx) | `0x00` (all input) | Receives IDB[7:0] data from 74LS374 latch via WMM strobe |
| Response (data tx) | Modified per output | Drives IDB[7:0] back to ND-120 CPU |
| RTC access (boot) | `0xF0` (upper=out, lower=in) | PA[7:4]=RTC register address, PA[3:0]=RTC data nibble read-back |

### Port B — Control Signals (Output, DDRB=0xFF, init=0x2F = 0b00101111)

Pin names are from sheet 40 of the 3202D schematic; the use of each pin is what the ROM bytes do with it (corrected 28-AUG-2026):

| Bit | Signal (sheet 40) | Direction | Function |
|-----|-------------------|-----------|----------|
| PB0 | WMM~ → 74LS374 (32B) CK | **Panel → ND-120** | Answer-byte strobe. Rising edge latches PA[7:0] into the 74LS374 → IDB[7:0] on EPANS. Used by `Output_Response_To_ND120_IDB` (0x09C5). The ONLY path from the panel to the CPU. |
| PB1 | WRCLK~ → MM58274 /WR | MM58274 only | Write strobe to the calendar chip. Used by 0x09EE, which writes the whole calendar (PA[7:4] = register address, PA[3:0] = BCD digit) after the CPU has set the time. Never reaches the ND-120. |
| PB2 | ROCLK~ → MM58274 /RD | MM58274 only | Read strobe. Used by 0x0AC0 to read the calendar (at boot and at every time READ, see 0x0705). |
| PB3 | RMM~ → DGA | **ND-120 → Panel** | FIFO read strobe. `Strobe_WMM_Read_From_FIFO` (0x09BC) = `BCLR 3,PORTB ; LDA PORTA ; BSET 3,PORTB`. While RMM~ is low the DGA drives the FIFO head on PA and pops it. |
| PB4 | STAT3 → DGA | Panel → ND-120 | Panel request. Pulsed high→low in the idle loop (0x0153/0x0155) every 255 EMP~ polls. The DGA (IDBS A282/A283) turns the edge into PRQ. Also PANS bit 11 via the 74LS244. |
| PB5 | STAT4 → DGA + PANS bit 12 path | Panel → ND-120 | "Answered" level: 1 at reset (PORTB=0x2F), cleared at the start of a clock command (0x06D3), set after the answer is latched (0x06ED/0x0712), cleared at 0x0195 after every command's display pipeline. The DGA makes VAL (PANS bit 12) from it. |
| PB6 | READ → PANS bit 13 | Panel → ND-120 | 1 = the latched answer byte is clock data (set 0x06FA on a read, cleared 0x06E1 on a write). |
| PB7 | PRES source | Hardware only | Permanently driven 0. Inverted by 74F04 (13G) → PRES=1 always → IDB:15=1 via 74LS244 |

> **PB0 vs PB3 — do not confuse these:** PB3 (RMM~) reads bytes FROM the ND-120 (FIFO→PA). PB0 (WMM~) writes ONE byte TO the ND-120 (PA→74LS374→IDB). They are opposite directions on the same data bus.

> **PB0 initial state = 1 (HIGH = /WMM deasserted).** The strobe fires as a LOW pulse: PB0 goes LOW then immediately HIGH. The 74LS374 latches PA on the **rising edge** (PB0 going HIGH).

> **PB7 hardware path:** PB7=0 → 74F04 inverter (13G) → PRES=1 → 74LS244 → IDB:15=1 when ND-120 asserts IDBS.MIPANS. The panel MCU never controls this value; MIPANS is asserted by ND-120 microcode MS20 every ~20ms to latch PRES into IDB:15.

### Port C — Display Shift Register Chain (Output, DDRC=0xFF, init=0xF8)

| Bit | Signal | Function |
|-----|--------|----------|
| PC[2:0] | STAT0-2 → 74LS244 → PANS bits 8-10 | PFUNC echo: 0x06C5-0x06CB copies the command's bits 2:0 here for every bit3=0 command (init 0xF8 = 000) |
| PC3 | DISP1 | Bit for display digit 1 (serial shift chain) |
| PC4 | DISP2 | Bit for display digit 2 |
| PC5 | DISP3 | Bit for display digit 3 |
| PC6 | DISP4 | Bit for display digit 4 |
| PC7 | DISP5 | Bit for display digit 5 (rightmost) |

Port C is the serial shift register output. All 5 display bits are clocked simultaneously for each bit position of the display bitmap.

### Port D — ND-120 CPU Status Monitoring (Input, DDRD=0x00)

| Bit | Signal | Function |
|-----|--------|----------|
| PD0 | PCR Ring[0] | CPU ring level bit 0 |
| PD1 | PCR Ring[1] | CPU ring level bit 1 |
| PD2 | PONI | Memory Protection ON (from ND-120) |
| PD3 | IONI | Interrupt system ON (from ND-120) |
| PD4 | LHIT | Cache hit (sampled by 0x09AF `BRCLR 4,PORTD`) |
| PD5 | LEV0 | 1 = CPU on level 0 = idle (sampled by 0x09B4 `BRSET 5,PORTD`) |
| PD6 | GND | Tied low on sheet 40 |
| PD7 | EMP~ | DGA FIFO not empty (XEMN = ~fifo_empty): 1 = a command byte is waiting |

### On-chip register addresses the ROM uses

$00-$03 = PORTA-PORTD, $04-$06 = DDRA-DDRC (DDRA is switched by 0x09C5, 0x09EE and 0x0AC0), $07 is cleared at boot (0x013A), $08 = TDR (reloaded by the ISR at 0x08CA, polled by the main loop at 0x0197), $09 = TCR (0x0141; the ISR clears its bit 7 at 0x08CC), $0A = MR (0x0149), $0B is written only by the soft reset of command 7 (0x0641). RAM starts at $10.

---

## 3. Boot Sequence

Entry point: **0x0110** (reset vector at 0x0FFE)

```mermaid
flowchart TD
    A[Reset / Power-on\n0x0110] --> B[Clear RAM\n0x10–0x8F = 128 bytes zeroed]
    B --> C[Init timing counters\n0x5B=16, 0x5C=200, 0x5D=2\n0x71=0x80 LHIT/LEV0 window = 128 ticks]
    C --> D[Configure ports\nDDRA=0 input\nPORTB=0x2F, DDRB=0xFF output\nPORTC=0xF8, DDRC=0xFF output\nDDRD=0x00 input]
    D --> E[Initialize MM58274 RTC\n0x0AC0: read year/month/day/hour/min\nSeed software RTC counters\n0x20=year, 0x21=month, 0x22=day\n0x23=hour, 0x24=min, 0x25=sec]
    E --> F[Start timer\nTCR=0x35 TOIE+prescaler/32\nTDR=3 reload\nMR=0x7F\n→ 400 Hz timer ISR enabled]
    F --> G[Clear system_config 0x1A = 0]
    G --> H[Main Loop\nsee section 5]
```

**Timer rate calculation:**

The timer uses an external clock input with /32 prescaler, reload value TDR=3. With the ND-120 board clock feeding the 68705 timer input:

- TCR=0x35: TOIE=1 (timer overflow interrupt enable), prescaler=/32, external clock
- **The ISR runs at 400 Hz.** The ROM proves the tick count: the software seconds counter advances once every 200 x 2 = 400 ISR ticks (0x5C and 0x5D, 0x08E5-0x08F5; 0x5B is NOT part of that chain, see section 4), so the software clock only keeps time at 400 Hz.
- The board gives exactly that rate: XTAL1 = 39.3216 MHz (`ND3202D.v`) → both halves of the 74393 at 13C divide by 256 → RTOSC = 153.6 kHz (`IO_DCD_38.v`, sheet 38) → the DGA divides by 4 (A633 and A629, `DECODE_DGA_POW.v`, DECODE design-doc pages 8-10) → PANOSC = 38.4 kHz on the 68705 timer pin → /32 prescaler = 1200 Hz → TDR counts 3 → 400 Hz. The name `Timer_1200Hz` in the old notes is the prescaler output, not the interrupt rate. The last step (one interrupt per 3 prescaler counts, since the ISR reloads 3 as soon as TDR reaches 0) follows the 6805 timer rule and has not been measured on a board.
- The "~247 Hz" (2026-04-06) and "6400 Hz" (28-AUG-2026) figures that earlier versions of this document gave are both wrong - see section 17.

---

## 4. Timer ISR (400 Hz)

Entry point: **0x08C8** (timer vector at 0x0FF8)

```mermaid
flowchart TD
    ISR[Timer ISR\n0x08C8] --> A[Reload TDR=3\nClear TIF bit 7 of TCR]
    A --> B[Sample_ND120_CPU_Status_Signals\n0x09D4\nPORTD → RAM 0x19\nLEV0/LEV1/LHIT via PD bits]
    B --> C[Update_CPU_Ring_PONI_IONI_Statistics\n0x06B2\nUpdate LED latch 0x60 from 0x19]
    C --> D{0x1B bit1 set?\nLHIT monitor active}
    D -->|yes| E[Update LHIT display\n0x0985]
    D -->|no| F
    E --> F[DEC 0x5B\nshift-prescaler counter]
    F --> G{0x5B == 0?}
    G -->|yes| H[Shift_CPU_Utilization_History_Buffer\n0x0948\nReload 0x5B=16]
    G -->|no| I[DEC 0x5C\n200-tick prescaler]
    H --> I
    I --> J{0x5C == 0?}
    J -->|no| K[RTI]
    J -->|yes| L[Reload 0x5C=200\nDEC 0x5D half-second divider]
    L --> M{0x5D == 0?}
    M -->|no| K
    M -->|yes| N[Reload 0x5D=2\nIncrement_Software_RTC_Counters\n0x08F9]
    N --> K
```

**Timer tick chain summary:**

| Counter | Reload | Fires every | Action |
|---------|--------|-------------|--------|
| 0x5B | 16 | 16 ticks = 40 ms | Shift CPU utilization history buffer |
| 0x5C | 200 | 200 ticks = 0.5 s | Outer prescaler |
| 0x5D | 2 | 2 × 200 = 400 ticks = 1 s | Software RTC tick (1 second) |

> **Note:** 0x5B and 0x5C are NOT in series: the ISR decrements 0x5C on every tick whatever 0x5B does (0x08DC `BNE $08E5` jumps straight to `DEC $5C`). So the seconds tick is 200 x 2 = 400 ticks, which is exactly 1 s at 400 Hz (section 3). The software clock is only used for the panel display; the time the CPU reads comes from the MM58274 (section 10).

---

## 5. Main Loop — FIFO Command Processing and /EMP Signal

After boot, the MCU enters an infinite polling loop at the end of `Init_And_Main_Loop` (0x0110+).

### /EMP (PD7) — The Central Trigger

`/EMP` is the FIFO "data ready" signal driven by the 3202D CBP board hardware. It appears on **Port D bit 7** (PD7). The MCU sees PD7=1 when the FIFO has a command byte ready to be read.

> **Critical:** /EMP is NOT an interrupt. The MCU polls PD7 at two specific points in its loop (see scenarios below). The timer ISR does NOT check PD7.

**IDB read path** (when PD7=1, MCU reads a byte):

```
0x09BC: Strobe_WMM_Read_From_FIFO
  SEI                    ; protect the bus transaction
  BCLR PB3              ; PB3 = RMM~ LOW  → DGA drives the FIFO head on PA and pops it
  A = PORTA             ; read the byte
  BSET PB3              ; PB3 = RMM~ HIGH
  CLI
  RTS
```

PB3 is RMM~ (sheet 40). The DGA (DECODE_DGA.v) does `XA_7_0 = RMM_n ? 0 : fifo_out` and pops one byte per XCLK while RMM~ is low. PB4 is STAT3 (panel request), NOT a FIFO strobe - see below.

---

### Scenario A — /EMP asserted while MCU is idle (waiting for first command)

This is the **normal wakeup path**. The MCU loops at 0x014E–0x0161, repeatedly pulsing PB4 (STAT3, the panel request to the DGA - not a FIFO strobe) and then polling PD7 up to 255 times before pulsing again.

```mermaid
flowchart TD
    IDLE[Main loop idle\n0x014E] --> T[Load timeout = 255\nRAM 0x1F = 0xFF]
    T --> P4[Pulse PB4 = STAT3 HIGH then LOW\npanel request to the DGA]
    P4 --> CHK{BRSET 7,PORTD\nPD7 == 1?\n/EMP asserted?}
    CHK -->|no: FIFO empty| DEC[DEC RAM 0x1F\ntimeout--]
    DEC --> ZRO{timeout == 0?}
    ZRO -->|no: keep waiting| CHK
    ZRO -->|yes: re-prime FIFO| IDLE
    CHK -->|yes: FIFO has data| CMD[JSR 0x04D8\nProcess_PANC_Command_From_FIFO\nread command byte via PB3 = RMM~]
    CMD --> DISP[Run full display pipeline\nclear bitmap → ROM lookup →\n3-pass bit merge → Port C serialize]
    DISP --> SYNC[Wait TDR==3\ntimer sync point]
    SYNC --> XCHG[Clock the bitmap out to Port C\n0x04A7 - nothing goes to the ND-120 here]
    XCHG --> EMP2{BRSET 7,PORTD\nPD7 still == 1?}
    EMP2 -->|yes → Scenario B| CMD
    EMP2 -->|no| DLY[Inter-command delay\n32×10 = 320 cycles]
    DLY --> IDLE
```

---

### Scenario B — /EMP asserted immediately after command completes (back-to-back)

At address **0x01A2**, after every full command+display cycle, PD7 is checked again **before** the inter-command delay. If the FIFO already has the next command loaded, the MCU re-enters command processing immediately without delay.

```mermaid
flowchart TD
    PREV[Previous command + display cycle complete\n0x019D–0x01A1] --> CHK2{BRSET 7,PORTD 0x01A2\nPD7 == 1?\n/EMP still asserted?}
    CHK2 -->|yes: more data in FIFO| FAST[Jump directly to 0x0161\nJSR 0x04D8\nread next command — NO DELAY]
    FAST --> DISP2[Display pipeline\nfor new command]
    DISP2 --> SYNC2[Timer sync]
    SYNC2 --> XCHG2[Port C bitmap out\n0x04A7]
    XCHG2 --> CHK2
    CHK2 -->|no: FIFO now empty| DLY2[Inter-command delay\n320 cycles\n0x01A5–0x01B1]
    DLY2 --> IDLE2[Return to idle polling\nJMP 0x014E]
```

---

### Combined /EMP State Machine

```mermaid
stateDiagram-v2
    [*] --> IDLE: Boot complete

    IDLE: Idle — polling PD7\nPulse STAT3 (PB4) every 255 checks
    IDLE --> CMD_ACTIVE: PD7=1 (/EMP asserted)\n→ jump to 0x0161

    CMD_ACTIVE: Command active\nReading FIFO bytes via PB3\nRunning display pipeline
    CMD_ACTIVE --> CMD_ACTIVE: PD7=1 at 0x01A2\n(back-to-back, no delay)
    CMD_ACTIVE --> DELAY: PD7=0 at 0x01A2\n(FIFO drained)

    DELAY: Inter-command delay\n320 CPU cycles
    DELAY --> IDLE: JMP 0x014E
```

---

### PB3 vs PB4 (corrected 28-AUG-2026)

| Pin | Sheet 40 | When used | What it does |
|-----|----------|-----------|-------------|
| **PB4** | STAT3 | Main idle loop (0x0152–0x0155), once per 255-poll timeout (~3 ms) | Pulses STAT3 HIGH→LOW towards the DGA. The DGA's A282/A283 edge detector turns it into a PRQ (panel request) that vectors the microcode to MOPC (PRQ: at o2340). It has nothing to do with the FIFO. |
| **PB3** | RMM~ | Inside every `Strobe_WMM_Read_From_FIFO` (0x09BC) | Read strobe to the DGA FIFO; MCU reads PORTA while RMM~ is LOW |

For a 5-byte command PB3 fires 5 times. PB4 fires only while the panel is idle.

---

### Main loop — complete flow

```mermaid
flowchart TD
    START[Main loop entry\n0x014E] --> A[Timeout = 255\n0x001F = 0xFF]
    A --> B[SEI\nPB4 = STAT3 HIGH→LOW\npanel request\nCLI]
    B --> C{PD7 == 1?\n0x0158: BRSET 7,PORTD}
    C -->|no| D[DEC 0x001F]
    D --> E{== 0?}
    E -->|no| C
    E -->|yes: re-prime| START
    C -->|yes| F[0x0161: JSR 0x04D8\nRead cmd byte via PB3\nDispatch cmd 0–7 or time response]
    F --> G[Clear bitmap 0x27–0x46]
    G --> H[Load char ROM → 0x52–0x59\n0x01B4: Load_Display_Character_Data_From_ROM]
    H --> I[Display merge pass 1\nmask=0x40, shift=4\n0x0479]
    I --> J[Format 7-seg patterns\n0x01ED]
    J --> K[Display merge pass 2\nmask=0x20, shift=2\n0x0479]
    K --> L[Alt display decode\n0x037B]
    L --> M[Display merge pass 3\nmask=0x10, shift=1\n0x0479]
    M --> N[PB5 LOW\nWait TDR==3\ntimer just reloaded]
    N --> O[SEI\nJSR 0x04A7\nClock 30 bitmap bytes to Port C\nCLI]
    O --> P{PD7 == 1?\n0x01A2: BRSET 7,PORTD}
    P -->|yes: more cmds| F
    P -->|no| Q[Inter-command delay\n32 × 10 cycles = 320]
    Q --> START
```

---

## 6. PANC Command Protocol — Receiving Commands

### Transport Layer

The ND-120 CPU sends commands with `TRR PANC`. Microcode RPANC (o1045 in the DELILAH-L listing) does `IDBS,SWAP COMM,LDPANC` twice, so the FIFO in the DGA receives A[15:8] first and A[7:0] second. The FIFO signals "not empty" on PD7 (EMP~). The MC68705 reads bytes one at a time with RMM~ (PB3).

**`Strobe_WMM_Read_From_FIFO` (0x09BC):**
1. `BCLR 3, PortB` (RMM~ LOW - the DGA drives the FIFO head on PA and pops it on XCLK)
2. Read Port A: `LDA PORTA`
3. `BSET 3, PortB` (RMM~ HIGH)
4. Return byte in A

So the command byte IS the high byte of the PANC register: bit 5 = PANC bit 13 ("read request"), bit 3 = PANC bit 11, bits 2:0 = PFUNC (PANC bits 10:8). The second byte is WPAN (PANC bits 7:0).

### Command Byte Format

```
 Bit:  7   6   5   4   3   2   1   0
      ┌───┬───┬───┬───┬───┬───┬───┬───┐
      │ X │ X │ X │ X │DIR│ CMD[2:0]  │
      └───┴───┴───┴───┴───┴───┴───┴───┘
```

| Bit | Name | Value=0 | Value=1 |
|-----|------|---------|---------|
| 3 (DIR) | Direction | clock path (0x06BE): PFUNC 4-7 read or write one of the four time bytes, PFUNC 0-3 do nothing | text/display command 0-7 |
| [2:0] (CMD) | Command type | — | 0–7 |

**Dispatch logic (0x04D8–0x04EA):**
```asm
JSR  Strobe_WMM_Read_From_FIFO   ; A = command byte
STA  0x001C                       ; store in RAM[0x1C]
BRSET 3, 0x001C, dispatch_write   ; bit3=1: config/display command
JMP  Output_RTC_Time_Data_To_ND120 ; bit3=0: ND-120 wants time data
dispatch_write:
LDA  0x001C
AND  #7                           ; A = cmd[2:0]
ASLA / ASLA                       ; ×4 (3-byte JMP entries)
TAX
JMP  0x04FC,X                     ; indexed jump into command table
```

### Command Jump Table (0x04FC)

| cmd[2:0] | Full byte | Jump target | Description | Input bytes |
|----------|-----------|-------------|-------------|-------------|
| 0 | `0x08` | 0x051B | SET_DISPLAY_DATA — set 5 time/display registers | 5 |
| 1 | `0x09` | 0x0575 | SET_TIME_DISPLAY — 4 bytes → time display regs 0x15–0x18 | 4 |
| 2 | `0x0A` | 0x0594 | SET_PERF_DISPLAY — enable performance mode, 2 params | 2 |
| 3 | `0x0B` | 0x05C3 | SET_EXT_DISPLAY — 3 bytes → extended display mode | 3 |
| 4 | `0x0C` | 0x05DF | SET_CHAR_DISPLAY — 1 byte index → ROM character lookup | 1 |
| 5 | `0x0D` | 0x0608 | SET_CONFIG — 1 byte → RAM[0x1A] configuration flags | 1 |
| 6 | `0x0E` | 0x0610 | SET_CHAR_INDICES — 4 bytes directly → display char buffer | 4 |
| 7 | `0x0F` | 0x0627 | SET_FORMAT_FLAGS — 2 bytes; 0x4X = soft reset | 2 |

### What each handler does (read from the ROM)

Every data byte is read with 0x09BC (RMM~). "$1B bits" are the display-mode flags.

| Cmd | Bytes go to (in arrival order) | Other work |
|-----|--------------------------------|------------|
| 0 (0x051B) | $14, $16, $15, $18, $17 | Clears $1B bits 1, 3, 4. $10 = 0x50 ('P'). If $1A bit 2 = 0: $11/$12/$13 = 0x45/0x58/0x4D ("PEXM"). If $1A bit 2 = 1: $11 = 0x54 ('T'), n = (($1A & 0x18) >> 1) \| ($1A & 3); $13 = n + 0x30 if n < 8, else $13 = n; $12 = 0 (0x053E-0x0570). |
| 1 (0x0575) | $18, $17, $16, $15 | $14 = 0; sets $1B bit 4, clears bits 1 and 3. |
| 2 (0x0594) | $18, $17 | Sets $1B bit 1 (the LEV0/LHIT bars, section 12), clears bits 3, 4. $1D = 0x10, $1E = 0. $12 = ($19 & 0x0F) + 0x10 (one-hot ring), $13 = (($19 & 0x30) >> 4) + 0x3A ({IONI, PONI}). |
| 3 (0x05C3) | $16, then $18, $17 | Sets $1B bit 3, clears bits 1, 4. $15 = $14 = 0 (cleared after the first byte). |
| 4 (0x05DF) | $52 (select byte) | X = (sel & 3) x 2: $13 = ROM[0x0D12+X], $12 = ROM[0x0D13+X]. X = (sel & 0x18) >> 2: $11 = ROM[0x0D1A+X], $10 = ROM[0x0D1B+X]. |
| 5 (0x0608) | $1A | Nothing else. $1A bit 2 and bits 4:3/1:0 are read by command 0. |
| 6 (0x0610) | $11, $10, $13, $12 | Nothing else (section 7). |
| 7 (0x0627) | $1D, $1E | If ($1E & 0xF0) = 0x40: soft reset - $0A (MR) = 0x40, $09 (TCR) = 0x47, $0B = 0x01, DDRA = DDRB = DDRC = 0, `JMP $0110` (0x0637-0x0649). Otherwise: clears $1B bit 2 and sets it again if ($1E & 0xF0) = 0x10; then {$1E, $1D} is shifted left twice and both are masked to 6 bits, so $1E = (($1E & 0x0F) << 2) \| ($1D >> 6) and $1D = $1D & 0x3F (0x0654-0x0666). |

**After every bit3=1 command (0x04ED):** if $1D bit 0 is set, 0x066B runs (shifts {$52, $17, $18} right by $1E places - $52 is $16 when $1B bit 3 is set, else 0 - then turns the low nibble of $18 into a single set bit in {$17, $18}). Then 0x0694 runs twice, with X = 0 and X = 1: it mixes $17/$18 with $5E/$5F and $6D/$6E under $1D bits 4 and 3 and stores the result in both places. What these two routines show on the panel has not been worked out.

---

## 7. PANC Text Protocol — Writing Text to the Panel

This section directly answers: **how does the ND-120 CPU write text to the front panel?**

### Method 1: Direct Character Write — Command 6 (`0x0E`)

This is the primary "write text" command. The ND-120 sends 5 bytes total:

```
Byte 0:  0x0E        Command byte (bit3=1, cmd=6)
Byte 1:  char1_idx   → stored at RAM[0x11]
Byte 2:  char0_idx   → stored at RAM[0x10]
Byte 3:  char3_idx   → stored at RAM[0x13]
Byte 4:  char2_idx   → stored at RAM[0x12]
```

> **Note:** The byte order is NOT sequential left-to-right. The order received is: pos1, pos0, pos3, pos2. This is confirmed by the disassembly at 0x0610–0x0624.

```asm
; 0x0610: Command 6 handler
JSR  Strobe_WMM_Read_From_FIFO  ; read byte 1
STA  0x0011                      ; → display position 1
JSR  Strobe_WMM_Read_From_FIFO  ; read byte 2
STA  0x0010                      ; → display position 0
JSR  Strobe_WMM_Read_From_FIFO  ; read byte 3
STA  0x0013                      ; → display position 3
JSR  Strobe_WMM_Read_From_FIFO  ; read byte 4
STA  0x0012                      ; → display position 2
JMP  0x04ED                      ; → post-command processing
```

**Display position layout:**
```
Panel: [pos0][pos1][pos2][pos3][pos4]
                                 ^--- pos4 is the performance/status digit (not set by cmd6)
RAM:  [0x10][0x11][0x12][0x13]
```

**Character index encoding:**
The values stored in RAM[0x10–0x13] are character codes, looked up through the character ROM at 0x0D22 (0x01B4: two bytes per code, at 0x0D22 + 2 x code; $13 → $59/$58, $12 → $57/$56, $11 → $55/$54, $10 → $53/$52). Letters and digits use their ASCII codes: command 0 writes 0x50 'P', 0x45 'E', 0x58 'X', 0x4D 'M', 0x54 'T' and a digit as 0x30 + n. Command 2 uses codes 0x10-0x1F and 0x3A-0x3D, and the bar display (0x0985) uses codes from 0x21 upwards. The separate 7-segment digit table used for the octal display starts at ROM 0x0CF8 with digit patterns at offset +0x10.

**Character ROM (ROM 0x0D22):**
- 2-byte entries per character
- Indexed by value in RAM[0x10–0x13]
- Used for symbolic characters like letters ('P', 'E', 'X', 'M', 'T', etc.)

### Method 2: ROM Character Select — Command 4 (`0x0C`)

Selects from 4 predefined character pairs stored in ROM. The ND-120 sends 2 bytes:

```
Byte 0:  0x0C        Command byte (bit3=1, cmd=4)
Byte 1:  sel         Selection byte:
                     bits[1:0] → index into ROM table at 0x0D12 → RAM[0x12],[0x13]
                     bits[4:3] → index into ROM table at 0x0D1A → RAM[0x10],[0x11]
```

### Method 3: Status/Time Command — Command 0 (`0x08`)

Sets predefined messages based on system mode:

```
Byte 0:  0x08        Command byte (bit3=1, cmd=0)
Bytes 1–5:           5 time/date bytes → RAM[0x14–0x18]

Result in display buffer:
  Normal mode (RAM[0x1A] bit2=0):  RAM[0x10..0x13] = 'P','E','X','M'  → shows "PEXM"
  Test mode   (RAM[0x1A] bit2=1):  RAM[0x10..0x13] = 'P','T', 0, ##   → shows "PT##"
```

### Display Update Sequence (after any command)

Once RAM[0x10–0x13] are updated, the main loop triggers the display pipeline on the next iteration:

```mermaid
sequenceDiagram
    participant ND120 as ND-120 CPU
    participant FIFO as FIFO Hardware
    participant MCU as MC68705U3
    participant DISP as Display Panel

    ND120->>FIFO: Write 0x0E (cmd6)
    ND120->>FIFO: Write char1_idx
    ND120->>FIFO: Write char0_idx
    ND120->>FIFO: Write char3_idx
    ND120->>FIFO: Write char2_idx
    FIFO-->>MCU: Assert /EMP (PD7=1)
    MCU->>FIFO: RMM~ strobe (PB3) × 5 reads
    MCU->>MCU: Store in RAM[0x10–0x13]
    MCU->>MCU: Look up 7-seg patterns (ROM 0x0CF8/0x0D22)
    MCU->>MCU: Build 32-byte bitmap (RAM 0x27–0x46)
    MCU->>DISP: Serialize bitmap to PC3–PC7\n(5 bits per clock cycle via shift registers)
```

---

## 8. PANC Response Protocol — Sending Data to ND-120

When the command byte has **bit3=0**, the clock path at **0x06BE** runs. This is the ND-100 hardware-clock protocol (ND-06.014 ch. 4.3, `ND-HWCLCK`): the time is four bytes, addressed by PFUNC 4..7, and every access carries a read/write bit.

```
0x06BE:  X = cmd ; PORTC[2:0] = cmd & 7          ; STAT2:0 = PFUNC (PANS bits 10:8)
         if (cmd & 4) == 0: RTS                  ; PFUNC 0-3: nothing (the WPAN byte
                                                 ;   stays in the FIFO and is read as
                                                 ;   the NEXT command byte)
         BCLR 5,PORTB                            ; STAT4 = 0 (busy)
         idx = (cmd & 3) ^ 3                     ; RAM $47+idx
         if (cmd & 0x20) == 0:                   ; --- CPU WRITES the clock
             BCLR 6,PORTB                        ; READ = 0
             A = FIFO byte (WPAN) ; $47[idx] = A ; answer(A) via 0x09C5 (WMM~)
             BSET 5,PORTB                        ; STAT4 = 1 (answered)
             if idx == 0: 0x0715 ($47..$4A -> calendar $20..$25) ; 0x09EE (write MM58274)
         else:                                   ; --- CPU READS the clock
             BSET 6,PORTB                        ; READ = 1
             FIFO byte read and discarded (WPAN)
             if idx == 3: 0x0AC0 (read MM58274 -> $20..$26) ; 0x0803 (calendar -> $47..$4A)
             answer($47[idx]) via 0x09C5 ; BSET 5,PORTB
```

| PFUNC | idx | RAM | Byte |
|-------|-----|-----|------|
| 4 | 3 | $4A | seconds within the half-day (0..43199), low byte |
| 5 | 2 | $49 | seconds, high byte |
| 6 | 1 | $48 | half-days since 1979-01-01 00:00, low byte |
| 7 | 0 | $47 | half-days, high byte |

The format is proven by the constants at ROM $80..$83: `02DA` = 730 half-days per year (732 in a leap year, 0x0751-0x0753), `0E10` = 3600 s/hour, `07BB` = 1979 (0x0763 `ADD #$4F` = 79 -> two-digit year), and by 0x07A2 `LSRA` / `BCC`: an odd half-day count sets hour = 12. A write only becomes the clock when PFUNC 7 arrives (the CPU writes 4,5,6,7 in that order); a read takes a fresh snapshot of the calendar on PFUNC 4 and returns bytes of that snapshot for 5,6,7.

### IDB Write Strobe

There is exactly ONE path from the panel to the CPU: PA[7:0] → 74LS374 (32B) → IDB[7:0], clocked by **PB0 = WMM~** in 0x09C5 `Output_Response_To_ND120_IDB`. The CPU reads it with `TRA PANS` (EPANS) together with {PRES, FUL~, READ, VAL, STAT3..0} from the 74LS244 (33B).

**PB1 is NOT an IDB strobe.** 0x09EE pulses PB1 = WRCLK~, the MM58274's /WR, with PA[7:4] = register address and PA[3:0] = one BCD digit (written as register←value): 0←F (PA=0x0F), F←0 (PA=0xF0), 0←5 (PA=0x05), F←1|leap, D←year tens, C←year units, B←month tens, A←month units, 9←day tens, 8←day units, 7←hour tens, 6←hour units, 5←min tens, 4←min units, 3←sec tens, 2←sec units, 0←1 (start). That is the MM58274 register map exactly. DDRA is FF for the whole sequence and cleared at the end (0x0ABD).

---

### PB0 → /WMM → 74LS374 CK → IDB[7:0] — Detailed Path

#### Hardware chain

```
MC68705 PB0
    │  (active-low pulse: HIGH→LOW→HIGH)
    ▼
/WMM signal on 3202D CBP board
    │
    ▼
74LS374 (32B) — octal D-type flip-flop, positive-edge triggered CK
    │  D[7:0] ← PA[7:0] from MC68705 Port A
    │  CK ← /WMM (latches on RISING EDGE when /WMM goes HIGH)
    │  /OE — output always enabled toward IDB
    ▼
IDB[7:0] — Internal Data Bus to ND-120 CPU
```

#### Exact code sequence at 0x09C5 (`Output_Response_To_ND120_IDB`)

```asm
09c5: SEI              ; disable interrupts — protect the atomic IDB transaction
09c6: STA 0x0000       ; PA output latch = data byte (DDRA still 0x00, pins still tristate)
09c8: LDA #0xFF
09ca: STA 0x0004       ; DDRA = 0xFF → enable PA output drivers → data now on PA pins
09cc: BCLR 0x0, 0x0001 ; PB0 LOW  → /WMM falls (hold time: data stable on PA)
09ce: BSET 0x0, 0x0001 ; PB0 HIGH → /WMM rises → 74LS374 CK RISING EDGE → LATCH PA→IDB
09d0: CLR 0x0004       ; DDRA = 0x00 → tristate PA (release IDB bus)
09d2: CLI              ; re-enable interrupts
09d3: RTS
```

> **Write order matters:** Data is written to the PA output latch BEFORE DDRA is set to output. This prevents a glitch where partially-settled data could appear on the bus. The sequence is: latch data (tristate) → enable drivers → strobe → release.

#### When does PB0 fire?

PB0 fires **only** for a clock command (**bit3=0 AND bit2=1**, i.e. PFUNC 4-7), once per command. It does **not** fire during any display/text command (bit3=1) and not for PFUNC 0-3.

```
Command byte decode (0x06BE):
  bit3 = 0  → clock path
  bit2 = 1  → PFUNC 4-7 (if bit2=0: early RTS, no answer)
  bit5 = 0  → CPU WRITES a time byte: it is stored and echoed back (PB0 once);
              on PFUNC 7 the calendar is recomputed and written to the MM58274 (PB1 = WRCLK~)
  bit5 = 1  → CPU READS a time byte: on PFUNC 4 the MM58274 is read first (PB2 = ROCLK~);
              the byte is answered (PB0 once)
```

```mermaid
sequenceDiagram
    participant ND120 as ND-120 CPU
    participant FIFO as FIFO Hardware
    participant MCU as MC68705U3
    participant PA as Port A (PA[7:0])
    participant PB0 as PB0 (/WMM)
    participant LS374 as 74LS374 (32B)
    participant IDB as IDB[7:0]

    ND120->>FIFO: Write command (bit3=0, bit2=1)
    FIFO-->>MCU: /EMP asserted → PD7=1
    MCU->>FIFO: PB3 (RMM~) strobe → read command byte into A
    MCU->>FIFO: PB3 (RMM~) strobe → read the WPAN byte into A
    Note over MCU: Build response byte in A
    MCU->>MCU: SEI (disable interrupts)
    MCU->>PA: STA 0x0000 → data into PA latch (pins tristate, DDRA=0)
    MCU->>PA: DDRA=0xFF → PA pins drive bus
    MCU->>PB0: BCLR → PB0 LOW (/WMM falls)
    MCU->>PB0: BSET → PB0 HIGH (/WMM rises ↑)
    PB0->>LS374: Rising edge on CK
    LS374->>IDB: Q[7:0] latched from D[7:0]=PA[7:0]
    MCU->>PA: DDRA=0 → PA tristate (IDB released)
    MCU->>MCU: CLI (re-enable interrupts)
    alt write of PFUNC 7 (idx 0)
        Note over MCU: 0x0715 converts $47..$4A to a calendar, 0x09EE writes it to the MM58274 (PB1 = WRCLK~, not the IDB)
    end
```

---

### 0x09EE — MM58274 write (was wrongly called "Full Time Packet to the ND-120")

0x09EE uses **PB1 = WRCLK~**, the MM58274's /WR. Nothing in it reaches the IDB. The old notes called it an "18-byte time packet to the ND-120"; the ROM has 17 writes, all to the MM58274: write 0 = register 0 ← F, write 1 = register F ← 0, write 2 = register 0 ← 5, write 3 = register F (leap-year field), then year..seconds digits into registers D..2, and the last write (0x0AB5, `01`) = register 0 ← 1 (start). What each control value means is in the MM58274 datasheet and has not been checked here.

```asm
; Pattern repeated for each of the 17 writes (0x09F2-0x0ABB):
STA  0x0000          ; PA = register address (high nibble) + digit (low nibble); DDRA = 0xFF, set once at entry
BCLR 0x1, 0x0001     ; PB1 LOW  → WRCLK~ falls
BSET 0x1, 0x0001     ; PB1 HIGH → WRCLK~ rises → the MM58274 takes the digit (nothing reaches the IDB)
```

**The 17 MM58274 writes** (in this order; the high nibble of PA is the MM58274 register address):

| Write | PA value | MM58274 register ← value |
|-------|----------|--------------------------|
| 0 | `0x0F` | 0 (control) ← F |
| 1 | `0xF0` | F ← 0 |
| 2 | `0x05` | 0 (control) ← 5 |
| 3 | `0xF1 \| (leap_cycle & 3) << 2` | F ← 1 with the leap-year count ($26) in bits 3:2 |
| 4 | `ROM[0x0E44 + year×2] \| 0xD0` | D (year tens) |
| 5 | `ROM[0x0E44 + year×2 + 1] \| 0xC0` | C (year units) |
| 6 | `ROM[0x0E44 + month×2] \| 0xB0` | B (month tens) |
| 7 | `ROM[0x0E44 + month×2 + 1] \| 0xA0` | A (month units) |
| 8 | `ROM[0x0E44 + day×2] \| 0x90` | 9 (day tens) |
| 9 | `ROM[0x0E44 + day×2 + 1] \| 0x80` | 8 (day units) |
| 10 | `ROM[0x0E44 + hour×2] \| 0x70` | 7 (hour tens) |
| 11 | `ROM[0x0E44 + hour×2 + 1] \| 0x60` | 6 (hour units) |
| 12 | `ROM[0x0E44 + min×2] \| 0x50` | 5 (minute tens) |
| 13 | `ROM[0x0E44 + min×2 + 1] \| 0x40` | 4 (minute units) |
| 14 | `ROM[0x0E44 + sec×2] \| 0x30` | 3 (second tens) |
| 15 | `ROM[0x0E44 + sec] \| 0x20` | 2 (second units) - **the ROM does not double the index here** (0x0AA8 `LDX $25` with no `LSLX`), so this digit is not the units of the seconds. As read from the bytes; not seen on a running board. |
| 16 | `0x01` | 0 (control) ← 1 |

ROM 0x0E44 is a binary-to-BCD table: two bytes (tens, units) for each value 0-99 (section 15). DDRA is cleared at the end (0x0ABD).

The digits come from the calendar in RAM $20-$25 that 0x0715 just computed from the four bytes the CPU wrote. On a READ the MM58274 is read again (0x0705 → 0x0AC0), so the battery-backed chip - not the software counters - is the source of the time the CPU gets.

---

## 9. Display Update — From Characters to Shift Register

### Overview

The display has 5 digits (DISP1–DISP5). Each digit is a 7-segment display. The MC68705 drives all 5 simultaneously through a **serial shift register chain** on PC3–PC7.

### Step 1: Character ROM Lookup

Characters in RAM[0x10–0x13] are used as indices. For octal-mode (standard numerics from RAM[0x16–0x18]), each 3-bit octal digit is extracted and looked up in the 7-segment pattern ROM:

```asm
; Extract 3-bit octal digit from packed data in RAM[0x18]
AND  #0x7        ; A = 3-bit nibble (0–7)
ADD  #0x10       ; A += 0x10 (offset into 7-seg table)
TAX
LDA  0xCF8,X    ; load 7-seg pattern from ROM
STA  0x0059      ; store in display work buffer
```

**7-segment pattern ROM (0x0CF8):**
- 32 entries total (0x00–0x1F)
- Digits 0–7 at offsets 0x10–0x17
- Letters and symbols at other offsets
- Custom encoding (not standard 7-seg BCD)

### Step 2: 3-Pass Bit Merge into Bitmap

The patterns are merged into the 32-byte display bitmap (RAM 0x27–0x46) in three passes, each using a different mask/shift:

| Pass | Mask | Shift | Port C bits affected |
|------|------|-------|---------------------|
| 1 | 0x40 | 4 | DISP4, DISP5 |
| 2 | 0x20 | 2 | DISP2, DISP3 |
| 3 | 0x10 | 1 | DISP1 |

`Process_7Segment_Display_Bit_Manipulation` extracts each bit from the 7-seg patterns and places it into the correct position within the 32-byte bitmap corresponding to the serial shift timing.

### Step 3: Serialize to Port C

`Update_RTC_Interface` (called mid-main-loop) serializes the 32-byte bitmap by clocking bits through PC3–PC7:

```
For each bit position (0–31):
  PC[7:3] = bitmap_byte[bit_pos][4:0]  (5 display bits simultaneously)
  PC[2:0] = unchanged (held 0)
  → rising edge of clock shifts all 5 bits into display shift registers
```

This means for each clock cycle, one bit column of all 5 displays is shifted in simultaneously. After 32 clocks, all 5 × 7-segment digits are fully loaded.

```mermaid
sequenceDiagram
    participant CPU68705 as MC68705
    participant PC as Port C (PC3..PC7)
    participant SR as Shift Register Chain
    participant D1 as DISP1
    participant D5 as DISP5

    loop 32 clock cycles
        CPU68705->>PC: Write bitmap byte (5 bits for DISP1–5)
        PC->>SR: Clock edge → shift all 5 bits in
    end
    SR->>D1: Latch DISP1 segments
    SR->>D5: Latch DISP5 segments
```

---

## 10. MM58274 RTC Interface

The MM58274 is the battery-backed calendar chip. It is read at boot (0x013C) AND at every time READ from the CPU (0x0705, PFUNC 4), and it is WRITTEN (0x09EE, PB1 = WRCLK~) whenever the CPU has written all four time bytes (PFUNC 7). The software RTC counters are only for the display.

### Hardware Connection

| MC68705 Pin | Signal | MM58274 Pin | Description |
|-------------|--------|-------------|-------------|
| PA[7:4] | Address out | A[3:0] | Register address (upper nibble of Port A) |
| PA[3:0] | Data in | D[3:0] | Data nibble read-back (lower nibble of Port A) |
| PB2 | /ROCLK | /RD | Read clock (active low pulse) — **confirmed from code** |
| PB1 | /WRCLK | /WR | Write clock (active low pulse) — **confirmed from hardware schematic** |

> **PB1/PB2 (corrected 28-AUG-2026):** 0x0AC0 reads with PB2 = ROCLK~; 0x09EE writes with PB1 = WRCLK~ (`STA PORTA ; BCLR 1,PORTB ; BSET 1,PORTB` per register, DDRA = FF). Both confirmed in the ROM and on sheet 40.

### MM58274 Read Protocol (from boot code 0x0AC0)

```
DDRA = 0xF0          ; PA[7:4] = output, PA[3:0] = input

; For each RTC register read:
PA = (reg_addr << 4) ; set address in upper nibble, lower nibble don't-care
BCLR PB2             ; /ROCLK LOW — assert read strobe
A = PORTA            ; read data nibble from PA[3:0]
BSET PB2             ; /ROCLK HIGH — deassert read strobe
A &= 0x0F            ; mask to 4-bit data nibble
```

### MM58274 register map (MM58274 datasheet)

| Addr | Register | Used by the ROM |
|------|----------|-----------------|
| 0 | Control register | read strobe only (0x0AC4, 0x0BC6); written 0←F, 0←5, 0←1 by 0x09EE |
| 1 | Tenths of seconds | never accessed |
| 2 / 3 | Units / tens of seconds | $25 |
| 4 / 5 | Units / tens of minutes | $24 |
| 6 / 7 | Units / tens of hours | $23 |
| 8 / 9 | Units / tens of days | $22 |
| A / B | Units / tens of months | $21 |
| C / D | Units / tens of years | $20 |
| E | Day of week | never accessed |
| F | Clock setting / interrupt register | $26 (leap-year count in bits 3:2) |

The ROM's own use agrees with this map: every tens register is the one it multiplies by 10 (below), and 0x09EE writes the same addresses.

### Register Read Sequence (0x0AC0 - at boot and on every PFUNC 4 read)

| PA value | Reg addr (PA[7:4]) | Contents seeded to |
|----------|--------------------|--------------------|
| 0x00 | 0x0 = control | ROCLK~ pulse only, Port A is not read (0x0AC4-0x0ACA) |
| 0xF0 | 0xF = clock setting | RAM[0x26] = (nibble & 0x0F) >> 2 = leap-year cycle (0=leap year, 1/2/3=non-leap) |
| 0xC0 | 0xC = Year units BCD | RAM[0x20] = units |
| 0xD0 | 0xD = Year tens BCD | RAM[0x20] += tens × 10 → binary year (0–99) |
| 0xA0 | 0xA = Month units BCD | RAM[0x21] = units |
| 0xB0 | 0xB = Month tens BCD | RAM[0x21] += tens × 10 |
| 0x80 | 0x8 = Day units BCD | RAM[0x22] = units |
| 0x90 | 0x9 = Day tens BCD | RAM[0x22] += tens × 10 |
| 0x60 / 0x70 | Hour units / tens | RAM[0x23] |
| 0x40 / 0x50 | Minute units / tens | RAM[0x24] |
| 0x20 / 0x30 | Second units / tens | RAM[0x25] |
| 0x00 | 0x0 = control | a last ROCLK~ pulse (0x0BC6) |

**BCD to binary conversion** is done inline: `tens × 10 + units` using multiply-by-8 (ASLX×3) + multiply-by-2 + add (e.g. 0x0AF6-0x0B01).

---

## 11. Software RTC (Timer-Driven)

Between MM58274 accesses (boot, every PFUNC 4 read, every PFUNC 7 write - section 10) the calendar in $20-$26 is kept by software: `Increment_Software_RTC_Counters` (0x08F9), called from the timer ISR once every 400 ticks = 1 s (section 4). These counters feed the panel display; the time the CPU reads is re-read from the MM58274.

### Software RTC Counters (RAM)

| Address | Counter | Range | Rollover (0x08F9-0x0947) |
|---------|---------|-------|---------|
| 0x25 | Seconds | 0–59 | at 60 → 0, increment minutes |
| 0x24 | Minutes | 0–59 | at 60 → 0, increment hours |
| 0x23 | Hours | 0–23 | at 24 → 0, increment days |
| 0x22 | Day of month | 1–31 | above the days-in-month value → 1, increment month |
| 0x21 | Month | 1–11 as coded | the test is `CMP` with 12 then `BHI` (0x092F-0x0935), so the month goes back to 1 and the year increments as soon as it REACHES 12 - December is skipped. Read from the bytes, not seen on a running board. |
| 0x20 | Year | 0–99 | incremented with no limit check (0x093B) |
| 0x26 | Leap-year cycle | 0–3 | incremented with the year, 4 → 0 (0x093D-0x0945); 0=leap, 1/2/3=non-leap |

### Leap Year Handling

ROM table at 0x0E37 holds days per month as bytes, indexed by the month (1–12): 31 28 31 30 31 30 31 31 30 31 30 31. There is no separate leap-year table: 0x0917-0x0924 adds 1 when the table value is 28 and $26 = 0.

---

## 12. CPU Performance Monitoring (Port D)

Every timer ISR tick (400 Hz - PANOSC = RTOSC/4 = 38.4 kHz, /32, TDR=3; see section 3):

1. `Sample_ND120_CPU_Status_Signals` (0x09D4): `A = PORTD ; $70 = A ; $19 = (A & 0x0C) << 2` = {PONI, IONI} in bits 5:4. Then, **only if PONI (bit 2) is set**: `X = A & 3` (the protect ring from PCR1:0), `$19 |= ROM[0x0F0C + X]` with the table `01 02 04 08` - one-hot ring bit in bits 3:0. Without paging the ring bits are meaningless, so they are skipped.
2. `Update_CPU_Ring_PONI_IONI_Statistics` (0x06B2): `$60 = ($60 & ~$6F) | $19 ; $19 = $60` - ORs the sample into the accumulator, dropping what fell out of the history window.
3. If display flag $1B bit 1 (performance mode, set by command 2): `Monitor_LEV0_LHIT` (0x0985), below.

**Ring level utilization accumulation:**

Every 16 ticks (40 ms): `Shift_CPU_Utilization_History_Buffer` (0x0948) moves the 15 bytes $5E-$6C up by three places to $61-$6F (`$6F = $6C ... $61 = $5E`), so the history is kept in groups of three bytes and the oldest group ($6D-$6F) is overwritten. $60 is the newest accumulator (step 2 above); $6F is the byte step 2 drops from it.

Nothing in the ISR sends statistics to the ND-120: the only path to the CPU is the single WMM~ answer byte of a clock command (section 8). The "every 200×2 ticks: utilization sent to the ND-120" statement of the 2026-04-06 text was wrong - 400 ticks is the software seconds tick.

**Cache hit rate and CPU utilisation - `Monitor_LEV0_LHIT` (0x0985), added 28-AUG-2026:**

```
0x0985:  DEC $71 ; BNE sample              ; $71 = window counter, reloaded with 128
         $71 = 128
         A = $72 (LHIT count)               ; if 0 -> bar = 0
         if A != 0: A = A >> 1 ; $72 = A    ; (halved, kept as a decaying carry-over)
                    A = A >> 4 ; A = A + 1  ; count/32 + 1  -> 1..5
         $11 = A + 0x21                     ; display position 1: bar character index
         A = $73 (busy count)               ; same maths
         $10 = A + 0x21                     ; display position 0: bar character index
sample:  BRCLR 4,PORTD,+2 ; INC $72         ; LHIT = 1  -> one more cache hit
         BRSET 5,PORTD,+2 ; INC $73         ; LEV0 = 0  -> one more busy sample (not idle)
         RTS
```

So the panel's "cache" bar is the number of ticks out of the last 128 (320 ms at 400 Hz) in which LHIT was high, in steps of 32 (the halved count of the previous window is carried over, so the value can go above 5); the "load" bar is the number of ticks in which the CPU was NOT on level 0. No PIL value ever reaches the panel: the only level information on Port D is LEV0.

**Port D signals (sheet 40):**

| PD bit | Signal | Meaning when 1 |
|--------|--------|----------------|
| PD[1:0] | PCR1:0 | Current protect ring (0..3), used only while PONI=1 |
| PD2 | PONI | Paging (memory protection) on |
| PD3 | IONI | Interrupt system on |
| PD4 | LHIT | Cache hit |
| PD5 | LEV0 | CPU on level 0 (idle) |
| PD6 | GND | - |
| PD7 | EMP~ | FIFO has a command byte |

---

## 13. PRES / MIPANS / IDB:15 Hardware Path

This is frequently misunderstood. The complete path:

```
MC68705 PB7 = 0 (always, driven low by firmware)
    ↓
74F04 inverter chip 13G
    ↓
PRES = 1 (always, because PB7=0 inverted)
    ↓
74LS244 buffer (enabled when ND-120 asserts IDBS.MIPANS)
    ↓
IDB:15 = 1 (always)
```

**MIPANS is NOT triggered by the panel MCU.** It is asserted by the ND-120 CPU's own microcode, specifically in the MS20 timer routine, every ~20ms. When MIPANS fires:
- The 74LS244 gates PRES onto IDB:15
- Since PRES=1 always, IDB:15=1 always
- The MS20 microcode reads IDB:15=1 → continues to MOPC code

**Implication:** The MC68705 never drives IDB:15 to 0. Any interpretation that the panel MCU controls the MS20 continuation decision is incorrect.

---

## 14. RAM Layout

| Address | Size | Name | Used by |
|---------|------|------|---------|
| 0x10 | 1 | display_char[0] | cmd 0/4/6, main display loop |
| 0x11 | 1 | display_char[1] | cmd 0/4/6 |
| 0x12 | 1 | display_char[2] | cmd 2/4/6 |
| 0x13 | 1 | display_char[3] | cmd 0/4/6 |
| 0x14 | 1 | time_byte1 (seconds seed) | cmd 0 |
| 0x15 | 1 | time_byte3 (minutes seed) | cmd 0/1 |
| 0x16 | 1 | time_byte2 (hours seed) | cmd 0/1/3 |
| 0x17 | 1 | time_byte5 (day seed) | cmd 0/1/2/3 |
| 0x18 | 1 | time_byte4 (month seed) | cmd 0/1/2/3 |
| 0x19 | 1 | cpu_status_raw | PORTD sample, timer ISR |
| 0x1A | 1 | system_config | cmd 5, controls display mode |
| 0x1B | 1 | control_flags | modified by all cmds; bit1=LHIT mode; bit2=feature; bit3=ext; bit4=time-only |
| 0x1C | 1 | last_command_byte | FIFO dispatcher |
| 0x1D | 1 | util_param1 | cmd 2/7, utilization params |
| 0x1E | 1 | util_param2 | cmd 2/7 |
| 0x1F | 1 | emp_timeout | main loop timeout counter |
| 0x20 | 1 | year (binary 0–99) | software RTC, init from MM58274 |
| 0x21 | 1 | month (binary 1–12) | software RTC |
| 0x22 | 1 | day (binary 1–31) | software RTC |
| 0x23 | 1 | hour (binary 0–23) | software RTC |
| 0x24 | 1 | minutes (binary 0–59) | software RTC |
| 0x25 | 1 | seconds (binary 0–59) | software RTC |
| 0x26 | 1 | leap_cycle (0–3) | software RTC leap year |
| 0x27–0x46 | 32 | display_bitmap | 7-seg serial shift buffer |
| 0x47–0x4A | 4 | data_store | the four ND-100 clock bytes (section 8) |
| 0x4B | 1 | merge_mask | 0x40 / 0x20 / 0x10 for the three 0x0479 passes (0x016E, 0x017C, 0x018A) |
| 0x4C | 1 | merge_shift | 4 / 2 / 1 for the three 0x0479 passes |
| 0x52–0x59 | 8 | seg_patterns | 7-seg pattern work area ($52 is also scratch: cmd 4 select byte, BCD maths in 0x0AC0) |
| 0x5B | 1 | shift_prescaler | timer: counts 16 ticks |
| 0x5C | 1 | window_prescaler | timer: counts 200 ticks (every tick, not after 0x5B) |
| 0x5D | 1 | rtc_divider | timer: counts 2 → 1-sec tick |
| 0x5E–0x5F | 2 | util_new | newest history bytes; written by 0x0694 (post-command) |
| 0x60 | 1 | led_accumulator | CPU status LED latch (0x06B2) |
| 0x61–0x6F | 15 | util_history | CPU utilization history, moved up 3 bytes every 16 ticks (0x0948) |
| 0x70 | 1 | portd_raw | raw PORTD copy from the last tick (0x09D6) |
| 0x71 | 1 | lhit_window | LEV0/LHIT window counter, 128 ticks (0x0124, 0x0985) |
| 0x72 | 1 | lhit_count | LHIT=1 ticks in the window (0x09B2) |
| 0x73 | 1 | busy_count | LEV0=0 ticks in the window (0x09B7) |

---

## 15. ROM Data Tables

| Address | Size | Name | Description |
|---------|------|------|-------------|
| 0x0080 | 6 | time_constants | `02DA` = 730 half-days per year, `0E10` = 3600 s per hour, `07BB` = 1979 (the ND-100 clock epoch year) - see section 8. Not a Unix epoch. |
| 0x0CF8 | 32 | seg_patterns | 7-segment patterns (custom encoding); digits 0–7 at +0x10 |
| 0x0D12 | 8 | cmd4_table_1 | command 4, select bits 1:0: 4 pairs → $13, $12 |
| 0x0D1A | 8 | cmd4_table_2 | command 4, select bits 4:3: 4 pairs → $11, $10 |
| 0x0D22 | varies | char_rom | Character ROM: 2-byte entries for display characters indexed by 0x10–0x13 |
| 0x0DDE | 26 | days_before_month | Cumulative days before each month ×2; non-leap at base, +0x0D offset for leap |
| 0x0E1F | 24 | sec_per_hour | Cumulative seconds per hour (16-bit): hour×3600 |
| 0x0E37 | 13 | days_in_month | Days per month (bytes, index 1–12; 0x0E37 itself = 0): 31 28 31 30 31 30 31 31 30 31 30 31 |
| 0x0E44 | 200 | bin_to_bcd | Binary to two BCD digits: for n = 0..99, ROM[0x0E44 + 2n] = tens, ROM[0x0E45 + 2n] = units (bytes 0x0E44-0x0F0B read `00 00 00 01 ... 09 09`). Used by 0x09EE. |
| 0x0F0C | 4 | cpu_bitmask | CPU status bit-mask table: 0x01, 0x02, 0x04, 0x08 |

---

## 16. Interrupt Vectors

(ROM 0x0FF0–0x0FFF, read from hexdump)

| Address | Vector | Handler | Notes |
|---------|--------|---------|-------|
| 0x0FF8 | Timer Overflow | 0x08C8 | 400 Hz main timing ISR |
| 0x0FFA | External INT | (unused) | Vector bytes are `00 00`; no handler |
| 0x0FFC | SWI (software) | 0x09BA | NOP + RTI (dummy) |
| 0x0FFE | Reset | 0x0110 | Boot / re-init entry point |

---

## 17. Corrections to Existing Analysis Documents

> **28-SEP-2026:** the older documents named in this section (`Analysis-U3.md`, `Commands-U3.md`, `C-code-u3.md` and, under `AI/`, `firmware_analysis_report.md`, `mm58274_rtc_analysis.md`, `nd100_integration_analysis.md`, `panc_command_specification.md`) have been removed from the repository. Every fact in them that the ROM confirms is merged into sections 1-16. The error lists below are kept as the record of what they got wrong.

### Corrections 28-AUG-2026 (to THIS document's 2026-04-06 text, from a fresh disassembly of the ROM)

| Old claim | ROM says | Where |
|-----------|----------|-------|
| PB4 is the "WMM FIFO strobe", PB3 a "state flag" | PB3 = RMM~ is the FIFO read strobe; PB4 = STAT3 is pulsed in the idle loop (panel request) | 0x09BC, 0x0153 |
| PB1 strobes an "18-byte time packet" to the ND-120 | PB1 = WRCLK~ writes the calendar into the MM58274; nothing but the single WMM~ byte reaches the CPU | 0x09EE |
| PB5 "sync control", PB6 "RTC mode" | PB5 = STAT4 (answered / VAL source), PB6 = READ (PANS bit 13) | 0x06D3, 0x06E1, 0x06FA, 0x0195 |
| PC[2:0] "reserved/low" | PC2:0 = STAT2:0 = PFUNC echo, PANS bits 10:8 | 0x06C5 |
| PD4/PD5 "reserved", PD6 = LHIT | PD4 = LHIT, PD5 = LEV0, PD6 = GND | 0x09AF, 0x09B4, sheet 40 |
| MM58274 "only read at boot", never written | read at boot and at every PFUNC 4 read; written after every PFUNC 7 write | 0x0705, 0x06F3 |
| Timer ISR "~247 Hz" | 6400 Hz (16 x 200 x 2 ticks per second in 0x08C8/0x08F9) | 0x08DA-0x08F5 |
| "IDB[11:8] for STAT bits - not confirmed" | confirmed: 74LS244 33B puts STAT3:0 on IDB11:8, VAL/READ/FUL~/PRES on IDB12:15 | sheet 40 |
| bit 3 = "ND-120 requests data FROM panel" | bit3=0 is the clock path: PFUNC 4-7 with bit 5 = read/write; PFUNC 0-3 do nothing | 0x06BE |

### Corrections 28-SEP-2026 (to the 28-AUG text above and to the rest of this document)

| Old claim | ROM says | Where |
|-----------|----------|-------|
| Timer ISR "6400 Hz" (the 28-AUG row above) | 400 Hz. 0x5B is not in series with 0x5C: 0x5C is decremented on every tick, so the seconds tick is 200 x 2 = 400 ticks. PANOSC = 39.3216 MHz / 256 / 4 = 38.4 kHz, /32, TDR=3 → 400 Hz (section 3) | 0x08DC, 0x08E5-0x08F5 |
| Boot sets "0x1B = 0x80" | boot sets $71 = 0x80 (LHIT/LEV0 window) | 0x0124 |
| 0x0AC0: C = year tens, D = year units (A/B, 8/9 likewise) | C, A, 8, 6, 4, 2 are the units; D, B, 9, 7, 5, 3 the tens (multiplied by 10) | 0x0ADC-0x0B01 |
| 0x09EE first write "F←0 (stop)" | PA = 0x0F = register 0 ← F; 17 writes, not 18 | 0x09F2 |
| ROM 0x0E44 = "day-of-week index table" | binary → two-digit BCD table, 200 bytes | 0x0E44-0x0F0B |
| ROM 0x0080 = "Unix epoch base" | 730 half-days/year, 3600 s/hour, 1979 | 0x0080-0x0085 |
| Leap year: "separate table entries" | +1 day when the table says 28 and $26 = 0 | 0x0917-0x0924 |
| History "16-byte ring at $64-$6F, shifted by one"; stats "sent to the ND-120 every 400 ticks" | $5E-$6C moved up three bytes to $61-$6F; nothing is sent to the CPU from the ISR | 0x0948 |
| Character codes "are not raw ASCII" | letters and digits in $10-$13 are ASCII codes ('P' = 0x50) | 0x053A, 0x055D |

The four-byte time format (half-days since 1979 + seconds in the half-day) and the PFUNC/idx table are in section 8.

The following documents in `Code/68705/U3/AI/` contain errors:

### `mm58274_rtc_analysis.md` — CRITICAL ERRORS

| Claim in document | Reality | Evidence |
|-------------------|---------|----------|
| "PC[3:0] is used for RTC address/data" | **WRONG.** Port A (PA[7:0]) is the RTC bus | Boot init code 0x0AC0: `STA 0x0000` (Port A), DDRA=0xF0 |
| "PORTC = ..." in C pseudocode for RTC | **WRONG.** No Port C access in RTC init | Only PB2 and PA are used in 0x0AC0–0x0B?? |
| MM58274 RAM mapping (0x20=tenths seconds) | **WRONG.** 0x20=year in actual firmware | Code at 0x0AE6–0x0B01: `STA 0x0020` after reading year register |
| "Firmware does continuous RTC reads for display" | **WRONG.** No polling for the display: 0x0AC0 reads the MM58274 at boot and on every PFUNC 4 read from the CPU; 0x09EE writes it after every PFUNC 7 write | 0x013C, 0x0705, 0x06F6; the display uses the software RTC counters |

**Port C is the display shift register output, NOT the RTC bus.**

### `nd100_integration_analysis.md` — ERRORS

| Claim | Reality |
|-------|---------|
| "1200Hz sampling rate" | 1200 Hz is the prescaler output (38.4 kHz PANOSC / 32); the ISR, and so the sampling, runs at **400 Hz** (TDR=3) - section 3 |
| Port C = "RTC Data Interface" | Port C = **display shift register** (DISP1–5 on PC3–PC7) |
| Port B PB1 = "Reserved", PB2 = "RTC Reset/Enable" | PB1=/WRCLK (write clock), PB2=/ROCLK (read clock) for MM58274 |
| "IDB[11:8] for STAT bits" | Right about the bits, wrong about their meaning: the 74LS244 (33B) puts STAT3:0 on IDB11:8 (sheet 40), but they are PFUNC echo (STAT2:0) and the panel request (STAT3), not the "CPU busy / RTC valid / cache" flags the document invents |

### `panc_command_specification.md` — MOSTLY CORRECT

This document has the most accurate command-level detail. Minor issues:
- The "Response Byte Format" table with STA/ERR/RDY/VAL/TYP fields is **speculative** — no evidence in disassembly of this field encoding. The actual response byte is raw data (time, status, etc.).
- MM58274 RAM mapping at 0x20–0x26 showing "tenths seconds" etc. is wrong — matches the `mm58274_rtc_analysis.md` error above.

### `firmware_analysis_report.md` — TOO GENERIC

This document is a guidance framework, not factual analysis. Port C described as "timing/clock hardware" is incorrect. Use this document only as a methodology reference, not as a source of facts about this specific firmware.

### `Analysis-U3.md`, `Commands-U3.md`, `C-code-u3.md` (in `Code/68705/U3/`) — ERRORS

These three carried their own "read this first" warnings; the errors are kept here:

| Claim | Reality |
|-------|---------|
| Port B: PB3 "WMM strobe", PB4 "command ready", PB5 "sync", PB6 "RTC mode"; Port C = MM58274 bus | PB3 = RMM~, PB4 = STAT3, PB5 = STAT4, PB6 = READ; Port A is the MM58274 bus, Port C the display chain (section 2) |
| Timer ISR at 1200 Hz, with 75 / 6 / 3 Hz sub-rates and a 333 ms RTC tick | ISR 400 Hz; 40 ms history shift, 1 s RTC tick (sections 3, 4) |
| 0x0AC0 "resets the RTC by clearing /ROCLK and clears $20-$26" | 0x0AC0 reads all time registers of the MM58274 into $20-$26 (section 10) |
| $20-$26 hold MM58274 tenths/seconds/... | $20 = year ... $25 = seconds, $26 = leap-year count (section 11) |
| Command byte bit 3 = 0 "writes RTC data to the ND-120"; bit 5 "0 = read RTC, 1 = write RTC"; bits 7, 6, 4 "RTC / MOD / RSV" flags | bit 3 = 0 is the ND-100 clock path, bit 5 = 1 means the CPU READS a time byte; bits 7, 6, 4 are not tested by the ROM (section 8) |
| A "status code 1" / date bytes are sent to the ND-120 after a clock write | 0x09EE writes the MM58274; its last write (PA = 0x01) is MM58274 register 0 ← 1 (section 8) |
| Response byte has STA/ERR/RDY/VAL/TYP fields | the answer byte is raw data |
| `u3.c` "strictly accurate reconstruction" | it is unchecked, does not compile, and has the errors above (1200 Hz, Port C RTC) |

---

## Key Function Address Reference

| Address | Name | Description |
|---------|------|-------------|
| 0x0110 | Init_And_Main_Loop | Reset entry, full init, then main polling loop |
| 0x04D8 | FIFO_Command_Dispatcher | Read command byte, dispatch cmd0–7 or time output |
| 0x04FC | Command_Jump_Table | 8 × JMP entries (3 bytes + 1 NOP each) |
| 0x0610 | cmd6_SET_CHAR_INDICES | Write 4 chars directly to display buffer 0x10–0x13 |
| 0x05DF | cmd4_SET_CHAR_DISPLAY | ROM character lookup into 0x10–0x13 |
| 0x051B | cmd0_SET_DISPLAY_DATA | 5 bytes → 0x14–0x18 + set "PEXM"/"PT##" |
| 0x06BE | Output_RTC_Time_Data_To_ND120 | cmd bit3=0: send time/status to ND-120 |
| 0x09BC | Strobe_WMM_Read_From_FIFO | Read one byte from the DGA FIFO via RMM~ (PB3) |
| 0x09C5 | Output_Response_To_ND120_IDB | Write one byte via IDB to ND-120 (PB0 latch) |
| 0x09EE | Write_MM58274_Calendar | Write the calendar ($20-$26) into the MM58274 via WRCLK~ (PB1) - NOT an ND-120 output |
| 0x08C8 | Timer_ISR | 400 Hz: sample CPU status, drive the software RTC chain |
| 0x08F9 | Increment_Software_RTC_Counters | Tick sec→min→hr→day→month→year |
| 0x0948 | Shift_CPU_Utilization_History_Buffer | Shift 16-byte ring buffer left |
| 0x09D4 | Sample_ND120_CPU_Status_Signals | PORTD → RAM[0x19] composite status |
| 0x0AC0 | Read_MM58274 | Read the MM58274 registers → $20-$26 (at boot and at every PFUNC 4 read) |
| 0x09BA | SWI_Dummy | NOP + RTI (software interrupt handler, unused) |
