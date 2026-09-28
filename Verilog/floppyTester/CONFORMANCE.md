# Floppy Conformance Matrix — Phase 0 deliverable

Full path: `Verilog/floppyTester/CONFORMANCE.md`
Date: 20-JUL-2026. Sources: three cited extractions —
(A) C oracle `src/devices/floppy/deviceFloppyDMA.c` + `.h` in the nd100x repository,
(B) Verilog `Verilog/ND-BUS-DEVICES/FLOPPY-DMA/circuit/ND_FLOPPY_DMA.v`,
(C) Microcode `Code/Microcode/ND-120-DELILAH-L.LISTING.txt`
(cross-verified against the EPROM words in `Code/Microcode/AM27256_4513{2,3}L.bin` and the nd120uc token JSON).
Every claim below carries its origin (A/B/C + line/CSA). Tags: **BUG** (must fix),
**DEVIATE** (differs from oracle, decide), **QUIRK** (oracle oddity, probably keep ours),
**UNKNOWN** (needs manual/NDInsight).

---

## Ground rules of the campaign

Kept from the retired `PLAN-floppy-validation.md` (20-JUL-2026; its goal, a
full `1560&` boot, was met 27-JUL-2026 - see `HISTORY.md`). The testbenches it
planned live in `Verilog/ND-BUS-DEVICES/FLOPPY-DMA/sim/`, not in this folder.

- **Oracle:** the nd100x C device (`deviceFloppyDMA.c` + `.h`) is the
  behavioural truth for floppy semantics. When the C code and the 3112 manual
  disagree, ND-11.021 decides (`Verilog/docs/floppy-3112-register-spec-ND-11.021.md`).
- **Test diskette:** `Verilog/runSim/FLOPPY.IMG` (1,261,568 bytes, FLOMON
  boot sector, TPE-MON-100-A02:BPUN + 20 :TEST programs), named `FLOPPY1.IMG`
  on SD cards.
- **Pass pattern for a real boot:** TPE ends at a `TPE>` prompt.
- **Who owns what (agreed 20-JUL-2026 with the NDDeviceCore work).** The
  NDDeviceCore side tests its portable C floppy by driving raw ND-bus signals
  from C in Verilator, with all Verilog devices disconnected.

  | NDDeviceCore side | Verilog device side |
  |---|---|
  | NDDeviceCore repo, `simDevices/NDCoreShim*`, `NDCoreBlockBackend*`, `NDDeviceCoreAdapter` | `ND_FLOPPY_DMA.v`, `ND_BUS_SLAVE.v`, `ND_DMA_MASTER.v`, `ND_TAPE_400.v`, SD-FAT stack, `floppyTester/` |
  | flags `DEVICECORE`/`DEVICECORE_FLOPPY`, env `ND120_FLOPPYCORE_IMG`, gates `test-floppy-core-iox` / `test-floppy-core-boot` (`Verilog/Makefile`) | env `ND120_FLOPPY_IMG`, gates `test-floppy-dma` / `-iox` / `-p2` / `-boot` / `-sdfat` (`ND-BUS-DEVICES/FLOPPY-DMA/sim/Makefile`) |

  Neither side edits the other's cores. Shared files, additive edits only:
  `runSim/Makefile`, `Run120.cpp`, `Verilog/Makefile`, and possibly
  `ND120_TOP.v` (sim-only master-signal ports behind `ifdef VERILATOR_SIM`).
  Their autoload is to be modelled on the nd100x oracle, not on our
  `ND_FLOPPY_DMA.v`.
- In `Run120.cpp`, `ND120_FLOPPYCORE_IMG` also counts as a mounted boot medium
  (it suppresses the DEBUG.BPUN default pre-deposit), and `ND120_PRELOAD_BPUN`
  set but empty means no pre-deposit in any build.
- `make run-floppy` pre-deposits `FILSYS-INV-Q04.BPUN` (the file-system
  investigator) so `20!` starts it against the mounted diskette.

## 0. HEADLINE — the `1560&` mystery is SOLVED (C)

1. **`$` and `&` are the SAME microcode handler.** `DOLOA:`/`ETLOA:` are two labels
   on CSA 002257; the dispatch words differ only in the compared character. Nothing
   downstream knows which was typed. (C: lines 6096-6101, EPROM words at 002470/002471.)
2. **Bit 13 of the typed octal NUMBER selects the mechanism, not the character:**
   - `1560&` (bit 13=0) → `ETLO1` (002262): the **character-stream BPUN parser** —
     the same grammar as tape `400$`. This is why our generated BPUN diskette boots.
   - **`21560&`** (bit 13=1) → `MASS` (002217): the **hardware-autoload path** — the
     CONTROLLER moves the boot image into core by DMA; the CPU never sees the data,
     then starts at address 0. (C: lines 5837-5955; ALD table pairs 1560/21560 as
     distinct entries, lines 9655-9694.)
3. **The stream parser has NO FLOMON branch** (C: §4 of the analysis, 002262-002332).
   A FLOMON boot sector fed to `1560&` parses as: load address 0, word count 0x0040
   (the FLOMON zero-triple + 1-byte count misread as BPUN fields), loads the monitor
   code to address 0, then hits a checksum word FLOMON does not have → **`?`**.
   **This exactly matches Ronny's observation** (`1560&` on FLOPPY.IMG → instant `?`).
   The microcode is behaving CORRECTLY; there is no stream-parser bug.
4. **VERDICT: booting a real FLOMON diskette requires the `21560&` MASS path, and
   NEITHER our Verilog device NOR the C oracle implements it.**
   - C oracle: `ExecuteAutoload` is a documented stub — always error oct 50 +
     DMAs the (Ghidra-verified, byte-exact) "** LOAD-ERROR: 50 **" program to core 0
     (A: .c:326-349, 293-323). Its own TODO describes the real firmware behavior:
     "read track 0, scan for '!', parse header, DMA image" → NDInsight FloppyDMA
     docs §4.3.
   - Verilog: implements only the per-word +0 stream serving used by `1560&`;
     the MASS register protocol (below) hits registers that ignore it → the CPU
     polls +4 forever = **silent hang** (B: +1/+6 writes ignored, +5 sets
     pointer-HI, +4 poll of `s_active` which never sets without a command).

### The MASS protocol our device must serve to boot real diskettes (C: 5870-5955)

| Step | IOX | Value | Microcode comment |
|---|---|---|---|
| 1 | write +1 | 0 | "CORE ADDRESS" (written TWICE, identical EPROM words at 002221/002222) |
| 2 | write +3 | 0 | "BLOCK ADDRESS" |
| 3 | write +7 | 2000₈ (=1024) | "WORD COUNTER" |
| 4 | write +5 | 4 | "ACTIVATE DEVICE" (bit 2) |
| 5 | poll read +4 | until bit 2 set | "DEVICE FINISHED" |
| 6 | read +4 | bit 1 = error → retry FOREVER from step 1 | |
| 7 | — | CPU sets P := 0, `COMM,START` | boot code must be at core 0 |

**RESOLVED by NDInsight** (`SINTRAN/Devices/FloppyDMA/04-boot-and-autoload.md`
in the NDInsight repository, from the reverse-engineered Z80 firmware ROM):

- The REAL diskette boot is performed by the **card's Z80 firmware**
  (`Autoload_BootstrapLoad @ram:1ae8`, firmware-verified): RESTORE to track 0 →
  read 2048 bytes → `CPIR` scan for **`'!'` (0x21)** → validate a CR within the
  preceding 128 bytes with an octal digit before it (else **err oct 50**) →
  parse the ASCII/stride-2 header (the FLOMON layout; fields at offsets -3, +5,
  +7, +10 relative to '!') into a 24-bit host load address + count → detect
  out-of-date FLO-MON (`'2'…'@'…checksum='R'` → **err oct 51**) → **DMA the
  image into ND memory itself** in 0x800-byte chunks → completion interrupt.
  The Z80 does NOT start the program — the ND-100 LOAD microcode jumps into
  the loaded image. On failure the firmware DMAs the byte-exact LOAD-ERROR
  print program to core 0 (the part the C oracle already replicates).
- Trigger ambiguity is documented in the firmware analysis (§4.2, COULD NOT
  DETERMINE whether the LOAD microcode asserts control bit 2, bit 8, or both;
  a bit-2-alone gate dispatches a different, non-bootstrap handler). §4.6
  gives the emulator recipe: accept the autoload control word, do the '!'
  scan/validate/parse/DMA/complete — exactly the role our Verilog device must
  play (it IS the card).
- Exact firmware header arithmetic is COULD-NOT-DETERMINE; §4.6(b) sanctions
  parsing the format from its own spec — we have that: the ndfs FLOMON parser
  (`ndfs-py/src/ndfs/boot_loader.py` in the norskdata-ndfs repository) + real
  diskettes to validate against. Ground-truth memory images for validation:
  `$ND_REPOS/RetroGhidra/N100-FLOPPY-3112/ND Code\` (Load_error.txt,
  wrong_bootstrap.txt, `DEPOSIT 0 77400.txt` = a working bootstrap image).

**Implementation shape that keeps today's working path intact:** leave the
`+3`-bit-2 stream-arm behavior exactly as is (`1560&` BPUN boot keeps working),
and trigger the firmware-equivalent FLOMON autoload off the **MASS sequence**
(`+5` write value 4 — a register write the stream path never performs), completing
by setting the status bit the MASS microcode polls, with the image DMA'd at the
header-derived address so the CPU's `START at 0` lands in it. Error paths oct
50/51/53 per §4.4, LOAD-ERROR image on failure (reuse the C oracle's byte-exact
builder as reference).

### Practical consequences

- **Today, without new RTL:** a real diskette can be booted by repacking its
  FLOMON payload as BPUN with ndtool (norskdata-ndfs repository) →
  `1560&` boots it. TPE-MON extraction is the same workflow.
- **To boot real diskettes AS-IS:** implement MASS autoload + FLOMON parsing in
  `ND_FLOPPY_DMA.v` (the device plays the Z80 firmware's role), per NDInsight §4.3.
- **NDDeviceCore team:** all of the above applies 1:1 to their Pico card — their
  autoload stub is inherited from the same C oracle, and the MASS protocol table
  above is exactly what their firmware must serve. Relay it.

### `1560&` stream protocol (ETLO1) — what the device must serve (C: §2-3)

- Activate: **IOX +3 write 4005₈** at entry AND after EVERY character (bit 2 set;
  note bits 0 and 11 also set, bit 1 clear).
- Per byte: poll +2 until status bit 3 (RFT) set (forever, no timeout), read +0,
  take the LOW byte (leader masked 177₈, binary part 377₈).
- Grammar: ASCII leader — octal digits accumulate; CR sets P (start address) from
  the accumulated number; '!' enters binary. Binary: load-address word (hi byte
  first), count word, count×data words (checksum = sum of DATA words only),
  checksum word (XOR-compare → mismatch = `?` via ILLEG 002473). Then one more
  ASCII number; if its TERMINATOR char is NUL → `COMM,START` at P, else return
  to MOPC leaving the program in memory.
- The only `?` producers for `&`/`$`: letters typed in front, CPU not in STOP,
  checksum mismatch. Device-never-ready = silent infinite poll (no `?`).

---

## 1. Register map conformance (A vs B)

| Reg | C oracle (A) | Verilog (B) | Tag |
|---|---|---|---|
| +0 read | constant 0x1 always (TODO in C; no boot machinery) | boot mode: buffer word at bootptr (+consume); else 0x1 | **DEVIATE (ours is the functional one — keep; oracle stubbed)** |
| +1 read / write | 0 / ignored | 0 / ignored | match (but MASS writes +1 = core address → **UNKNOWN** pending §4.3) |
| +2 read | hardware status word | same | match |
| +3 write | control word | same | match |
| +4 read | SAME word as +2 (per ND-11.021 §3.1 Note 1) | same | match |
| +5 write | pointerHI = full 16-bit value stored, masked only at use | `s_ptr_hi <= wdata[7:0]` (masked at write) | minor DEVIATE (observable only if SW writes junk high bits then reads back — no readback exists → harmless) |
| +7 write | pointerLO | same | match |
| +5/+6/+7 read | 0 | 0 | match |

## 2. Status words (A §2 vs B §2)

| Item | C | Verilog | Tag |
|---|---|---|---|
| b15 dualDensity=1 on IOX status | yes | yes | match |
| numeric error code on IOX status | forced 0 | absent | match |
| SW1 (CB+6): code in b14-9, b15=0 | yes | yes | match |
| **RFT after reset** | **0** (line that sets 1 is commented out; needs device-clear) | **1** (`s_rft` resets to 1) | **DEVIATE — decide.** C requires SW to device-clear first; ours is ready at power-on. Level-sensitive INT means ours asserts as soon as b1 is enabled while idle. Manual tiebreak. |
| deviceActive (b2) | NEVER set true in C | set during commands | **QUIRK (C limitation)** — ours is almost certainly right; but note the MASS path POLLS +4 bit 2 as "finished" — semantics there differ per §4.3. |
| deletedRecord/retry bits | always 0 | always 0 | match |
| hardError | only autoload-fail sets it | o41/o43 DMA errors set it | DEVIATE (C's is stub-related; ours reasonable) — verify vs manual |

## 3. Control word (A §3 vs B §3)

| Item | C | Verilog | Tag |
|---|---|---|---|
| b1 int-enable stored on EVERY write | yes | yes | match — note microcode's per-char 4005₈ writes have b1=0, so interrupts stay disabled during stream boot; consistent both sides |
| b4 device clear | drive:=-1(255!), RFT:=1; does NOT clear error code | RFT:=1, active/hard_err/err_code:=0, boot exit, eng idle | **DEVIATE**: C keeps err_code, ours clears; C corrupts `drive` to 255 (**QUIRK — C bug, do not copy**) |
| b2 autoload priority over b8 | yes (if/else) | yes | match |
| b3 test mode | stub (no-op) | stored, never used | match (both no-op) |
| b5 streamer | no-op TODO | absent | match |
| b8 execute + b3 test | runs test stub | executes normally (b3 ignored) | minor DEVIATE — C gates execute on !testMode; ours ignores b3. Only matters for TEST programs (FLOPPY-STREA uses test mode!). **Fix candidate for running FLOPPY-STREA-C00:TEST.** |

## 4. Command block (A §4 vs B §4)

| Item | C | Verilog | Tag |
|---|---|---|---|
| fetch words 0-5 (+6 in C, unused) | 0-6 fetched, w6 discarded | 0-5 fetched | match effectively |
| memoryAddressHi mask 0xFF at fetch | yes | `s_cb[2][7:0]` at use | match |
| word/sector count select w4 b15 | yes | yes | match |
| 24-bit count | yes | yes ({w4[7:0],w5}) | match |
| CB+6 written twice (busy then ready) | yes (WBACK + ReadEnd) | yes (E_WBACK + E_FINAL) | match |
| **CB+10/+11 content** | words TRANSFERRED (24-bit split hi/lo) | CB+10 hardcoded 0; CB+11 = words REMAINING [15:0] | **BUG-CANDIDATE (three-way: manual says "remaining")** — at clean completion C gives N/ours gives 0; a driver checking either sees different values. Manual tiebreak, then align. |
| CB+7 status2: drive b9:8; READ FORMAT ORs fmt bits; 8" branch WIPES drive bits | yes | identical incl. the wipe | match (quirk faithfully copied) |
| writeback on autoload | AutoLoadEnd writes NO CB | no writeback (no CB) | match |
| dma_err during writeback | n/a in C (function calls) | **ignored** | **BUG-CANDIDATE** (silent success after bus error) |

## 5. Transfer engine (A §5 vs B §5)

| Item | C | Verilog | Tag |
|---|---|---|---|
| fmt sector sizes | 512/256/**123**/1024 bytes | 512/256/**128**/1024 | **QUIRK — C's 123 is a typo-grade oddity; keep 128, confirm manual** |
| sector/track math | dead code (%17 vs /18) | absent | match (both linear logical-sector) |
| partial final sector | C: buffer sized by rounding DOWN; tail overruns heap (undefined) | proper chunking, write commits only chunk words | **DEVIATE — ours is defined and safer; keep ours** |
| read error path | DMA-writes zeros for failed read, still completes | error → E_WBACK, no data | DEVIATE — decide (C DMAs zeros!; ours aborts). Manual tiebreak |
| write-protect | WRITE → err o16, nothing written | **not implemented** (no readOnly input) | **GAP in ours** — backend has no read-only signal; note for adapter/backend seam |
| unknown/stub functions | complete-with-clean-status | same (E_WBACK) | match |
| completion delay | one queued delay per command | DELAY_TICKS=300 | match in shape; exact IODELAY_FLOPPY value UNKNOWN in C |

## 6. Interrupts + IDENT (A §9 vs B §8)

| Item | C | Verilog | Tag |
|---|---|---|---|
| level 11, ident 021 | yes | yes | match |
| pending = enabled && RFT (level-sensitive) | yes | yes | match |
| IDENT clears the ENABLE bit | yes | yes | match |
| immediate int update on some errors, not others | inconsistent in C (READ short-read commented out) | uniform (level-sensitive makes it moot) | match effectively |

## 7. Device-side BUG CANDIDATES found in ours (B §10) — P1/P2/P4 test targets

1. Boot +0 read gated on neither `s_rft` nor `s_buf_valid` → stale-data window,
   over-consumption if `iox_rd` is >1 cycle (depends on ND_BUS_SLAVE strobe width
   — VERIFY in P2).
2. **Bootptr overrun hang**: refill only fires at `s_bootptr == 512` exactly; one
   extra read → 513 → refill unreachable until device-clear. (Candidate for the
   silicon "silent after 1560&" symptom.)
3. Autoload disk-error leaves `s_boot_active=1` and raises RFT — CPU reads stale
   buffer with no error indication except status b4.
4. Refill activate does not clear a prior `s_err_code` (first activate does).
5. `dma_err` ignored in E_WBACK/E_FINAL.
6. Every control write rewrites int-enable from b1 (by design? C does the same —
   keep, but document).
7. Unreachable autoload branch in E_MEM_WR (dead code — remove or justify).

## 8. Anomaly adjudication (from the campaign plan)

- **Tang silent `1560&`**: now EXPLAINED as most likely correct-behavior chain:
  FLOMON diskette → stream parse loads ~64 words to address 0 → checksum `?`
  (possibly unseen on the hung console) — with bug-candidates 7.2/7.3 available
  as aggravators. The `002000` RAM contents seen on the Tang were never verified
  against the image and are likely stale. P5/P6 re-tests with known media.
- **Combined-tb 7/8 DMA errors**: RESOLVED 26-JUL-2026 - the device is correct; the
  errors were a harness ACK-sampling artifact, and the `MIN_GAP_TICKS` recovery gap
  was proven load-bearing. Measured results: `PLAN-P3-dma-master-validation.md` §0.

## 9. Actions out of Phase 0

1. ~~Find and read NDInsight FloppyDMA §4.3~~ DONE — see §0; the firmware
   behavior is fully documented and the implementation recipe (§4.6) is clear.
2. Ronny decision: real-diskette boot = implement the firmware-equivalent
   FLOMON autoload in `ND_FLOPPY_DMA.v` (triggered by the MASS sequence,
   stream path untouched — recommended, silicon-faithful), with ndtool
   BPUN-repack as the works-today stopgap. If approved this becomes a new
   campaign phase (P4b: implement + host-test, gated by a FLOMON boot tb).
3. P1 tb asserts the full register/status/control matrix above (incl. RFT-reset
   question both ways, pending the manual).
4. P2 verifies `iox_rd` strobe width + the boot-read consume rule.
5. P4 feeds BOTH BPUN and FLOMON streams and asserts the exact predicted
   outcomes (BPUN boots; FLOMON → 64 words to addr 0 + `?` — a regression trap
   documenting today's truth).
6. Relay to NDDeviceCore: the MASS protocol table + FLOMON verdict + the oracle's
   autoload stub status.
