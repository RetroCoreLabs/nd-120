# USB flash-drive storage for the ND-120 boards: feasibility, options, effort

**Full path:** `Verilog/docs/usb-storage-options.md`
**Date:** 13-JUL-2026. Research answer to: "the Basys3 has a USB port - can
the FAT SD-card logic get a variant that uses USB?" Sources cited inline;
the code-layering facts come from
`Verilog/SD-FAT/circuit/` (analyzed
13-JUL-2026).

---

## 1. The hard fact first: the Basys3's own USB ports CANNOT do this

Per the Digilent Basys 3 reference manual
(https://digilent.com/reference/programmable-logic/basys-3/reference-manual):

- The **USB-A "HID Host" port (J2)** is not wired to FPGA I/O at all. It
  terminates at the Auxiliary Function microcontroller (Microchip
  PIC24FJ128), whose closed Digilent firmware supports ONLY a keyboard or
  mouse (no hubs) and presents **PS/2-style signals** to the FPGA. The one
  mass-storage feature that exists - "program the FPGA from a .bit file on
  a FAT32 stick" (JP1=USB) - runs entirely inside the PIC24 and drives the
  FPGA's *configuration* port; that data path ends at configuration and is
  never visible to the user design. USB D+/D- never touch FPGA pins.
- The **micro-B port (J4)** is the FTDI FT2232HQ - a USB *device* to the
  PC (JTAG + UART). A flash drive plugged into it does nothing.

**Verdict: no firmware trick, no HDL trick - USB mass storage through the
built-in ports is electrically impossible. Any USB-stick variant means a
small add-on board on a Pmod connector** (Basys3 has 3 general-purpose
Pmods, 8 signals each at 3.3 V, VCC good for 1 A).

## 2. What our stack already gives us (layering analysis)

Full analysis of `Verilog/SD-FAT/circuit/`:

- **The FAT write/update logic is already transport-neutral.**
  `sd_fat_rewrite.v` (670 lines), `sd_fat_check.v` (425), and
  `sd_fat_freescan.v` (206) contain zero SD commands; they speak the
  **`eng_*` sector port** (`eng_start/eng_rd/eng_sector[31:0]/eng_busy/
  eng_done/eng_err` + 512-byte rx/tx byte streams -
  `sd_fat_rewrite.v:86-98`). Any backend that reads/writes 512-byte
  sectors by LBA drops in with a re-wire in `nd_storage.v:401-437`.
- **The FAT read/mount logic is welded to SD.** `sd_file_reader.v`
  (1537 lines, one 44-state FSM) interleaves SD init/commands with
  MBR/BPB parse, directory scan (incl. VFAT long names), and cluster-chain
  walking; ~15 states poke its private SD bit-engine directly. Reusing it
  over another transport requires splitting that file at an `eng_*`-style
  port - a medium refactor, not a wiring job.
- **Everything above `nd_storage`'s client port is transport-agnostic.**
  The engine/SDRAM-cache (`nd_storage_engine.v`), mount, and the floppy/
  tape adapters only ever see slot-open + 2048-byte block requests
  (`nd_storage.v:91-107`); they would be untouched by ANY backend swap.

- **USB-MSC is shape-compatible with FAT.** A USB stick presents 512-byte
  LBA sectors via SCSI READ(10)/WRITE(10) wrapped in Bulk-Only Transport -
  exactly the abstraction our `eng_*` port already encodes. So "do we know
  how to make FAT work on USB hw?" - **yes, conceptually solved**: FAT
  never needs to know it is on USB. The real cost is the USB HOST
  transport underneath (enumeration + BOT + SCSI), for which **no
  open-source pure-HDL implementation exists anywhere** (verified: all
  reference code is C - USB_Host_Shield_2.0, TinyUSB).

## 3. The options

### Option A - CH376 file-bridge chip on a Pmod (DAYS) - recommended if USB sticks are the goal

WCH CH376 ("USB flash disk and SD card file-manage control chip",
English datasheets: https://www.wch-ic.com/downloads/CH376DS1_PDF.html +
DS2): embeds the complete full-speed USB host, MSC/BOT/SCSI stack **and a
FAT12/16/32 filesystem**. The FPGA talks byte commands over SPI (4-5
wires) or UART (2 wires): SET_FILE_NAME / FILE_OPEN / BYTE_READ /
FILE_CLOSE - or raw-sector mode (DISK_READ/DISK_WRITE) if we want to keep
our own FAT. ~$5 modules everywhere; retro-computing scene (MSX/Z80)
drives them from simple bus FSMs routinely.

Integration shape (from the layering analysis): use FILE-LEVEL mode and
**bypass all five SD/FAT modules entirely** - a thin bridge adapter
implements `nd_storage`'s slot-open (name -> FILE_OPEN) and maps
block-N requests to file-offset reads/writes. Engine, cache, floppy/tape
adapters, ND-BUS side: untouched. Testbench: model the CH376 command
protocol the way `sd_card_model.v` models the card.

- Effort: **days (~a week with bring-up quirks)** - the least work of any
  option, and it needs NO FAT logic at all.
- Caveats: 8.3 filenames (LFN limited), single-LUN sticks, trusting WCH
  firmware for corner cases; keep the write-path safety gates culture.
- Works identically on the Tang Nano 20K and CMOD A7 (same SPI FSM).

### Option B - MAX3421E USB host chip on a Pmod (WEEKS, 2-5) - "we own the whole stack"

Analog Devices MAX3421E (active part;
https://www.analog.com/media/en/technical-documentation/data-sheets/max3421e.pdf):
does the USB SIE + transceivers; we implement over SPI: enumeration
control transfers, then BOT+SCSI as an RTL FSM - the same *shape* as our
SD stack (command FSM + 512-byte block engine), and our write-side FAT
drops straight onto it via `eng_*`. Reference implementations are C only
(USB_Host_Shield_2.0, TinyUSB MAX3421E host) - we would write the first
HDL driver, using those as the spec-in-practice. Boards: Adafruit USB
Host FeatherWing/BFF (~$10), 5-7 wires to a Pmod.

To also MOUNT/READ files through our own FAT, this option wants the
`sd_file_reader.v` split at the `eng_*` port - a medium refactor that is
independently worthwhile (it makes our whole FAT stack multi-backend,
SD or USB or anything).

### Option C - pure-RTL USB host core (MONTHS) - not recommended

USB 1.1 SIE cores exist (ultraembedded core_usb_host ~400 LUT, GPL-3;
OpenCores usbhostslave; full-speed needs only D+/D- + resistors on 3.3V
pins), but they are register files designed for a CPU driver. Nobody has
published CPU-less enumeration+BOT+SCSI in RTL; we would be first, with
more new RTL than the entire existing SD+FAT stack. High risk, no prior
art.

### Option D - soft CPU (PicoRV32/VexRiscv ~0.5-2K LUT) + TinyUSB/FatFs in C (WEEKS)

Mature software stack, ~3-5K LUTs + firmware BRAM on the XC7A35T
(fits beside our ~10-15K CPU). But it drags in a RISC-V toolchain and a
second debugging domain - culturally at odds with the Verilog +
self-checking-testbench flow of this repo.

### Option E - no USB at all: the two cheap alternatives

1. **SD-card Pmod on the Basys3** (already the plan in TODO.md "SD-card
   block devices across all boards"): reuses the existing, hardware-proven
   SD+FAT stack **100% unchanged** - same SPI mode, just different pins.
   Effort: cst/pinout + bring-up. For "Basys3 needs storage", this beats
   every USB option on effort and risk.
2. **UART sector-server over the existing FT2232 (J4)**: FT2232H does up
   to 12 Mbaud (~1.2 MB/s) - a tiny LBA-request/data-response FSM on the
   FPGA + a PC daemon serving a disk-image file, presenting the same
   `eng_*`/block interface. **Days** of work, zero hardware, fully
   testbench-able - but the board is tethered to a PC. Excellent
   development accelerator regardless of the standalone choice.

## 4. Speed reality check

USB full-speed (12 Mbit/s) MSC sustains ~0.5-1 MB/s with multi-sector
READ(10) (~167 KB/s if done sector-at-a-time). Modern USB 2.0/3.x sticks
are REQUIRED to fall back to full-speed operation, so they will work.
That is 4-7x our measured 137 KB/s SD-SPI - but the SD speed ladder
(13.5 MHz + CMD18/CMD25 multi-block) lands in the same league - and the
4-bit bus measured 3418 KB/s write, 5981 KB/s read on the Tang on 12-JUL-2026
(`sd-cmd18-block-gap-research.md`, last section). **USB wins on connector
convenience, not on speed.**

## 5. Recommendation

1. For Basys3 storage soonest: **SD-card Pmod, existing stack unchanged**
   (Option E1). It was already the plan; nothing about USB improves on it
   technically.
2. If USB sticks are wanted for convenience: **CH376 on a Pmod, file-level
   mode, thin nd_storage bridge adapter** (Option A, days). Same module
   works on all boards.
3. If we want to OWN a real USB host stack in RTL (and make our FAT truly
   multi-backend): **MAX3421E** (Option B, weeks) + the `sd_file_reader`
   split at `eng_*` - do the split first, it pays off for SD too.
4. Do the **UART sector-server** (Option E2) opportunistically as a dev
   tool - days, and it accelerates every board.

Answering the original questions directly:
- "Variant of the FAT SD logic that uses USB?" - the FAT *write* layer is
  already backend-neutral (`eng_*`); the FAT *read/mount* layer needs a
  split before it can sit on anything but SD. With a CH376 the question
  disappears (the chip does FAT).
- "Do we actually know how to make FAT work on USB hw?" - yes: USB-MSC is
  LBA 512-byte sectors, the same abstraction our FAT already consumes.
  What does NOT exist anywhere as open-source HDL is the USB *host
  transport* (enumeration/BOT/SCSI) - that is the part you buy (CH376,
  MAX3421E partially) or build (weeks-months).
