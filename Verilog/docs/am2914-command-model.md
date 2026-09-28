# Am2914 Command Model — SHARED SPEC for the ND-120 CGA_INTR

Definitive reference for building command-SEQUENCE functional tests against the
ND-120 DELILAH interrupt controller (`CGA_INTR` / `CGA_INTR_CNTLR`). Every claim
here is traced to one of: the **AMD 1978 *Am2900 Family Data Book*** (the Am2914
datasheet, Table I and the block-diagram text), the **RTL** (file:line), the
**microcode** (the nd120uc repository, `source/ND-120-DELILAH-L.LISTING.txt`
and `.../scripts/nd120_tokens.json`), or a **measured iverilog probe** of
`CGA_INTR_CNTLR`. Anything not so grounded is marked **unknown / inferred**.

> Provenance note. The Am2914 datasheet text quoted below was extracted with
> `pdftotext -layout` from a local copy of
> `1978_The_Am2900_Family_Data_Book.pdf` (Am2914 section, book pages 2-106…2-114;
> Table I "MICROINSTRUCTION SET FOR Am2914 PRIORITY INTERRUPT CIRCUIT",
> book page 2-108). OCR artefacts in the dump were corrected against the RTL.

Repo root for relative paths below: `Verilog`.

---

## 0. Executive summary of the command model

The ND-120 interrupt controller is a faithful re-implementation of the **AMD
Am2914 Vectored Priority Interrupt Controller**, *doubled* to 16 levels (two
8-level Am2914 "groups" — HI and LO — merged into one gate-array block). It is
driven exactly like a real Am2914:

* A **4-bit instruction field** selects one of 16 microinstructions. In the
  ND-120 that field is the port **`LAA_3_0`** (Latched Address A), and its value
  **equals the Am2914 I3–I0 code directly** (decimal). The microcode `PIC,*`
  A-OP field is this same 4-bit value.
* An **instruction-enable** gate: the Am2914 executes the command only when its
  `IE` pin is LOW. In the ND-120 the equivalent is **`EPIC` (active HIGH)** —
  `EPIC=1` executes, `EPIC=0` makes the command a NOP. (Every decoder strobe in
  `CGA_INTR_CNTLR_MDCD.v` is ANDed with `EPIC`.)
* **One `MCLK` rising edge commits a command.** All state (interrupt register,
  mask register, status register, vector-hold register, pass-all / vector-clear
  flip-flops) is edge-triggered on `MCLK` — matching the datasheet: *"The CP
  clock signal is used to clock the Interrupt Register, Mask Register, Status
  Register, Vector Hold Register … all on the clock LOW-to-HIGH transition."*
* **Requests** arrive on `IREQ_15_0_N` (active-LOW), are latched into the
  interrupt register on `MCLK`, ANDed with the mask, and priority-encoded to a
  **3-bit vector `PICV_2_0` + group status `PICS_2_0`**, asserting `IRQN`
  (active-LOW interrupt request) when the winning vector ≥ the status fence.
* **Mask polarity (measured):** a mask bit **= 1 DISABLES** that level, **= 0
  ENABLES** it (classic Am2914). `PICMASK_15_0` reads back the raw mask bits.
  The ND *software* PIE convention is the inverse (1 = enabled), so the microcode
  **inverts** before `PIC,LMSK` (e.g. `ALUF,INVQ` at CS 000730).

**Watch-outs for builders** (details in §4/§6): the software "set a request bit"
path is an ND extension (`FIDBO`+`EMPID` in `CGA_INTR_IRSRC`), **not** an Am2914
instruction; and a full-`CGA_INTR_CNTLR` event-sim can **oscillate/hang** on
X-initialised set/reset latches unless you issue Master Clear + several `MCLK`
pulses first (or test submodules individually, as the existing tbs do).
Since 15-JUL-2026 the 16 request bits use the loop-free `RQBIT_V2`
(`CGA_INTR_CNTLR_IRQ_REG.v` header), so the request-latch case below no longer
applies as written; whether any other latch in the block (e.g. `MASKBIT`) can
still oscillate from X has not been measured since.

---

## 1. THE Am2914 INSTRUCTION SET (datasheet, Table I)

Source: AMD *Am2900 Family Data Book* (1978), Am2914 datasheet, **Table I —
MICROINSTRUCTION SET FOR Am2914 PRIORITY INTERRUPT CIRCUIT** (book p. 2-108).
Code column is the **decimal value of I3 I2 I1 I0** (the datasheet lists the
decimal, not binary). Mnemonics are the datasheet's own.

| Code (I3–I0 dec) | Binary | Mnemonic | Datasheet function |
|---:|:---:|:---|:---|
| 0  | 0000 | **MCLR**  | Master Clear: clear all interrupts, clear mask register, clear status register, clear LGE flip-flop, enable interrupt request |
| 1  | 0001 | **CLAIN** | Clear all interrupts |
| 2  | 0010 | **CLRMB** | Clear interrupts from M-bus data |
| 3  | 0011 | **CLRMR** | Clear interrupts from mask-register data (uses the M bus) |
| 4  | 0100 | **CLRVC** | Clear the individual interrupt associated with the last vector read |
| 5  | 0101 | **RDVC**  | Read vector to V outputs; **load V+1 into the status register**; load V into the vector-hold register; set the vector-clear-enable flip-flop |
| 6  | 0110 | **ROSTA** | Read status register to the S bus |
| 7  | 0111 | **ROM**   | Read mask register to the M bus |
| 8  | 1000 | **SETM**  | Set mask register (**inhibits all interrupts**) |
| 9  | 1001 | **LOSTA** | Load status register from the S bus, and load the LGE flip-flop from the GE input |
| 10 | 1010 | **BCLRM** | Bit clear mask register from M bus (data bit = 1 clears that mask bit) |
| 11 | 1011 | **BSETM** | Bit set mask register from M bus (data bit = 1 sets that mask bit) |
| 12 | 1100 | **CLAM**  | Clear mask register (**enables all priorities**) |
| 13 | 1101 | **DISIN** | Disable interrupt request |
| 14 | 1110 | **LDM**   | Load mask register from M bus |
| 15 | 1111 | **ENIN**  | Enable interrupt request |

Datasheet facts that the tests depend on (block-diagram text, book p. 2-107):

* **Interrupt register** — "eight-bit, edge-triggered register which is set on
  the rising edge of the CP Clock." A LOW on an interrupt input is a request.
* **Mask register** — "the entire register or individual mask bits may be set or
  cleared"; a **set mask bit inhibits** its interrupt (SETM inhibits all, CLAM
  enables all).
* **Priority encoder** — "produces a three-bit encoded vector representing the
  **highest numbered input which is not masked**."
* **Status register** — "holds code for **lowest allowed interrupt** … an
  interrupt request output will occur if the **vector is greater than or equal
  to status**." "Whenever a vector is read … the status register is
  automatically updated to point to one level higher than the vector read"
  (this is the RDVC "V+1 → status" auto-load — the interrupt fence).
* **Status Overflow** — "used to disable all interrupts … indicates the highest
  priority interrupt vector has been read and the Status Register has
  overflowed."
* **Cascade / expansion** signals (for >8 levels): **Group Advance Send / Group
  Advance Receive** (move status upward across devices), **Ripple Disable**,
  **Parallel Disable**, **Interrupt Disable**, **Group Signal (GS)**, **Group
  Enable (GE)** input and the **Lowest-Group-Enabled (LGE)** flip-flop. "In a
  cascaded system only one LGE flip-flop is LOW at a time … the eight-interrupt
  group which contains the lowest-priority level that will be accepted."
* **Instruction enable**: "The command on the instruction lines is executed if
  IE is LOW and is ignored if IE is HIGH." (ND-120: replaced by active-HIGH
  `EPIC`.)

---

## 2. THE ND-120 MAPPING (Am2914 instruction → LAA_3_0 → PIC mnemonic → effect)

**Key fact:** the microcode `PIC,*` A-OP field is a 4-bit value that is wired to
`LAA_3_0`, and **that value is the Am2914 I-code**. The A-OP is written in the
listings as an *octal* digit (e.g. `PIC,LMSK` = "A-OP IS 16" octal = 0xE000 in
microword `w1` → top nibble `E` = **14** decimal = Am2914 **LDM**). All A-OP
values below are taken from
the nd120uc repository, `source/scripts/nd120_tokens.json` (`w1` field) and the
JS `PIC_COMMANDS` table in the nd120uc repository, `docs/index.html:876`.

The per-LAA decoder strobes come from
`DELILAH-CPU/CGA_INTR/circuit/CGA_INTR_CNTLR_MDCD.v` (two `ND38GLP` 3→8 decoders
turn `LAA_3_0` into one-hot active-low lines d0…d15; `sel[X] = (LAA==X)`), and
were independently re-derived and exhaustively checked in
`DELILAH-CPU/CGA_INTR/sim/CGA_INTR_CNTLR_MDCD_tb.v` (128-combo sweep, all 19
strobes). Strobe → register wiring is from `CGA_INTR_CNTLR.v`,
`..._IRQ_MASK(_MASKBIT).v`, `..._CLR.v`, `..._VECGEN*.v`, `..._IRGEL*.v`.

| Am2914 instr | LAA_3_0 | ND PIC mnemonic | MDCD strobes asserted (with EPIC=1) | Effect / register driven |
|:---|:---:|:---|:---|:---|
| MCLR (0)  | 0  | `PIC,MCL`    | A, C, J, HIK, LOK, G, M, L, H, D | **Master Clear.** A/C → mask register → 0 (enable all, measured); J+HIK/LOK → `CLRQ` clears the whole interrupt register (`CLR.v`); status/pass-all reset. |
| CLAIN (1) | 1  | *(none — "CLRMPID", not issued by DELILAH)* | HIK, LOK (unconditional) | Clear **all** latched interrupts via `CLR.v` (HIK/LOK = DCDK for hi/lo groups). Reserved; DELILAH never emits it. |
| CLRMB (2) | 2  | `PIC,MCLPID` | J | Clear interrupts selected by M-bus data. J = `DCDJ` clear-enable in `CLR.v`; the ND "Masked CLear PID". |
| CLRMR (3) | 3  | *(none)* | OEM (EPICMASKN), J | Clear interrupts from **mask-register** data: `OEM` gates `PICMASK` onto the `DIN` mux (`CGA_INTR_CNTLR.v:124` `Multiplexer_bus_2 sel=s_oem`), J enables the clear. Reserved; not emitted by DELILAH. |
| CLRVC (4) | 4  | *(none — "LCLRMPID", not issued)* | HIK & LOK **gated by pass-all latch** (m43q / m42q) | Clear the single interrupt of the **last vector read** (pass-all FFs `MEMORY_42/43` in `MDCD.v` remember which group's vector was read). Reserved. |
| RDVC (5)  | 5  | `PIC,RVECT`  | N (S=~N), HIF and/or LOF, G, M, H | **Read Vector.** `N` clocks the vector-hold register (`VECGEN_VHR`) and drives the V+1→status increment (`VECGEN_STAT`); vector appears on `PICV_2_0`. |
| ROSTA (6) | 6  | `PIC,RSTS`   | OESN (active-low output-enable) | **Read Status:** enables the status register onto the S-bus / `PICS_2_0` (`VECGEN_OSMUX`, `OESN`). |
| ROM (7)   | 7  | `PIC,RMSK`   | OEM (EPICMASKN active-low) | **Read Mask:** `OEM` enables `PICMASK_15_0` onto the M-bus/`DIN` path. Read-only (measured: mask unchanged). |
| SETM (8)  | 8  | *(none)* | A, C (DCDCN=~C=1) | **Set mask = inhibit all** (measured PICMASK→all 1). Reserved; DELILAH uses the `LDM`/`BSETM` path instead. |
| LOSTA (9) | 9  | `PIC,LOSTS`  | HIF and LOF (both), L, H | **Load Status** from the S-bus (`FIDBO_2_0` → HISIN/LOSIN in `VECGEN_STAT`); loads the group-enable / LGE from FIDBO3/FIDBO4. This is the software-written fence used by the `TRA IIC` scan. |
| BCLRM (10)| 10 | `PIC,MCLMSK` | A, B, C (DCDCN=~C=1) | **Bit-clear mask** from M-bus data (measured: data bit=1 → mask bit→0 = enable that level). ND "Masked CLear MASK". |
| BSETM (11)| 11 | `PIC,MSTMSK` | B | **Bit-set mask** from M-bus data (measured: data bit=1 → mask bit→1 = disable that level). ND "Masked SeT MASK". |
| CLAM (12) | 12 | *(none)* | A only (DCDCN=~C=0) | **Clear mask = enable all** (measured PICMASK→all 0). Reserved; DELILAH uses `PIC,MCL`/explicit loads. |
| DISIN (13)| 13 | `PIC,IOF`   | E (=~sel13, active), D | **Disable interrupt request** ("interrupt off"). E/D feed `IRGEL` (HIRL/LORL) group-enable logic that gates `IRQN`. |
| LDM (14)  | 14 | `PIC,LMSK`   | A, B (DCDCN=~C=0) | **Load mask** register from M-bus/`FIDBO` (measured: `PICMASK = FIDBO` straight, all 16 bits). |
| ENIN (15) | 15 | `PIC,ION`   | D only | **Enable interrupt request** ("interrupt on"). D feeds `IRGEL` group-enable. |

**Instructions DELILAH actually issues** (grep of the L-listing): MCL(0),
MCLPID(2), RVECT(5), RSTS(6), RMSK(7), LOSTS(9), MCLMSK(10), MSTMSK(11), IOF(13),
LMSK(14), ION(15). **Not used:** CLAIN(1), CLRMR(3), CLRVC(4), SETM(8), CLAM(12).
(The doc `docs/RUN-level14-livelock-analysis.md` notes A-OP 1/4 exist in the
Microprogrammer's Guide ND-06.031 as CLRMPID/LCLRMPID but the DELILAH microcode
dismisses internal detects via CLR14/MCLPID instead.)

Mask-command decode→`MASKBIT` mapping (from `CGA_INTR_CNTLR_IRQ_MASK.v` +
`..._MASKBIT.v`): `DCDA=A`, `DCDB=B`, `DCDCN=~C`. Measured outcomes
(§4 probe): LDM=load, BSETM=set-where-data1, BCLRM=clear-where-data1,
SETM=all-1, CLAM/MCLR=all-0, ROM=read-only.

**unknown:** exact intended semantics of the reserved combos on **LAA 3 and 8**
inside *this* ND wiring beyond the Am2914 datasheet function (they are never
exercised by DELILAH, so untested here). The `EMPIDN` origin (see §4) is a board
decode not visible in `CGA_INTR` — labelled unknown.

---

## 3. THE 16-LEVEL CASCADE (two Am2914 groups: HI + LO)

Confirmed from `CGA_INTR_CNTLR_VECGEN_PTY.v` and `..._PTY_PTYENC.v`:

* Two 8-input priority encoders. **HI group = `MIREQ_15_8_N`, LO group =
  `MIREQ_7_0_N`** (active-LOW masked requests):
  ```
  PTYENC_HI: RN = MIREQ_15_0_N[15:8]  -> HIDET, HIVEC[2:0]
  PTYENC_LO: RN = MIREQ_15_0_N[7:0]   -> LODET, LOVEC[2:0]
  ```
  (`CGA_INTR_CNTLR_VECGEN_PTY.v:52-62`.)
* Each encoder picks the **highest-numbered active (LOW) input** in its group
  (`..._PTYENC.v`: `V2 = OR(r4..r7)`, etc. — standard highest-wins), and `DET=1`
  if any input in the group is active. This matches the datasheet "highest
  numbered input which is not masked."
* **HI wins over LO.** The winning group's vector is selected in
  `CGA_INTR_CNTLR_IRGEL_VMUX.v` via `HVE`/`LVE` (high/low vector-enable, driven
  by the `IRGEL` HIRL/LORL request-generate + `HIVGES`/`LOVGES` fence-pass
  signals). Group signals `HIGSN`/`LOGSN` and the status registers
  (`HISTAT`/`LOSTAT`) carry the higher-order status/group bits — the ND
  equivalent of the Am2914 GS / LGE / Group-Advance cascade, merged on-chip.

### IREQ bit → (group, in-group level) → reported vector

From `CGA_INTR_IRSRC.v` (source→IREQ bit) cross-referenced with
`docs/RUN-level14-livelock-analysis.md` (measured hivec values):

| IREQ_15_0_N bit | Source (`IRSRC.v`) | Group | In-group idx = reported `PICV_2_0` | Notes |
|---:|:---|:---:|:---:|:---|
| 15 | `BINT15N` \| FIDBO15·EMPID | HI | 7 | highest priority overall |
| 14 | FIDBO14·EMPID (software only) | HI | 6 | the level-14 / MPID software bit; measured hivec 6 |
| 13 | `POWFAILN` \| FIDBO13·EMPID | HI | 5 | POWER FAIL (internal detect) |
| 12 | `MORN` \| FIDBO12·EMPID | HI | 4 | Memory-Out-of-Range; measured hivec 4 |
| 11 | `PARERRN` \| FIDBO11·EMPID | HI | 3 | Parity error |
| 10 | `IOXERRN` \| FIDBO10·EMPID | HI | 2 | IOX error; measured hivec 2 |
| 9  | FIDBO9·EMPID | HI | 1 | (spare / software) |
| 8  | `Z` \| FIDBO8·EMPID | HI | 0 | ALU error flag `Z` |
| 7  | FIDBO7·EMPID | LO | 7 | (software) |
| 6  | FIDBO6·EMPID | LO | 6 | (software) |
| 5  | FIDBO5·EMPID | LO | 5 | (software) |
| 4  | FIDBO4·EMPID | LO | 4 | (software) |
| 3  | `BINT13N` \| FIDBO3·EMPID | LO | 3 | external bus interrupt level 13 |
| 2  | `BINT12N` \| FIDBO2·EMPID | LO | 2 | external bus interrupt level 12 |
| 1  | `BINT11N` \| FIDBO1·EMPID | LO | 1 | external bus interrupt level 11 |
| 0  | `BINT10N` \| FIDBO0·EMPID | LO | 0 | external bus interrupt level 10 (lowest) |

**Absolute priority order, highest → lowest:** bit 15, 14, …, 8 (HI group), then
bit 7, 6, …, 0 (LO group). `PICV_2_0` reports the winning group's in-group index
(`bit-8` for HI, `bit` for LO). The winning group is indicated by
`HIGSN`/`LOGSN` (active-low group signals) and reflected in `PICS_2_0` (the
selected group's status). Internal-interrupt "IIC" code (per the RUN analysis):
`IIC_bit = IREQ_bit − 3` (e.g. IOX IREQ10 → IID/IIC bit 7).

---

## 4. THE DUT + DRIVE MODEL for sequence tests

### DUT candidates

* **`CGA_INTR_CNTLR`** (`DELILAH-CPU/CGA_INTR/circuit/CGA_INTR_CNTLR.v`) — the
  Am2914-equivalent core. **Recommended DUT** for command-sequence tests
  (`IREQ_15_0_N` is a direct input; no board glue).
* **`CGA_INTR`** (`.../CGA_INTR.v`) — wraps CNTLR + `IRSRC` (source→request
  decode) + the `INTRQN`/`PANN` gating. Use this when you must exercise the
  **hardware source pins** (`BINT10N`…`BINT15N`, `IOXERRN`, `MORN`, `PARERRN`,
  `POWFAILN`, `Z`) or the **software set-request** path (`EMPIDN`+`FIDBO`).

### `CGA_INTR_CNTLR` port list (`CGA_INTR_CNTLR.v:12-30`)

Inputs: `sysclk`, `MCLK_EN` (FF-mode clock-enable; 0 in plain latch/event sim),
`EPIC` (active-HIGH command enable), `FIDBO_15_0` (M-bus/S-bus data in),
`IREQ_15_0_N` (active-LOW interrupt requests), `LAA_3_0` (4-bit Am2914 command),
`MCLK` (the CP clock).
Outputs: `EPICMASKN` (mask output-enable, active-low, = ~OEM), `HIGSN`, `LOGSN`
(group signals, active-low), `IRQN` (interrupt request, active-LOW), `PD`,
`PICMASK_15_0` (mask read-back), `PICS_2_0` (status/group), `PICV_2_0` (vector).

### How to issue a command

```
LAA_3_0 = <Am2914 code>;   EPIC = 1;
FIDBO_15_0 = <data>;       // only for LDM/BSETM/BCLRM (M-bus) and LOSTA (S-bus[2:0]=FIDBO[2:0], FIDBO3/4=group-enable)
<rising edge of MCLK>;     // ONE edge commits (all registers are MCLK-posedge)
EPIC = 0 (or change LAA);  // idle
```

* **Clock edges per command: 1** `MCLK` rising edge commits every state-changing
  command (mask ops, LOSTA, RDVC's V+1→status, request-register latching, the
  clear ops). Pure *read* enables (ROSTA/ROM present data combinationally through
  `OESN`/`OEM`; RDVC's V value is combinational, its status side-effect needs the
  edge).
* **`EPIC=0` ⇒ NOP** (Am2914 `IE`-high equivalent).
* **When are outputs valid?** `PICMASK_15_0` is a combinational read-back of the
  mask flip-flops → valid after the committing edge settles. `PICV/PICS/IRQN/
  HIGSN/LOGSN` are combinational functions of the latched request+mask+status
  state → valid once that state has been clocked and the decode settles (a few
  delta-cycles after the `MCLK` edge). `MCLK_EN` is only consulted in
  `FPGA_FF_MODE`; for iverilog event-sim leave `MCLK_EN=0` and toggle the real
  `MCLK` net.

### The four required sub-paths

1. **SET-INTERRUPT-VIA-COMMAND (software raises a request, not a pin).**
   This is an **ND extension, not an Am2914 instruction.** In
   `CGA_INTR_IRSRC.v` each request bit is
   `IREQ_n_N = ~( SOURCE_pin  OR  (FIDBO[n] AND EMPID) )`, e.g.
   `IREQ[10]_N = NOR( NAND(FIDBO[10],EMPID), IOXERRN )`
   (`IRSRC.v:261-275`; `EMPID = ~EMPIDN`). So asserting **`EMPIDN=0`** with the
   desired bit set in **`FIDBO`** forces that request into the interrupt register
   on the next `MCLK` (ND "load PID / MST PID"). Available only through the
   **`CGA_INTR`** wrapper (EMPIDN is a CGA_INTR port). **unknown:** the exact
   board decode that produces `EMPIDN` (labelled in `CGA_INTR.v:23` as
   `EPIC.LDMPIE`); not derivable from these modules.

2. **SET-ALLOWED / mask-load (which levels are enabled).** Use **`LDM` (LAA 14,
   `PIC,LMSK`)** with the mask on `FIDBO`. Measured: `PICMASK = FIDBO` straight.
   **mask bit 1 = disabled, 0 = enabled.** For "enable a set of levels", write
   0s at those bit positions. (`CLAM`/LAA 12 enables all; `SETM`/LAA 8 disables
   all; `BSETM`/`BCLRM` do per-bit set/clear from `FIDBO`.)

3. **CLEAR paths** (`CGA_INTR_CNTLR_CLR.v`, 16 `CLRBIT` cells → `CLRQ_15_0` →
   `IRQ_REG` async-ish clear):
   * **Clear ALL** — `MCLR` (LAA 0) or `CLAIN` (LAA 1): J+HIK+LOK assert →
     `CLRQ` clears every request bit. Measured: after `PIC,MCL` the request
     register and mask both read 0.
   * **Clear from M-bus data** — `CLRMB` (LAA 2, `PIC,MCLPID`): J + `DIN`
     (=FIDBO) selects which bits clear.
   * **Clear last-vector-read** — `CLRVC` (LAA 4): HIK/LOK gated by the pass-all
     FFs (`MDCD` `MEMORY_42/43`) clear only the just-serviced level.
   * The clear decode uses the per-bit `HX_2_0`/`LX_2_0` vector decodes + `HIK`/
     `LOK`/`J` (`CLR.v:68-226`).

4. **Read back the reported level.** `PICV_2_0` = winning in-group 3-bit vector;
   `PICS_2_0` = winning group's status (via `VECGEN_OSMUX`, enabled by `OESN`
   from `ROSTA`); `IRQN` (active-LOW) asserts when a masked request passes the
   status fence `V ≥ S` (`VECGEN_CMP`/`MAGCMP`). To formally read status/vector
   the microcode issues `ROSTA`/`RDVC`; for a testbench the ports are readable
   combinationally at any time.

### Measured drive facts (probe of `CGA_INTR_CNTLR`, iverilog)

Probe files: `…/scratchpad/probe_mask.v` (+ `probe_intr.v`). All commands issued
as `LAA_3_0=code; EPIC=1; FIDBO=data;` then one `MCLK` pulse:

```
LDM(14)  FIDBO=FFFF -> PICMASK=1111111111111111
LDM(14)  FIDBO=0000 -> PICMASK=0000000000000000
SETM(8)             -> PICMASK=1111111111111111   (inhibit all)
CLAM(12)            -> PICMASK=0000000000000000   (enable all)
BCLRM(10) d=00F0    -> PICMASK=1111111100001111   (data bit=1 -> mask bit->0)
BSETM(11) d=0F00    -> PICMASK=0000111100000000   (data bit=1 -> mask bit->1)
ROM(7)              -> EPICMASKN=0 (OEM active), PICMASK unchanged (read-only)
MCLR(0)             -> PICMASK=0000000000000000   (clears mask)
```

**CAUTION — event-sim hazard (measured before 15-JUL-2026, when the request
bits were still the cross-coupled `RQBIT`; they are now the loop-free
`RQBIT_V2`).** Driving the *whole* `CGA_INTR_CNTLR` with
interrupt-request latching from an X-initial state can make the set/reset latches
(`IRQ_REG_RQBIT` NAND feedback) **oscillate and hang** iverilog (observed: a
2-minute timeout on a request-latching probe; the mask-only probe above runs
instantly). Mitigations for builders: (a) start every sequence with `MCLR`
(LAA 0) + a few `MCLK` pulses and `IREQ_15_0_N=16'hFFFF`; (b) prefer `FPGA_FF_MODE`
(`MCLK_EN`) drive; (c) for tight unit checks, target the submodules directly —
the existing tbs already do this: `CGA_INTR_CNTLR_MDCD_tb.v` (all 16 commands ×
strobes), `..._IRQ_MASK(_MASKBIT)_tb.v` (mask ops), `..._IRQ_REG(_RQBIT)_tb.v`
(request latch), `..._VECGEN_*_tb.v` (encoder/status/compare), `..._CLR_tb.v`
(clears), `..._IRGEL*_tb.v` (group generate). Full list under
`DELILAH-CPU/CGA_INTR/sim/`.

---

## 5. WORKED REFERENCE SEQUENCE

Golden flow for builders, on **`CGA_INTR_CNTLR`** (or `CGA_INTR` where a
hardware pin is needed). `IREQ_15_0_N` is active-LOW: bit set to 0 = request
present. Each numbered step = set inputs, one `MCLK` rising edge, then read.
Expected outputs are **derived from the RTL + the measured facts above**; steps
whose dynamic outcome is X-init-sensitive in bare event-sim are flagged.

Assume power-on X. **Preamble:** `IREQ_15_0_N=FFFF`, `EPIC=1`, `LAA=0` (MCLR),
pulse `MCLK` ×3–5 to flush the latches out of X.

| # | Action | LAA (instr) | FIDBO | IREQ_15_0_N (active-low) | Expected after the MCLK edge |
|---:|:---|:---|:---|:---|:---|
| 1 | **Master Clear** | 0 (MCLR) | 0000 | FFFF | `PICMASK=0000` (enable all), request reg cleared, `IRQN=1` (no request). *Needs several edges from cold X.* |
| 2 | **Set allowed = enable all** (LDM with 0 = all enabled) | 14 (LDM) | 0000 | FFFF | `PICMASK=0000000000000000`. |
| 2b | *(alt: enable only some)* LDM with mask | 14 (LDM) | e.g. `FBFF` (bit10 enabled=0, rest disabled=1) | FFFF | `PICMASK=1111101111111111`. |
| 3 | **Assert multiple requests** — pins bit10 (IOX, HI-grp idx2) + bit3 (lvl13, LO-grp idx3) + bit0 (lvl10, LO-grp idx0). Latch with `EPIC=0` (NOP) so decode is frozen while `IRQ_REG` clocks. | 0, `EPIC=0` | — | `FFFF & ~0x0409` = `1111101111110110` | **HI wins:** `PICV_2_0 = 2` (bit10-8), HI group selected → `HIGSN=0`, `LOGSN=1`; `IRQN=0` (request pending, mask all-enabled, fence low). |
| 4 | **Read level** (confirm highest-priority + HI-over-LO cascade) | — (read ports) | — | (unchanged) | `PICV=2`, group=HI. If bit10 were absent, the next winner is bit3 → `PICV=3`, `LOGSN=0`. |
| 5 | **Set a request bit via the internal command** (software raise bit9, HI-grp idx1) — **`CGA_INTR` DUT**, assert `EMPIDN=0`, `FIDBO[9]=1` | 0/idle | `0200` | (pins as step 3) | bit9 enters the interrupt register on the edge. Winner still bit10 (idx2 > idx1) → `PICV=2`. Raise `FIDBO[14]=1` instead (`4000`) → bit14 wins → `PICV=6`. |
| 6 | **Re-read level** | — | — | — | reflects the new highest HI request (`PICV=6` if bit14 raised). |
| 7 | **Clear one interrupt pin** (drop IOX bit10; keep bit3, bit0) | 0, `EPIC=0` | — | `FFFF & ~0x0009` = `1111111111110110` | HI group now empty → **LO wins**: `PICV=3` (bit3), `HIGSN=1`, `LOGSN=0`, `IRQN=0`. |
| 8 | **Re-read level** | — | — | — | `PICV=3`, group=LO. |
| 9 | **Clear detection / chip** (Master Clear) | 0 (MCLR) | 0000 | FFFF | request register + mask cleared; `IRQN=1` (no request); `PICMASK=0`. |
| 10 | **Verify cleared** | — | — | FFFF | `IRQN=1`, no vector asserted. |

Notes / uncertainties for this sequence:

* Steps 1–2 and 9–10 (mask + clear) are **measured** (§4 probe). Steps 3–8
  (request→vector dynamics) are **derived from the RTL priority/mask/cascade
  logic and the measured hivec mapping** in
  `docs/RUN-level14-livelock-analysis.md` (IOX→hivec2, MOR→hivec4, INT14→hivec6);
  the bare-event-sim of the full request path is X-sensitive, so run the preamble
  and expect a few settling edges.
* The **status fence** (`RDVC` V+1→status, `LOSTA` software fence) gates whether a
  request of vector `V` still asserts `IRQN` after a higher one was serviced:
  `IRQN` asserts only when `V ≥ status`. To exercise the fence, insert an `RDVC`
  (LAA 5) after step 4 (loads status = winning V+1) and confirm a same-or-lower
  vector no longer asserts `IRQN` until cleared or status is reloaded via
  `LOSTA`. The FIDBO→status mapping is **straight-through** (`s_fidbo_2_0[i]=
  FIDBO[i]`, `CGA_INTR_CNTLR.v:110-112`) — a 1↔2 swap here was a real fixed bug
  (`CGA_INTR_CNTLR_tb.v` regression-guards it; see the 15-JUL entry in the RUN
  analysis).

---

## 6. Quick reference — signal polarities

* `EPIC` — active **HIGH** command enable (Am2914 `IE` is active-low; ND inverts).
* `IREQ_15_0_N`, `MIREQ_15_0_N` — active **LOW** requests.
* `IRQN`, `HIGSN`, `LOGSN`, `OESN`, `EPICMASKN` — active **LOW**.
* `PICMASK_15_0` — raw mask read-back; **1 = level disabled, 0 = enabled**
  (software PIE = inverse; microcode inverts before `PIC,LMSK`, e.g. CS 000730
  `PIC,LMSK ALUF,INVQ`).
* All registers clock on **`MCLK` rising edge**; combinational strobes A…S track
  `LAA_3_0`+`EPIC` with no clock.
* `MCLK_EN` — only used in `FPGA_FF_MODE`; keep `0` for latch/event sim.

## 7. Source index (absolute paths)

RTL (`Verilog/DELILAH-CPU/CGA_INTR/`):
`circuit/CGA_INTR.v`, `circuit/CGA_INTR_IRSRC.v`, `circuit/CGA_INTR_CNTLR.v`,
`circuit/CGA_INTR_CNTLR_MDCD.v`, `circuit/CGA_INTR_CNTLR_IRQ.v`,
`circuit/CGA_INTR_CNTLR_IRQ_REG(_RQBIT).v`, `circuit/CGA_INTR_CNTLR_IRQ_MASK(_MASKBIT).v`,
`circuit/CGA_INTR_CNTLR_IRQ_MREQ.v`, `circuit/CGA_INTR_CNTLR_CLR(_CLRBIT).v`,
`circuit/CGA_INTR_CNTLR_VECGEN.v` (+ `_PTY(_PTYENC)`, `_ISMUX`, `_OSMUX`, `_CMP(_MAGCMP)`,
`_STAT(_SBIT)`, `_VHR`), `circuit/CGA_INTR_CNTLR_IRGEL.v` (+ `_HIGEL`, `_LOGEL`,
`_HIRL`, `_LORL`, `_VMUX`). Testbenches under `sim/`.

Datasheet: AMD *Am2900 Family Data Book* (1978), Am2914 section, Table I
(book p. 2-108) and block-diagram text (p. 2-107).

Microcode: the nd120uc repository, `source/ND-120-DELILAH-L.LISTING.txt`
(AIIC/`TRA IIC` scan at CS 000725; APID scan at CS 000716),
the nd120uc repository, `source/scripts/nd120_tokens.json` (PIC A-OP `w1`
fields), the nd120uc repository, `docs/index.html:876` (`PIC_COMMANDS`).

Cross-refs: `Verilog/docs/RUN-level14-livelock-analysis.md`
(IIC architecture, measured hivec/status values, FIDBO-swap fix);
`$ND_REPOS/ND110Compile/traces/PIC-TRACE-RUN-ND120.md` (C# PIC
trace); `~/repos/nd100x/src/cpu/cpu.c` (`calcIIC`).
