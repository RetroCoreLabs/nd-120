# Winchester oracle traces

**Full path:** `Verilog/ND-BUS-DEVICES/WINCHESTER/oracle/`

Reference IOX traces for the Winchester controller, captured from a
**working** machine. They exist so a silicon or Verilator run can be diffed
against known-good behaviour instead of against somebody's memory of it.

These were regenerated from scratch more than once because the only copy
lived in a temporary directory that was deleted with the session. They are
committed now.

## `fsi-lifi-nd100x.trace`

The File System Investigator (FILSYS-INV-Q04) opening the Winchester, reading
the SINTRAN directory and listing the file names of user 0, captured from the
**nd100x C emulator** (`src/devices/winchester/device_winchester.c`, the model
with two units, the arm position per unit and the drive timing), which
performs this successfully end to end. 84 IOX accesses, most of them status
polls while an operation is running: the model keeps the card active for the
drive's time, so the FSI polls 060005 / 020005 many times before each
completion.

The opening sequence, which any working implementation must reproduce:

| # | Access | Meaning |
|---|--------|---------|
| 1 | `READ +4 -> 060000` | status at power-on: ON CYLINDER (b14), card identity (b13) |
| 2 | `WRITE +5 = 0` | control word, no activate |
| 3 | `READ +4 -> 060010` | on cylinder, finished |
| 4 | `WRITE +7`, `+3`, `+1` x2, `+7` | word count 0, block address 0, memory address 0/061100, word count 2000 |
| 5 | `WRITE +5 = 5` | GO, M0-Read, cylinder 0 sector 0, 1024 words |
| 6 | `READ +4 -> 060005` (repeated) | active while the sectors pass |
| 7 | `READ +4 -> 060011` | finished, interrupt enabled |
| 8 | `READ +0` x2 -> `063100`, `0` | memory address moved on by 2000, low half first |
| 9 | `WRITE +7 = 1616`, `WRITE +5 = 060105` | M4 seek 910 cylinders out |
| 10 | `READ +4 -> 020005` (repeated) | active and NOT on cylinder while the heads travel |

Then the directory reads at 910/2/4 and 910/2/2, a 3-cylinder seek to 913,
and the read at 913/2/4.

Why on cylinder at power-on: a real 3041 with a Micropolis 1325 read 060011
after its first control word 000011, with no return to zero before it (the
DISC-TEMA start-up trace kept in RetroCore's
`Emulated.HW/ND/CPU/NDBUS/NDBusDiscControllerWinchester.cs`, "tested on a real
3041 controller with an Micropolis 1325 disk connected"). The manual says
master clear puts the heads on cylinder 0 (ND-11.015.01 sec 3.4.8 and 5.5).

### How it was captured

```bash
cd ~/repos/nd100x
cmake -S . -B build-wd -DND100X_ENABLE_ND500=OFF && cmake --build build-wd --target nd100x
cp WD0.IMG /tmp/WD0-copy.IMG
./build-wd/bin/nd100x --pipe --boot=bpun --image=images/FILSYS-INV-Q04.BPUN \
    --wd0=/tmp/WD0-copy.IMG --log=wd:debug 2> fsi-lifi-nd100x.trace
```

Answer `DISC-74MB-1`, unit `0`, `LI-FI`, then user number `0`. Run it from a
folder with no `nd100x.ini`, so nothing but the command line sets it up.

**Always use a copy of the image.** The FSI is read-only, but the SINTRAN
boot path (`20500&`) writes back to LBA 0.

## `fsi-lifi-nd100x-old-model.trace`

The same FSI run captured earlier from the OLDER nd100x model
(`deviceWinchester.c`, `ND100X_WD_DEBUG=1`). Kept because
`../sim/nd_winchester_rtz_tb.v` and the M7 note in `../circuit/ND_WINCHESTER.v`
cite its opening M7. That model read 020000 at power-on (NOT on cylinder), so
the FSI opened with an M7 return to zero (`WRITE +5 = 034005`), and every
operation ended after a flat delay. Do not diff a new capture against it; use
`fsi-lifi-nd100x.trace`.

## Comparing a capture against it

`Verilog/tools/wdtrace.py` decodes the Tang's on-chip trace ring and diffs it
against this file:

```bash
# first argument is the SILICON capture (5-hex-digit ring dump),
# second is this oracle file - not the other way round
python3 ../../../tools/wdtrace.py captured.txt fsi-lifi-nd100x.trace
```

Capture the silicon side with the committed console driver, which streams to
disk as bytes arrive (a one-shot ring dump piped through `tail` loses its
head - that mistake cost two capture attempts):

```bash
python3 ../../../tools/ndconsole.py --seconds 180 --out captured.txt 'LI-FI'
```

The ring packs FIVE record kinds, and reading it as read/write only produced
two wrong conclusions before it was noticed - a dump full of `C01xx` records
is not an empty ring, it is **foreign IOX**, another device's address going
past on the bus (`C0100`/`C0102`/`C0103` are octal 400/402/403, the paper
tape reader). See the decoder's own docstring and the `trace_rec` assignment
in `../circuit/ND_WINCHESTER.v`.

## Status values worth recognising

| Octal | Bits | Meaning |
|-------|------|---------|
| `060000` | b14,b13 | idle, on cylinder. Power-on state - NOT an error |
| `020005` | b13,b2,b0 | ACTIVE and NOT on cylinder: a seek (M4) or return to zero (M7) is moving the heads |
| `060005` | b14,b13,b2,b0 | on-cylinder, ACTIVE, interrupt enabled |
| `060011` | b14,b13,b3,b0 | on-cylinder, FINISHED, interrupt enabled |
| `060010` | b14,b13,b3 | on-cylinder, finished, interrupt disabled |
| `020000` | b13 | idle, NOT on cylinder: the older model's power-on value; a real 3041 reads on cylinder |

Bit 13 is always 1 on the 3041 (controller identity), which is why every
healthy value starts with `02` or `06`.
