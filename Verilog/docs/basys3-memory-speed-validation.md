# Basys3 main-memory options vs the ND-120 DRAM protocol: speed validation

**Full path:** `Verilog/docs/basys3-memory-speed-validation.md`
**Date:** 13-JUL-2026.
**Question answered:** of all the main-memory options researched for the
Digilent Basys3 (Artix-7 XC7A35T, no external RAM on board, only Pmod
expansion), which are FAST ENOUGH for the ND-120 recreation at the stated
~40 MHz target (39.06 MHz = the original ND OSC, see
`Verilog/fpga/basys3/exp_slowclk.tcl`:
"25.6 ns = 39.06 MHz (original ND OSC target)")?

**Short answer: nothing external through the Pmod connectors meets the
protocol at 40 MHz. On-chip BRAM is the only Basys3 backend that does, and
it caps out around 64K words (128 KB of data) - far below the 4 MB a
BSD/SINTRAN-class configuration needs. The protocol cannot be stalled, so a
cache-plus-slow-backing-store architecture is also impossible without
changing the recreated PAL state machine.** Details and arithmetic below.

---

## 1. Ground truth: the measured protocol (what "fast enough" means)

Source: `Verilog/docs/nd120-dram-memory.md`
(measured from 25,008 captured accesses, `-DDBG_MEM` Verilator run; every
access had the identical signature). N = the OSC cycle of the RAS falling
edge (chip-side; RAS rise on the sheet-49 interface):

| OSC cycle | Event |
|-----------|-------|
| N | row address on `AA_9_0`; `W_n` already valid |
| N+1 | `AA` has switched to the **column** address |
| N+2 | CAS falls - access begins; write data `DD_17_0_IN` valid |
| N+3 | both-low window (proven BRAM path has read data out from the START of N+3) |
| N+4 | both-low window (last) - read data must be on `DD_17_0_OUT` **by the start of N+4 at the latest**, registered and held |
| N+5 | RAS released |

RAS-to-RAS spacing: **minimum 11 cycles** (1,280 of 25,008 accesses), mode
17. ~10% of accesses are writes; the write is executed **once**, at the
first both-low window edge.

**The no-stall property, verbatim from the doc (section 3):**

> The PAL comment "NO WAIT STATE ON CPU TO MEMORY WRITE" is literal: **the
> sequence has fixed length, there is no way for the memory to stall it.**
> Any replacement backend must meet the fixed deadline.

The sequencer is `PAL_44902A` (a registered PAL16R8 clocked on OSC,
`Verilog/PAL/PAL_44902A.v`); the `RDATA`
sample strobe comes from `MEM_LBDIF_48`. There is no ready/ack input
anywhere in the chain. **A backend that cannot meet N+4 cannot ask for a
wait state - it simply returns garbage.** (Section 8 revisits what changing
this would mean.)

### 1.1 The original hardware's memory speed (context)

The real ND-120 used six Toshiba **1M x 9 DRAM SIP modules**
(THM91020/THM91070, per `nd120-dram-memory.md` section 1).

- **THM91070AS-70** is listed as "Fast Page DRAM Module, 1MX9, **70 ns**" -
  <https://www.datasheets360.com/part/detail/thm91070as-70/3667810165906245724/>
- Part listings also show a **THM91020AL70** (implying a -70 = 70 ns grade
  of the THM91020); the exact speed grade fitted in the ND-120 is
  **unverified** (the family databook is the 1994 Toshiba DRAM Components
  and Modules book, <http://bitsavers.org/components/toshiba/_dataBook/1994_Toshiba_DRAM_Components_and_Modules.pdf>,
  scanned images - not text-searchable here).
- This matches the project owner's recollection that the machine expects
  roughly **60-70 ns** memory access, and it cross-checks the budget math
  below: at 39.06 MHz the column-to-data window is 76.8 ns - exactly the
  window a -70 fast-page DRAM (tAA ~= 35-40 ns from column address) sits
  comfortably inside.

---

## 2. The hard timing budget (derivation)

The budget is **3 OSC cycles from column-known to data-valid**, fixed by
the protocol shape, independent of frequency:

- Column address is on `AA` at the start of **N+1**.
- Read data must be on `DD_17_0_OUT` by the start of **N+4**.
- N+4 - (N+1) = **3 OSC cycles**.

| OSC | Cycle time | Column -> data (3 cyc) | Row -> data (4 cyc) | Write capture window |
|-----|-----------|------------------------|---------------------|----------------------|
| 40.00 MHz | 25.0 ns | 3 x 25.0 = **75.0 ns** | 100.0 ns | data valid at N+2; executed once |
| 39.06 MHz | 25.6 ns | 3 x 25.6 = **76.8 ns** | 102.4 ns | " |
| 25.00 MHz | 40.0 ns | **120 ns** | 160 ns | " |
| 16.67 MHz | 60.0 ns | **180 ns** | 240 ns | " |

The proven reference (Basys3 BRAM path in
`Verilog/Shared/support/SIP1M9.v`,
`ramSize=3`) actually delivers by the start of **N+3** - i.e. the "safe
side of proven behaviour" target is really **2 cycles = 50 ns at 40 MHz**;
N+4 is the absolute latest.

**Write path budget:** `DD_17_0_IN` is valid at N+2 and the write is
executed once at the first both-low edge. The backend then has until the
earliest possible next access - RAS-to-RAS minimum 11 cycles - to complete
the write internally: ~9 cycles = **225 ns at 40 MHz**. Writes are never
the constraint; **reads are**.

**Overheads any EXTERNAL backend must subtract from the read budget**
(engineering estimates, not datasheet values):

- FPGA output path (register -> IOB -> pin): ~3-6 ns
- FPGA input path (pin -> route -> capture setup): ~2-4 ns
- Total in+out through the FPGA: **~5-10 ns**
- Pmod header + unmatched traces: ~1-2 ns flight + signal-integrity
  settling on unterminated stubs (unquantifiable without measurement)
- Series protection resistors on standard Pmod ports (RC with the load
  capacitance): ~2-3 ns per edge - *unverified for the Basys3
  specifically; check the Basys3 schematic at bring-up*
- If the backend runs its own clock domain (true CDC, not a same-PLL
  integer ratio): 2-flop synchronizer = **2 backend clock periods** each way

Digilent's own positioning of the Pmod interface (Pmod Interface
Specification, <https://digilent.com/reference/_media/reference/pmod/pmod-interface-specification-1_2_0.pdf>):
the interface **"is not intended for high frequency operation"**; the
spec's demonstrated figure is signals "sent reliably at **24 MHz**" (over
RJ45/twisted pair at distance), with >100 MHz described only as
theoretically achievable "using high-speed ports with direct connection".
The Basys3 reference manual states it VERBATIM (extracted from the manual
PDF, Pmod Ports section): "Pmod data signals are not matched pairs, and
they are routed using best-available tracks without impedance control or
delay matching."
(<https://digilent.com/reference/programmable-logic/basys-3/reference-manual>).
The repo's own analysis in
`Verilog/docs/usb-storage-options.md`
confirms the Basys3 has **3 general-purpose Pmods (8 signals each, 3.3 V)**
plus the dual-purpose JXADC Pmod = **32 signals maximum, 24 if an SD-card
Pmod occupies one connector** (SD is the planned storage per
`Verilog/TODO.md`, "SD-card block devices
across all boards").

---

## 3. Inventory of the researched options

From the repo (all read for this report):

1. **On-chip BRAM** (`MAIN_RAM_BLOCKRAM`) - current Basys3 backend.
   `Verilog/CPU-BOARD-3202/circuit/MEM_RAM_49_BLOCKRAM.v`,
   proven path in `Verilog/Shared/support/SIP1M9.v` (ramSize=3),
   standalone hardware test `Verilog/fpga/basys3/mem-test/basys3_mem_test_top.v`.
2. **512 KB async SRAM, 8-bit bus, on dedicated pins** - the CMOD A7-35T
   plan: `Verilog/fpga/cmod-a7-35t/README.md`
   and `Verilog/TODO.md` ("CMOD A7-35T
   target"). Never timing-validated; evaluated in section 4.3, and its
   Pmod-transplanted variant in 4.2.
3. **16-bit SDRAM, burst-of-2 bridge** - the QMTECH XC7A35T stage-3 plan:
   `Verilog/fpga/qmtech-a35t/docs/board-notes.md`
   (W9825G6KH-6, BL=2, per-ND-word data beat + parity beat; superseded on
   the Tang by `ND_SDRAM_PACK16` per `nd120-dram-memory.md` section 6).
4. **Tang Nano 20K SDRAM 2x-clock bridge** - implemented and
   hardware-validated; its deadline math is the template
   (`nd120-dram-memory.md` section 6,
   `Verilog/fpga/tang-nano-20k/sdram-bridge/`).
5. **HyperRAM / octal PSRAM on a Pmod** - **no prior document in this repo
   mentions it** (verified: `grep -riE 'hyperram|psram'` over
   `Verilog/docs` and
   `Verilog/fpga` returns nothing).
   Evaluated here as the obvious modern add-on (off-the-shelf module:
   1BitSquared Pmod HyperRAM, <https://1bitsquared.com/products/pmod-hyperram>).
6. **UART sector-server / CH376 / SD-card Pmod** - storage backends from
   `Verilog/docs/usb-storage-options.md`;
   included to state explicitly that they are NOT main-memory candidates.

---

## 4. Validation of each option against the budget

### 4.1 On-chip BRAM (`MAIN_RAM_BLOCKRAM`) - MEETS TIMING, capacity-limited

**Timing:** trivially met at any achievable OSC. The proven path does a
registered read on the first both-low edge, so data is on `DD_17_0_OUT`
from the **start of N+3** and held (one full cycle of margin over the N+4
deadline). Same clock, no CDC, no I/O pins. Xilinx 7-series block RAM
supports clock rates far above anything this design will reach, so BRAM
remains valid at the 39.06/40 MHz target and beyond - the limit is the
CPU logic's timing closure, not the memory.

**Capacity - the real question.** XC7A35T total BRAM: **1,800 Kbit
(50 RAMB36 / 100 RAMB18) = 225 KB**
(`Verilog/fpga/basys3/README.md`, board
table; matches AMD/Xilinx 7-series product tables). Deductions:

- **WCS**: 8192 x 64-bit microwords = 524,288 bits = **512 Kbit** (fixed cost).
- **Microcode PROM images** (2x AM27256, 32K x 8 each) = another
  **~512 Kbit**, currently duplicated into BRAM. The full Basys3 build
  measures **~1,044 Kbit** of BRAM used, "dominated by the duplicated
  microcode PROM + WCS"
  (`Verilog/fpga/basys3/README.md`, Status) -
  that figure includes the current default main RAM (3 banks x 4K words x
  18 bit = 216 Kbit = **24 KB**, the "Basys3's 24 KB BRAM main-memory
  limit" cited in the QMTECH handoff).
- `SKIP_WCS_LOAD` can reclaim the PROM's ~512 Kbit
  (`Verilog/docs/skip-wcs-load.md`: "its
  ~512 Kbit BRAM can be dropped").

Arithmetic for maximum ND main memory (18-bit words, `MEM_RAM_49_BLOCKRAM`
`BANK_ADDR_BITS` raised):

```
Total                       1800 Kbit
- current build (incl 24KB) 1044 Kbit   -> free ~756 Kbit  = ~42K extra words
- with SKIP_WCS_LOAD        +512 Kbit   -> free ~1268 Kbit = ~70K words total headroom
64K words x 18 bit = 1152 Kbit = 32 RAMB36  -> fits with SKIP_WCS_LOAD, tight
```

**Realistic maximum: 32K-64K 18-bit words (64-128 KB of 16-bit data),
64 KW only with `SKIP_WCS_LOAD` and nothing else growing.** The
BSD/SINTRAN-class requirement of **4 MB = 2M words x 18 bit = 36 Mbit** is
**20x the entire chip's BRAM** - categorically impossible on the XC7A35T.
What DOES fit is a small-memory ND-120 (the machine was sold with partial
memory; boot-time bank sizing handles it per `nd120-dram-memory.md`
section 6) - enough for microcode-level work, OPCOM, self-test,
instruction verification, and small standalone programs; not enough for
an OS image.

### 4.2 Async SRAM on Pmods (IS61WV-class, homebrew/3rd-party Pmod) - FAILS at 40 MHz

**Pin count first (honest):**

| Configuration | Pins needed | Fits 32 signals (4 Pmods)? | Fits 24 (SD plugged)? |
|---------------|------------|----------------------------|----------------------|
| 1M x 16 (e.g. ISSI IS61WV102416) | 20 addr + 16 data + ~4 ctrl = **40** | NO | NO |
| 1M x 18 (word-per-word ideal) | 20 + 18 + 3 = **41** | NO | NO |
| 512K x 8 (IS61WV5128, the CMOD part) | 19 + 8 + 3 = **30** | yes, barely (all 4 Pmods incl. JXADC) | NO |
| 512K x 8 + external address latches (multiplexed) | ~8 data + 8 addr/latch + ~5 ctrl = ~21 | yes | yes |

So a **wide** (single-access) SRAM does not fit the pins at all; only
byte-serial or latch-multiplexed schemes fit, and those cost multiple
Pmod round trips per ND word.

**Timing per byte access through a Pmod** (registered address out on one
OSC edge, data captured on the next - the only safe discipline on
unmatched traces):

```
Tco+IOB out (~3-6) + trace/connector (~1-2) + series-R RC (~2-3, unverified)
+ SRAM tAA 10 ns + return trace + input route/setup (~2-4)
= ~18-25 ns per settled byte  -> exactly one full 25 ns cycle at 40 MHz, ZERO margin
```

(SRAM tAA: the CMOD's part is IS61WV5128BLL-**10**BLI = 10 ns grade per
the ISSI datasheet <https://www.issi.com/WW/pdf/61-64WV5128Axx-Bxx.pdf>;
the CMOD README/Digilent claim of "8 ns at 3.3 V" is the faster bin -
use 10 ns for margin math.)

**Budget check at 40 MHz (75 ns = 3 cycles):**

- 16-bit word as 2 bytes (pack16, parity computed on read): earliest
  pipeline is addr0 out at N+1, capture byte0 at N+2 + addr1 out, capture
  byte1 at N+3, present assembled word -> data valid *just after* N+3,
  meeting "start of N+4" **only if every one of those three 25 ns cycles
  closes the ~18-25 ns round trip above through an unmatched Pmod with
  zero retiming slack**. Against Digilent's own "not intended for high
  frequency operation" / 24 MHz-demonstrated guidance, calling this "meets
  timing" would be dishonest. **Verdict: FAILS at 40 MHz** (design has no
  margin; first reflection or crosstalk event corrupts memory silently -
  remember, no wait state, no retry).
- 18-bit word as 3-4 bytes (data + parity byte(s)): needs 3-4 round trips
  in 3 cycles -> **arithmetically impossible** even with perfect signal
  integrity.
- Latch-multiplexed address (to fit 24 pins): each latch load burns one
  more round trip before the access even starts -> worse.

**Max OSC where it works:** at 25 MHz the column-to-data budget is 120 ns:
2 bytes x ~40 ns/byte (one byte per 40 ns cycle, comfortable margin) =
80 ns + assembly -> **pack16 on a Pmod SRAM plausibly works at <= ~25 MHz**.
At 16.67 MHz (180 ns budget) even a 3-byte (data+parity) scheme fits
(3 x 60 = 180 ns, borderline; pack16 comfortable). All of this is
**unvalidated** - no such Pmod module or bridge exists in the repo today.

### 4.3 The CMOD A7 512 KB SRAM plan (dedicated pins, NOT a Basys3 option) - the 40 MHz ambition is INVALID as planned

Plan source: `Verilog/fpga/cmod-a7-35t/README.md`
(backend phase 2): "8-bit bus means **~4 byte-accesses per 18-bit ND word**
(2 data bytes + parity)". This was never timing-validated. On the CMOD's
dedicated short traces a byte access can be done in **one** clock cycle
(Tco ~4 + tAA 10 + tsu ~2 = ~16 ns < 25 ns), which is the best case:

- **4 byte-accesses**: earliest captures at edges N+2, N+3, N+4, N+5 ->
  word assembled after **N+5**. Deadline is start of N+4. **Misses by 2
  cycles - at ANY frequency**, because the budget is 3 cycles regardless of
  OSC speed when the backend shares the OSC clock. Running an internal 2x
  clock (80 MHz at OSC=40 MHz) does not save it either: 16 ns per byte
  round trip does not fit a 12.5 ns fast cycle, so each byte still needs
  2 fast cycles -> 4 x 25 ns = 100 ns > 75 ns. **The plan's implicit
  40 MHz ambition is invalid as written.**
- **Valid at what OSC?** With a 2x internal clock and 2 fast cycles per
  byte: 4 bytes = 8 fast cycles = 4 OSC cycles -> needs budget >= 4 cycles
  + sync, i.e. **fails the 3-cycle budget at every same-ratio frequency**;
  with a FASTER internal clock (e.g. 100 MHz fixed, 2 x 10 ns cycles per
  byte = 20 ns/byte -> 80 ns + CDC ~20 ns = ~100 ns total) it fits a
  120 ns budget: **OSC <= ~25 MHz**. Note that a same-clock byte-serial
  bridge (>= 1 OSC cycle per byte, 4 bytes) can NEVER fit the 3-cycle
  budget at any frequency - the internal-fast-clock form is mandatory.
- **pack16 rescue (2 bytes, parity computed - the same refactor already
  adopted for the Tang as `ND_SDRAM_PACK16`,
  `Verilog/docs/nd120-parity-analysis.md`):**
  captures at N+2 and N+3, held-register presentation -> meets start of
  N+4 at 40 MHz **with zero slack**, comfortable at <= 33 MHz. This is the
  only shape in which the CMOD SRAM ever reaches 40 MHz, and it is
  borderline.

(The CMOD is research-only, no purchase planned, per its README - but this
validates/invalidates the recorded plan as requested.)

### 4.4 QMTECH-style 16-bit SDRAM burst-of-2 (W9825G6KH-6) - MEETS 40 MHz, but is not a Basys3 option

Datasheet numbers (Winbond W9825G6KH, Rev A04,
<https://www.mouser.com/datasheet/2/949/w9825g6kh_a04-1489735.pdf>, AC
table read from the PDF): **-6 grade = "166MHz/CL3 or 133MHz/CL2"** (order
information table); tCK(CL2) min **7.5 ns**; tRCD min **15 ns**; tRP min
**15 ns**; tAC(CL2) max **6 ns**; tRC min **60 ns**.

Redo the Tang bridge arithmetic at 40 MHz OSC with the section-6 recipe
(2x controller clock = **80 MHz**, fast cycle 12.5 ns - CL2 at 80 MHz is
in spec since CL2 is warranted to 133 MHz):

```
N   : capture row/bank/W_n
N+1 : capture column; issue to controller           (fast edge f0)
f0  : ACTIVE      (tRCD 15 ns -> next command >= f2, 2 x 12.5 = 25 ns OK)
f2  : READ, CL2, BL=2
f4  : data word 0  (f0+4 fast cycles = 50 ns after issue)
f5  : data word 1  (62.5 ns)
      -> both words registered ~2.5-3 OSC cycles after N+1 = by N+4. MEETS.
tAC(CL2) = 6 ns < 12.5 ns fast cycle (with IOB margin, on dedicated PCB pins).
Refresh (we own it): AUTO REFRESH after N+5; tRC 60 ns = 4.8 fast = 2.4 OSC,
done long before the earliest next access at N+11. OK.
Write: ACTIVE f0, WRITE f2 with both beats f2/f3, tWR 2 + tRP 15 ns -> all
inside the 11-cycle (275 ns) RAS-to-RAS floor. OK.
```

**Verdict: the burst-of-2 CL2 bridge meets N+4 at 40 MHz OSC / 80 MHz
controller, in-datasheet.** (The QMTECH handoff's own note - vendor
warrants CL2 @ 100 MHz on this PCB - covers the 80 MHz signal integrity.)
**But this is the QMTECH/Tang answer, not a Basys3 one:** the Basys3 has
no SDRAM chip; transplanting one onto Pmods needs ~34-39 pins (vs 32 max)
and an 80 MHz single-ended bus across unmatched Pmod traces - both
disqualifying. Included only because it was on the researched option list.
(For reference, the implemented Tang bridge's own ceiling with the current
nand2mario controller parameters is OSC ~33 MHz / SDRAM ~66 MHz -
`nd120-dram-memory.md` section 7.)

### 4.5 HyperRAM / octal PSRAM on a Pmod - FAILS at 40 MHz by 3-4x

Reference part: ISSI IS66WVH8M8ALL/BLL 64 Mbit HyperRAM (datasheet:
<https://community.nxp.com/pwmxy87654/attachments/pwmxy87654/imxrt/4083/1/ISSI%2066-67WVH8M8ALL%20HyperRam.pdf>;
purchasable 3 V grade IS66WVH8M8BLL-100B1LI,
<https://www.lcsc.com/product-detail/SRAM_ISSI-Integrated-Silicon-Solution-IS66WVH8M8BLL-100B1LI-TR_C2063871.html>).
Key datasheet numbers: max clock **166 MHz at 1.8 V**, **100 MHz at
3.0 V** (the Pmod-compatible grade); initial access **tACC max 36 ns**;
**CS#-to-first-data-word 56 ns at 166 MHz, EXCLUDING refresh latency**.
A comparable part, Winbond W956D8MBYA, is the same story (200 MHz grade,
35 ns latency - <https://www.lisleapex.com/product-w956d8mbya5i-tr>,
datasheet mirror <https://datasheet4u.com/datasheet/Winbond/W956D8MBYA-1426137>).
Off-the-shelf module: 1BitSquared Pmod HyperRAM
(<https://1bitsquared.com/products/pmod-hyperram>).

The killer is that HyperBus latency is counted in **clock cycles**
(CS# assert + 3-clock Command/Address phase + a configured initial-latency
count whose duration must cover tACC), so slowing the bus clock scales the
entire latency up. The 56 ns figure is ~9.3 clocks at 166 MHz. Best-case
first-word latency through a Pmod:

```
At 100 MHz bus (3 V chip max - NOT credible over unmatched Pmod traces,
  where Digilent's demonstrated figure is 24 MHz and this is a DDR bus
  with a bidirectional RWDS strobe):
  ~9.3 x 10 ns                       = ~93 ns   + FPGA I/O ~5-10 + CDC 2 fast
  -> ~110-120 ns                     vs 75.0 ns  FAIL
At 50 MHz bus (already generous for a Pmod):
  ~9.3 x 20 ns                       = ~186 ns  -> ~210 ns total  FAIL (2.8x)
Refresh collision (RWDS-signaled additional latency) DOUBLES the initial
latency - and with NO wait states the design must budget the 2x case on
EVERY access:
  50 MHz worst case ~ 320-370 ns     vs 75.0 ns  FAIL (4-5x)
```

**Verdict: fails at 40 MHz by a factor of ~3 nominal, ~4-5 worst-case.**
Max OSC it could support (50 MHz bus, 2x-refresh case budgeted, ~340 ns):
3 x Tosc >= 340 ns -> Tosc >= ~113 ns -> **OSC <= ~9 MHz**; even taking the
reckless nominal-only 210 ns figure, OSC <= ~14 MHz. HyperRAM is a
burst-throughput device; this protocol pays its full first-word latency on
every single 1-2 word access. Not a main-memory option here.

### 4.6 UART sector-server / CH376 / SD-card Pmod - storage only, by definition

From `Verilog/docs/usb-storage-options.md`:
the UART sector-server (FT2232, up to 12 Mbaud ~= 1.2 MB/s), the CH376
USB-stick bridge, the MAX3421E host, and the SD-card Pmod all present
**512-byte LBA sectors over the `eng_*` port with millisecond-class
latencies** - 4-7 orders of magnitude away from 75 ns. They are block
STORAGE backends behind `nd_storage`
(`Verilog/docs/nd-storage-design.md`), never
main-memory candidates. Listed here so the option inventory is complete
and their role is unambiguous.

---

## 5. The cache escape hatch - checked and CLOSED

Could a small BRAM cache in front of a slow big store (SRAM/HyperRAM/
sector-server) fake a large main memory? **No.**
`Verilog/docs/nd120-dram-memory.md` is
explicit that stalling is impossible: the PAL_44902A sequence "has fixed
length, there is no way for the memory to stall it". A cache miss needs
tens-to-thousands of cycles to fill; with no wait-state mechanism the
fixed sequence would sample `DD_17_0_OUT` at N+4 regardless and consume
garbage. A cache that may never miss is not a cache. The only way around
it is to **change the PAL FSM contract** - modify `PAL_44902A.v` (and the
`MEM_LBDIF_48` RDATA strobe generation, and the CPU-side grant logic) to
insert wait states that the original hardware never had. That is a
deliberate departure from the measured/recreated hardware behaviour and a
project-level decision, not a memory-backend option.

---

## 6. Verdict table (Basys3 at 40 MHz OSC unless noted)

| Option | First-access latency achievable (column->data) | Meets 75 ns (3 cyc) @ 40 MHz? | Max OSC it could support | Capacity | Pins / hardware | Notes |
|---|---|---|---|---|---|---|
| On-chip BRAM (`MAIN_RAM_BLOCKRAM`) | 1 cycle (data at start of N+3) | **YES**, with a cycle to spare | any (CPU timing closure is the limit, not the RAM) | 24 KB today; ~**64K words / 128 KB max** with `SKIP_WCS_LOAD`; 4 MB = 20x the chip, impossible | 0 pins | The only Basys3 backend that works at target speed |
| Async SRAM on Pmods (512K x 8, pack16) | ~2-3 Pmod round trips ~= 50-75 ns with ZERO margin | **NO** (no engineering margin on unmatched traces; Digilent guidance ~24 MHz signals) | **~25 MHz** (pack16); ~16.67 MHz with parity byte | 512 KB-1 MB per chip | 30 of 32 signals (blocks the SD Pmod); wide SRAM needs 40+ pins - does not fit | Hypothetical module; nothing exists in-repo |
| CMOD A7 512 KB SRAM plan, 4 byte-accesses (dedicated pins, not Basys3) | 4+ cycles | **NO - at any OSC** (3-cycle budget is frequency-independent for a same-clock bridge) | ~25 MHz with a ~100 MHz internal byte engine | 512 KB | CMOD dedicated pins | The plan's 40 MHz ambition is invalid as written |
| CMOD A7 SRAM, pack16 (2 bytes) | 2 cycles + I/O, zero slack | borderline-YES on dedicated pins only | ~33 MHz comfortably; 40 MHz zero-slack | 256K x 16-bit words | CMOD dedicated pins | Only viable shape; still not a Basys3 option |
| QMTECH W9825G6KH-6 SDRAM, BL=2, CL2, 2x clock | data words by ~N+3.5/N+4 (50-62.5 ns after issue at 80 MHz) | **YES - on the QMTECH board** (in-datasheet: CL2 good to 133 MHz) | ~40 MHz+ (controller-parameter limited; Tang's current bridge ~33 MHz) | 2-4 MB for the CPU | on-board chip, 39 pins - impossible via Pmod | Not a Basys3 option; validates the QMTECH stage-3 plan at 40 MHz |
| HyperRAM on Pmod (IS66WVH8M8 / W956D8MBYA) | ~210 ns nominal / ~340 ns refresh-collision at a 50 MHz Pmod bus | **NO** (3-5x over) | **~9 MHz** (worst case budgeted, as no-stall requires); <= ~14 MHz nominal-only | 8 MB | ~12 signals, module exists (1BitSquared) | Clock-counted latency scales with the slow Pmod clock; burst device, wrong workload |
| UART sector-server / CH376 / SD Pmod | milliseconds | NO (storage only) | n/a | GB-class | 2-8 signals | Block storage behind `nd_storage` `eng_*`; never main memory |
| Cache-in-BRAM + any slow store | hit: 1 cycle; miss: unbounded | **NO - architecturally impossible** | n/a | n/a | n/a | Protocol has no wait states; only a PAL_44902A contract change could enable it |

**Plain statement, as required: no external memory reachable through the
Basys3's Pmod connectors meets the ND-120 protocol at 40 MHz. Nothing
comes close except a hypothetical pack16 Pmod SRAM, and that one has zero
engineering margin on connectors Digilent itself rates for ~24 MHz
signalling.**

---

## 7. Recommendations

1. **Accept the board roles.** The Basys3 is the debug/ILA board; the
   Tang Nano 20K (4 MB SDRAM, bridge implemented, OSC <= ~33 MHz today)
   and the QMTECH XC7A35T (32 MB SDRAM; section 4.4 shows its planned
   BL=2/CL2 bridge is in-spec at 40 MHz OSC) are the memory boards. This
   is already the direction of
   `Verilog/fpga/qmtech-a35t/docs/board-notes.md`
   - this report just confirms it with arithmetic.
2. **On the Basys3, run BRAM at full speed and maximize it.** Raise
   `BANK_ADDR_BITS` in
   `Verilog/CPU-BOARD-3202/circuit/MEM_RAM_49_BLOCKRAM.v`
   toward 32K-64K words and adopt `SKIP_WCS_LOAD`
   (`Verilog/docs/skip-wcs-load.md`) to
   reclaim the ~512 Kbit PROM duplicate. 64 KW at 39.06 MHz is a real,
   useful small-memory ND-120 for microcode/instruction/OPCOM/self-test
   work. Do not chase MB-class memory on this board.
3. **Do not build a Pmod SRAM module for 40 MHz.** If Basys3 main memory
   beyond BRAM is ever truly needed, the honest configurations are
   pack16 Pmod SRAM at **<= ~25 MHz OSC**, or staying at 16.67 MHz - and
   both trade away the very 39.06 MHz target that motivated the question.
4. **If MB-class memory on the Basys3 ever becomes non-negotiable**, the
   only real lever is changing the no-wait-state PAL contract
   (`Verilog/PAL/PAL_44902A.v` +
   `MEM_LBDIF_48`) to permit stalls - a deliberate divergence from the
   measured original hardware that should be decided as such, not slipped
   in as a memory backend.
5. **Carry the pack16 lesson everywhere:** every byte- or beat-serial
   backend only fits the 3-cycle budget when an ND word costs at most 2
   backend beats. The parity-computed pack16 contract
   (`Verilog/docs/nd120-parity-analysis.md`)
   is what makes the SDRAM boards work and is the precondition for any
   future SRAM bridge.

---

## 8. Sources

Repo ground truth (all absolute paths):

- `Verilog/docs/nd120-dram-memory.md` - measured protocol, no-wait-state property, backend family, Tang bridge math
- `Verilog/TODO.md` - CMOD A7 section, SD-card plan
- `Verilog/fpga/cmod-a7-35t/README.md` - 512 KB SRAM plan, IS61WV5128BLL-10BLI facts
- `Verilog/fpga/qmtech-a35t/docs/board-notes.md` - board facts; the 16-bit bridge was built as `ND_SDRAM_DQ16`
- `Verilog/fpga/basys3/README.md` - XC7A35T BRAM totals, ~1,044 Kbit utilization
- `Verilog/fpga/basys3/mem-test/basys3_mem_test_top.v` - standalone BRAM-path protocol test
- `Verilog/Shared/support/SIP1M9.v` - proven ramSize=3 BRAM path (registered read, first both-low edge)
- `Verilog/CPU-BOARD-3202/circuit/MEM_RAM_49_BLOCKRAM.v` - `BANK_ADDR_BITS` parameterization
- `Verilog/docs/skip-wcs-load.md` - ~512 Kbit PROM BRAM reclaim
- `Verilog/docs/usb-storage-options.md` - Pmod counts, storage backends
- `Verilog/fpga/basys3/exp_slowclk.tcl` - the 39.06 MHz target statement

External (datasheets/specs, cited inline above):

- Winbond W9825G6KH datasheet Rev A04 (order info + AC characteristics table): <https://www.mouser.com/datasheet/2/949/w9825g6kh_a04-1489735.pdf> (also <https://pdf.digi-electronics.com/pdf/2809/W9825G6KH6ITR-datasheet.pdf>)
- ISSI IS61WV5128 SRAM datasheet: <https://www.issi.com/WW/pdf/61-64WV5128Axx-Bxx.pdf>
- ISSI IS66WVH8M8ALL/BLL HyperRAM datasheet: <https://community.nxp.com/pwmxy87654/attachments/pwmxy87654/imxrt/4083/1/ISSI%2066-67WVH8M8ALL%20HyperRam.pdf>; 3 V 100 MHz grade at <https://www.lcsc.com/product-detail/SRAM_ISSI-Integrated-Silicon-Solution-IS66WVH8M8BLL-100B1LI-TR_C2063871.html>
- Winbond W956D8MBYA HyperRAM: <https://datasheet4u.com/datasheet/Winbond/W956D8MBYA-1426137>, <https://www.lisleapex.com/product-w956d8mbya5i-tr>
- Digilent Pmod Interface Specification 1.2.0: <https://digilent.com/reference/_media/reference/pmod/pmod-interface-specification-1_2_0.pdf>
- Digilent Basys3 reference manual (Pmod routing statement UNVERIFIED - page returned 403 during research): <https://digilent.com/reference/programmable-logic/basys-3/reference-manual>
- 1BitSquared Pmod HyperRAM module: <https://1bitsquared.com/products/pmod-hyperram>
- Toshiba THM91070AS-70 (1M x 9, 70 ns): <https://www.datasheets360.com/part/detail/thm91070as-70/3667810165906245724/>; family databook: <http://bitsavers.org/components/toshiba/_dataBook/1994_Toshiba_DRAM_Components_and_Modules.pdf>

Explicitly UNVERIFIED items in this report: series-resistor values on the
Basys3's standard Pmod ports; the exact speed grade of the THM91020
modules fitted in original ND-120s; all FPGA IOB/route delay figures
(engineering estimates, to be replaced by post-route timing reports when
a bridge is actually built). (The Pmod-routing quote was verified verbatim
against the manual PDF on 13-JUL-2026.)
