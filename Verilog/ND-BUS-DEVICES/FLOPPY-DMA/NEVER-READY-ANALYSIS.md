# "Device 156362 Never Ready. Status:000003" - root cause (FIXED)

Status: the RTL fix is in the tree (commit `ae2cfa9`, `ND_FLOPPY_DMA.v`
`E_FINAL` and `disk_media_fmt`). This file keeps the diagnosis; the full
analysis (register map, failure narrative, fix plan F1-F4) is in git history.
The verified register layout of the 3112 is
`Verilog/docs/floppy-3112-register-spec-ND-11.021.md` - use that, not the
nd100x C model, which mixes up the two status words (see the header of
`circuit/ND_FLOPPY_DMA.v`).

## Symptom

runSim, `1560&` boot of the TPE diskette (210523I01): the boot byte-server
loads and starts the program ("No notes exist."), but the TPE monitor never
prints its banner and, after a long software timeout, prints

    Device 156362 Never Ready.   Status:000003

## Decode

- `000003` cannot be a hardware STATUS 1 read (bit 15, dual density, is
  always 1). It is STATUS WORD 2 (the format word): 1024 bytes/sector with
  double-sided and double-density both 0 - a combination no real controller
  produces. It was the old RTL echoing the command-word format bits into
  CB+7, where the real READ FORMAT reports the media (017 for the 1,261,568
  byte TPE image).
- `156362` is not an IOX address (the IOX field is 11 bits). Most likely it
  is a memory address: CB+6 (STATUS 1) of a command block at 156354. Not
  checked against the trace.

## Root cause

1. The old RTL wrote the status words back to the command block (CB+6..CB+11)
   BEFORE its completion delay, while still busy, and never wrote them
   again. The driver waits on the memory copy of STATUS 1 (bit 3 ready, bit 2
   busy clear), so it saw "not ready" forever. The C model re-writes CB+6
   at completion (its `ReadEnd`). Fixed by `E_FINAL`: re-write CB+6 with
   READY=1 / BUSY=0 at completion.
2. READ FORMAT (function 0x22) was a stub and STATUS 2 an echo of the
   command word. Fixed by a real `s_status2` register loaded from the new
   `disk_media_fmt` input.

## Still open

`Verilog/docs/floppy-review-findings.md` ("NEVER-READY-ANALYSIS.md
verification"): a control-word write (autoload / execute) during a
transfer is still dropped, where the C model always acts on it.
