# SD CMD18 inter-block gap - research notes (12-JUL-2026)

Background: on Tang Nano 20K hardware, CMD18 multi-block READ failed
(menu 7 "SD READ FAILED") while CMD25 multi-block WRITE ran at
1575 KB/s and CMD17 single reads passed - all three green in sim.
Root-cause theory: the burst-read FSM re-arms start-bit detection too
late for a real card that streams blocks back-to-back. This research
confirmed the theory and collected the proven fixes. The speed facts
from the same work (formerly in sd-speed-plan.md) are in the last
section below.

## Spec timing facts (SD Physical Layer FULL spec v3.01)

The simplified spec blanks section 4.12 "Timings"; numbers below are
from the full spec (Part_1_Physical_Layer_Specification_Ver3.01).

- Table 4-51 (sec 4.12.4): NAC min = 2 SD clocks, and the definition
  explicitly covers the gap BETWEEN data blocks of a multiple-block
  read: "Period between an end bit of command and a start bit of read
  data, and period between data blocks." A card may legally start
  block N+1 two clocks after block N's end bit.
- Figure 4-29 (sec 4.12.1) shows the multiple-block read timing:
  end bit, a few push clocks, immediately the next start bit.
- Sec 4.12.5.2: the 8-clock minimum block gap exists only in UHS-I
  tuning mode. At default/high-speed only the 2-clock minimum holds.
- Sec 4.4 "Clock Control": the HOST may lower or STOP sdclk at any
  time "to control the data flow (to avoid under-run or over-run
  conditions)". Only obligation: 8 clocks after the last transaction
  end bit. Pausing sdclk mid-transfer legally freezes the card.
- CMD12: card stops driving DAT two clocks after the CMD12 end bit
  (NSD = 2). The spec itself says issuing CMD12 at exact timing "is
  difficult to control" and recommends CMD23 (Set Block Count) - but
  CMD23 is optional on non-UHS cards (SCR CMD_SUPPORT flags) and
  ACMD23 is a WRITE pre-erase hint only, it does not bound reads.

Field evidence: LiteSDCard issue #22 documents the same symptom class
(multi-block read timeouts at full clock, single-block fine); root
causes were host-FSM re-arm races, fixed in the core - not card
misbehavior.

## How proven cores handle the boundary

- LiteSDCard (enjoy-digital/litesdcard, phy.py) - BSD-2-Clause, the
  architecture to copy:
  * Start-bit detection is a CONTINUOUS sampler, not an FSM state:
    start = (all DAT lines == 0) - in 4-bit mode the start bit is
    driven on ALL FOUR lines (spec 3.6.1), so DAT[3:0]==0 is a robust
    start-nibble match. A run latch + bit counter frame the block.
  * sdclk is emitted only while the FSM requests bus activity; on
    consumer backpressure the clock pauses and the card freezes.
    Flow control by clock gating - re-arm latency becomes irrelevant.
  * CRC16 runs concurrently per line and is compared bit-serially
    during the 16 CRC clocks; the data stream is never stalled.
- ZipCPU sdspi/SDIO (GPL-3.0 - ideas only, never code): free-running
  24-bit sampling shift register; io_started latches on DAT0 low and
  is cleared only by reset/tx/rx-disable; framing by counting; no
  consumer backpressure into the receiver; CRC by remainder==0; a
  clock generator that can halt sdclk between blocks.
- MiSTeryNano / WangXuan95 lineage (GPL): never issue CMD18/CMD25 at
  all - one CMD17/CMD24 per sector. Instructive anti-pattern: a
  64-clock RTAIL wait after each block, which would swallow the next
  start bit in any real CMD18 stream.

## Tang Nano 20K SD slot facts

Pins, the on-board pull-ups (R53-R57), the CLK series resistor (R49),
`PULL_MODE=NONE`, the BL616 sharing and the DAT2 edge-header trap are in
`Verilog/fpga/tang-nano-20k/doc/SD-SLOT-WIRING.md`.

## Recommendations adopted for our sd_writer fix

1. Design for a 2-clock inter-block gap (spec minimum).
2. Continuous start-bit sampler decoupled from the block FSM
   (DAT[3:0]==0 in 4-bit, DAT0==0 in 1-bit), framing by bit counter.
3. PRIMARY FIX: pause sdclk at block boundaries / whenever the
   consumer is not ready - we generate the clock, the card waits.
   8 clocks after the final end bit before stopping for good.
4. CRC16 concurrent, never a blocking post-block state.
5. CMD12 sent after the last wanted block, receiver tolerates and
   discards a partial trailing block (card releases DAT after NSD=2).
6. License hygiene: only LiteSDCard is vendorable (BSD-2); everything
   else in this survey is GPL-encumbered - patterns only, own RTL.

## Speed facts (11/12-JUL-2026 speed work, formerly sd-speed-plan.md)

- Where the time goes on a single-sector write: at a 2.7 MHz bit clock one
  sector is 1.52 ms of data on the wire + 0.04 ms of command overhead + about
  2.2 ms of card programming busy = 3.74 ms. The programming busy dominates,
  so a faster clock alone gives less than 2x; CMD25 multi-block write hides
  the busy across a burst (SD Speed Class ratings are defined that way).
- 25 MHz default speed is mandatory on every card, so our 13.5 MHz data clock
  needs no CMD6 and depends on no card feature.
- CMD6 mode 1 (argument 0x80FFFFF1, a 512-bit status block on DAT, an 8-clock
  switch window) unlocks 50 MHz high speed. Not built: the 4-bit bus at
  13.5 MHz already exceeds every device budget in nd-storage-design.md.
- Multi-block write CRC status and busy stay on DAT0 in every bus width.
  Block-gap busy timeout budget: 250-500 ms.
- Measured on the Tang (sd-fat-test menus 6/7, 12-JUL-2026, 32 GB SDHC FAT32,
  4-bit): WRITE 3418 KB/s, READ 5981 KB/s against a 137 KB/s 1-bit baseline.
  The three silicon-only bugs that had to be fixed first are in
  `Verilog/fpga/tang-nano-20k/sd-fat-test/README.md`.
