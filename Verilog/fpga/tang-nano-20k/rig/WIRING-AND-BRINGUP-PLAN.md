# Tang Nano 20K ↔ Olimex RP2350 rig — wiring reference + bring-up plan

**Purpose:** the canonical wire list for the ND-120 bring-up rig, and the plan to
**physically validate every dupont wire** before any ND-bus protocol runs. The rig
joins the **Tang Nano 20K** (runs the ND-120 CPU + rig HAL) to the **Olimex
RP2350-PICO2-BB48R** (runs NDModulE device firmware) with dupont wires — 3.3 V,
point-to-point, no PCB (design phase). Seam: `nd_bus_if.h`.

> **Authoritative source of the pin map:** `NDModulE/docs/design/nd120_tang20k_rig.cst`
> (Tang balls, from the Sipeed pin-label sheet) and `NDModulE/src/bus/nd_bus_gpio.h` /
> `nd_bus_pins.h` (Pico GPIO). The wiring below is transcribed from that `.cst`.
> The visual diagram is the artifact "Pico ↔ Tang Nano 20K — ND-bus rig wiring";
> if the diagram and the `.cst` ever disagree, **the `.cst` wins** (Ronny's call,
> 08-SEP-2026).

## Decisions locked (08-SEP-2026)

1. **Wire list = 31-wire latched-interrupt map** (the newer `.cst`), not the older
   34-wire `TANG-RIG-PIN-BUDGET.STALE.md` individual-interrupt map. Interrupts are NOT
   dedicated pins: the Pico writes a 4-bit mask on DBUS and pulses `LE_INT`; balls
   79/80/85 are freed (ball 31 now carries /BAPR_OUT, moved off ball 79 = onboard
   WS2812 LED). Daisy OE not wired (a single-card rig can't exercise it).
2. **Firmware form = compile-time stage in each project.** Pico: a `wiring-test`
   stage beside the existing `gpio-walk`/`sniff` stages. Tang: the wiring-test top
   is the **first commit of the rig gateware** here in nd-120, later grown into the
   latch-model top.
3. **Host tool = C# .NET console**, driving both control UARTs.

## The wiring — 31 signals + clk/rst

Direction is from the **FPGA's** point of view: `o_*` = Tang drives → Pico samples;
`i_*` = Pico drives → Tang samples; `io_dbus[*]` = bidirectional. All signal balls
LVCMOS33, `PULL_MODE=NONE`. Pico physical header pin (0.1″ position) is **TBD** —
read from `boards/olimex_rp2350_pico2_bb48r.h` before wiring; the GPIO numbers below
are authoritative.

### Clock / reset (dedicated Tang balls, not among the 31)
| Signal | Tang ball | Note |
|---|---|---|
| `clk`   | 4  | 27 MHz onboard osc, `PULL_MODE=UP` |
| `rst_n` | 88 | S1 button, active-low, `PULL_MODE=UP` |

### DBUS0..7 — bidirectional (8), `DRIVE=8`, 220 Ω series on the wire
| Signal | Tang ball | Pico GPIO |
|---|---|---|
| io_dbus[0] | 42 | 12 |
| io_dbus[1] | 41 | 13 |
| io_dbus[2] | 56 | 14 |
| io_dbus[3] | 54 | 15 |
| io_dbus[4] | 51 | 16 |
| io_dbus[5] | 48 | 17 |
| io_dbus[6] | 55 | 18 |
| io_dbus[7] | 49 | 19 |

### Trigger sniffs — Tang drives → Pico samples (4)
| Signal | Tang ball | Pico GPIO |
|---|---|---|
| o_bapr (/BAPR_IN)   | 15 | 20 |
| o_bioxe (/BIOXE_IN) | 16 | 21 |
| o_bdap (/BDAP_IN)   | 76 | 22 |
| o_bdry_in (/BDRY_IN)| 86 | 23 |

### Latch control — Pico drives → Tang samples (8)
| Signal | Tang ball | Pico GPIO |
|---|---|---|
| i_oe_in0 (/OE_IN_0)   | 73 | 26 |
| i_oe_in1 (/OE_IN_1)   | 74 | 27 |
| i_oe_in2 (/OE_IN_2)   | 75 | 28 |
| i_le_out0 (LE_OUT_0)  | 77 | 29 |
| i_le_out1 (LE_OUT_1)  | 27 | 30 |
| i_le_out2 (LE_OUT_2)  | 28 | 31 |
| i_bd_oe_bus (/BD_OE_BUS) | 25 | 32 |
| i_le_int (LE_INT, 4th latch — interrupt/config mask off DBUS) | 30 | 39 |

### Slow sniffs — Tang drives → Pico samples (6)
| Signal | Tang ball | Pico GPIO |
|---|---|---|
| o_bmem (BMEM)      | 17 | 33 |
| o_binack (BINACK)  | 18 | 34 |
| o_bmcl (BMCL)      | 26 | 35 |
| o_binput (BINPUT)  | 29 | 36 |
| o_ingrant (INGRANT)| 19 | 37 |
| o_inident (INIDENT)| 20 | 38 |

### Control drives — Pico drives → Tang samples (5)
| Signal | Tang ball | Pico GPIO |
|---|---|---|
| i_bapr_out (/BAPR_OUT)     | 31 | 41 | (moved off ball 79 = onboard WS2812 LED) |
| i_bdry_out (/BDRY_OUT)     | 72 | 42 |
| i_binput_out (/BINPUT_OUT) | 71 | 43 |
| i_bdap_out (/BDAP_OUT)     | 53 | 44 |
| i_breq_out (/BREQ_OUT)     | 52 | 45 |

**Count:** 8 + 4 + 8 + 6 + 5 = **31 signal wires** (+ clk + rst_n). Matches the
`.cst` ("wires only 31 by latching the interrupts").

## Why the walking test is clean here

- Every rig wire already has a **fixed direction** (except the 8 DBUS bits), so the
  walking-ones test needs no reconfigurable IO: each wire is driven by its natural
  driver and read by its natural receiver. DBUS is tested in **both** directions.
- Both sides have a **control UART independent of the wires under test**:
  Pico = USB-CDC (COM7); Tang = the onboard FT2232 UART on dedicated balls **69/70**
  (not among the 31). So the pulse-and-report loop never rides a wire it is checking.

## Bring-up phases

### Phase 0 — the golden map
Emit the table above as a machine-readable map (CSV/JSON) that BOTH the C# tool and
this doc share. It is simultaneously the file Ronny wires from (the visual reference)
and the tool's expected-connection oracle — one source, no drift. Include the Pico
physical header pin once read from the Olimex board header.

### Phase 1 — Tang→Pico wires (o_* and DBUS-as-Tang-drives)
- Tang wiring-test top: on UART command, drive exactly ONE of its output-capable
  balls high (walking-ones), rest low; or `read` to report all inputs.
- Pico wiring-test stage: `read` reports the state of all its input GPIOs over COM7.
- C# tool walks each Tang-driven wire: command Tang to drive it, command Pico to
  read, assert **exactly** the expected Pico GPIO is high and no others.
  - none high → **open** wire; wrong GPIO → **swap**; more than one → **short**.

### Phase 2 — Pico→Tang wires (i_* and DBUS-as-Pico-drives)
- Same walk, reversed: Pico drives one GPIO, Tang reports its inputs.

### Phase 3 — gross-short sweep
- Drive all-high then all-low on each side; the receiver must see all-high/all-low.
  Catches rail shorts and stuck pins the walk can miss.

### Phase 4 — report
- C# tool prints a PASS/FAIL line per wire with the human-readable signal name and
  both pin numbers, and a final tally. Only an all-PASS clears the rig for the actual
  ND-bus bring-up (the Pico `nd_bus_gpio.c` path, still scaffold/gated-off today).

## State today (verified 08-SEP-2026)
- Tang rig gateware: **not written** (the `.cst` says so).
- Pico `nd_bus_gpio.c`: **scaffold, unvalidated, CMake-gated OFF**.
- Nothing physically wired.

Cross-refs: `NDModulE/docs/design/nd120_tang20k_rig.cst`,
`NDModulE/docs/design/TANG-RIG-PIN-BUDGET.STALE.md`,
`NDModulE/docs/design/PIO-BUS-ARBITER.md` (§2a — DBUS/LE_INT latch payload),
`NDModulE/docs/BENCH.md` (USB/serial map).
