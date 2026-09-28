# nd_storage - multi-client storage facade specification

Spec for the generic storage library layer (lives in Verilog/SD-FAT/)
that serves ALL ND-100 bus devices (tape-400, floppy, later SMD/HDD)
from one microSD card + the spare SDRAM. Written for the SD-FAT
workstream to implement; the device side (ND-BUS-DEVICES/) is already
built against the client contract in section 4.

Status: the contract (client port, no-queue arbiter, write-through before
done) is what the built stack implements. Two things in the first version of
this spec were replaced by owner decision and are corrected below: images are
no longer preloaded into SDRAM (04-AUG-2026, block cache instead), and files
no longer have to be contiguous (07-AUG-2026, the engine walks the FAT chain).
The as-built design is `Verilog/docs/nd-storage-design.md`.

Companion docs: Verilog/docs/nd-storage-design.md (as-built design),
Verilog/docs/sd-bpun-device-plan.md (SD pins, tape-400 facts),
Verilog/docs/nd100-bus-dma.md (bus/DMA protocol).

## 1. The one-sentence contract

nd_storage gives N independent client ports, each bound to one file on
the FAT card; a client reads and writes its file in 2048-byte blocks
(1 kiloword = 4 SD sectors); disc clients are served through a shared
block cache in SDRAM, tape and floppy clients read straight from the
card (DIRECT); every write is written through to the card before the
client sees done.

## 2. Placement and layering rules (from the master plan)

- Everything generic lives in Verilog/SD-FAT/ (this module, the FAT
  core, the sector engine). Board glue (pins, clocks) stays in
  fpga/<board>/. NOTHING storage-related ever goes into DELILAH-CPU/,
  DECODE-GateArray/ or CPU-BOARD-3202/.
- One physical SD slot, one sector engine, ONE nd_storage instance.
  The devices in ND-BUS-DEVICES/ are the clients.
- SDRAM is shared with the ND-120 main memory: fixed partition, low
  region = CPU memory (as today), high region = the storage region
  (one staging line + the shared cache pool).
  The CPU port of the SDRAM controller has ABSOLUTE priority;
  nd_storage takes leftover cycles only.

## 3. Concurrency model: no queue, one request per client

Decision (11-JUL-2026): there is NO request queue.

- Each client port carries AT MOST ONE outstanding request. The
  devices are single-threaded by construction: the tape streams
  sequentially, the floppy controller executes one command at a time,
  an SMD channel does one word/block chain at a time. A device that
  has issued req simply waits for done before issuing the next.
- A round-robin arbiter scans the client ports; among ports with a
  pending request it grants ONE, runs that block operation to
  completion (no preemption), then advances the scan pointer past the
  granted client.
- Worst-case wait for a client = (N-1) block operations. With reads
  served from SDRAM (microseconds) and only write-through touching
  the card (milliseconds), this is far inside every device's timing
  budget (the floppy's own emulated command delay is longer).
- Fairness: advancing the round-robin pointer past the winner makes
  starvation impossible.
- Consequence for the implementer: per client you need only a
  1-bit pending latch + the latched request fields. No FIFOs.

## 4. Client port (the contract the devices are built against)

All signals in the storage clock domain; the bus-device side runs in
the CPU sysclk domain - the CDC (clock domain crossing) is INSIDE
nd_storage (2-flop synchronizers on the strobes, data is stable while
the handshake crosses). N_CLIENTS is a parameter, 8 as built:
client 0 = tape-400, 1-2 = floppy units, 3-5 = SMD units 0-2,
6-7 = Winchester units 0-1 (design section 1.3).

Per client c:

    // --- binding / mount ---
    open_req[c]      in   pulse: (re)open the file (find it, latch its
                          geometry - no data is moved)
    open_ok[c]       out  level: file open
    open_err[c]      out  level: file not found / FS error
    size_bytes[c]    out  [31:0] file size after open

    // --- block operations (2048-byte blocks within the file) ---
    req[c]           in   pulse: start operation (only when open_ok
                          and busy=0; nd_storage may IGNORE a req
                          while busy - the client must not pulse it)
    wr[c]            in   with req: 0 = read block, 1 = write block
    block[c]         in   [15:0] block number, 0-based within file
    busy[c]          out  level: request latched or in progress
    done[c]          out  pulse: operation complete (data transferred
                          AND, for writes, committed to the card)
    err[c]           out  valid with done: out-of-range block, SD
                          write failure, card removed

    // --- data: nd_storage masters the CLIENT's buffer ---
    buf_addr[c]      out  [9:0]  word address in the client buffer
    buf_wdata[c]     out  [15:0] read path: block data -> client
    buf_we[c]        out  write strobe into the client buffer
    buf_rdata[c]     in   [15:0] write path: client buffer -> block

Data-path rationale: every device core already owns a BRAM buffer
(the floppy's 1024-word interface buffer; the tape adapter's block
buffer). nd_storage therefore never stores payload; during a granted
read it streams the 1024 words of the block into the client's buffer
via buf_addr/buf_wdata/buf_we, during a write it reads buf_rdata
one word per cycle (address presented one cycle ahead, standard
synchronous BRAM timing). This port is ALREADY implemented on the
device side: see dbuf_addr/dbuf_wdata/dbuf_we/dbuf_rdata on
Verilog/ND-BUS-DEVICES/FLOPPY/circuit/ND_FLOPPY_PIO.v.

Handshake timing (read):

    req[c]      _/\_______________________________________
    busy[c]     __/------------------------------\________
    (grant)           ...arbiter wait...
    buf_we[c]   __________/-- 1024 words --\______________
    done[c]     ____________________________________/\____

Write is identical except buf_we is replaced by buf_rdata sampling,
and done fires only after the 4 SD sectors are written and the card
has acknowledged (write-through commits BEFORE done - the card is
always consistent, safe to pull at any idle moment).

## 5. Tape byte-stream adapter

The tape device consumes bytes, not blocks. That gap is closed by a
small adapter (part of the storage library, one per byte client):
nd_storage_tape_adapter holds one 2048-byte block buffer, exposes the
tape core's byte port (byte_req pulse -> byte_valid pulse + byte_data,
plus rewind), and behind the scenes issues sequential block reads on
its client port; rewind resets the block/byte pointers (no card
access until the next byte is asked for). EOF: byte_req past
size_bytes simply never answers valid, which leaves the tape's
ready-for-transfer flag low - exactly the C model's EOF behavior.

## 6. Storage region and block access (as built)

The first version of this section gave every client a fixed SDRAM slot,
streamed the whole file into it at open, and refused a file larger than
its slot. That was replaced on 04-AUG-2026 (owner decision: no image is
preloaded). Now:

- open_req: FAT-mount (reusing the sd_file_reader mount logic), find the
  file by its FIXED root name (parameter), latch size, first sector,
  first cluster and the volume geometry, then raise open_ok. No data
  moves at open; an image is limited only by the 16-bit block count
  (128 MB).
- Per client, CACHE_MASK selects CACHED (disc classes: SMD, Winchester)
  or DIRECT (tape, floppy). A cached block read is served from the
  shared, 4-way set-associative, LRU, write-allocate cache in the
  storage region; a miss fetches the block's 4 sectors from the card
  first. A DIRECT read fetches from the card into one shared staging
  line and serves from there.
- Block write = write-through: the 2048 bytes go to the card first
  (4 sectors), then to the region, then done.
- Card sectors are found by walking the file's FAT chain (per-client
  memo, so sequential access costs 0 or 1 FAT reads). Fragmented files
  are correct; an end of chain before the wanted block answers
  done+err.
- The SDRAM port used is the leftover-cycles device port (CPU absolute
  priority). The arbiter in nd_storage never holds the SDRAM port
  across blocks.

## 7. Error and hot-swap rules

- Card errors during write-through: done+err to the client; open_ok
  stays up (the SDRAM copy is intact); a status output pin/register
  reports the SD state for the board top to show on LEDs.
- Card removal is only detected at the next card access (a write, an
  open, a cache miss or any DIRECT read). Cached blocks keep reading
  from SDRAM.
- Re-inserting a card requires open_req again (same as the sd-fat-test
  per-command re-init, which doubles as tape rewind-to-card).

## 8. What NOT to build (v1 scope fence)

- No dynamic filenames, no directories, no create/delete - fixed root
  filenames per client.
- No request queue, no out-of-order completion, no per-client
  priority levels (round-robin only).
- (Two items of the first scope fence were lifted: tag-based caching
  was built for the disc classes on 04-AUG-2026, and FAT-chain walking
  replaced the contiguous-files rule on 07-AUG-2026.)

## 9. Acceptance tests (each self-checking, registered in
tests/run_all_tests.sh per the standing rule)

1. Unit tb, sd_card_model + SDRAM model: open two clients, interleave
   read requests, verify round-robin order and data integrity.
2. Write-through: client writes block k; verify SDRAM copy AND the
   card model image both updated before done; fsck-style recheck of
   the card image (the sd-fat-test sims already do this).
3. Concurrency: all 4 clients pending simultaneously; verify each is
   served exactly once per round, no starvation, no cross-client data
   leak (distinct patterns per client).
4. Tape adapter: byte-stream a known image through the adapter,
   compare byte-for-byte; rewind mid-stream and verify restart;
   EOF behavior (no byte_valid past end).
5. Error: block out of range -> done+err without SD traffic; write
   failure injected in the card model -> done+err, SDRAM intact.
6. System: the floppy disk backend port wired to a client port
   (the disk_*/dbuf_* signals map 1:1) - sector read/write through
   the full stack against the card model. As built this is
   ND_FLOPPY_DMA's backend (`test-nds-floppy`), not ND_FLOPPY_PIO.
