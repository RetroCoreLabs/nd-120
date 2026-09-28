# The Back-Wiring PROM (installation number) — mechanism, and how to bake it into a bitstream

**Full path:** `Verilog/docs/backwiring-prom-installation-number.md`
**Last updated:** 20-JUL-2026

Every claim below is marked **VERIFIED** (read out of a file in one of these repos,
with the file:line) or **INFERENCE** (reasoned, no schematic found) or **CHOICE**
(a default we picked, not a sourced fact). Nothing else.

---

## 1. What it is

The back-wiring PROM is a small PROM in the ND-100/ND-120 **backplane wiring**
(hence "back wiring"), behind the CPU board's **B-plug**. It holds the machine's
*installation number* and a couple of related site values. SINTRAN III reads it
during startup and uses it to print the **CPU NUMBER** and **CPU TYPE** in its
banner, and to pick up a legal-user count.

It is **not** an I/O device:

- not reachable by `IOX`
- not memory mapped
- not reachable by `TRA`/`TRR`

The **only** way to read it is the **`VERSN` instruction** (opcode `140133`
octal), which selects the internal-data-bus source **`IDBS,INR` = `35` octal**.

---

## 2. Signal path (VERIFIED, with citations)

| What | Where |
|---|---|
| The IDB source itself | `Verilog/DECODE-GateArray/DGA/circuit/DECODE_DGA_IDBS.v:32` — `RINRN //! Read Installation Number from B-PLUG (RINR) - IDBS=35` |
| The 8 data bits come IN from the B-plug | `Verilog/CPU-BOARD-3202/circuit/ND3202D.v:83` — `input [7:0] INR_7_0,` under the `BACKPLANE B-PLUG` / `FROM B plug` header |
| PIL goes OUT to the same B-plug | `Verilog/CPU-BOARD-3202/circuit/ND3202D.v:89` — `output [3:0] PIL` |
| The `RINR_n` gate onto the IDB | `Verilog/CPU-BOARD-3202/circuit/IO_REG_41.v:189` — `assign s_idb_7_0_inr_out[7:0] = s_rinr_n ? 8'b0 : s_inr_7_0[7:0];` |
| The IDB source mux entry | `Verilog/CPU-BOARD-3202/circuit/IO_37.v:295` — `5'o35: s_idb_mux = s_idb_15_0_reg_out; // RINR (installation number)` |
| PIL is STS bits 11:8 | `Verilog/DELILAH-CPU/CGA_ALU/circuit/CGA_ALU.v:134` — `assign s_pil_3_0_out[3:0] = s_sts_15_0[11:8];` |

**B-plug pin mapping of the eight INR bits** (VERIFIED — this comment was already
in `ND120_CORE.v` on the `.INR_7_0()` connection and is preserved there):

```
INR7 .. INR0  =  B15, B4, B5, B17, B8, B7, B13, B6
```

and the PIL nibble that (see §3) addresses the PROM:

```
XPIL3 = B-C8,  PIL2 = B-B12,  PIL1 = B-B10,  PIL0 = B-B9
```

---

## 3. The byte address is PIL[3:0] — **INFERENCE, not read from a schematic**

**No backplane schematic showing the PROM address decode was found**, in this
repo or in NDInsight. The PIL→PROM decode is therefore *not* documented
anywhere we have; it is reconstructed. It is nevertheless a **strong**
inference, resting on three independent legs:

1. **The VERSN microcode loads PIL and then immediately samples INR.**
   `Code/Microcode/ND-120-DELILAH-L.LISTING.txt:115-119` (VERIFIED):

   ```
   0115  000022          A,A                 ALUF,PASSA          ALUD,NONE
   0116  000022          IDBS,ALU            COMM,LDPIL          T,NEXT      T,HOLD;
   0000  000023  % L-ONLY WORD: inserted in version L (not present in the K print)
   0000  000023                              COMM,SLOW           T,NEXT      T,HOLD;
   0118  000024          B,D                 ALUF,PASSD          ALUD,B
   0119  000024          IDBS,INR                                T,NEXT      T,HOLD;
   ```

   `COMM,LDPIL` takes the value off the IDB (here the A register, `ALUF,PASSA`)
   and lands it in **STS bits 11:8**, which *are* PIL (`CGA_ALU.v:134`, VERIFIED).
   So `VERSN`'s "argument" is A bits 8-11 — a 4-bit byte address — and the very
   next thing the microcode does is read INR.

2. **The CPU board drives PIL out to the B-plug and reads INR back in from it**
   (`ND3202D.v:83` and `:89`, both under the B-plug header). A 4-bit output and
   an 8-bit input on the same connector, used by the same instruction.

3. **SINTRAN reads exactly 8 bytes, one per interrupt level 0..7.**
   the NDInsight repository, `SINTRAN/NPL-SOURCE/NPL/PH-P2-OPPSTART.NPL:3534-3570`
   (VERIFIED, quoted in §5) — and its own comment says the level *is* the byte
   number.

**Not known:** whether a real PROM is 16 bytes or larger with PIL as only the
low nibble. We model 16 bytes because PIL is 4 bits.
**Also not known:** the contents of any real back-wiring PROM — **no dump of one
exists in these repos**. Bytes 8-15 in particular are pure filler here.

---

## 4. The LDPIL settle bug and the revision-L `COMM,SLOW` fix

**VERIFIED.** `COMM,LDPIL` has not settled by the time the *next* microword
samples `IDBS,INR`, so the **current** PIL — not the one just loaded — selects
the byte.

- **Revision K** (`Code/Microcode/ND-120-DELILAH-K.LISTING.txt:116-119`) has
  `LDPIL` at `000022` and `IDBS,INR` at `000023`, back to back. Bug present.
  The ND-100/ND-110 are the same.
- **Revision L** (`ND-120-DELILAH-L.LISTING.txt:122`) inserts one extra
  microword `COMM,SLOW` at `000023` between them, marked in the listing as
  `% L-ONLY WORD: inserted in version L (not present in the K print)`. Fix
  present.

**Which microcode does this FPGA/sim build actually load?** Revision **L**.
The control-store PROM images in `Code/Microcode/` are `AM27256_45132L.hex` /
`AM27256_45133L.hex` (loaded by `Verilog/CPU-BOARD-3202/circuit/CPU_CS_PROM_19.v:55,59`),
and `Code/Microcode/readme.md:15` records that `nd-120-delilah-L-from-K.uc`
"Compiles **bit-exact against the EPROM dump — all 4886 words**". The
`wcs_*.hex` preload images used by `runSim` / Tang are generated from those same
two PROM files by `Code/Microcode/gen_wcs_image.py`. So the running machine has
the **L** microcode, i.e. the `COMM,SLOW` fix. *(The L *listing* is itself a
reconstruction — `Code/Microcode/readme.md:14`, "Version L, derived from K by
applying ND's own changes" — but the .uc that produced it is bit-exact against
the real EPROM, which is what matters.)*

**It does not matter for us either way.** SINTRAN works around the bug
unconditionally (§5), and our PROM model simply decodes whatever PIL nibble the
CPU board presents. Both behaviours read the right bytes.

---

## 5. How SINTRAN consumes it — `GCPUNR`

**VERIFIED**, the NDInsight repository, `SINTRAN/NPL-SOURCE/NPL/PH-P2-OPPSTART.NPL:3534-3570`:

```
%       G C P U N R
%       ROUTINE TO GET CPU NUMBER FROM BACK WIRING PROM.
%       CALLED ONLY IF 110/120 CPU.
%       DUE TO ERROR IN MICROPROGRAM THE VERSN INSTRUCTION HAS TO BE
%       EXECUTED ON THE LEVEL CORRESPONDING TO THE BYT NO. TO BE READ.
SUBR GCPUNR
INTEGER INF0,INF1,INF2,INF3
GCPUNR: *PIOF
        400;  *IRW 10 DA; LDA (EXVE; IRW 10 DP      % plant EXVE on level 1
        ... levels 2..7 the same ...
        377; *TRR PIE; TRR PID; ION; IOF; PON
        A:=0; *TRR PIE; VERSN; 1BANK               % level 0 -> byte 0
        T:="INF0"; X:=0; A:=D; *SBYT
        X+1; *IRR 10 DD; SBYT                      % level 1 -> byte 1
        ... levels 2..7 ...
        IF INF3><52652 THEN EXIT FI                % NOT CORRECT PROM
        IF INF0><-1 THEN
           A=:SYSNO=:FCPUN; 1=:PRFLAG              % CPU NUMBER
        FI
        IF INF1><-1 THEN A=:HWINFO(2) FI           % CPU TYPE
        IF INF2 SHZ -10><377 THEN A=:NLEGU FI      % NUMBER OF LEGAL USERS
        EXIT
EXVE:   *VERSN; WAIT
```

Note `A:=0` before every `VERSN` — SINTRAN never uses the A-register byte
address at all. It plants a one-instruction `VERSN` stub on interrupt levels 1-7
and runs each one, so the *current* PIL supplies the byte number. That is the
unconditional workaround for the §4 bug, and it is why levels 0..7 / bytes 0..7
are the only ones ever read.

### Decoded byte layout

| Byte(s) | Meaning | "absent" sentinel |
|---|---|---|
| 0 (MSB) + 1 (LSB) | `SYSNO` → banner **CPU NUMBER** (also `FCPUN`, sets `PRFLAG`) | word = `-1` (`0xFFFF`) ⇒ skipped |
| 2 (MSB) + 3 (LSB) | `HWINFO(2)` system type → banner **CPU TYPE** | word = `-1` (`0xFFFF`) ⇒ skipped |
| 4 | `NLEGU`, number of legal users | byte 4 = `0377`B (`0xFF`) ⇒ skipped |
| 5 | low half of `INF2`; **`GCPUNR` only uses the high byte** (`INF2 SHZ -10`), so byte 5 has no known consumer | — |
| 6 + 7 | signature `INF3`, **must be `52652`B = 21930 = `0x55AA`** (byte6 = `0x55`, byte7 = `0xAA`) | — |
| 8-15 | unknown; SINTRAN never reads them | — |

**The signature gates everything.** `IF INF3><52652 THEN EXIT FI` runs *first*:
a wrong signature and `GCPUNR` returns having applied nothing at all.

**Values.** Documented system types are `100, 102, 500, 502, 5561`, and the list
is explicitly open-ended (`OPPSTART.NPL:3440`) — there is **no ND-120-specific
system-type value documented anywhere we found**; the CPU identity proper lives
in `HWINFO(0)`, not `HWINFO(2)`. One live-verified pair exists:
`SYSNO=102 / HWINFO(2)=9883`
(the NDInsight repository, `SINTRAN/SINTRAN Structures/SINTRAN-STRUCTURES.md:2036-2039`).

**`SYSNO` is functional, not cosmetic** — COSMOS local-vs-remote routing keys on
it, so it must be **unique per machine** on a site.

---

## 6. What this repo used to do (the defect) and what it does now

**Before:** `Verilog/ND120_CORE.v:222` hardwired

```verilog
wire [7:0] installation_number = 8'd123;
```

for *every* PIL value. Byte 6 read `123` instead of `0x55`, so `INF3` could
never be `52652`B, so `GCPUNR` always hit `EXIT` — the FPGA/sim machine could
never report a configured CPU NUMBER or CPU TYPE.

**Now:** a real 16-byte PROM, `BACKWIRING_PROM`, addressed by `PIL[3:0]`:

- `Verilog/Shared/support/BACKWIRING_PROM.v` — the PROM model
- `Verilog/Shared/support/nd120_backwiring_defaults.vh` — build-time defaults + sentinels
- `Verilog/ND120_CORE.v` — `installation_number` is now a wire driven by the
  `BACKPLANE_INR_PROM` instance, whose `.PIL_3_0` is the same `PIL` nibble the
  CPU board drives to the B-plug
- `Verilog/Shared/support/sim/BACKWIRING_PROM_tb.v` — unit testbench
  (`make test-inrprom`, registered in `Verilog/tests/run_all_tests.sh`)

### Why the PROM sits in `ND120_CORE`, not in `CPU-BOARD-3202`

On the real machine the PROM is part of the **back wiring**; the CPU board only
drives `PIL` out on the B-plug and takes `INR_7_0` back in. `ND120_CORE.v` is
the first level above the CPU board and already owns the other B-plug constants
(`EBUS`, `SEL5MS_n`), so it is exactly the right side of that interface.
**Nothing inside `CPU-BOARD-3202/` was changed** — `ND3202D.v`, `IO_37.v` and
`IO_REG_41.v` were already correct.

---

## 7. Setting the values at build time

Three parameters, exposed both as Verilog `parameter`s (on `BACKWIRING_PROM`
and passed through `ND120_CORE`) and as `` `define`` macros — the same
`param + `define default` idiom `SC2661_UART.v:139-144` uses for
`BOARD_CLK_FREQ` / `UART_BAUD_RATE`. Macros are what the build flows here
actually use, so that is the documented route.

| Macro / parameter | Width | Default | Sentinel = "not present" |
|---|---|---|---|
| `ND120_SYSNO` / `SYSNO` | 16 | `16'd120` — **CHOICE**, see below | `16'hFFFF` |
| `ND120_HWINFO2` / `HWINFO2` | 16 | `16'd102` — **CHOICE**, see below | `16'hFFFF` |
| `ND120_NLEGU` / `NLEGU` | 8 | `8'o377` (= absent) — **CHOICE**, see below | `8'o377` |
| `ND120_INR_BYTE5` | 8 | `8'h00` — filler, no known consumer | — |
| `ND120_INR_FILLER` | 8 | `8'h00` — bytes 8-15, never read by SINTRAN | — |

Bytes 6/7 are `localparam`s `0x55` / `0xAA` inside `BACKWIRING_PROM.v` and are
**deliberately not parameterisable**: a wrong signature disables every other
field, so there is no legitimate build that wants a different value.

### The defaults are choices, not documentation

- **`SYSNO = 120`** — **CHOSEN**, no source. `SYSNO` must be unique per machine
  on a COSMOS site; 120 is just "this is the ND-120". *Override it per build.*
- **`HWINFO2 = 102`** — **CHOSEN** from the documented open-ended type list
  (`100, 102, 500, 502, 5561`). It is a documented type, and 102 is the SYSNO of
  the one live-verified pair we have. It is **not** an ND-120-specific value;
  no such value is documented.
- **`NLEGU = 0377`B (absent)** — **CHOSEN deliberately as the sentinel**. NLEGU
  is a licence limit; inventing a number could silently shrink a working
  system's user count, so the stock build declines to answer and SINTRAN keeps
  whatever its own image has.

With these defaults a **stock build has a VALID PROM** (correct signature) and
SINTRAN will print a configured CPU NUMBER (120) and CPU TYPE (102) instead of
falling through to the image-baked values.

### Override syntax

**Verilator / `runSim` and `sim` — VERIFIED**
(the `EXTRA_VDEFINES` hook already exists in `runSim/Makefile:15-18`):

```bash
make -C runSim compile EXTRA_VDEFINES="-DND120_SYSNO=16'd42 -DND120_HWINFO2=16'd9883 -DND120_NLEGU=8'd32"
```

**iverilog (unit tb) — VERIFIED**:

```bash
cd Verilog/Shared/support/sim
iverilog -g2012 -DND120_SYSNO=16\'d4242 -DND120_NLEGU=8\'d64 -o /tmp/inr_ovr -I.. BACKWIRING_PROM_tb.v ../BACKWIRING_PROM.v
vvp /tmp/inr_ovr
```

**yosys (the OSS Tang flow's front end) — VERIFIED.** Elaborating the PROM alone
with the override and dumping the result shows the bytes actually change:

```bash
yosys -q -p "read_verilog -DND120_SYSNO=16'd4242 -I. BACKWIRING_PROM.v; \
             hierarchy -top BACKWIRING_PROM; proc; opt -full; write_verilog /tmp/inr_yosys.v"
```

```
[0] = 8'h10;   [1] = 8'h92;    <- 0x1092 = 4242, the override took
[2] = 8'h00;   [3] = 8'h66;    <- 0x0066 = 102, the default HWINFO2
[4] = 8'hff;                   <- NLEGU default = "absent"
[6] = 8'h55;   [7] = 8'haa;    <- signature, forced
```

**Tang Nano 20K (Gowin GW2AR-18, the flow that builds bitstreams today) —
ELABORATION VERIFIED, no bitstream built.** `read_verilog` + `hierarchy -top
ND120_TANG20K_TOP` over the full `nd120_tang20k.gprj` file list (with the new
`-I../../Shared/support`) completes with no errors. The repo's own
one-source-of-truth mechanism for values is the defines file, which is compiled
first, so add:

```verilog
// Verilog/fpga/tang-nano-20k/src/tang20k_defines.v
`define ND120_SYSNO   16'd42
`define ND120_HWINFO2 16'd102
`define ND120_NLEGU   8'd32
```

The yosys command-line form works too (verified above); in the Tang Makefile it
would go in `VDEFS` — but overriding `VDEFS` on the make command line clobbers
the `VARIANT` define, so the defines file is the safe route.

**Gotcha, learned the hard way:** a Verilog comment whose text *starts* with the
word `verilator` (case-insensitive, leading whitespace ignored) is parsed by
Verilator as a metacomment and aborts the build with
`%Error: Unknown verilator comment`. That is why the tool names in
`nd120_backwiring_defaults.vh` are bulleted with `* ` instead of leading the line.

**Basys3 / Vivado** — `BACKWIRING_PROM.v` and `nd120_backwiring_defaults.vh`
were added to the explicit source list in `fpga/basys3/vivado_build.tcl`.
Override would be via `verilog_define` on `synth_1`. **NOT TESTED** (no Vivado
run was performed here).

### Building a "nothing is configured" bitstream

Set all three to their sentinels; the signature stays valid, so `GCPUNR` runs to
the end and simply skips every field:

```bash
make -C runSim compile EXTRA_VDEFINES="-DND120_SYSNO=16'hFFFF -DND120_HWINFO2=16'hFFFF -DND120_NLEGU=8'o377"
```

This case is covered by pass 3 of `BACKWIRING_PROM_tb.v`.

---

## 8. What is NOT verified

- **The PIL→PROM address decode itself** — inference (§3). No backplane
  schematic found.
- **The contents of a real back-wiring PROM** — no dump exists in these repos.
  Bytes 8-15 are our filler; byte 5 is our filler.
- **Whether a real machine's PROM is 16 bytes.** PIL is 4 bits; we model 16.
- **End-to-end `VERSN` execution in simulation.** The `runSim` harness does not
  boot SINTRAN and no test in the repo executes `VERSN`, so nothing here proves
  the *instruction* returns these bytes on this RTL — only that the PROM
  returns the right byte for every `PIL` value (unit tb) and that the design
  still elaborates, builds and boots identically (§9 of the commit report).
- **Any FPGA bitstream build** (Gowin or Vivado) after this change.

---

## 9. NOT the PROM: print number / print release / ECO level (the ALD register)

`VERSN` returns **three** registers, and only **D** comes from the back-wiring
PROM. **T** is the microprogram version and **A** is a bit-field describing the
**CPU board itself**. Those A-register fields are frequently confused with the
back-wiring PROM, so they are recorded here — they are *board* attributes, wired
on the CPU board, and have nothing to do with the backplane PROM.

### 9.1 The A-register layout (VERIFIED, from the microcode)

The `VERSN` microroutine reads the ALD register (`IDBS,ALD`) and XORs it with an
`ARG` literal. `Code/Microcode/ND-120-DELILAH-L.LISTING.txt` lines 124-133:

```
0124  000026                              ALUF,PASSD          ALUD,Q
0125  000026          IDBS,ARG                                T,NEXT      T,HOLD
0126  000026          40377;
0128  000027  %CC INVERT BIT 0-3 (ALD), BIT 4-6 (PRINT RELEASE), BIT 7 (CX); BIT14 (PRINT NO)
0129  000027  %CC BIT7=1 => HIGH SPEED, BIT 15-13=101 => 3202
0131  000027          B,A                 ALUF,XORDQ          ALUD,B
0132  000027          IDBS,ALD                                T,JMP       T,HOLD
```

`40377` octal = `0x40FF` = bits 0-7 plus bit 14, so exactly those bits are
inverted. The value the guest sees is therefore:

| A bits | field | ND-120 / 3202D value |
|--------|-------|----------------------|
| 15-13 | PRINT NUMBER | `101` binary = 5 → board print **3202** (microcode comment, line 129) |
| 12-8  | ECO LEVEL (straps 5..9) | `10100` binary = 20 |
| 7     | CX / HIGH SPEED | 1 |
| 6-4   | PRINT RELEASE | `100` binary = 4 → release **D** |
| 3-0   | ALD switch code | the ALD setting |

### 9.2 Where each field is wired (VERIFIED)

All of them are on **CPU board 3202 sheet 41**,
`CPU-BOARD-3202/circuit/IO_REG_41.v`:

- **PRINT RELEASE** — `:121` `assign s_print_no[2:0] = 3'b011;  // 011 == 3202D`,
  driven onto IDB 6/5/4 by `CHIP_25A_ALD` (`:222-240`). The microcode inverts
  bits 4-6, so the raw `011` is seen by software as `100` — which is exactly the
  "`0b100` for version D" recorded in `Logisim/CPU-BOARD-3202/readme.md:59`.
- **CX** — `s_cx_n` onto IDB 7 in the same buffer; inverted by the XOR, so a
  fitted CX (active-low, 0) reads back as 1 = "HIGH SPEED".
- **ECO LEVEL** — `:126-130`, the five straps
  (`STRAP9→IDB8, STRAP8→IDB9, STRAP7→IDB10, STRAP6→IDB11, STRAP5→IDB12`), driven
  by `CHIP_27A_STRAP` (`:198-219`). A *fitted* strap pulls the line LOW, so a
  fitted strap reads 0. The stock build is commented
  "`Set to ECO 100-785. Strap on 6,8 and 9`" → straps 9,8,7,6,5 = 0,0,1,0,1 →
  field value `10100` binary = 20. These bits are **NOT** inverted by the XOR.
  `Logisim/CPU-BOARD-3202/readme.md:59` says the same in words: "ALD register has
  also STRAP 5-9 info in IDB11-IDB8 (For reading ECO level)".
- **PRINT NUMBER** — IDB 15/14/13 are the `1'b1, 1'b1, s_strap_5`-side constants
  of `CHIP_27A_STRAP` (`:198-219`): IDB15 = 1, IDB14 = 1, IDB13 = 1. The XOR
  inverts **bit 14 only**, so software sees `101` — the code the microcode
  comment maps to print 3202.

### 9.2b How TPE renders the ECO level — **MEASURED**, not sourced

No listing of the TPE `INSTRUCTION` diagnostic's decode was found. It was probed
instead, by booting the real TPE floppy in the RetroCore emulator once per strap
value and reading the `ECO level............:` line:

| A bits 12-8 | TPE prints |
|-------------|------------|
| 0, 1, 2, 3, 4, 5, 8 (bit 12 clear) | `B` |
| 16 (bit 12 set, bits 11-8 = 0) | `T` |
| 20 (bit 12 set, bits 11-8 = 4) | `P` |
| 31 (bit 12 set, bits 11-8 = 15) | `C` |

Those three "bit 12 set" points fit a **descending letter list that skips `I` and
`O`** — `T S R Q P N M L K J H G F E D C` — indexed by bits 11-8. The list is an
**INFERENCE** from three samples, not a read of TPE's code. With the stock 3202D
straps (field value 20) TPE prints **`P`**.

### 9.2c A caveat found while emulating this (MEASURED)

The RetroCore emulator was changed to return this exact A bit-field. Reporting the
sourced print-number code `101` makes the **SINTRAN III disk image RetroCore boots**
abort during `LOCOSTORE` with

```
Mismatch  CPU / micro-code-segm
System malfunction. Sintran halt in ERRFATAL. L-reg: 035551
```

(the CPU-vs-microcode-segment branch at `PH-P2-RESTART.NPL:035542`), on both an
ND-110/CX and an ND-120/CX. Bisection showed the ECO straps and the microprogram
version are innocent — it is specifically A bits 15-13. Why that particular
SINTRAN image rejects the 3202 code was **not** root-caused, and it is **not** a
claim about real hardware or about this RTL. Recorded here only so the next person
who wires these bits into an emulator is not surprised.

### 9.3 ND-110 difference (VERIFIED)

The ND-110 microcode (`ND110Compile/ND110Compile/uCode/ND-110-RASK.LISTING.TXT`
lines 123-128) XORs with **`17` octal only**, i.e. it inverts just the ALD nibble
and passes bits 4-15 straight through from that board's ALD register. The
*layout* is the same (the same TPE diagnostic decodes both); only the raw strap
polarity differs. No ND-110 CPU-board schematic or strap list exists in these
repos, so the ND-110's own print number / release / ECO straps are **UNKNOWN**.

### 9.4 Also not the PROM: the microprogram version (T)

`VERSN` loads T straight from an `ARG` literal in its first microword:

- `ND-110-RASK.LISTING.TXT:107-109` → `13;` = octal 13 = `0x000B` (revision K)
- `ND-120-DELILAH-K.LISTING.txt:106-108` → `100013;` = `0x800B`
- `ND-120-DELILAH-L.LISTING.txt:106-108` → `100014;` = `0x800C`

Octal `100000` is bit 15, the ND-120 CPU-type identity bit; the **high byte is
zero** in all three. Low 8 bits = revision letter as plain alphabet position
(A=1 … K=013 … L=014, "I" not skipped).

### 9.5 Should these be build parameters like `ND120_SYSNO`? — **No** (decision)

`SYSNO` / `HWINFO2` / `NLEGU` are *site/installation* values: they legitimately
differ per machine, which is why they were parameterised in
`Shared/support/nd120_backwiring_defaults.vh`. Print number, print release and
the ECO straps are *this board's identity* — they say "this is a 3202D at ECO
100-785". Changing them would make the simulated board lie about which board it
is. They are therefore left as the plain, commented `assign` constants in
`IO_REG_41.v`, which is already the accurate model of the real board. Anyone
building a different board revision edits those two `assign` lines (`:121` and
`:126-130`), which are documented above.
