# Tang Nano 20K SD-FAT test

A standalone test of the reusable SD/FAT library (`Verilog/SD-FAT/`) on
real silicon with an interactive UART menu - no CPU, no ND-100 bus. It was
Milestone 1 of `Verilog/docs/sd-bpun-device-plan.md`; both milestones are done
(the SD stack was proven here 11-JUL-2026, and the ND-120 booted a BPUN tape
from the card 14-JUL-2026 - see `HISTORY.md`). Use it to check a card or the
library without the CPU in the way.

## What it does

USB serial console (the BL616 port of the board), **9600 baud 8N1**.
The **default build is READ-ONLY** (see "Read-only by default" below), so
the menu it prints is:

```
SD-FAT TEST 10-JUL-2026
SD: NOT CHECKED
1=LIST 2=DUMP 5=CHECK 8=BLOCK 9=SECTOR
R=RANGE N=NAME H=HELP
# 
```

- `1` - init the card, mount the FAT16/FAT32 filesystem, list the root
  directory with size, date, first cluster (hex), **first absolute
  sector** (decimal) and name, then the disk-info line:

  ```
      327680  10-AUG-2026  00000002         161  BIG.BPUN
          19  10-AUG-2026  00000282         801  BOOT.BPUN
       <DIR>  11-JUL-2026  00000011         176  HDD
  CARD 8 MB  VOL 8 MB  FREE 7 MB  SPC 1 DBASE 159
  ```

  The sector column is the number to type into command `9`, and it is what
  an addressing bug in the ND-120 storage stack has to agree with. It is
  computed exactly the way the info line's last two fields say:
  `first sector = DBASE + SPC * first cluster` (SPC = sectors per cluster,
  DBASE = data base sector, already biased so cluster *c* starts at
  `DBASE + SPC*c`). An empty file records cluster 0 and prints sector 0.

- `2` - init the card, find the target file in the root directory (by
  default `BOOT.BPUN`, or whatever `N` last set), buffer it in a 64 KB
  BRAM and dump it:

  ```
  CARD: SDHC
  FS: FAT16
  FILE: FOUND
  000000: 00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00 
  ...
  OCTAL WORDS AFTER LEADER: 105015 030060 ...
  LENGTH: 000000007026 BYTES
  DONE
  ```

  (BPUN tapes start with a zero leader; the octal line shows the first
  8 words from the first NONZERO byte, so it is readable at a glance.)
  Files larger than the buffer are cut off with
  `ERROR: FILE TRUNCATED TO BUFFER` - use `8` for those.
- `5` - CHECK ("fsck-lite"): walks every root file's cluster chain
  through the FAT and reports first cluster, reachable chain length and
  the length expected from the size - `OK` or `BAD` per file:

  ```
  BOOT.BPUN   CL 00000002 LEN 00014 EXP 00014 OK
  TEST.TXT    CL 00001812 LEN 00014 EXP 00014 OK
  HDD         CL 00000011 DIR
  CHECK DONE
  ```

  LEN and EXP are in CLUSTERS: LEN is the chain length actually
  reachable through the FAT, EXP is what the size field demands
  (ceil(size / cluster bytes) - e.g. 46566 bytes on a 32 KB-cluster
  card = 2). A chain that hits a free entry, an out-of-range pointer
  or a loop, or whose length disagrees with the size, is flagged
  BAD - exactly the damage a wrong FAT write leaves behind. Read-only.
- `8` - BLOCK: dump **1-kiloword block N of the target file**, typed in
  decimal, WITHOUT buffering the file. ND-120 block framing: 1 block =
  1024 x 16-bit words = 2048 bytes = 4 SD sectors, and block N starts at
  `file_first_sector + 4*N`. The filesystem reader stops at the
  directory match (it never streams the file), the 4 sectors are read
  one at a time and dumped, so a 75 MB image costs exactly what a 7 KB
  one costs - which is the point: `2` cannot look past 64 KB at all.

  ```
  # 8
  BLOCK NUMBER, DECIMAL, THEN CR: 100
  CARD: SDHC
  FS: FAT16
  FILE: FOUND
  AT SECTOR 00000231
  000000: 90 00 90 01 90 02 90 03  90 04 90 05 90 06 90 07 
  ...
  LENGTH: 000000002048 BYTES
  DONE
  ```

  `AT SECTOR` is the absolute sector the block was read from, in hex.
  The command refuses with `ERROR: BLOCK OUT OF RANGE` when the file is
  shorter than `(N+1)*2048` bytes - those sectors belong to another file
  and reporting them as this file's data is the confusion this tool
  exists to remove. **The `first sector + 4*N` addressing assumes the
  file occupies consecutive sectors**, which is how these images are
  written; `9` is how that assumption gets checked.
- `9` - SECTOR: dump one **absolute SD sector**, number typed in
  decimal, with the FAT not consulted at all. This is what separates
  "the directory entry points somewhere wrong" from "the card really
  holds zeros there" - through `2` the two look identical. It works on a
  card whose filesystem does not mount (no `FS:` line is printed and no
  mount is required), and the dump is 512 bytes.
- `R` - RANGE: read a run of **consecutive blocks** - start block and
  count, both typed in decimal - and report whether the run completed
  cleanly. Nothing is dumped and nothing is buffered: the same 4-sector
  block loop is re-armed one block further on, and only a 16-bit word
  checksum and a block counter move. This is the case that matters for
  SINTRAN segment handling, which is the first thing on the ND-120 that
  reads many blocks in a row; everything validated before it read a
  single block.

  ```
  # R
  START BLOCK, DECIMAL, THEN CR: 7
  BLOCK COUNT, DECIMAL, THEN CR: 70
  CARD: SDHC
  FS: FAT16
  FILE: FOUND
  READING BLOCK RANGE AT SECTOR 000000BD
  AT BLOCK 00000040
  BLOCKS READ 00000046
  SECTORS READ 00000118
  CHECKSUM 00008C01
  CYCLES 000BB3C8
  RESULT: PASS
  ```

  (Those are the exact numbers `make -C sim test-block` produces against
  the simulated card - 70 blocks = 280 sectors = 143360 bytes.)

  Every number after a label is 8 **hex** digits. `CYCLES` counts the
  27 MHz system clock while sectors are actually moving (the counter is
  stopped around every console line), so seconds = CYCLES / 27000000.
  One `AT BLOCK` progress line is printed after each completed group of
  64 blocks (128 KB) - at 9600 baud a line per block would cost more
  time than the reading does. A run of 64 blocks or fewer therefore
  prints no progress line at all.

  Cost of a long run: the simulated card needs 2741 cycles per sector
  (101 us at 27 MHz, 4-bit bus), so **1000 blocks = 4000 sectors takes
  about 0.41 s of card traffic**, plus about 0.28 s for the 15 progress
  lines at 9600 baud and the one-off card init and directory scan - a
  couple of seconds all told, which is a practical thing to run on
  hardware. A real card adds read latency the model does not have, so
  treat 0.41 s as a floor, not a prediction.

  The checksum is `sum = rotate_left(sum,1) + word` over every 16-bit
  big-endian word. The rotate is not decoration: blocks are 1024 words,
  so with a plain sum a block read from the wrong place would cancel out
  in 16 bits for any position-linear content, and the checksum would not
  notice. It is a data-integrity indicator, not a CRC.

  On the **first card read error the run stops** and names the exact
  place before summarising. This is the output of the simulation gate's
  injected-failure case, where the card model is told to stop sending
  read data one sector into the run:

  ```
  READING BLOCK RANGE AT SECTOR 000000A1
  ERROR: SD READ FAILED
  AT SECTOR 000000A1
  AT BLOCK 00000000
  BLOCKS READ 00000000
  SECTORS READ 00000000
  CHECKSUM 00000000
  CYCLES 001E86FE
  RESULT: FAIL
  ```

  The error is raised by `sd_writer`'s own read watchdog (1000000 sdclk
  ticks, about 74 ms at 13.5 MHz), so a card that simply goes quiet is
  caught rather than hanging the tool.

  Ranges that reach past the end of the file are refused with
  `ERROR: BLOCK OUT OF RANGE`, using the same arithmetic as `8`, and the
  same contiguous-file assumption applies.
- `N` - set the target file name from the console, up to 12 characters,
  terminated by CR. Lower case is folded to upper case. The reader
  matches **root-directory entries only** and compares the name
  **length-exactly** (case-insensitively), so `WD0.IMG` finds `WD0.IMG`
  and nothing else. Empty at power-on: the compile-time `FILE_NAME`
  parameter (`BOOT.BPUN`) is used until `N` is pressed.
- `H` - detailed help; any other key reprints the menu.
- `S1` or `S2` button - full reset.

Type the number or name only AFTER its prompt has appeared, and one
character at a time: the UART has no receive buffer, and each typed
character is echoed before the next one can be read, so anything that
arrives while the prompt or the echo is still going out is lost. A
human typist is slow enough; a script must pace characters (~0.1 s
apart, the same pacing every other console on this board needs).

**Write-capable build only** (see below) - `3` COPY the target file over
`TEST.TXT` (in place when the allocation fits, otherwise `sd_fat_rewrite`
frees the old chain and allocates a fresh contiguous one); `4` WRBLK1
writes a counter pattern (1024 big-endian words, `word[w] = w`) into 1KW
block 1 of the target file; `6` WRITE SPEED rewrites `IO.DAT` with 1000
1KW blocks in CMD25 bursts and prints `WRITE NNNNN KB/S`; `7` READ SPEED
reads it back in CMD18 bursts and prints `READ NNNNN KB/S` (refuses with
`ERROR: IO.DAT WRONG SIZE - RUN 6 FIRST` until `6` has run).

Every command is a complete SD re-init, so the card can be swapped
between commands, and this restart path is exactly the future
device-400 "tape rewind". Nothing hangs without a diagnosis: a
watchdog (10 s) aborts a dead card / stuck read with an `ERROR:` line
and the menu `SD:` status shows `NOT CHECKED` / `NO CARD` / `ERROR` /
`OK`.

LEDs (active low): `0` alive, `1` FS mounted, `2` file found,
`3` command done, `4` file truncated (>64 KB), `5` error.

## Read-only by default

`src/sd_fat_test_config.vh` defines `SDFAT_TEST_READONLY`, and that is
the DEFAULT for every build of this project. The tool is pointed at
cards whose contents are already suspect, and a bitstream that can write
is a bitstream that can destroy the evidence being collected.

With the define in place:

- menu `3`, `4` and `6` are not offered and answer `NOT IMPLEMENTED`
  when typed anyway;
- `sd_fat_rewrite` (the FAT surgeon) and the speed tests are not
  compiled in - `SDFAT_NO_REWRITE` removes them through the dependency
  chain in `../../../SD-FAT/circuit/sd_fat_features.vh`;
- the `sd_writer` engine's `rd_mode` input is tied to a constant 1, so
  its CMD24/CMD25 paths have no reachable driver at all. The engine
  itself stays: its READ side is what serves `5`, `8`, `9`, `R` and the
  LIST free-space scan.

The simulation gate `make -C sim test-block` asserts all of this,
including that no CMD24 or CMD25 ever reaches the card model.

To build the write-capable tool, comment the `define out in
`src/sd_fat_test_config.vh` (or, for a one-off,
`make SDFAT_FEATURES="-DSDFAT_TEST_WRITE_ENABLE"`). The write-side
simulation gates pass that same define, so the header stays the single
source of truth.

## Card preparation

Full guide incl. formatting, payload choices and the first-run sanity
sequence: CARD-SETUP.md in this directory. Short form:

```bash
# whole-card FAT16 - avoids the vendored core's FAT32 16-bit
# first-cluster limitation; 1 sector/cluster keeps it a REAL FAT16
sudo mkfs.vfat -F 16 -n ND120 /dev/sdX
mcopy -i /dev/sdX Verilog/runSim/INSTRUCTION-B.BPUN ::BOOT.BPUN
# COPY target: must exist, any size (COPY reallocates it when needed)
printf 'test\n' > TEST.TXT
mcopy -i /dev/sdX TEST.TXT ::TEST.TXT
# speed-test target for menu 6/7: same rule, any size
printf 'io\n' > IO.DAT
mcopy -i /dev/sdX IO.DAT ::IO.DAT
# files must be in the ROOT directory with plain Archive attribute
```

Verify the dump on the host with `xxd BOOT.BPUN` (spot-check the
first/last 64 bytes and the LENGTH line).

## Build and load (OSS flow)

```bash
make          # yosys -> nextpnr-himbaechel -> gowin_pack -> build/sd_fat_test_top.fs
make load     # volatile load into SRAM (fast iteration)
make flash    # persistent: writes the config flash
```

The Makefile finds oss-cad-suite by itself (default `~/oss-cad-suite`,
override with `make OSS_CAD=/path`). Console: 9600 8N1 on the BL616 USB
serial; if its `TangNano20K />` CLI answers instead of the menu, type
`choose uart` once to switch the chip into UART-bridge mode. Loading
resets the USB device - reconnect the terminal afterwards.

Resource check (GW2AR-18): 32/46 BSRAM (the 64 KB buffer), Fmax
~77 MHz against the 27 MHz crystal - comfortable.

### USE_4BIT - SD bus width (speed switch)

Top-level parameter in `src/sd_fat_test_top.v` (speed ladder rung c,
see the "Speed facts" section of `Verilog/docs/sd-cmd18-block-gap-research.md`):

| Setting | Data wires | Bulk transfer speed (sim) | When to use |
|---|---|---|---|
| `USE_4BIT = 1` | DAT0-DAT3 | ~5.9 MB/s write, ~6.4 MB/s read | THE production setting - full speed |
| `USE_4BIT = 0` | DAT0 only | ~1.6 MB/s | diagnosis / boards with only DAT0 wired (e.g. some PMODs) |

Only the data payload widens: commands, responses, CRC status and busy
signalling stay on their single lines in both modes, and the card is
switched per-operation (ACMD6), so the setting is safe to flip freely.
The FAT mount/scan path (sd_file_reader) always runs 1-bit; bulk data
(speed tests, CHECK/COPY/WRBLK1 FAT and payload traffic through
sd_writer) follows this switch.

Hardware status: **4-bit works on this board and is the default**
(`USE_4BIT = 1`). Measured 12-JUL-2026 on a real 32 GB SDHC FAT32 card:
WRITE 3418 KB/s, READ 5981 KB/s, and the full FAT walk (LIST freescan,
CHECK over a 75 MB image) over 4-bit as well.

The board wiring question is settled - all four data lines are routed
from socket J7 to FPGA pins 84/85/80/81, with 10K pull-ups R53-R57. The
schematic table and its evidence are in
`Verilog/fpga/tang-nano-20k/doc/SD-SLOT-WIRING.md`.

(An earlier 11-JUL-2026 note here said 4-bit had FAILED its first
silicon run and was parked at 0. That was true for one day. Three
silicon-only bugs were then found and fixed - the nested-ternary pad
idiom that yosys collapsed to an always-on OBUF, a mount reader parked
mid-CMD17, and an RCA snooped off the CMD line instead of taken from
the reader's CMD3 export. The speed plan these rungs came from,
`Verilog/docs/sd-speed-plan.md`, was deleted 28-SEP-2026 - git history.)

## Simulation (run BEFORE hardware, in this order)

```bash
cd sim
make test-dumper     # iverilog unit tb (seconds)
make test-block      # iverilog: streaming BLOCK/SECTOR dumps + read-only
                     # gate, ~2 min - the gate for the diagnostic commands
make test-verilator  # Verilator full-system test (~2 min) - the hardware gate
make test-system     # same plan in pure iverilog (SLOW: 30-60 min, manual)
```

`test-block` builds its own card image (`make_block_image.sh`:
`blockdump.img`, FAT16, 1 sector/cluster) whose `BIG.BPUN` is 327680
bytes - five times the dump buffer, so command `2` cannot reach it at
all. Big-endian word *w* of the file holds `w mod 65536`, so every word
carries its own position and a block read from the wrong place changes
both the dump and the checksum. The bench sets the file name from the
console, dumps block 100 (file byte 204800) and checks every one of the
2048 bytes, takes the file's first absolute sector out of the LIST
column, dumps that same sector by absolute number and requires the two
to agree, then reads **70 consecutive blocks (280 sectors)** with `R`
and requires the reported block count, sector count and checksum to
match values it computes from the image model - plus the read-only
assertions above, the progress-line rule, and both out-of-range
refusals.

**Interactive console** - drive the menu yourself against the simulated
board (same FAT16 image), before any hardware exists:

```bash
make console         # from the project root or from sim/
```

Your terminal becomes the UART: the banner and menu appear, the menu
keys execute live, `ESC` exits the simulation. (The console build is
write-capable - the Verilator flow passes `SDFAT_TEST_WRITE_ENABLE` so
its plans can exercise the write paths.)
`make help` (project root and `sim/`) lists every target.

Both system tests drive the menu like a terminal user against a real
FAT16 image (`make_test_image.sh`: mkfs.vfat + mcopy, payload
`Verilog/runSim/RTC.BPUN` served as `BOOT.BPUN`) and verify the dumped
bytes against the payload file byte-for-byte, plus the LIST output and
the SD status lines. Verdict line: `TB_RESULT: PASS`.

`test-dumper`, `test-block` and the `test-verilator*` plans are
registered in the global `make test` registry
(`Verilog/tests/run_all_tests.sh`); `test-system` is the manual
pure-iverilog equivalent of `test-verilator` (iverilog is ~1000x slower
than Verilator on this design).

## Structure

```
Makefile              OSS build (sources the SD/FAT lib from ../../../SD-FAT)
src/sd_fat_test_config.vh  READ-ONLY switch (default) - see above
src/sd_fat_test_top.v menu FSM, 64 KB buffer, SD status tracking,
                      streaming block/sector dumps, multi-block range
                      read with checksum, console number and file-name
                      entry, COPY + 1KW-block write control
src/status_printer.v  fixed status/menu lines -> shared uart_tx
src/hex_dumper.v      hex + octal-words + LENGTH + DONE formatter
src/buf_text_printer.v raw buffer printer (LIST output)
src/uart_tx.v/uart_rx.v  9600-8N1 (copies of the sdram-test ones)
src/nano20k_sd.cst    pins: clock 4, S1 88, UART 69/70, LEDs 15-20,
                      SD CLK=83 CMD=82 DAT0=84 DAT1=85 DAT2=80 DAT3=81
sim/                  testbenches + SD card image build scripts
                      (make_test_image.sh, make_block_image.sh)
```

Baud note: 9600 8N1 for bring-up (matches every other board test);
the `BAUD` parameter takes 115200 later without further changes - the
testbenches already run the same logic at 1 Mbaud.
