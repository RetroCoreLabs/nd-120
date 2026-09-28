# SD-card BPUN loading and ND-100 device emulation - reference

Status: BUILT. This started as the 11-JUL-2026 design plan for an SD card +
FAT stack, a Verilog paper tape reader at device 400 and the road to floppy
and SMD. All of that exists now: the SD-FAT library (`Verilog/SD-FAT/`,
clean-room MIT reader and writer, 4-bit bus proven on the Tang Nano 20K
12-JUL-2026), the device bus interface (`ND-BUS-DEVICES/BUS-IF/circuit/ND_BUS_SLAVE.v`),
the tape reader (`ND-BUS-DEVICES/TAPE-400/circuit/ND_TAPE_400.v`), and the
storage facade that serves tape, floppy, SMD and Winchester images from the
card (`Verilog/docs/nd-storage-design.md`). The plan sections (folder layout,
component specs, milestones, core selection) were removed; they are in git
history. What stays is the verified reference material below.

All paths are relative to the repository root.
Anything not confirmed against a primary source is marked UNVERIFIED.

---

## 4. ND-100 paper tape reader, device 400 octal - verified spec

Primary sources, cross-checked and in agreement:

- "NORD-100 Input/Output System" ND-06.016.01, Appendix A page A-3
  (device table) and section I.3.5 (standardized PIO status/control):
  http://www.bitsavers.org/pdf/norskData/ND-100-IO-ND-06.016.01_NORD-100_Input_Output_System_1980.pdf
- "ND-100 Functional Description" ND-06.015.02, sections 7.2.2 (ALD)
  and 7.2.5 (binary format load), and appendix B.2 (paper tape reader
  spec, quoted in `Emulated.HW/ND/CPU/NDBUS/NDBusPapertapeReader.cs` in
  the RetroCore repository):
  http://www.bitsavers.org/pdf/norskData/ND-100-FD-ND-06.015.02_ND-100_Functional_Description_1985.pdf
- https://www.ndwiki.org/wiki/BPUN_File_Format (bootstrap listing)
- `Verilog/simDevices/NDDevices.cpp` (working sim implementation)

### 4.1 Identity

| Property | Value |
|---|---|
| Register address range | 400-403 octal (reader 2: 404-407) |
| Interrupt level | 12 (input-channel PIO level) |
| Ident code | 2 octal (reader 2: 22 octal) |
| SINTRAN logical device | 2 (nd100x uses 3 - manual says 2; punch is 3) |

### 4.2 Register map (register = device number + offset)

| IOX addr (octal) | Dir | Name | Behavior |
|---|---|---|---|
| 400 | read | Read data register | 8 data bits right-justified in A bits 7-0. Reading clears status bit 3 (ready for transfer). Same character may be read repeatedly until the next activate. |
| 401 | write | Write data buffer | Not used by the reader (punch-style slot). Accept and ignore. |
| 402 | read | Read status register | See bits below. |
| 403 | write | Write control word | See bits below. |

IOX addressing rule: even offset = device-to-A (read), odd = A-to-device
(write); address bits 2-0 select the register, higher bits the device
(https://ndwiki.org/wiki/IOX).

### 4.3 Status register bits (IOX 402)

| Bit | Meaning |
|---|---|
| 0 | Interrupt-on-ready-for-transfer enabled (echo of control bit 0) |
| 2 | Read active (device busy fetching a character) |
| 3 | READY FOR TRANSFER - data register holds a valid character. This is the bit the boot loader polls (`BSKP ONE 30 DA`). |
| others | Not used on the reader (return 0) |

Interrupt condition: status bit 0 AND status bit 3 -> raise level 12.
IDENT on level 12 returns ident code 2 and clears the interrupt (and
clears the interrupt-enable bit - both `NDDevices.cpp` `IDENT()` and
`NDBusPapertapeReader.cs` do this).

### 4.4 Control word bits (IOX 403)

| Bit | Meaning |
|---|---|
| 0 | Enable interrupt on ready for transfer |
| 2 | ACTIVATE - fetch the next character from the tape; when it is in the buffer, status bit 3 sets |
| 3 | Test mode (interface self-test; optional - see below) |
| 4 | Device clear - clears control/status, empties the buffer, rewinds the tape (in our case: reopen / seek 0 of the file) |
| others | Not used |

Behavioral contract, distilled from `Verilog/simDevices/NDDevices.cpp`
`PaperTape::Write()` (the version the CPU microcode is proven to boot
against in Verilator):

1. On control write: copy bit0 -> status bit0, bit2 -> status bit2.
2. If bit4 (device clear): clear read-active and ready-for-transfer,
   zero the character buffer, rewind the tape.
3. If read-active: clear ready-for-transfer, fetch one byte from the
   tape stream; on success put it in the data register and set
   ready-for-transfer; on EOF leave ready-for-transfer clear. Then
   clear read-active.
4. Update the interrupt line: level-12 request = status bit0 AND bit3.

Note the hardware nuance: in the real interface the fetch takes tape
time and status bit 2 stays set meanwhile; in the C++ model the fetch
is immediate. The Verilog device should insert a SMALL delay (a few
bus-clock cycles, or "data ready when the SD FIFO has a byte") - the
polling loop tolerates any latency, and instant-ready is also proven
to work in sim, so latency is a free parameter.

Control bit 3 (test mode) lets diagnostics increment the data register
without a reader; implement it only if the ND test programs need it -
mark: OPTIONAL, not needed for boot.

### 4.5 The boot flow (why this device is enough to boot)

The CPU card ALD strap in `Verilog/CPU-BOARD-3202/circuit/IO_REG_41.v`
was `0100` binary = ALD switch position 11 = ALD value 400 octal = "BPUN
load from paper tape (400) and run" when this was written. Since
07-AUG-2026 it is `0010` = bootstrap load from the Winchester (500), so a
bare `&` boots the disc; the tape is reached explicitly with `400$` or
`400&`. Either makes the MOPC microcode run its built-in
binary loader ("Octal load is not implemented in ND-100" - the binary
loader is microcode, ND-06.015.02 page 7-20). The microcode issues
exactly the polled loop:

```
rdbyt: SAA 4          A := 4 (control bit 2 = activate)
       IOX 403        write control word
wait:  IOX 402        read status
       BSKP ONE 30 DA skip when status bit 3 set
       JMP * -2
       IOX 400        read the byte
```

### 4.6 BPUN stream format (what comes off the "tape")

From ndwiki BPUN page and ND-06.015.02 section 7.2.5.1 (fields A-I),
matching `loadfile()` in `Verilog/runSim/Run120.cpp`:

| Field | Content |
|---|---|
| A | Preamble: any bytes except `!`. Historically an ASCII bootstrap with even parity; the ND-100 microcode just scans past it. |
| B | Start address, ASCII octal digits terminated by CR (LF ignored) |
| C | Bootstrap loader address, ASCII octal terminated by `!` |
| `!` | Delimiter (41 octal) - binary section begins |
| E | Load address: 2 bytes, MSB first |
| F | Word count: 2 bytes, MSB first |
| G | F 16-bit data words, each MSB first |
| H | Checksum: 16-bit arithmetic sum of G, MSB first |
| I | Action code: 0 = start CPU at address B; nonzero = return to OPCOM with P = B |

Important consequence: the device does NOT parse BPUN. It is a dumb
byte pipe - the microcode does all parsing and checksumming. The
Verilog TapeReader only needs "give me the next byte of the file".

---

## 5. How a device-400 IOX reaches a device in THIS design

There are two distinct I/O paths in the 3202D board and it matters
which one we use:

1. **On-board (internal IDB) devices** - console UART (SC2661 model,
   `Verilog/CPU-BOARD-3202/circuit/IO_UART_42.v`), RTC, panel. Their
   chip selects (`CEUART_n`, `RUART_n`, ...) are decoded inside the
   DECODE gate array (instantiated in
   `Verilog/CPU-BOARD-3202/circuit/IO_DCD_38.v`) and their data goes
   straight onto the internal IDB via the source mux in
   `Verilog/CPU-BOARD-3202/circuit/IO_37.v`. This decode is fixed by
   the DGA - we cannot (and should not) add device 400 here.

2. **External ND-100 bus devices** - everything else, including device
   400. An IOX whose address is not on-board becomes an external bus
   cycle through the Bus InterFace (`Verilog/CPU-BOARD-3202/circuit/
   BIF_5.v` and children), using the active-low multiplexed bus
   `BD_23_0_n` plus the control strobes. In the Verilator sim these
   come out of `Verilog/ND120_TOP.v` as ports and are serviced by
   `proccess_bif_signal()` in `Verilog/simDevices/NDBus.cpp` (the
   legacy C devices, `VERILOG_TAPE=0`) or by the Verilog devices in
   `ND120_CORE.v` (the default).

### 5.1 The bus protocol to implement (from `Verilog/simDevices/NDBus.cpp`)

All `BD` data/address bits are ACTIVE LOW on the bus (value = `~BD`).
Edge semantics, in order of a typical IOX transfer:

| Event (CPU asserts) | Device action |
|---|---|
| `BAPR_n` falling | Latch address = `~BD_23_0_n & 0xFFFFFF`. Address bit 0 even = READ cycle, odd = WRITE cycle. Deassert `BINPUT_n`. |
| `BIOXE_n` falling | WRITE cycle: data = `~BD_23_0_n & 0xFFFF`; perform the register write; assert `BDRY_n` (data accepted). READ cycle: assert `BINPUT_n` (request to drive the bus) and wait for `BINACK_n`. |
| `BINACK_n` falling | READ cycle: drive `BD_23_0_n = ~data`; assert `BDAP_n` and `BDRY_n`. |
| `BIOXE_n` rising | Release everything: `BDRY_n=1, BDAP_n=1, BINPUT_n=1`, stop driving BD (drive all-ones = inactive). Cycle done. |
| `OUTIDENT_n` falling | The address bus holds the IDENT level code: 004 octal -> level 10, 011 -> 11, 022 -> 12, 043 -> 13. If this device has a pending interrupt on that level: assert `BINPUT_n`, put `~identcode` on BD, then complete via `BINACK_n`/`BDAP_n`/`BDRY_n` as a read. Clear the interrupt. |
| `OUTIDENT_n` rising | Release BD, `BINPUT_n`, `BDRY_n`. |
| (continuous) | Drive `BINT12_n` low while the device requests level-12 interrupt. |

Memory cycles (`BMEM_n`) are ignored by I/O devices.

Inside the FPGA the "bus" is not a real tri-state bus: each device
outputs a 24-bit data word and a drive-enable; a rail module ORs/muxes
them (repo tri-state rule). The active-low inversion is kept at the
rail so the CPU-side BIF sees exactly the polarity it sees in sim.

### 5.2 Where it plugs in

The Verilog devices hang off `ND_BUS_SLAVE` inside `Verilog/ND120_CORE.v`,
which every board top and `ND120_TOP.v` (Verilator) instantiate. The C++
device path in `Verilog/simDevices/` still builds with `VERILOG_TAPE=0`.

---

## 6. SD hardware

### 6.1 Tang Nano 20K microSD slot (primary target)

Pin numbers verified against three independent constraint files:
Sipeed's own https://github.com/sipeed/TangNano-20K-example
(`nestang/src/nestang.cst`), https://github.com/nand2mario/nestang
(`src/boards/nano20k.cst`) and https://github.com/nand2mario/snestang
(`src/boards/nano20k.cst`). Board schematic:
https://dl.sipeed.com/shareURL/TANG/Nano_20K/2_Schematic

| Signal | FPGA pin (QN88) | SD-native role | SPI role |
|---|---|---|---|
| `sd_clk` | 83 | CLK | SCLK |
| `sd_cmd` | 82 | CMD (bidir) | MOSI |
| `sd_dat0` | 84 | DAT0 | MISO |
| `sd_dat1` | 85 | DAT1 (drive 1) | unused (drive 1) |
| `sd_dat2` | 80 | DAT2 (drive 1) | unused (drive 1) |
| `sd_dat3` | 81 | DAT3 (drive 1) | CS |

All `IO_TYPE=LVCMOS33 PULL_MODE=NONE`. Driving DAT1-3 high keeps the
card in SD-native mode / deselected-for-SPI as appropriate. No card
detect line appears in any constraint file (UNVERIFIED whether the
slot has one at all - assume none; detect the card by init success).
Both modes are proven on this exact slot: Sipeed's NESTang example
uses WangXuan95's SD-native 1-bit reader; nand2mario's iosys uses SPI.

### 6.2 Basys3 (second target) - Pmod microSD

The Basys3 has no SD slot; use a Digilent Pmod MicroSD (or compatible)
on Pmod header JA. UNVERIFIED until the adapter is in hand - verify
against the Digilent Basys3 master XDC and the Pmod MicroSD reference
manual. Expected mapping (Basys3 master XDC pin names for JA):

| Pmod pin | JA site | FPGA pin (UNVERIFIED) | Pmod MicroSD signal |
|---|---|---|---|
| 1 | JA1 | J1 | DAT3 / CS |
| 2 | JA2 | L2 | MOSI (CMD) |
| 3 | JA3 | J2 | MISO (DAT0) |
| 4 | JA4 | G2 | SCK |
| 7 | JA7 | H1 | DAT1 |
| 8 | JA8 | K2 | DAT2 |
| 9 | JA9 | H2 | CD (card detect) |
| 10 | JA10 | G3 | (nc) |

Because the wiring is identical minus the connector, the SD/FAT
component must not hard-code pins or vendor primitives - plain
Verilog, pins only in each board's constraint file.

## 12. Still open from the plan

- The Tang slot shows no card-detect line in any constraint file
  (UNVERIFIED whether the slot has one); the stack detects a card by init
  success or timeout.
- The Basys3 Pmod MicroSD pinout in section 6.2 is unverified; no Basys3
  SD build exists.
- `sd_file_reader` scans the root directory only; subdirectories are not
  searched (card recipe: `Verilog/fpga/tang-nano-20k/sd-fat-test/CARD-SETUP.md`).

---

## 13. Summary of verified facts (quick reference)

- Tang Nano 20K SD pins: CLK=83, CMD=82, DAT0=84, DAT1=85, DAT2=80,
  DAT3=81, all LVCMOS33 (three independent .cst sources).
- SD/FAT core: the clean-room MIT `Verilog/SD-FAT/circuit/sd_file_reader.v`
  (replaced the GPL WangXuan95 reader on 12-JUL-2026) plus `sd_writer.v`.
- Device 400 octal: registers 400 data / 402 status / 403 control;
  status bit 3 = ready-for-transfer (polled by boot loader), control
  bit 2 = activate, bit 4 = device clear, bit 0 = interrupt enable;
  interrupt level 12, ident code 2 octal.
- ALD strap in `Verilog/CPU-BOARD-3202/circuit/IO_REG_41.v` is the
  Winchester (500) since 07-AUG-2026; `400$` / `400&` at OPCOM boots from
  the tape reader.
- The device does not parse BPUN; the microcode binary loader does.
- Device side of the ND-100 bus protocol = `proccess_bif_signal()` in
  `Verilog/simDevices/NDBus.cpp`; the Verilog version is
  `ND-BUS-DEVICES/BUS-IF/circuit/ND_BUS_SLAVE.v`.
