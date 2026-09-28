# nd_storage - RTL design and implementation plan

Status: BUILT and in use - SINTRAN III boots on the Tang Nano 20K from a
Winchester image on the SD card through this stack (24-AUG-2026). Written as
the plan of record on 11-JUL-2026, derived from nd-storage-interface-spec.md;
the decisions of the 11-JUL spec review are folded in.

**Two parts of the original plan were replaced after it was built. Read this
first - some sections below still describe the old model and say so:**

- **Nothing is preloaded any more (04-AUG-2026).** A mount only finds the file
  and latches its geometry. Disc clients (SMD, Winchester) are served through
  one shared block cache; tape and floppy are DIRECT (every request goes to the
  card). Image size is no longer bounded by a slot. See section 2.7.
- **Files no longer have to be contiguous (07-AUG-2026).** The engine walks the
  FAT chain on every access (section 2.2, "FAT-chain resolve"). The mount-time
  contiguity checker (section 2.4) is retired from every build and kept only
  as a diagnostic.

Build steps (each ended with a registered passing test; the per-step test
notes are in git history):

| step | what | gate |
|---|---|---|
| 1 | `nds_sync.v` + CDC word bridge | `SD-FAT/sim test-nds-cdc` |
| 2 | `nds_mem_model.v` + engine read path (round-robin arbiter, client front-ends, range check) | `test-nds-engine` |
| 3 | engine write path against the real `sd_writer` (card first, region second) | `test-nds-write` |
| 4 | `nd_storage_mount.v` + `nd_storage.v` top; the engine's client indices widened to 3 bits | `test-nds-mount` |
| 5 | `nd_storage_fatchk.v` contiguity gate (now a diagnostic only, see above) | `test-nds-fatchk-unit`, `test-nds-fatchk` |
| 6 | Verilator system gate: `nd_storage_vtop.v` + `test_nd_storage.cpp` (C++ card and mem models, clocks 27.03/23.04 MHz to stress the CDC) | `test-storage` |
| 7 | `nd_storage_tape_adapter.v` | `test-nds-tape` |
| 8 | `nd_storage_floppy_adapter.v` (targets `ND_FLOPPY_DMA`'s backend) | `test-nds-floppy` |
| 9 | storage device port in the SDRAM bridge (`ND_STORAGE_PORT`) | `fpga/tang-nano-20k/sdram-bridge/sim test-storage-port` |
| 10 | board wiring: the Tang build defines `ND_STORAGE_PORT` (`tang20k_defines.v`) and wires `nd_storage` in `ND120_TANG20K_TOP.v` | SINTRAN boots from the card |
| Phase 4 | shared block cache (`nd_storage_cache.v`) | `test-nds-cache`, `test-nds-cachepath` |
| FAT walk | runtime FAT-chain resolve in the engine | `nd_storage_tb.v` case d2 (reads byte-exact across a relocated cluster of `FRAG.IMG`) |

Facts from the build steps that still hold:

- **Never write the partial tail block of a file** whose size is not a
  multiple of 2048 bytes: the card writes would spill past the file's
  clusters into the next file. Tape is read-only; the floppy adapter refuses
  a write unless `(block+1)*2048 <= size_bytes`.
- Owner decisions 11-JUL: (i) the floppy adapter targets `ND_FLOPPY_DMA`'s
  backend, not `ND_FLOPPY_PIO` (`1560&` mass boot is the proven path; a PIO
  adapter is optional later work); (ii) SMD images are real-world size
  (75 MB), so SMD is served by the cache - no small-image shortcut.
- Step 9, the SDRAM bridge port: `ND_STORAGE_PORT` requires
  `ND_SDRAM_PACK16`. Device ops are granted exactly like refresh - the B_POST
  slot after each CPU access, B_TAIL during absent-row accesses, B_IDLE behind
  the `idle_cnt` guard, always behind refresh - so CPU accesses always win.
  Device address D is issued as half-word `{1'b1, D, 1'b0}`; the leading 1 is
  forced in the grant, so device traffic cannot reach the CPU half of the
  chip. Under PACK16 the CPU keeps its 4 MB and storage owns the upper 4 MB as
  32-bit locations `{1'b1, addr[19:0]}`. The CPU/storage boundary knob is
  `MEM_RAM_49_SDRAM #(CPU_PART_ROWS)` (1K-word ND rows, default 2048 = full
  4 MB for the CPU; keep multiples of 1024; never hard-code the boundary).
  Under PACK16 `sdram18.v`'s CPU-side address is a 22-bit half-word address;
  the device port uses the full-location (32-bit word) view.
  `ND_STORAGE_PARTITION` (section 1.3) is superseded.

Design for the multi-client storage facade specified in
`Verilog/docs/nd-storage-interface-spec.md` (the binding contract).
Companions: `Verilog/docs/sd-bpun-device-plan.md` (SD pins, tape-400 facts),
`Verilog/SD-FAT/README.md` (library state), `Verilog/docs/nd120-dram-memory.md`
(memory bridge). All paths relative to the repository root.

Everything generic lands in `Verilog/SD-FAT/circuit/`; board glue lands in
`Verilog/fpga/tang-nano-20k/sdram-bridge/`. Nothing touches DELILAH-CPU/,
DECODE-GateArray/ or CPU-BOARD-3202/.

## 1. Clocking, layering and the SDRAM decision

### 1.1 Clock domains

| Domain | Name | Tang value | Contents |
|---|---|---|---|
| storage | `clk_stor` | 27 MHz crystal/rPLL | nd_storage core, sd_file_reader (CLK_DIV=2), sd_writer (CLKDIV=5), mount FSM, block engine |
| client | `clk_cpu` | ND sysclk (27 MHz on Tang, ~16.7 MHz on Basys3) | per-client front-ends, all `open_*`/`req`/`done`/`buf_*` client signals (spec section 4: CDC is INSIDE nd_storage) |
| memory | `clk2x` | 54 MHz (2x OSC, same rPLL) | MEM_RAM_49_SDRAM bridge + sdram18 (existing) |

nd_storage is designed for `clk_stor != clk_cpu` (2-flop toggle synchronizers
everywhere); on Tang they may be the same 27 MHz net, which simply makes the
synchronizers fast. No new derived clocks; both clocks are PLL outputs
(standing constraint).

### 1.2 Which SDRAM controller nd_storage targets

Decision: **the 18-bit sdram18.v controller behind MEM_RAM_49_SDRAM**, via a
new device port added to the bridge - NOT the standalone byte controller
(`sdram-test/src/sdram.v`). Reasons:

- One controller must own the chip, and the CPU port already lives on
  sdram18 through the bridge.
- The "CPU absolute priority" rule can only be enforced where CPU access
  timing is visible: the bridge FSM knows RAS rise and owns the
  guaranteed-idle B_POST slot (it already schedules refresh there). Device
  ops are granted exactly like refresh: in B_POST after each CPU access, and
  in B_IDLE behind the same `idle_cnt` guard. A device op is 5 clk2x cycles;
  the post-access slot has >= 14 free cycles before the earliest next CPU
  access (N+11 rule) - a device op can never push CPU read data past the
  proven worst case.

nd_storage itself never sees sdram18. It talks to an abstract **mem port**
(section 5.2) in `clk_stor`; board glue (`sdram-bridge`) implements it, sim
uses a behavioral model.

### 1.3 The storage region (as built)

The storage region is 2048 blocks of 2048 bytes = 4 MB, addressed as
`mem_addr[19:0] = {blk_abs[10:0], word[8:0]}` (32-bit words). It cannot be
made larger cheaply: `s_blk_abs` in `nd_storage_engine.v` is 11 bits and the
address feeds `ND120_CORE`, `ND3202D`, `MEM_43` and the SDRAM bridge. On the
Tang the region is the upper 4 MB of the SDRAM (PACK16, see the step-9 note
at the top); the CPU keeps its full 4 MB.

Layout (parameters of `nd_storage.v`, defaults):

| blocks | use |
|---|---|
| 0 (`STAGE_BASE_BLK`) | one shared staging line for every DIRECT client (tape, floppy) - safe because the arbiter serves one client at a time and a DIRECT line never outlives its own operation |
| 1 .. 1024 (`POOL_BASE_BLK`, `CACHE_SETS` x `CACHE_WAYS` = 256 x 4) | the shared cache pool for the cached clients |
| 1025 .. 2047 | unused (~2 MB) - see the open item in section 2.7 |

Card file set (root directory, fixed names, 8 clients):

| client | device | file | default |
|---|---|---|---|
| 0 | tape-400 | `TAPE.BPUN` | DIRECT |
| 1 | floppy unit 1 | `FLOPPY1.IMG` | DIRECT |
| 2 | floppy unit 2 | `FLOPPY2.IMG` | DIRECT |
| 3-5 | SMD units 0-2 | `SMD0.IMG` .. `SMD2.IMG` | cached |
| 6-7 | Winchester units 0-1 | `WD0.IMG`, `WD1.IMG` | cached |

`CACHE_MASK[c]` selects cached (1) or DIRECT (0) per client; the default is
`8'b11111000`. Boards override the file names and the mask (see
`nd_storage_devices.v` and the board tops).

The old model, for reading the history: the plan gave up ND BANK1 for a disk
partition (`ND_STORAGE_PARTITION`) and preloaded tape and floppy images whole
into fixed slots (`SLOTn_BASE_BLK`/`SLOTn_SIZE_BLK`). PACK16 removed the need
for the partition, and Phase 4 removed the preload. The `SLOTn_*` parameters
are still in `nd_storage.v` but bound nothing.

## 2. Module breakdown (Verilog/SD-FAT/circuit/ unless noted)

| File | Responsibility (one line) | approx size |
|---|---|---|
| `nd_storage.v` | Top: SD reader+writer instances, SD pin mux (phase_write), mount/engine/cache wiring, status outputs | ~450 lines |
| `nd_storage_engine.v` | Round-robin arbiter, per-client pending latches + clk_cpu front-ends (generate), CDC word bridge, block read/write engine, cache fill, FAT-chain resolve, 512x32 staging BRAM | ~750 lines (plan) |
| `nd_storage_mount.v` | Open FSM: drive sd_file_reader per open, capture geometry/size/first-sector/first cluster, park reader (no preload since Phase 4) | ~320 lines (plan) |
| `nd_storage_fatchk.v` | Mount-time contiguity walker (diagnostic only since 07-AUG, section 2.4) | ~180 lines |
| `nd_storage_cache.v` | Tag/LRU directory of the shared block cache (section 2.7) | - |
| `nd_storage_tape_adapter.v` | Byte-stream adapter (spec section 5): one 1024x16 block buffer over one client port; byte_req/byte_valid/rewind, EOF = silence | ~230 lines |
| `nd_storage_floppy_adapter.v` | Sector-device glue: ND_FLOPPY_DMA disk_*/dbuf_* onto one client port (section 2.6); write = read-modify-write with internal 1024x16 buffer | ~280 lines |
| `nds_sync.v` | 2-flop toggle/pulse synchronizer primitive (one module, instantiated everywhere) | ~50 lines |
| `Verilog/SD-FAT/sim/nds_mem_model.v` | Behavioral mem-port model: 1M x 32 array, parameterized/randomized ack latency, $readmem preload + hierarchical checking | ~110 lines |
| `Verilog/fpga/tang-nano-20k/sdram-bridge/sdram18.v` (edit) | Add 32-bit data path: `din` widened to [31:0] internally via new `din32`, new `dout32` (nand2mario's sdram.v already has the dout32 pattern); CPU 18-bit path bit-identical | ~25 line diff |
| `Verilog/fpga/tang-nano-20k/sdram-bridge/MEM_RAM_49_SDRAM.v` (edit) | Device port (`ND_STORAGE_PORT`): mem-port toggles synced into clk2x, grant in B_POST/B_TAIL/idle slots (same policy as refresh) | ~90 line diff |

### 2.1 nd_storage.v (top)

Owns the single set of SD signals and both SD cores, exactly the
sd_fat_test_top pattern:

- `sd_file_reader` instance: `rstn = rst_stor_n & s_mount_active &
  ~s_mount_park` - the reader is HELD IN RESET except while a mount runs
  (per-open full re-init = the proven rewind/card-swap recovery).
  `target_name`/`target_len` muxed from the granted client's FILE parameters.
- `sd_writer` instance: `rst_n = rst_stor_n`, always alive. Its command pins
  are muxed: fatchk owns it while `chk_busy` (diagnostic builds only),
  otherwise the engine - write-through, cache fill and FAT-walk reads (the
  arbiter serializes mount and block ops, so there is never contention).
- Pin mux (the ONLY consumers; tristate stays at the board top):

```
assign sd_clk_o   = s_phase_write ? wr_sdclk  : rd_sdclk;
assign sd_cmd_o   = s_phase_write ? wr_cmd_o  : rd_cmd_o;
assign sd_cmd_oe  = s_phase_write ? wr_cmd_oe : rd_cmd_oe;
assign sd_dat0_o  = wr_dat0_o;
assign sd_dat0_oe = s_phase_write & wr_dat0_oe;
```

- `s_phase_write` register (clk_stor): cleared by the mount FSM in M_INIT
  (reader owns the card), set in M_PARK and out of reset. Geometry/size/
  first-sector latches are captured from the reader on `file_found` BEFORE
  parking (same-edge capture, the ST_C_FIND lesson).

Reset/park ownership summary (task item): mount FSM is the only agent that
releases the reader; the engine/fatchk are the only agents that pulse
sd_writer `start`, and only while `s_phase_write=1`; both are mutually
exclusive by arbiter construction.

### 2.2 nd_storage_engine.v

**Arbiter** (clk_stor): per client `s_pend_open[c]`, `s_pend_blk[c]` with
latched `s_op_wr[c]`, `s_op_block[c][15:0]` (set on the synced request
toggles, cleared at op end). Scan: grant the first pending client at
`ptr+1, ptr+2, ... ptr` (mod N_CLIENTS); at op completion `ptr <= grant`.
One op runs to completion, no preemption. No FIFOs anywhere - exactly the
one-request-per-client model of spec section 3.

**Engine FSM** (clk_stor):

```
E_IDLE    : scan; on grant -> E_GRANT
E_GRANT   : open pending  -> E_OPEN (hand to mount FSM)
            block pending -> range check: s_op_block >= n_blocks[c]
                             -> E_DONE with err=1 (NO SD/SDRAM traffic)
            read  -> R_MEM,  write -> W_PULL
E_OPEN    : mnt_start pulse; wait mnt_done/mnt_err -> E_DONE
R_MEM     : mem_start=1, mem_we=0, mem_addr={s_blk_abs[10:0], s_wcnt[8:0]}
R_WAIT    : mem_done -> latch mem_rdata -> R_PUSH_HI
R_PUSH_HI : word bridge push mem_rdata[31:16] (client word 2m)   -> R_PUSH_LO
R_PUSH_LO : push mem_rdata[15:0] (word 2m+1); s_wcnt++;
            s_wcnt==511 done ? E_DONE : R_MEM
W_PULL    : word bridge pull 1024 words -> staging BRAM (512x32,
            pack big-endian pairs); then W_SEC_GO with s_sec=0
W_SEC_GO  : wr_start=1, sector = s_first_sector[c] + {s_op_block,2'b00} + s_sec,
            rd_data served from staging (see 4.2)              -> W_SEC_WAIT
W_SEC_WAIT: wr_done -> s_sec==3 ? W_MEM : W_SEC_GO(s_sec+1)
            wr_err  -> E_DONE with err=1  (SDRAM NOT touched - test 5)
W_MEM     : 512 mem writes from staging (mem_we=1), W_MEM_WAIT loop
E_DONE    : set s_err_c, flip done_tgl[grant]; clear pend; ptr<=grant -> E_IDLE
```

Ordering rule (from acceptance test 5): **card first, SDRAM second, done
last.** A failed CMD24 leaves the SDRAM copy untouched; a successful write
commits to the card before `done` (spec: card always consistent, safe to
pull).

Every SD/mem wait state carries the WD_MAX watchdog (sd-fat-test pattern);
timeout -> E_DONE err=1 plus `sd_status <= SD_ERROR`.

**Changes since the FSM above was written.** `E_GRANT` no longer maps a
client block 1:1 onto a region block. A cached client goes through the cache
directory (`C_LOOK`); a miss fetches 4 card sectors through `sd_writer`
`rd_mode=1` (`C_SEC_GO`/`C_SEC_WAIT`), writes the line with `W_MEM`,
publishes the tag (`C_ALLOC`) and then serves. A DIRECT client fetches into the
staging line and serves from it inside its own grant. Bytes at or past
`size_bytes` read as zero (the fill zero-fills them), so the slack at the end
of a file's last cluster never reaches a client. See section 2.7.

**FAT-chain resolve (07-AUG-2026).** The card sector is no longer
`first_sector + block*4 + sec`, which assumed a contiguous file. Both
card-sector paths - the cache fill (`C_SEC_GO`) and the write-through
(`W_SEC_GO`) - get a resolve step in front (states `F_RES`, `F_STEP`,
`F_FAT_GO`, `F_FAT_WAIT` in `nd_storage_engine.v`):

- `target_sector_in_file = block*4 + sec`,
  `target_cluster_idx = target_sector_in_file >> log2(cluster_size)`;
- resolve the cluster index to a cluster by walking the FAT from the nearest
  known point, then
  `lba = data_start + (cluster-2)*cluster_size + (target_sector_in_file & (cluster_size-1))`;
- a per-client walk memo `(memo_idx, memo_cluster)` plus `first_cluster`
  (small registers, no RAM). A forward target walks from the memo; a backward
  target restarts at `first_cluster`. Sequential and block-local access costs
  0 or 1 FAT hops;
- one hop = CMD17 of the FAT sector that holds the current cluster's entry
  (`fat0_sector + (cluster*ENTSZ)/512`, ENTSZ 4 for FAT32, 2 for FAT16),
  keeping only the entry's 2 or 4 bytes as the read stream passes offset
  `(cluster*ENTSZ)%512`. No sector buffer; consecutive clusters usually share
  a FAT sector but the hop re-reads on purpose (zero RAM, and the memo keeps
  the steady state at about one hop). Entry masks and end-of-chain rules are
  those of `nd_storage_fatchk.v` (FAT16 end at >= 0xFFF7; FAT32 uses bits
  [27:0], end at >= 0x0FFFFFF7). An end of chain or an entry < 2 before the
  target index is reached answers done+err - never a wrong-sector access;
- geometry: the mount exports per-client `first_cluster` (captured at that
  client's `open_ok`); cluster size, FAT start and FAT32 flag are
  volume-global. `data_start = first_sector[c] - (first_cluster[c]-2)*cluster_size`
  (cluster size is a power of two, so this is a shift).

Ordering: the resolve runs BEFORE the write path commits client data to the
card (`W_SEC_GO`) and before the cache-fill CMD17s (`C_SEC_GO`). Both paths
already go through single-request serialization, so the resolve is a straight
state insertion; the only shared resource is the `sd_writer` command port,
which the engine already owns in those states.

**Per-client front-end** (clk_cpu, generate block, one per client):

```
on req[c] & ~fe_busy[c] & open_ok_sync[c]:
    fe_busy[c]<=1; latch {wr[c], block[c]}; flip req_tgl[c]
    (req while fe_busy is IGNORED - spec allows it)
read stream : on rd_have_tgl edge (synced) & grant_id_sync==c:
    buf_addr[c]<=fe_cnt; buf_wdata[c]<=bridge_rd_data; buf_we[c]<=1 (1 cycle);
    fe_cnt++; flip rd_ack_tgl
write stream: on wr_want_tgl edge & grant_id_sync==c:
    cycle A: buf_addr[c]<=fe_cnt
    cycle B: bridge_wr_data<=buf_rdata[c]; flip wr_have_tgl; fe_cnt++
    (address presented one cycle ahead - works for the floppy's
     combinational dbuf_rdata and for registered BRAMs alike)
on done_tgl[c] edge: err[c]<=err_sync; done[c] 1-cycle pulse;
    fe_busy[c]<=0; fe_cnt<=0
open: open_req[c] & ~fe_busy -> flip open_tgl[c];
    open_ok/open_err are 2-flop-synced levels; size_bytes[c] sampled
    when open_ok_sync rises (stable long before the toggle).
busy[c] = fe_busy[c]   (covers arbiter wait, per the spec waveform)
```

### 2.3 nd_storage_mount.v

FSM (clk_stor), invoked by the engine per granted open. Since Phase 4 the
mount establishes geometry only - it never moves file data:

```
M_IDLE  -> M_INIT : phase_write<=0; release reader reset; clear open_ok[c]
M_CARD  : wait card_stat>=8 (card_ready) | watchdog -> M_FAIL(SD_NOCARD)
M_SCAN  : file_found -> latch {size, found_file_first_sector, fs geometry,
          found_file_cluster}; NO size-versus-slot check (an image is
          limited only by the 16-bit block count, 128 MB). The reader
          runs with no_stream=1, so it stops after the directory match
          instead of streaming the file.
          scan_done after a match -> M_PARK (clean command boundary)
          scan_done without file_found | watchdog -> M_FAIL
M_PARK  : reader rstn low (parked), phase_write<=1
M_CHK   : only with SDFAT_STORAGE_CHECK (diagnostic build):
          chk_start; ok -> M_OK, bad -> M_FAIL
M_OK    : open_ok[c]<=1; n_blocks[c]<=ceil(size/2048); mnt_done
M_FAIL  : open_err[c]<=1; mnt_done (engine converts to done)
```

`open_ok` stays up across later write errors (spec section 7); only a new
open_req clears/rebuilds it.

Two facts that cost time:

- **Never stop the SD reader in the middle of a transfer.** Stopping
  `rd_run` the moment `file_found` rises left the card inside a CMD17, and
  the next card user failed. `no_stream` makes the reader stop at `H_DIR_NX`,
  which is entered with the card idle, and the mount waits for `scan_done`.
  So an open costs one directory scan, not one file read.
- `M_LOAD`, the old preload streamer (8x32 FIFO, 24-bit byte packer), is
  still in the file but can no longer be reached. `s_slot_bytes` is unused.
  Both are open clean-up items.

### 2.4 nd_storage_fatchk.v (retired from builds)

The mount-time contiguity checker. For
`n = ceil(size_bytes / (cluster_size*512))` clusters from `first_cluster` it
requires `FAT[first+i] == first+i+1` for i<n-1 and an end mark at
`FAT[first+n-1]`, reading through `sd_writer` `rd_mode=1` with the reader
parked. Since 07-AUG-2026 the engine walks the FAT chain itself, so a
fragmented file is simply correct and nothing is left for this gate to
protect. `sd_fat_features.vh` only builds it under
`-DSDFAT_FORCE_STORAGE_CHECK`; its testbenches force it so the diagnostic
keeps its coverage. Removing it returned its logic to the Tang budget (the
tape+floppy+WD build was 114 cells over with it).

### 2.5 nd_storage_tape_adapter.v (clk_cpu, single clock)

Ports mirror ND_TAPE_400's byte source 1:1 (`byte_req` in pulse,
`byte_valid` out pulse, `byte_data[7:0]`, `rewind` in pulse - wire
`source_rewind` to `rewind`) plus one full client port (c_open_req out,
c_open_ok/err/size in, c_req/c_wr=0/c_block out, c_busy/done/err in,
c_buf_addr/wdata/we in, c_buf_rdata out = 16'd0) and an `open_start` input
for the board/boot logic.

Internals: `blkbuf[0:1023]` (BRAM) filled by c_buf_we; `bptr[31:0]` byte
position; `cur_blk[15:0]`, `have_blk`. FSM: on byte_req: `bptr >=
c_size_bytes` -> never answer (EOF = RFT stays low, C-model behavior);
hit (`bptr[26:11]==cur_blk && have_blk`) -> byte_valid with
`bptr[0] ? word[7:0] : word[15:8]` (big-endian), bptr++; miss -> c_req with
c_block=bptr[26:11], wait c_done, then serve. `rewind`: bptr<=0,
have_blk<=0 - no card access until the next byte_req (since Phase 4 the
tape client is DIRECT, so that fetch goes to the card). c_err on done:
drop have_blk, stay silent (tape runout).

### 2.6 nd_storage_floppy_adapter.v (clk_cpu) - AS BUILT (step 8)

Retargeted 11-JUL (owner decision) to ND_FLOPPY_DMA's disk-image backend
port - 1560& mass boot is the proven path; a PIO adapter is optional later
work. The interview note guessed a disk_start/blkaddr1/blkaddr2/unit shape;
the DEVICE SOURCE (ND-BUS-DEVICES/FLOPPY-DMA/circuit/ND_FLOPPY_DMA.v) is
authoritative and differs: the backend moves ONE LOGICAL SECTOR per
request, addressed by a 16-bit logical sector number, not by a 32-bit
block address pair. The actual contract (adapter side, pin-for-pin):

```
disk_req        in   1-cycle pulse: move one sector (fields registered in
                     the device, stable from the pulse until disk_done)
disk_wr         in   0 = image -> device buffer, 1 = device buffer -> image
disk_lsect      in   [15:0] logical sector number
disk_format     in   [1:0]  words/sector: 0=256, 1=128, 2=64, 3=512
disk_drive      in   [1:0]  drive select (command word b7:6; boot uses 0)
disk_wordcount  in   [10:0] words to move (the device passes words/sector)
disk_done       out  1-cycle pulse (the device waits on it as a level)
disk_err        out  valid with disk_done (wire to the device disk_err_in)
dbuf_addr/wdata/we   out: fill the device's 1024x16 sector buffer (reads)
dbuf_rdata      in   device buffer readout (combinational in the device;
                     the adapter samples with a settle cycle, so a
                     registered backend would also be correct)
```

Parameter DRIVE[1:0]: one instance serves one drive (FLOPPY1.IMG =
client 1 = DRIVE 0, FLOPPY2.IMG = client 2 = DRIVE 1). A request with
disk_drive != DRIVE is ignored completely, all outputs parked at 0, so two
instances share the controller's disk_* outputs with disk_done/disk_err/
dbuf_* OR-combined.

Geometry: linear word offset = lsect << log2(words/sector); c_block =
offset[24:10], word-in-block = offset[9:0]. Every sector size divides
1024, so a sector never straddles a client block. The 1024x16 local buffer
doubles as a one-block cache: the '1560&' sequential boot stream fetches
each block once per two 512-word chunks.

```
READ  : cache hit -> serve wordcount words via dbuf_*; miss -> one c_req
        read into the local buffer, then serve.
WRITE : read-modify-write: c_req read of the containing block (skipped on
        a cache hit or a full aligned 1024-word transfer), overlay the
        device's words (dbuf_addr walk, settle cycle, sample), then one
        c_req write served from the local buffer (registered c_buf_rdata;
        the engine's A/B/C sampling gives it 2 cycles). After a successful
        commit the buffer stays valid as the cache.
errors: not-open, out-of-range, c_err  ->  disk_done WITH disk_err, cache
        dropped, zero card/SDRAM side effects, always retryable.
        HARD RULE (step-6 FLAG): a write errs unless the WHOLE containing
        block lies inside the file ((block+1)*2048 <= size_bytes) - never
        write the partial tail block of a non-2048-multiple file. Floppy
        images are block multiples, so in-range requests are never refused.
```

open_start (board/boot pulse) passes through as c_open_req, as in the tape
adapter. This module is used both by acceptance test 6 (gate
test-nds-floppy) and by the real Tang build.

### 2.7 nd_storage_cache.v - the shared block cache (Phase 4, as built 04/05-AUG-2026)

**Why.** v1 mapped an image block straight onto a region block
(`s_blk_abs <= slot_base + op_block`), so an image could never be larger than
its slot, and the mount refused it. A real Winchester image (`WD0.IMG`,
78,643,200 bytes) against a 128-block (256 KB) slot failed to mount; every
block request then took the zero-fill error path, and DISC-TEMA reported a
controller that finished with no error bit and all-zero data (status
`060010b`). The controller was not at fault.

**Owner's rules (04-AUG-2026):** no image is preloaded; a dynamic read cache
with write-through that keeps the most used blocks; floppy and tape are not
cached (the SD card is quick enough for them), the SMD and the Winchester are,
so SINTRAN runs quickly; caching can be turned on and off per device class.
The owner chose one SHARED pool over all cached clients, 4-way
set-associative, true LRU, write-through and write-allocate. Shared rather
than per unit, so the disc doing the work gets the whole pool and an idle
second unit costs nothing.

**Organisation** (the module header of `SD-FAT/circuit/nd_storage_cache.v`
is the detailed reference):

- `set = client_block[SETIDX-1:0]`, `tag = {client[2:0], client_block[15:SETIDX]}`,
  `region block = POOL_BASE_BLK + set*WAYS + way`. The client id is inside the
  tag, so unit 0 block 5 and unit 1 block 5 cannot alias.
- One array, `dir_ram`, holds `{ valid(WAYS) | rank(WAYS*2) | tag(WAYS*TAGW) }`
  per set: one write port, one registered read, no reset. All ways of a set
  compare in the same cycle.
- After reset a walking clear (one set per cycle) empties the directory.
- Interface: `lookup_req/done/hit/way/line`, `alloc_req/done`,
  `inval_req/done`; one outstanding lookup (the engine serialises anyway).
- Enabling the floppy later is one bit in `CACHE_MASK`.

**Measured with yosys `synth_gowin` on the module alone, 512 sets x 4 ways:**

| version of the directory | result |
|---|---|
| separate `rank_ram`/`valid_ram` flip-flop arrays, read combinationally | 187,283 AND gates |
| merged into one word, but written inside the async-reset process | 844,694 AND gates |
| merged, written in its own reset-free process | ~700 LUT-class cells + 2 BSRAM + ~190 FF |

512 sets cost no more logic than 256, because it all lives in block RAM.

Four faults found while building it, all fixed:

1. Stopping the SD reader in the middle of a transfer corrupts the next card
   access (section 2.3).
2. The engine first gave each DIRECT client its own staging line at
   `STAGE_BASE_BLK + client`, which overlapped the pool at `POOL_BASE_BLK = 1`:
   silent cross-corruption. Now one shared staging line.
3. A fill pulls whole 2048-byte blocks, so the last block of a file that is
   not a multiple of 2048 dragged in cluster slack (`TAPE.BPUN`, 3001 bytes,
   returned junk from byte 3001). The fill now zero-fills at and past
   `size_bytes`.
4. Dropping the reset loop to get block RAM left the LRU ranks undefined;
   early eviction tests had passed by luck. The walking clear gives every way
   a defined rank.

What `test-nds-cachepath` (`nd_storage_cachepath_tb.v`, 2 sets x 2 ways)
proves: a cold fill returns the card's bytes; a re-read is a hit with zero
card and zero region traffic; a cold set fills both ways before evicting; the
third tag in a set evicts the LRU way (the survivor is checked before the
victim is re-read); write-allocate; write-through to a resident line returns
the new data; an out-of-range block answers done+err with no traffic; a
DIRECT client never raises a lookup. Built with `CACHE_MASK = 0` it fails
with 6 errors, so the checks have teeth.

**Open (listed in `Verilog/TODO.md`):**

- Remove the dead `M_LOAD` path and `s_slot_bytes` from
  `nd_storage_mount.v` (frees an 8x32 FIFO, the byte packer and counters).
- Remove the vestigial `SLOTn_*` parameters from `nd_storage.v`.
- The pool uses 1024 of the 2048 region blocks; ~2 MB is unused. A
  power-of-two pool plus one staging line cannot reach 2048. The options are
  to accept it, or `CACHE_WAYS = 3` with `CACHE_SETS = 512` (1536 lines,
  3-way LRU - the 2-bit rank field and the `WAYW` derivation already handle
  3). The geometry is the owner's call.

Measured null result (Tang, 6.75 MHz / 9600-baud era, 23-AUG-2026): cache on,
`-DiscsUncached` and `-NoStorageCache` all reached the same point at 143 s -
no boot-speed difference at 1 s resolution over ~30 disc operations.

## 3. Parameterization and feature flags

`nd_storage` parameters (Verilog-2001, per-index pairs like the existing
FILE2_NAME/FILE3_NAME pattern; N_CLIENTS <= 4 uses the first N):

```
parameter            N_CLIENTS    = 8
parameter [2:0]      RD_CLK_DIV   = 3'd2          // sd_file_reader (25-50 MHz clk)
parameter [7:0]      WR_CLKDIV    = 8'd1          // sd_writer bit clock divider
parameter integer    USE_4BIT     = 0             // 1 = 4-bit SD data bus
parameter [31:0]     WD_MAX       = 32'd270_000_000
parameter            SIMULATE     = 0             // short SD init in sim
parameter [7:0]      CACHE_MASK   = 8'b11111000   // disc classes cached
parameter [31:0]     STAGE_BASE_BLK = 32'd0
parameter [31:0]     POOL_BASE_BLK  = 32'd1
parameter            CACHE_SETS = 256, CACHE_SETIDX = 8, CACHE_WAYS = 4
parameter [52*8-1:0] FILE0_NAME = "TAPE.BPUN"   , FILE0_LEN = 8'd9
parameter [52*8-1:0] FILE1_NAME = "FLOPPY1.IMG" , FILE1_LEN = 8'd11
parameter [52*8-1:0] FILE2_NAME = "FLOPPY2.IMG" , FILE2_LEN = 8'd11
parameter [52*8-1:0] FILE3_NAME = "SMD0.IMG"    , FILE3_LEN = 8'd8
parameter [52*8-1:0] FILE4_NAME = "SMD1.IMG"    , FILE4_LEN = 8'd8
parameter [52*8-1:0] FILE5_NAME = "SMD2.IMG"    , FILE5_LEN = 8'd8
parameter [52*8-1:0] FILE6_NAME = "WD0.IMG"     , FILE6_LEN = 8'd7
parameter [52*8-1:0] FILE7_NAME = "WD1.IMG"     , FILE7_LEN = 8'd7
SLOTn_BASE_BLK / SLOTn_SIZE_BLK: vestigial since Phase 4 (section 1.3)
```

The name parameters are left-justified string literals converted to the
reader's byte-0-in-low-byte `target_name` layout by the same generate loop
sd_fat_test_top uses (`g_target_names`), muxed per granted client.

`sd_fat_features.vh` additions (follow the existing dependency-resolution
pattern; storage needs the write engine for write-through AND for the
fatchk/mount read path):

```
`ifdef SDFAT_WRITE
  `ifndef SDFAT_NO_STORAGE
    `define SDFAT_STORAGE
  `endif
`endif
`ifdef SDFAT_STORAGE
  `ifdef SDFAT_FORCE_STORAGE_CHECK
    `define SDFAT_STORAGE_CHECK        // diagnostic contiguity gate only
  `endif
`endif
```

Without SDFAT_STORAGE_CHECK (every normal build since 07-AUG-2026) the mount
skips M_CHK; the engine's FAT walk makes contiguity unnecessary.

## 4. Data-path definition and exact timing

### 4.1 Byte/word order (normative)

One block = 2048 bytes = 4 SD sectors = 1024 client words = 512 SDRAM words.
Let `k` = linear byte 0..2047 within the block (`k = 512*s + b`, sector s,
sector byte b), `w` = client word 0..1023, `m` = SDRAM 32-bit word 0..511:

```
client word w  = {byte 2w, byte 2w+1}        big-endian, byte 2w = [15:8]
                                             (identical to the proven WRBLK1
                                              pattern: even byte = high byte)
SDRAM word m   = {word 2m, word 2m+1}
               = {byte 4m, byte 4m+1, byte 4m+2, byte 4m+3}   byte 4m = dq[31:24]
SD sector addr = the card sector the FAT-chain resolve finds for file
                 sector 4*block + s (section 2.2); for a contiguous file
                 this equals found_file_first_sector[c] + 4*block + s
SDRAM word addr= mem_addr[19:0] = {blk_abs[10:0], m[8:0]},
                 blk_abs = the cache line (POOL_BASE_BLK + set*WAYS + way),
                 or STAGE_BASE_BLK for a DIRECT client
```

The cache fill and the engine both use this order, so a byte on the card, in
SDRAM and in a client buffer always corresponds 1:1.

### 4.2 Read op (spec section 4 waveform, annotated)

```
clk_cpu : req[c]   _/\____________________________________________
          busy[c]  __/--------------------------------------\_____
clk_stor:            [req_tgl 2-flop, arbiter wait, grant]
          per m=0..511:
            mem_start _/\    (mem_we=0, addr={blk_abs,m})
            mem_done  ....\_/    (~10-30 clk_stor: sync into clk2x,
                                  wait leftover slot, 5-cycle op, sync back)
            rd_have_tgl flips twice (hi word, then lo word); data bus
            bridge_rd_data[15:0] is stable ONE clk_stor before each flip
clk_cpu : buf_we[c]  ____/- 1024 single-cycle pulses, buf_addr 0..1023 -\__
          (each pulse: 2-flop edge detect on rd_have_tgl, then ack toggle)
clk_stor: done_tgl flips after word 1023 acked
clk_cpu : done[c]  ________________________________________/\_____
          err[c]   valid during done (0 here)
```

Per-word CDC round trip ~= 3 clk_stor + 3 clk_cpu each way; block read total
~= 0.5-0.9 ms at 27/27 MHz including SDRAM handshakes. (Permitted
optimization, not required for v1: issue mem read m+1 while pushing word
pair m - the FSM shape above allows adding one skid register later.)

### 4.3 Write op

```
Phase 1 - pull:   engine flips wr_want_tgl 1024x; FE presents buf_addr one
                  cycle ahead, samples buf_rdata the next cycle (standard
                  synchronous-BRAM timing; also correct for the floppy's
                  combinational dbuf_rdata), returns wr_have_tgl + data.
                  Engine packs pairs into staging BRAM (512x32).
Phase 2 - card:   4x sd_writer CMD24. sd_writer's byte fetch contract is a
                  REGISTERED read port with 1-clk latency and ~80 clk_stor
                  between fetches (8 bit-ticks at CLKDIV=5): serve
                  rd_data <= staging[{s_sec[1:0], rd_addr[8:2]}] byte lane
                  ~rd_addr[1:0] via a 2-stage registered read - trivially
                  inside the budget. wr_err at ANY sector -> done+err,
                  skip phase 3 (SDRAM copy stays intact - test 5).
Phase 3 - SDRAM:  512 mem writes (mem_we=1, mem_wdata = staging[m]).
done[c] fires only after phase 3 - i.e. after the card has acknowledged all
4 sectors AND the SDRAM copy matches (write-through commits before done).
```

The 2 KB staging BRAM is a deliberate, engine-internal deviation from the
"nd_storage never stores payload" rationale: that rule bans per-client
buffering/queueing; one shared staging block avoids pulling the client
buffer twice over the CDC and makes the card-first/SDRAM-second ordering of
test 5 natural. Document it in the module header.

Timing: dominated by 4x CMD24 at 2.7 MHz ~= 10-20 ms/block; worst-case
client wait (N-1) ops ~= 60 ms - inside every device budget (spec section 3).

### 4.4 CDC inventory (all 2-flop, toggle-based, via nds_sync.v)

| Crossing | Signals | Data rule |
|---|---|---|
| cpu->stor, per client | `open_tgl[c]`, `req_tgl[c]` | `wr[c]`, `block[c]` latched by the FE and stable until done |
| stor->cpu, per client | `done_tgl[c]` | `err_c`, updated open_ok/open_err/size_bytes stable >= 2 clk_stor before the flip; sampled after edge detect |
| stor->cpu, shared | `rd_have_tgl`, `bridge_rd_data[15:0]`, `grant_id[1:0]` | data/grant stable one clk_stor before flip; grant changes only while bridge idle |
| cpu->stor, shared | `rd_ack_tgl`, `wr_have_tgl`, `bridge_wr_data[15:0]` | same rule mirrored |
| stor->cpu, levels | `open_ok[N]`, `open_err[N]`, `sd_status[1:0]` | quasi-static, plain 2-flop per bit |
| stor<->clk2x (shim) | `mem_start_tgl` out / `mem_done_tgl` back | `{mem_we, mem_addr, mem_wdata}` stable from start to done; `mem_rdata` stable at done flip. Same-PLL integer-ratio clocks - the 2-flop pattern is conservative-safe |

## 5. External interfaces (exact)

### 5.1 nd_storage port list

```verilog
module nd_storage #(...parameters of section 3...) (
    input  wire clk_stor,  input wire rst_stor_n,
    input  wire clk_cpu,   input wire rst_cpu_n,
    // SD pads (single tristate at the board top, repo rule)
    output wire sd_clk_o,
    input  wire sd_cmd_i,  output wire sd_cmd_o,  output wire sd_cmd_oe,
    input  wire sd_dat0_i, output wire sd_dat0_o, output wire sd_dat0_oe,
    // SDRAM device port (clk_stor domain, see 5.2)
    output wire        mem_start,   // 1-cycle pulse, only when mem_busy=0
    output wire        mem_we,
    output wire [19:0] mem_addr,    // 32-bit-word address inside the region
    output wire [31:0] mem_wdata,
    input  wire [31:0] mem_rdata,   // valid at mem_done, then held
    input  wire        mem_busy,
    input  wire        mem_done,    // 1-cycle pulse
    // client ports (clk_cpu domain, flattened; names/widths per spec sec 4)
    input  wire [N_CLIENTS-1:0]     open_req,
    output wire [N_CLIENTS-1:0]     open_ok,
    output wire [N_CLIENTS-1:0]     open_err,
    output wire [N_CLIENTS*32-1:0]  size_bytes,
    input  wire [N_CLIENTS-1:0]     req,
    input  wire [N_CLIENTS-1:0]     wr,
    input  wire [N_CLIENTS*16-1:0]  block,
    output wire [N_CLIENTS-1:0]     busy,
    output wire [N_CLIENTS-1:0]     done,
    output wire [N_CLIENTS-1:0]     err,
    output wire [N_CLIENTS*10-1:0]  buf_addr,
    output wire [N_CLIENTS*16-1:0]  buf_wdata,
    output wire [N_CLIENTS-1:0]     buf_we,
    input  wire [N_CLIENTS*16-1:0]  buf_rdata,
    // status (for board LEDs / console, spec sec 7)
    output wire [1:0] sd_status,    // 0 NOTCHK, 1 NOCARD, 2 ERROR, 3 OK
    output wire [1:0] card_type,
    output wire [1:0] fs_type
);
```

### 5.2 Mem-port shim (board glue contract)

The nd_storage-facing side is the `mem_*` group above (start/busy/done
idiom, same shape as sd_writer's command interface). The Tang implementation
lives in MEM_RAM_49_SDRAM: sync `mem_start` toggle into clk2x; hold
`{we,addr,wdata}` stable; issue to sdram18 with
`s_addr = {1'b1, mem_addr[19:0]}` (device region), `din32 = mem_wdata`,
grant ONLY in B_POST (after refresh_needed is serviced) or in B_IDLE behind
the existing `idle_cnt == IDLE_REFRESH_AFTER` guard; on
`data_ready`/write-complete flip `mem_done` toggle with `mem_rdata = dout32`.
One outstanding op; CPU traffic keeps absolute priority by construction.
The sim model `nds_mem_model.v` implements the identical contract with
randomized 4..40-cycle latency.

## 6. Simulation strategy (acceptance tests, spec section 9)

Models: `SD-FAT/sim/sd_card_model.v` (exists - CMD17/CMD24 with CRC, image
in/out, iverilog only); the C++ card model in
`fpga/tang-nano-20k/sd-fat-test/sim/test_sd_fat.cpp` (Verilator path,
reused); `SD-FAT/sim/nds_mem_model.v` (new) as the SDRAM stand-in for all
storage tbs - the REAL sdram18 chain is exercised separately at the bridge
level (step 9). Card images built by a `make_test_image.sh` variant creating
2-4 contiguous files with distinct patterns, plus one deliberately
fragmented file for the fatchk case. All tbs run `clk_cpu` and `clk_stor` at
DIFFERENT, non-integer-ratio frequencies (e.g. 23/27 MHz) to stress the CDC.

Split, following the sd-fat-test precedent (fast Verilator gate + registered
unit tbs; heavyweight iverilog full-system stays a manual target):

| Spec test | Vehicle | Tool | Registered as |
|---|---|---|---|
| 1 round-robin + integrity (2 clients) | `SD-FAT/sim/test_nd_storage.cpp` + `nd_storage_vtop.v` (tristate wrapper + C++ card + C++ mem model) | Verilator | `SD-FAT/sim :: test-storage` |
| 2 write-through + fsck recheck | same Verilator program: write block k, compare card-model memory AND mem-model word-for-word before `done` returns; Makefile runs `fsck.vfat -n` on the post-image | Verilator + fsck | part of `test-storage` |
| 3 concurrency, 4 clients, distinct patterns, no starvation/leak | same program, phase 3 | Verilator | part of `test-storage` |
| 4 tape adapter (stream/rewind/EOF) | `SD-FAT/sim/nd_storage_tape_tb.v` - adapter against a SCRIPTED client-port stub serving an array image (no SD, no SDRAM - pure unit tb) | iverilog | `SD-FAT/sim :: test-nds-tape` |
| 5 errors (range, injected write fail) | range-err asserted in the engine unit tb (below); write-fail injected via the C++ card model's error flag in `test-storage` (verify done+err, SDRAM word unchanged) | both | `test-nds-engine` + `test-storage` |
| 6 system: floppy through the full stack | as built: tier B of the floppy adapter testbench - the adapter on client 1 of the real stack against `nds_storage.img` (sector and read-modify-write writes checked in the card image, whole-card compare against stray writes). The planned ND_FLOPPY_PIO `test-floppy-storage` was not built: the adapter targets ND_FLOPPY_DMA | iverilog | `SD-FAT/sim :: test-nds-floppy` |

Plus engine-level unit tbs that need no card: `nd_storage_cdc_tb.v` (word
bridge + toggle sync across skewed clocks, x1000 words, random stalls) and
`nd_storage_engine_tb.v` (arbiter order, read integrity from a preloaded
mem model, range err path; write path against the real sd_writer +
sd_card_model as in the existing `sd_writer_tb`). Every tb prints
`TB_RESULT: PASS` and is registered in `Verilog/tests/run_all_tests.sh`
(standing rule). A pure-iverilog full-system tb (`nd_storage_tb.v`,
mount + 2 opens + interleaved ops with tiny files, SIMULATE=1) exists as a
manual `test-system`-style target, mirroring the sd-fat-test arrangement.

### Key files
- Verilog/docs/nd-storage-interface-spec.md (binding contract: ports, handshake, tests)
- Verilog/fpga/tang-nano-20k/sd-fat-test/src/sd_fat_test_top.v (proven reader/writer pin-mux, park/re-init, geometry-latch and watchdog patterns to lift)
- Verilog/SD-FAT/circuit/sd_file_reader.v (mount source: target_name port, geometry/first-sector exports, outen/outbyte stream semantics)
- Verilog/SD-FAT/circuit/sd_writer.v (write-through engine contract: start/busy/done/err, registered rd_addr/rd_data timing)
- Verilog/fpga/tang-nano-20k/sdram-bridge/MEM_RAM_49_SDRAM.v (device port; B_POST/idle grant slots)
