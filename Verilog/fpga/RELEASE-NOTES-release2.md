# ND-120 FPGA — Release 2 (bitstreams-2026-09)

Ready-built bitstreams so you can run the 1988 Norsk Data ND-120 CPU without
installing Vivado, Gowin or Quartus. Attached to this GitHub Release; the
binaries are never checked into git.

**Source commit:** `b09302e` — *mega65: the whole ND-120 machine on the
MiSTer2MEGA65 framework, both revisions*.

**What is new since Release 1 (bitstreams-2026-08):**
- **MEGA65** — the whole machine, first release, two cores (see below).
- **MiSTer (DE10-Nano)** — first release, TDV2200 console.
- **QMTECH XC7A35T SDRAM core board** — first release. The same Artix-7 die as
  the Basys3, but with 32 MB of SDRAM on board, which is what lifts the
  Basys3's 24 KB memory ceiling and makes this the one Artix-7 target of that
  size that can run SINTRAN. Built and timing-clean; never run on a board.
- The real **TDV2200 box-drawing font** (character set 2, dumped from
  RetroCore), now **embedded in `font_rom.v`** so every board carries the
  correct glyphs with no loose hex file to copy.
- The physical **Left-arrow key** fix (the Nexys USB-PS/2 bridge drops the E0
  prefix; Left arrives as bare `0x6B`).
- A fourth power-on **banner line**: board / CPU clock / cache on-off, filled
  in from the build settings.

**Console settings — every file, no exceptions:** 115200 baud, **7 data bits,
EVEN parity, 1 stop bit**, no flow control. One terminal setting for the whole
release.

---

## Artifacts

| File | Board | Format | CPU clock | Verified |
|---|---|---|---|---|
| `nd120_mega65_rev3_13MHz_115200.cor` | MEGA65 **R3 / R3A** | `.cor` | 13.33 MHz | **Built + timing-clean. NOT yet run on a MEGA65.** |
| `nd120_mega65_r6_20MHz_115200.cor` | MEGA65 **R4 / R5 / R6** | `.cor` | 20 MHz | **Built + timing-clean. NOT yet run on a MEGA65.** |
| `nd120_nexys4ddr_33MHz_115200.bit` | Nexys 4 DDR | `.bit` | 33.333 MHz | *pending — refresh build in preparation* |
| `nd120_tang20k_fast20_20MHz_115200.fs` | Tang Nano 20K | `.fs` | 20.25 MHz | *pending — refresh build in preparation* |
| `nd120_mister_20MHz_115200.rbf` | MiSTer (DE10-Nano) | `.rbf` | 20 MHz | **Built + run on a DE10-Nano (02-SEP-2026): boots to OPCOM, boots SINTRAN from a mounted Winchester image, TDV2200 font and keyboard confirmed.** |
| `nd120_qmtech_a35t_20MHz_115200.bit` | QMTECH XC7A35T SDRAM core board | `.bit` | 20 MHz | **Built + timing met (+4.645 ns). NOT yet run on a board.** |
| `SHA256SUMS` | — | — | — | regenerated when the whole set is final |

The two MEGA65 cores (the 04-SEP rebuild, uploaded 05-SEP) and the
hardware-verified MiSTer `.rbf` are attached. The QMTECH `.bit` is staged but
not attached until someone has run it on a board; the Nexys/Tang refresh is
added as each is built and checked, and the `SHA256SUMS` asset is regenerated
and re-uploaded with any such change - never on its own.

### SHA-256 (MEGA65 cores + MiSTer + QMTECH)

Regenerated 04-SEP-2026 from `fpga/release-staging/` by
`./stage-release.sh --sums`, which is the only place these should ever be
copied from.

```
a24dee1a5c2503286013d29738a3629436da2aa74559ddecaf45002e56abb2a0  nd120_mega65_rev3_13MHz_115200.cor
c00b13faf3a8ffec4a67a200e8bc8128ef8ed85d415002746f23d595b086caa3  nd120_mega65_r6_20MHz_115200.cor
deb9e1ea499baa0dab8d6595f01f696a360b4df536209d9d42b0397df680520a  nd120_mister_20MHz_115200.rbf
61d23600cf20de9f0754085399b3f15579a6ac931fb5cfc35f334d675f204732  nd120_qmtech_a35t_20MHz_115200.bit
```

**The MEGA65 cores on the live release were replaced on 05-SEP-2026**, and
these are the hashes of what downloads today. Until that upload the release
still served the 02-SEP build: the 04-SEP rebuild (raw microcode word 0o2002,
RUN/STOP = EXIT) had gone into `fpga/release-staging/` but never onto GitHub,
so the body advertised `e936a868` / `28f7d186` - correct for the old files
that were actually attached.

| file | was attached | now attached |
|---|---|---|
| `nd120_mega65_rev3_13MHz_115200.cor` | 4,782,231 bytes, `e936a868...` | 4,782,031 bytes, `a24dee1a...` |
| `nd120_mega65_r6_20MHz_115200.cor` | 4,508,055 bytes, `28f7d186...` | 4,508,431 bytes, `c00b13fa...` |
| `nd120_mister_20MHz_115200.rbf` | `deb9e1ea...` | `deb9e1ea...` - untouched |

The MiSTer `.rbf` matching on both sides is what proved the difference was
the rebuild and not the checksum method.

**The lesson, because it nearly went the wrong way:** the first reading of
this was "the published hashes are stale, correct them". They were not stale
- they matched the attached binaries exactly, and rewriting them would have
advertised checksums matching nothing on the server, turning a release that
verified into one that did not. **Compare the asset SIZES before concluding
anything about a hash mismatch.** A release is only consistent if the body,
the `SHA256SUMS` asset and the binaries are replaced together, in that
order-independent group: all three carried the old pair.

Verified after the 05-SEP upload by downloading every asset fresh and running
`sha256sum -c SHA256SUMS` against the server's own copy: 3 of 3 OK.

`nd120_qmtech_a35t_20MHz_115200.bit` (`61d23600...`) is staged locally but
**deliberately not attached** - it waits on a first hardware bring-up.

---

## MEGA65 — read this first

**These two cores are built and timing-clean, but no MEGA65 was available to
run them on. You are the verification channel.** They go out labelled
"not yet run on a MEGA65". [`QUICKSTART-mega65.md`](https://github.com/RonnyA/nd-120/blob/bitstreams-2026-09/Verilog/fpga/QUICKSTART-mega65.md) tells you what to see and what
to report back.

**Pick the core for your board revision — the flash menu refuses a
wrong-model `.cor`:**

- **R3 / R3A** → `nd120_mega65_rev3_13MHz_115200.cor` (13.33 MHz). The 4 MB of
  ND-120 memory lives in the board's **HyperRAM** (Nexys cache seam + an Avalon
  port). Timing: WNS +0.093 ns, WHS +0.035 ns.
- **R4 / R5 / R6** → `nd120_mega65_r6_20MHz_115200.cor` (20 MHz). The 4 MB lives
  in the board's **64 MB SDRAM** (the MiSTer sheet-49 bridge). Timing:
  WNS +0.249 ns, WHS +0.003 ns. Built for R6; R4/R5 rebuild from source with
  `BOARD=r4` / `BOARD=r5` (same memory, different top).

Both cores are the whole machine: CPU, 4 MB memory, TDV2200 console on the
MEGA65's own keyboard and screen, and the framework's virtual floppy 0/1 +
Winchester 0/1 + tape. Build stamp `e5bdea5+ 02-Sep-2026 16:27`.

**What to report:** does the power-on banner render (including the box-drawing
lines), does the Left arrow work, does OPCOM answer, does `20500&` run — and the
power LED verdict. Details in [`QUICKSTART-mega65.md`](https://github.com/RonnyA/nd-120/blob/bitstreams-2026-09/Verilog/fpga/QUICKSTART-mega65.md).

---

## QMTECH XC7A35T — read this first too

**Also built, also never run on a board.** Same honesty as the MEGA65 rows
above, but this one asks more of you: the board has **no USB data path, no
on-board UART and no SD slot**, so the console and the SD card go on **jumper
wires to a raw 2x25 header (JP3)**, and programming is JTAG-only and
**volatile** — a power cycle wipes it and you program it again.

It is worth the trouble because of what it is: the same Artix-7 die as the
Basys3, but with 32 MB of SDRAM on board. The Basys3 cannot run SINTRAN for
want of memory and no clock speed fixes that. This board carries the whole
machine — CPU, 4 MB of main memory in the SDRAM, SD storage and the serial
console — at 20 MHz with +4.645 ns of timing margin, using 12,619 of 20,800
logic cells and 22 of 50 block RAM tiles.

**One fact in the wiring guide is unmeasured and you are the one who can
measure it: which JP3 pin is ground.** The candidates are pins 3, 4, 21 and
22; the 6-pin JTAG header gives you a known ground to check them against with
a meter. Do that before wiring — a card with no shared ground behaves exactly
like a broken card.

[`QUICKSTART-qmtech-a35t.md`](https://github.com/RonnyA/nd-120/blob/main/Verilog/fpga/QUICKSTART-qmtech-a35t.md)
has the full pin table, the meter check, the console settings and what to
report back.

---

## How to load them

- **MEGA65** — `.cor` files flash from the MEGA65's own core menu; SD card holds
  the `/nd120` disc images. Full walkthrough: **[`QUICKSTART-mega65.md`](https://github.com/RonnyA/nd-120/blob/bitstreams-2026-09/Verilog/fpga/QUICKSTART-mega65.md)**.
- **Nexys 4 DDR** — microSD config at power-on (one card carries the `.bit` and
  the disc image), or Vivado/openFPGALoader over USB-JTAG.
  See **[`QUICKSTART-nexys4ddr.md`](https://github.com/RonnyA/nd-120/blob/bitstreams-2026-09/Verilog/fpga/QUICKSTART-nexys4ddr.md)**.
- **Tang Nano 20K** — `openFPGALoader -f` writes onboard SPI flash once, boots
  the ND-120 at every power-on after. See **[`QUICKSTART-tang-nano-20k.md`](https://github.com/RonnyA/nd-120/blob/bitstreams-2026-09/Verilog/fpga/QUICKSTART-tang-nano-20k.md)**.
- **MiSTer (DE10-Nano)** — copy `nd120_mister_20MHz_115200.rbf` to the SD card
  as `/media/fat/_Computer/ND120.rbf` and load it from the MiSTer menu. Attach
  a Winchester image (for example `WD0.IMG`) from the OSD, then at the `#`
  monitor type `&` to boot it. The console is the MiSTer's own screen and
  keyboard; the CPU's serial line is also on the HPS `/dev/ttyS1` at 115200 7E1.
  Full walkthrough: **[`QUICKSTART-mister.md`](https://github.com/RonnyA/nd-120/blob/main/Verilog/fpga/QUICKSTART-mister.md)**.

- **QMTECH XC7A35T** — no copy-a-file path exists on this board. Wire the
  console and an SD Pmod to header JP3 first, then program
  `nd120_qmtech_a35t_20MHz_115200.bit` over the 6-pin JTAG header with a
  Xilinx Platform Cable USB II (Vivado Hardware Manager, or the free Vivado
  Lab Tools). Volatile — re-program after every power cycle. Full wiring
  diagram and walkthrough:
  **[`QUICKSTART-qmtech-a35t.md`](https://github.com/RonnyA/nd-120/blob/main/Verilog/fpga/QUICKSTART-qmtech-a35t.md)**.

**Disc image is not in the release** (instructions only): the machine needs a
Winchester image on the card's FAT root. A bitstream with no image still comes
up in OPCOM — the quickstarts use that as the "it works" smoke test.
