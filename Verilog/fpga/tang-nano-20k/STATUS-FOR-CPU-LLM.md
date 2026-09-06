# STATUS / TEST REQUEST for the CPU session - Tang `400$` hard hang

Copy-paste this whole file to the other LLM.

---

## The ask

On the Tang Nano 20K (real hardware, `FPGA_FF_MODE`), the OPCOM command `400$`
(BPUN tape load from device 400) **hangs the CPU hard**. The identical RTL
completes the same load in Verilator. **Storage has been eliminated as the
cause - please test whether this is a CPU/interrupt problem.**

## What is MEASURED on the board (not inferred)

1. **`400$` echoes `400$`, then 60 s of total silence.** No `?`, no prompt, no
   further output.
2. **ESC does NOT recover it.** 6 ESCs then CR returned **zero bytes**. Only S1
   (Master Clear) recovers. This is different from the `20!`/HELP hang that
   Ronny CAN escape with repeated ESC.
3. **The load ACTUALLY WORKS.** After `400$` hung, S1 (which resets the CPU but
   preserves SDRAM), I dumped **all 23,244 words** of the loaded image over the
   console and diffed them against the card's BPUN file
   (`CONFIGURATIO-C08.BPUN`, 23244 words at load address 0):

   ```
   words compared 23244 of 23244 (100.0% of the image)
   21 of 23 1K-blocks: OK
   RESULT: 14 of 23244 words differ  (23,230 correct)
   ```

   So the SD -> tape -> CPU byte path delivered the whole file into memory.
   **The bytes are not the problem.**

4. The 14 outliers, for completeness. **12 of 14 are addresses where the FILE
   holds 000000 but memory holds a leftover non-zero** (the same program had
   been run earlier via `20!`, and S1 does not clear SDRAM):

   ```
    addr     file    memory
    045226  000000  000026
    045506  012313  001400
    045507  076161  001001
    045666  000000  000026
    045670  000000  055314     <- note: 055314 = this BPUN's own word count
    045671  000000  000307
    052514  000000  000400
    055102  000000  000307
    055103  000000  000510
    055106  000000  000400
    055107  000000  000002
    055110  000000  000001
    055111  000000  050040
    055112  000000  045733
   ```
   **NOT yet explained - do not assume these are the cause.** They may be the
   loaded program's own variables surviving from the earlier run, or words the
   load never wrote. Unresolved.

5. **The CPU's BPUN loader and its checksum arithmetic WORK on silicon.**
   Earlier, with a genuinely corrupt `BOOT.BPUN` on the card, `400$` completed
   and printed `?` - the correct `ILLEG` branch. Microcode reference:
   `/mnt/e/Dev/Ronny/nd120uc/source/nd-120-delilah-L-from-K.uc:6212`
   ("ALL WORDS ARE PLACED IN MEMORY" -> read checksum -> `XORAB` -> `ILLEG` on
   mismatch). With the file fixed, the checksum no longer fails - it hangs
   instead.
6. Storage subsystem is healthy: `sd_status = OK` (the mount FSM only reaches
   `M_OK` via `M_SCAN -> M_LOAD -> M_PARK -> M_CHK`), and the board LEDs confirm
   the CPU asked the tape for a byte and bytes were served.

## The hypothesis we want you to test (UNVERIFIED)

**The tape-400 level-12 interrupt storm.**
See `Verilog/docs/BUG-tape400-sd-level12-storm.md`.

`400$` is known to storm level-12 interrupts from the tape device. In Verilator
that only makes the sim slow - the tests still complete. **On real silicon a
storm could livelock the CPU**, which would look exactly like this: the load
data all arrives, and the CPU never returns to the prompt.

This is a guess. It has NOT been measured. Please confirm or kill it.

Related known CPU issues that may or may not be the same family - your call:
- The RUN-area level-14 livelock (`MPIE` mask never reloaded on the switch to
  14; `PLINT` early-return skips the `PICF2 LMSK` reload).
- `0!` hangs and `HELP` hangs on the Tang as well - neither touches the tape.

## Reproducing it (exact recipe - the console is fussy)

Board attach after every replug (the Tang was **busid 2-3**; the Basys3 is ALSO
`0403:6010` at busid 1-7, so do **not** select by VID:PID):
```
powershell.exe -NoProfile -Command "usbipd attach --wsl --busid 2-3"
sudo chmod 666 /dev/bus/usb/001/006       # bus path CHANGES per attach
sudo chmod 666 /dev/ttyUSB0 /dev/ttyUSB1
```

Build and load - **the OSS flow (yosys/nextpnr) CANNOT PnR** (22 combinational
loops in `CGA_INTR ... IRQ_REG.RQBIT_*`, proven pre-existing), so use Gowin:
```
cd Verilog/fpga/tang-nano-20k
make gowin VARIANT=slow
make load-gowin            # volatile SRAM - a power cycle wipes it
```

Console `/dev/ttyUSB1` @ 9600 8N1. **Input MUST be paced ~0.3 s/char** or MOPC
silently drops characters - an unpaced `0<77` returns literally nothing.
Memory dump syntax is `n<y` (start, end, octal).

To re-take the pristine dump: `400$` (hangs) -> **press S1** -> do NOT run
`20!` (it scribbles its own scratch into memory) -> dump. Tool:
```
cd Verilog/tools
./check_bpun_memory.py --bpun ../runSim/CONFIGURATIO-C08.BPUN --commands
./check_bpun_memory.py --bpun ../runSim/CONFIGURATIO-C08.BPUN --dump cap.log
```

## Reference: the same thing WORKS in Verilator

```
cd Verilog/runSim
make run          # 400$ boots INSTRUCTION-B off a simulated SD card
make run-config   # CONFIGURATIO-C08
make run-fs       # FILSYS-INV-Q04
```
`400$` completes there with **RAM starting empty** (the harness's BPUN
pre-deposit is now gated off under `ND120_SD_STORAGE` - it used to hide exactly
this class of bug).

## Things that are NOT bugs - please do not re-chase

- **`?` after `400$`** = BPUN checksum error, and the machine was RIGHT: the
  card's file was corrupt. Fixed.
- **`400$` not auto-starting the program.** All three BPUNs have
  `execute = 000000` = action code 0 = "load only, do not start". `20!` is the
  intended start. This explains a *clean* load returning to the prompt; it does
  **NOT** explain the hard hang.
- **Words 1..15 reading `000001..000017`** - that address ramp is the program's
  real content.
- **Contiguity** - `sd_file_reader.v:37` walks the FAT chain; the contiguity
  rule is `nd_storage` v1's own contract and Ronny's card already passes it.

## Ownership

INSTRUCTION-B's `RUN` is yours - I have not touched it. CONFIGURATION-C08's
`RUN` (a device probe, `make run-config`) is a different command and is fine.

## Full paths to everything referenced

- Handoff (storage side, full detail):
  `Verilog/fpga/tang-nano-20k/HANDOFF-tang-sd-tape-boot.md`
- This file:
  `Verilog/fpga/tang-nano-20k/STATUS-FOR-CPU-LLM.md`
- Memory-dump comparison tool:
  `Verilog/tools/check_bpun_memory.py`
- Level-12 storm bug:
  `Verilog/docs/BUG-tape400-sd-level12-storm.md`
- Tang board top:
  `Verilog/fpga/tang-nano-20k/src/ND120_TANG20K_TOP.v`
- Tape SD source:
  `Verilog/ND-BUS-DEVICES/TAPE-400/circuit/nd_storage_devices.v`
- Tape device:
  `Verilog/ND-BUS-DEVICES/TAPE-400/circuit/ND_TAPE_400.v`
- Microcode (checksum/ILLEG branch):
  `/mnt/e/Dev/Ronny/nd120uc/source/nd-120-delilah-L-from-K.uc:6212`
- BPUN format + loader:
  `Verilog/runSim/Run120.cpp`
- BSRAM budget:
  `Verilog/fpga/tang-nano-20k/BSRAM-BUDGET.md`
