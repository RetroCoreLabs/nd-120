/**************************************************************************
** ND120 - Tang Nano 20K build defines                                   **
**                                                                       **
** This file MUST be the FIRST Verilog file in the Gowin project so the  **
** macros are visible to every following file (GowinSynthesis compiles   **
** the file list as one ordered compilation unit).                       **
** See docs/build-defines.md for what each define does.                  **
**                                                                       **
** Last reviewed: 8-JUL-2026                                             **
** Ronny Hansen                                                          **
***************************************************************************/

// FPGA vendor: Gowin primitives (PROM_19 drops the Xilinx BRAM ROM path)
`define GOWIN

// Board target marker
`define TARGET_TANG20K

// Edge-triggered flip-flop mode (CYC_36 generated-clock handling)
`define FPGA_FF_MODE

// Bitstream-preloaded WCS; the runtime microcode load phase is skipped and
// the microcode PROM is never read (required to fit the 828 Kbit BSRAM)
`define SKIP_WCS_LOAD

// Main memory = embedded 8 MB SDRAM through MEM_RAM_49_SDRAM (2 banks, 4 MB)
`define MAIN_RAM_SDRAM

// Packed main memory: store 16 DATA bits only, two ND words per 32-bit SDRAM
// location (DQM lane-masked writes, parity computed on read). CPU keeps the
// full 4 MB in the LOWER half of the chip; the upper 4 MB is reserved for the
// nd_storage disk-image cache. Semantics pinned by docs/nd120-parity-analysis.md;
// tbs: sdram-bridge/sim test-pack16 / test-pack16-part. Only meaningful with
// MAIN_RAM_SDRAM; no effect on Verilator/Basys3 builds.
`define ND_SDRAM_PACK16

// nd_storage device port on the SDRAM backend (requires ND_SDRAM_PACK16):
// a start/busy/done port in its own stor_clk domain that reads/writes whole
// 32-bit locations at {1'b1, mem_addr} - the upper-half storage region ONLY,
// the leading 1 is forced inside MEM_RAM_49_SDRAM so device traffic physically
// cannot reach the CPU's memory. This is what nd_storage_devices uses to
// stage BOOT.BPUN off the SD card for the '400$' tape boot.
// Threaded ND120_TANG20K_TOP -> ND120_CORE -> ND3202D -> MEM_43 -> the backend.
// tb: sdram-bridge/sim test-storage-port.
`define ND_STORAGE_PORT

// ---- Storage device select (Ronny 19-JUL: don't carry tape+floppy at once) --
// TANG_FLOPPY = floppy-only build (1560&, ND_FLOPPY_DMA + nd_storage FLOPPY1.IMG
// client; NO tape). Comment it out for the DEFAULT tape-only build (400$, the
// proven silicon config). Consumed by ND120_TANG20K_TOP.v (TANG_INC_TAPE/FLOPPY)
// and by the SDFAT_NO_STORAGE_CHECK guard below.
// OFF 09-AUG-2026, single-variable experiment for the Winchester read failure.
// ND_FLOPPY_DMA is ALSO interrupt level 11 (ident 21) and sits ahead of the
// Winchester in the ident grant chain. A silicon capture of the File System
// Investigator showed two level-11 IDENT cycles that NO device answered
// (grant_in=1 at the Winchester, so nothing ahead claimed them either),
// after which the Winchester's own completion interrupt was never identified
// at all. Dropping the floppy removes the only other level-11 device, so if
// the unclaimed cycles vanish and LI-FI proceeds, the floppy raised them.
// The tape (400$) is unaffected: TANG_INC_TAPE is 1 in both branches and
// BOOT_NAME("BOOT.TAP") is not conditional on this define.
`define TANG_FLOPPY

// TANG_SMD = ADD the ND_SMD disk controller at 1540 (boot '1540&') on top of
// the selected base build: ND_SMD + its own ND_DMA_MASTER in the core, and
// nd_storage_disc_adapter serving SMD0.IMG off the SD card (nd_storage client
// 3, slot remapped to 1376 blocks -> image limit 2,818,048 bytes). Costs ONE
// BSRAM (the controller's 1024x16 buffer; the adapter is zero-BSRAM
// stream-through) - that is the LAST free BSRAM block, 46/46 with it in.
// Writes are supported for FULL ALIGNED 1024-word blocks only (even-sector
// starts, 1024-word-multiple lengths); anything else answers disk_err.
// Comment out to drop the SMD alone if resources overflow.
//`define TANG_SMD   // OFF for the TANG_WD build (mutually exclusive)

// TANG_WD = ADD the ND_WINCHESTER disc controller at 500 (ST506 card 3041)
// instead of the SMD: ND_WINCHESTER + its own ND_DMA_MASTER in the core, and
// nd_storage_disc_adapter (the SAME adapter, at Winchester geometry - it has
// nothing SMD-specific in it) serving WD0.IMG off the SD card, nd_storage
// client 6. Images are WDn.IMG, never SMDn.IMG.
//
// MUTUALLY EXCLUSIVE WITH TANG_SMD, and not by preference - by BSRAM. The
// note above records that TANG_SMD takes the LAST free block, 46/46 with it
// in. ND_WINCHESTER has its own 1024x16 buffer and would need a 47th that
// does not exist. Defining both is caught at elaboration below rather than
// left to a confusing place-and-route failure.
//
// Why you might want this one instead: the ND-120's MASS STORAGE LOAD
// microcode (PROM listing, CSA 002221-002227) writes the core address TWICE
// and the word count ONCE, which is the Winchester's register protocol, not
// the SMD's. The SMD core needs a boot-mode special case to cope; this one
// does not.
`define TANG_WD

// CACHE COMPILED OUT (the default). Fixing the cache-hit comparator (sheets
// 27 and 24) made the cache REAL: it used to compare six wrong bits against a
// signal that is zero on every mapped access, so most of the cache path was
// dead logic the synthesiser removed. With it live the design needs 28330
// logic cells against this part's 20736 (measured 25-AUG-2026), so it DOES
// NOT FIT the GW2AR-18. ND120_NO_CACHE omits the five cache memories and the
// used-bit PAL, forces the board's own SW1 cache-off position, and makes the
// machine REPORT the cache as disabled. Gate: make test-mmucache-nocache.
//
// ND120_FORCE_CACHE (gowin_build.ps1 -Cache, or `make CACHE=1` in the OSS
// flow) suppresses ND120_NO_CACHE so the cache is synthesized. It exists so
// the cache knob is symmetric across every build flow and so anyone attacking
// the fit problem has the switch - expect the build to OVERFLOW the part
// until someone closes that 28330-vs-20736 gap. This file stays the
// default-off authority: with no pre-define the cache is out, same as always.
`ifndef ND120_FORCE_CACHE
`define ND120_NO_CACHE
`endif

// (the TANG_SMD / TANG_WD mutual-exclusion guard lives inside
//  ND120_TANG20K_TOP.v, where an instantiation is legal syntax and the
//  error names itself instead of being a bare 'syntax error' here)

// TANG_WD_TRACE_DUMP = capture the Winchester's IOX register accesses on
// SILICON and dump them over the debug UART.
//
// Why it exists: ND_WINCHESTER.v replays the nd100x C model's ENTIRE
// DISC-TEMA "DU-DI-C" IOX trace - all 33 operations, every status word -
// with zero divergence (ND-BUS-DEVICES/WINCHESTER/sim, `make test-wd-oracle`),
// and DISC-TEMA on this board still reports "Memory address Register not as
// expected" while returning perfect data and the identical status word
// 060010. The controller is therefore NOT the fault, and the sequence the
// CPU actually issues has never been observed anywhere. ND_SMD.v carries the
// same facility (ND120_SMD_TRACE) and that is what made the SMD tractable.
//
// What it does: rings the last 512 COMPLETED IOX accesses to the card - one
// entry per access, not per clock - triggers on a READ of +0 (the memory
// address readback that fails), keeps 8 more, then streams them as five hex
// digits per line: digit 1 = {rw, register offset} (rw 1 = write), digits
// 2-5 = the 16-bit value written or returned. It takes the console only
// after the diagnostic has printed, like the other capture modes.
//
// Costs a 512x20 capture ring and the dumper. Leave it OFF for normal builds.
// DISABLED 09-AUG-2026. Re-enable ONLY to capture the card side. Once the
// dump fires it takes the console permanently (the debug TX keeps the mux),
// so anything that needs to read memory or registers AFTER the traffic -
// e.g. a deposited program that stores what the CPU captured from an IOX
// read - must run on a build with this OFF.
// REQUIRED BY ND_WD_TRACE_TVEC_CSA (measured 17-AUG-2026): wd_trace_rec/we/done
// are declared AND connected to the storage block ONLY inside this define
// (ND120_TANG20K_TOP.v:194-198 and :1410-1414). Without it they are undriven
// implicit wires, so wd_count never leaves 0 and the TVEC_CSA capture trigger
// - which needs wd_count >= 3 plus 45 s of card idle (:775) - can NEVER fire.
// A first Tang run with TVEC_CSA alone sat through 420 s of quiet and dumped
// nothing for exactly this reason.
// DISABLED 18-AUG-2026 to get a TRUSTWORTHY TPE verdict on silicon.
// With this on, the dumper owns the console TX mux and prints 20-bit records
// as 5 hex digits. A TPE PAGING run on 17-AUG came back reading
//   "6. PAGE FAULT interrupt   E0109" then "50109" over and over,
// which was taken for a TPE error code. It is not: E0109/50109/00103 are
// trace records, and TPE's own "- End of test -" / error table never reached
// the terminal at all. Any TPE or OPCOM session that must be BELIEVED has to
// run on a build with this OFF.
//`define TANG_WD_TRACE_DUMP

// ND_WD_TRACE_BLKONLY = keep the IOX trace, but let ONLY block-address
// writes (+3) into the ring. One record per disc operation, so 256 entries
// cover the whole '20500&' SINTRAN load (251 block addresses, counted from
// the nd100x trace of the same WD0.IMG) instead of its last thirteen
// operations. Use this to find WHERE the machine first asks for a different
// disc address than the working emulator does; then go back to the full
// trace to see what that operation did.
//`define ND_WD_TRACE_BLKONLY

// ND_WD_TRACE_OPSONLY = keep the IOX trace, but let only the three
// records that describe an operation into the ring: block address (+3),
// word count (+7), and the ACTIVATING control word (+5 with bit 2 set).
// 85 operations of history instead of thirteen, with the opcode and the
// length of each - which BLKONLY does not carry. Takes precedence over
// ND_WD_TRACE_BLKONLY when both are defined.
//`define ND_WD_TRACE_OPSONLY

// ND_WD_TRACE_DBUF = make the ring capture the adapter's buffer writes
// (WDBUF_WE/WDBUF_WDATA) instead of IOX traffic. Discriminates the last two
// suspects for the zero-read. See the note in ND120_TANG20K_TOP.v.
//`define ND_WD_TRACE_DBUF

// ND_WD_TRACE_TVEC = ring the TRAP DISPATCH instead of the Winchester
// registers: one record per entry to level 14, carrying TVEC, TRAPN and the
// level. Needs the matching export in DELILAH-CPU/CGA_MIC/circuit/CGA_MIC.v,
// which is guarded by this same define.
//
// BROKEN - DO NOT USE (measured 17-AUG-2026). This define names a branch in
// BOTH capture chains of ND120_TANG20K_TOP.v (:445 and :602) that contains
// comments and NOTHING ELSE: it assigns neither s_cap_src nor s_cap_stb, so
// the ring has no source and no strobe. Use ND_WD_TRACE_TVEC_CSA below.
//
// The numbering in the old comment here was also wrong and is what made the
// 11-AUG silicon record read "TVEC=3 = page fault". TVEC is the DELILAH
// MICROCODE trap vector, not the ND-100 internal-interrupt code. The golden
// self-checking bench states the microcode table explicitly
// (DELILAH-CPU/CGA_TRAP/sim/CGA_TRAP_TVGEN_tb.v:16-17):
//   1 = page fault, 2 = protect violation, 3 = RING DOWN, 4 = PGU, 5 = WIP.
//`define ND_WD_TRACE_TVEC

// ND_WD_TRACE_TVEC_CSA = the WORKING trap-dispatch capture. One record per
// dispatched trap, strobed on the FALLING EDGE of TRAPN - the only moment TVEC
// is valid (sampling on the PIL->14 transition is too late and returns idle on
// every record). Word = {4'hA, TVEC[3:0], TRAPN, CSA[10:0]}, so each record
// carries both the vector and the microcode address that took it.
`define ND_WD_TRACE_TVEC_CSA

// ND_WD_TRACE_CSATRAP = free-run the microcode address (CSA) and TRIGGER on a
// trap that happens after the card has been idle 45 s, i.e. at the livelock.
// The ring then holds the ~256 clk2x cycles of microcode BEFORE the fault -
// the run-up that sampling at the trap instant cannot show, because on a trap
// the micro-address bus is the trap vector itself.
//`define ND_WD_TRACE_CSATRAP

// ND_WD_TRACE_REGION = capture what the SDRAM region returns on each read
// completion. Follows the dbuf probe, which proved the words are already
// zero before the adapter sees them.
//`define ND_WD_TRACE_REGION

// ND_WD_TRACE_FILL = capture card bytes during a fill, raw AND after the
// end-of-file gate. Follows the region probe (63/63 D0000), which proved the
// region was written with zeros, so staging itself was filled with zeros.
//
// OFF 09-AUG-2026. Two runs of this probe returned 64/64 records of 00000 and
// BOTH were unreadable, because the tape client is grant 0: a real record of a
// zero card byte encodes as 00000, which is byte-identical to a cap_mem entry
// that was never written. The tag now carries a written-marker bit (see
// s_cap_src in ND120_TANG20K_TOP.v) so a future fill run is decidable, but the
// IOX trace below answers the open question directly and needs no new marker.
// ON again 09-AUG-2026, and now DECIDABLE: bit 19 of the record is a
// written-marker, so 00000 can only mean "never written". The RTZ fix made
// the File System Investigator actually issue its transfer, so this probe now
// samples a fill driven by the real driver rather than a deposited program.
//`define ND_WD_TRACE_FILL

// ND_WD_TRACE_LBA = the card sector each fetch actually reads, per client.
//`define ND_WD_TRACE_LBA

// ND_WD_TRACE_FSEC = the mount's first_sector for the granted client.
//`define ND_WD_TRACE_FSEC

// ND_WD_TRACE_WDATA = the word written into the region. The resolve is proven
// correct, so this splits staging-empty from region-write-broken.
//`define ND_WD_TRACE_WDATA

// ND_WD_TRACE_RDATA = what the region returns on read-back.
//`define ND_WD_TRACE_RDATA

// ND_WD_TRACE_BUFW = the word handed to the client buffer - last unmeasured
// signal between the proven-good region read and the zero-filled adapter.
//`define ND_WD_TRACE_BUFW

// ND_WD_TRACE_PIL = record every change of the CPU's priority interrupt level
// instead of the Winchester's registers. The register trace is exhausted: the
// device-open sequence matches the nd100x oracle exactly and LI-FI then issues
// no IOX at all, so the failing decision is CPU-side. This shows whether the
// machine ever reaches level 11.
// OFF again: the RTZ completion-delay fix in ND_WINCHESTER.v is the thing
// under test now, and answering "does the File System Investigator finally
// issue the transfer" needs the Winchester REGISTER trace, not the PIL trace.
//`define ND_WD_TRACE_PIL

// ND_WD_TRACE_ESTATE = record every CHANGE of the storage engine's state with
// the granted client. The byte-strobe probe has now returned an empty ring
// three times; watching the state machine says which states a Winchester read
// really visits rather than inferring it.
//`define ND_WD_TRACE_ESTATE

// ND_STORAGE_DISCS_UNCACHED = serve the disc clients DIRECT instead of
// through the Phase-4 cache. Diagnostic for the 09-AUG-2026 silicon
// zero-read: the DIRECT tape client reads the same card correctly while the
// CACHED Winchester client returns zeros with a clean status. See the long
// note at the CACHE_MASK parameter in nd_storage_devices.v.
// RE-ENABLED 24-AUG-2026 (Ronny): the Winchester read cache is BACK ON.
// This define was left active from the 09-AUG zero-read diagnostic and forced
// CACHE_MASK to 0, so every disc client ran DIRECT. With it commented out the
// mask at nd_storage_devices.v:573-574 evaluates to 8'b11000000 - clients 6
// and 7, i.e. the Winchester - so WD0 reads go through the Phase-4 cache
// again. The 23-AUG triple-null experiment measured no functional difference
// (cache on / masked off / not synthesized all reached the same ERRFATAL in
// the same 143 s), and the ERRFATAL itself is now fixed at ND3202D.v:533.
//`define ND_STORAGE_DISCS_UNCACHED

// ND_STORAGE_WD_BADNAME = control experiment: make the Winchester client
// open a file that is NOT on the card, so the mount must fail. Proves
// whether a clean status really means "the read happened". See the note at
// FILE6_NAME in nd_storage_devices.v.
//`define ND_STORAGE_WD_BADNAME

// ND_STORAGE_WD_USE_BOOTTAP = discriminator: serve the Winchester client the
// SMALL BOOT.TAP instead of the 75 MB WD0.IMG, to separate a file-dependent
// fault from a client-path fault. See nd_storage_devices.v.
// ON 10-AUG-2026, paired with ND_WD_TRACE_LBA to make the resolve DECIDABLE
// without any ground truth about the card's layout. With this on, client 0
// and client 6 open the SAME file, so the sectors they resolve MUST match.
// The tape client's resolve is known good - 400$ loads the File System
// Investigator from BOOT.TAP off this very card. So:
//   client 6 sectors == client 0 sectors -> the resolve is right, and the
//     zeros come from what happens to the data AFTER the fetch.
//   client 6 sectors != client 0 sectors -> the per-client resolve is wrong,
//     the fetch reads blank card space, and that is the whole bug.
// Neither outcome needs to know where WD0.IMG physically lives.
//`define ND_STORAGE_WD_USE_BOOTTAP   // back to the real WD0.IMG

// ND120_SMD_15MHZ = strap the SMD controller as the 15 MHz two-access card
// (24-bit Memory Address and Word Count loaded HI-then-LO, read back LO-then-HI)
// instead of the ECC single-access card.
//
// Measured on silicon 03-AUG-2026: with the ECC strap the controller answers
// IDENT 17 (octal), which TPE's configuration tool prints as "SMD 15 MHZ DISC
// CONTR.", so TPE drives it with the 15 MHz two-access protocol. DISC-TEMA's
// Memory Address Register test then fails on EVERY value with the second read
// returning the low word again - expected 00000000001b, found 00000200001b,
// i.e. (N<<16)|N - and every later command has a mis-loaded address and word
// count ("Disc unit not ready" / "Controller not active after activate", all
// data zero). Test 1, the data-way test, passes either way.
//
// KNOWN CONFLICT: the mass-storage boot microroutine at CSA o2217 writes the
// word count with ONE +7 write of 002000, which under this two-access protocol
// loads only the HI byte and leaves the count at zero - so '21540&' is expected
// to stop working while this is defined. The ident and the strap disagree; one
// of them is wrong, and this define is how we test which.
//
// LEFT OFF for now. The root cause turned out to be that ND_SMD announced the
// WRONG TYPE: seek-condition b12 (the SMD 10/15 MHz identity bit) was hardwired
// to 1 and ECC-pattern b14 to 0 regardless of this strap, so a card strapped as
// the single-access ECC controller still told software it was a 15 MHz card and
// software drove the two-access protocol against it. Both bits now follow
// HAS_WC_FLIPFLOP.
//
// ON, because DISC-TEMA requires it. Measured in nd100x 03-AUG-2026 with the
// new ND100X_SMD_TYPE selector, running the same du-di-c read both ways:
//   ND100X_SMD_TYPE=smd15 -> read returns real data, no errors
//   ND100X_SMD_TYPE=ecc   -> "Disc controller not present for this disc type !"
// DISC-TEMA probes the controller type and will not test DISC-75MB-1 on an ECC
// card at all, so with the identity bits now truthful an ECC-strapped Tang
// would be REFUSED rather than tested.
//
// The mass-load objection is RESOLVED, not ignored: that microroutine writes
// the memory address with TWO +1 accesses but the word count with ONE +7 write
// of 002000 (ground truth: ND-BUS-DEVICES/SMD/sim/traces/mass-load-21540.trace),
// and ND_SMD now straps those two registers SEPARATELY. ND120_CORE sets the
// memory address two-access (what DISC-TEMA requires) and the word counter
// single-access (what the mass load requires). Verified compatible in nd100x:
// FUNCTION as the 15 MHz card with the word counter forced single-access scores
// IDENTICALLY to the all-two-access card, so DISC-TEMA constrains only the
// memory address.
//
// LEFT OFF. The ND-120's own MASS STORAGE LOAD microcode settles it: the PROM
// listing at CSA 002221-002227 (nd120uc source/ND-120-DELILAH-L.LISTING.txt
// lines 5866+) writes
//     IOX N+1 (0) CORE ADDRESS      twice, value 0 both times
//     IOX N+3 (0) BLOCK ADDRESS
//     IOX N+7 (2000) WORD COUNTER   ONCE
//     IOX N+5 (4) ACTIVATE
// Two ZERO writes to the core address are harmless on a single-access card, so
// they are NOT evidence of the two-access protocol. The single +7 of 002000
// only means 1024 words on a SINGLE-ACCESS controller - on a two-access card it
// loads the high byte with 002000 & 0xFF = 0 and the count stays zero.
// So this machine is a single-access (ECC / NORD-10 large-disc generation)
// controller, and '21540&' works only with this define OFF.
//
// Consequence to accept: DISC-TEMA J02 probes the controller type and REFUSES
// single-access controllers outright ("Disc controller not present for this
// disc type"), so it can never test this machine's disc however much we fix.
// Read validation needs a different program - the SMD manual's own test-program
// chapter lists PASCAN (2226), Super-Rand (2222), an ECC Test that "completely
// diagnoses the 3043/3044 card", and BIGFUNC.
//`define ND120_SMD_15MHZ

// ---- TAPE-ONLY SD-FAT reader slimming (docs/fat-reader-slimming-plan.md) ----
// The Tang tape boot path is READ-ONLY of a contiguous boot file. These cuts
// reclaim FPGA LUT+ALU so the OSS placer fits. They are SAFE ONLY while the SD
// path is tape-read-only; REMOVE them when a floppy/SMD build is added here
// (random-access / writeback needs the full FAT reader and the contiguity
// gate).
//
//   SDFAT_NO_STORAGE_CHECK  - drop the mount-time contiguity checker
//                             (nd_storage_fatchk.v, ~1177 LUT+ALU); the card
//                             recipe alone guarantees a contiguous boot image.
//                             Mount M_CHK passes straight through. ENABLED FOR
//                             TAPE ONLY - a floppy build (TANG_FLOPPY) needs the
//                             contiguity gate back (random access), so the cut
//                             is guarded off there.
//                             (and a TANG_SMD build needs it too: random
//                             access + writeback, same as floppy).
//
//                             TANG_WD ADDED TO THE GUARD 05-AUG-2026. The
//                             Winchester build was inheriting the cut: the
//                             list said "tape only" but only TANG_FLOPPY and
//                             TANG_SMD were excluded, so TANG_WD - random
//                             access AND writeback over a 75 MB WD0.IMG -
//                             mounted with no contiguity gate at all. The
//                             Phase-4 cache addresses a block as
//                             first_sector + 4*block (nd_storage_engine.v
//                             C_SEC_GO), which is only the right sector while
//                             the file occupies consecutive clusters. On a
//                             fragmented image every block past the first
//                             fragment reads and WRITES the wrong sectors,
//                             silently, with no error anywhere. Cost of
//                             putting it back: ~1177 LUT+ALU on a part that
//                             was already near its LUT4 limit - if TANG_WD
//                             stops fitting, the answer is to slim something
//                             else, not to drop this gate.
`ifndef TANG_FLOPPY
`ifndef TANG_SMD
`ifndef TANG_WD
`define SDFAT_NO_STORAGE_CHECK
`endif
`endif
`endif

//   SDFAT_NO_LFN            - strip VFAT long-filename parsing in
//                             sd_file_reader.v (~1800 LUT+ALU); files matched
//                             by 8.3 short name only. *** NOT ENABLED ***:
//                             the tape client searches for "BOOT.BPUN"
//                             (nd_storage_devices.v FILE0_NAME), whose 4-char
//                             ".BPUN" extension is NOT 8.3-representable - FAT
//                             stores it as a mangled short name (BOOT~1.BPU)
//                             plus a VFAT long entry, so the name is only
//                             reachable via LFN. Enabling this cut breaks the
//                             tape open (verified: oerr=1). To claim the saving,
//                             first rename the boot file to a real 8.3 name
//                             (<=8 base, <=3 ext) and update FILE0_NAME to
//                             match; THEN uncomment the line below. The ifdef
//                             machinery in sd_file_reader.v is implemented and
//                             validated - this is a one-line flip once renamed.
//
//                             ENABLED 05-AUG-2026, BUT ONLY FOR A NO-TAPE
//                             BUILD. The blocker above is the TAPE client and
//                             nothing else: ND120_TANG20K_TOP.v:498 sets
//                             TANG_INC_TAPE = 0 whenever TANG_FLOPPY is
//                             defined, so a floppy build never searches for
//                             BOOT.BPUN and the 4-char extension stops
//                             mattering. The files such a build DOES open -
//                             FLOPPY1.IMG and WD0.IMG - are both real 8.3
//                             names (<=8 base, <=3 extension), so no card
//                             layout changes.
//
//                             Why it is enabled: the TANG_WD build overflowed
//                             at 92% logic / 96% CLS with 335 unrouted nets
//                             once the Phase-4 cache directory and the
//                             contiguity checker were both in. This reclaims
//                             ~1800 LUT+ALU. The alternative was to strip the
//                             contiguity checker again, which would put back
//                             silent wrong-sector reads AND writes on a
//                             fragmented image - a far worse trade.
//
//                             The guard is deliberately the SAME condition as
//                             TANG_INC_TAPE: reinstate the tape (comment out
//                             TANG_FLOPPY) and long filenames come back on
//                             their own, instead of the tape open silently
//                             failing with oerr=1.
`ifdef TANG_FLOPPY
`define SDFAT_NO_LFN
`endif

//   TANG_GRANT_CAPTURE     - DEBUG PROBE for the masked-level-10 grant.
//                            Repurposes the on-chip 512-sample analyzer to
//                            record {PIL[3:0], CSA[11:0]} and trigger on PIL
//                            entering level 10 (448 pre + 64 post). On the
//                            hang it takes the console TX and streams 512
//                            hex lines "hhhh" (PIL = hex digit 1, CSA = lower
//                            3 hex digits, octal-decode the CSA). Reveals
//                            whether PIL->10 runs the normal level-switch
//                            microcode (PLINT 01133 / LVSWP 01146-01155) or
//                            bypasses it. See ANALYSIS-cga-intr-masked-grant-
//                            root-cause.md sec 3c. Instrumentation only; leave
//                            OFF for normal builds.
// `define TANG_GRANT_CAPTURE   // A/B: OFF for the control build (Issue I)

//   TANG_TRAP_CAPTURE      - DEBUG PROBE for the PAGING-test-3 eject (Issue D).
//                            Repurposes the 512-sample analyzer to record
//                            {TVEC[3:0], TRAPN, CSA[10:0]} (TVEC/TRAPN arrive
//                            via the XMIC_DBG bus, repacked in CGA_MIC.v under
//                            this same define - sim probe semantics untouched
//                            because the sim never defines it). Trigger =
//                            CSA held at 7 (the vector-7 self-jump) for 16
//                            clk2x cycles, OR the frozen-CSA hang detector.
//                            480 pre + 32 post. Decodes: TVEC = top hex digit
//                            bits 15:12, bit 11 = TRAPN, low 11 bits = CSA.
//                            If TVEC==7 at the CSA->7 jump the trap generator
//                            really computed 7 on silicon; if TVEC!=7 the CSA
//                            latch caught a mid-transition value (comb-path
//                            setup failure). If test 3 ejects WITHOUT firing
//                            this, vector 7 is not taken on silicon at all.
//                            Instrumentation only; leave OFF for normal builds.
// `define TANG_TRAP_CAPTURE

//   TANG_NO_CONKICK - DIAGNOSTIC: disable the IO_37 console-pacing STAT3 pulse
//   (the un-original missing-68705 stand-in) so console traffic raises NO panel
//   request. Tests whether the conkick is the PAN source of the phantom macro-
//   interrupt / PIL->10 hang. If the hang vanishes, this is the faithful fix.

//   TANG_NO_RTC_PAN - DIAGNOSTIC: drop the RTC's contribution to PAN (panel
//   request). With conkick already off, this removes the last PAN source. If
//   the PIL->10 hang vanishes, the held RTC PAN is the confirmed trigger.
// `define TANG_NO_IOXERR   (turned OFF for IREQ capture - let bit10/IOXERR show)

// ---- Clock variant selection (slow / crawl / full) ----------------------
// Slow bring-up clocking (G1): first Gowin build measured CPU-domain Fmax at
// 9.38 MHz (31 levels) with derived-clock domains down to 4.7 MHz - the known
// derived-clock architecture problem. Until the clock-enable refactor closes
// timing at 27 MHz, run CPU/bus at 6.75 MHz (SDRAM pair at 13.5 MHz), which
// sits under every measured Fmax with margin.
//
// Crawl bring-up (P0 mechanism probe): halve the slow bring-up again -
// CPU/bus 3.375 MHz, SDRAM pair 6.75 MHz. The probe .tr measured the
// CPU-domain Fmax at 4.84 MHz, so at 3.375 MHz the SAME netlist meets
// timing. Crawl = TANG_CRAWL_BRINGUP defined IN ADDITION to
// TANG_SLOW_BRINGUP (it overrides the PLL and clock counts).
//
// The variant is selected WITHOUT editing this file: the build flows
// pre-define TANG_VARIANT_FULL or TANG_VARIANT_CRAWL on top of this
// compilation unit (OSS: `make VARIANT=full|crawl|slow` passes -D flags;
// Gowin: `gowin_build.ps1 -Variant ...` emits build/tang20k_variant.v as
// the first project file). No variant define = slow bring-up, the same
// default as before. See ../README.md "Two build flows".
`ifdef TANG_VARIANT_FULL
  // full speed 27/54 MHz: neither SLOW nor CRAWL defined
`elsif TANG_VARIANT_FAST20
  // fast20 (26-AUG-2026): CPU 20.25 MHz / SDRAM 40.5 MHz - deliberately AT
  // the measured CPU-domain Fmax (20.4 MHz, nd120_tang20k_build.tr), the
  // Tang's equivalent of the Nexys wall probes. Console 115200 in this
  // variant only.
  `define TANG_FAST20_BRINGUP
`elsif TANG_VARIANT_MID
  `define TANG_MID_BRINGUP
`elsif TANG_VARIANT_CRAWL
  `define TANG_SLOW_BRINGUP
  `define TANG_CRAWL_BRINGUP
`else
  `define TANG_SLOW_BRINGUP
`endif

// Clock/baud parameters - keep ALL derived counts slaved to these
`ifdef TANG_CRAWL_BRINGUP
`define BOARD_CLK_FREQ 3_375_000
`elsif TANG_SLOW_BRINGUP
`define BOARD_CLK_FREQ 6_750_000
`elsif TANG_MID_BRINGUP
`define BOARD_CLK_FREQ 13_500_000
`elsif TANG_FAST20_BRINGUP
`define BOARD_CLK_FREQ 20_250_000
`else
`define BOARD_CLK_FREQ 27_000_000
`endif
// Console baud: 115200 for EVERY variant since 26-AUG-2026 (Ronny). The
// physical rate is this constant alone - the SC2661 emulation stores the
// microcode's BAUDV mode value (thumbwheel 8 = 9600) but times every bit
// off DELAY_FRAMES, and TX-ready is a polled flag (proven on the Nexys and
// on fast20: SINTRAN runs a 115200 console while believing 9600).
// NOTE for tooling: pf_capture_run.py, boardtests and every console script
// that opened 9600 must open 115200 (7E2) against bitstreams built after
// this change.
`define UART_BAUD_RATE 115200
