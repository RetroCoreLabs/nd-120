# ND120 - top-level test entry points
#
#   make test        run EVERY self-checking unit testbench in the repo,
#                    fail-fast: the first failure aborts loudly (exit 1).
#                    Registry: tests/run_all_tests.sh - add new tbs there.
#
#   make test-full   `make test` plus the heavy system-level gates:
#                      - sim/ latch-vs-FF trace compare against the goldens
#                      - runSim FF-mode console against the golden log
#                      - fpga/tang-nano-20k vtest (full Tang boot + deposit
#                        + verified readback, ~100 s)
#
#   make test-tape   heavy system gate for the Verilog tape-400 device
#                    (ND-BUS-DEVICES): boots INSTRUCTION-B twice via
#                    '400$' - once with the C papertape model, once with
#                    the Verilog device (VERILOG_TAPE=1) - and requires
#                    identical console tails and identical loaded RAM.
#                    ~25 min (two full runSim compiles + runs).
#
# Board builds stay in fpga/<board>/ (see fpga/README.md); the CPU sims
# stay in sim/ and runSim/. This Makefile only aggregates TESTS.

#   make test-floppy-boot  heavy system gate for the floppy mass boot:
#                    '1560&' at the OPCOM prompt makes the DMA floppy
#                    controller AUTOLOAD the boot sector to ND memory 0
#                    (verified word-for-word against a generated image
#                    with a WAIT instruction at word 0). ~12 min.
#
#   make test-smd-boot  heavy system gate for the SMD mass boot:
#                    '1540&' triggers the controller's boot handshake
#                    (control to +3, ready polled on +2), block 0
#                    (1024 words) DMA-lands at ND memory 0. ~12 min.
#
#   make test-dma-rtl  heavy system gate for DMA bus mastering: the
#                    Verilog ND_DMA_MASTER inside ND120_TOP requests the
#                    bus from the REAL arbiter (PAL_44801A) while the CPU
#                    runs, DMA-writes a pattern into the REAL RAM,
#                    verifies the RAM arrays, DMA-reads it back.
#                    ~12 min (one runSim compile + run).
#
#   make test-dma-xcheck  heavy system gate: OPCOM<->DMA cross-check. The
#                    CPU deposits known words via OPCOM (A/V<CR>) through
#                    the normal store path; the Verilog ND_DMA_MASTER then
#                    DMA-reads those same word addresses and asserts it
#                    sees exactly what OPCOM wrote - DMA and CPU address
#                    one and the same memory. ~12 min (one compile + run).

#   make test-democore  heavy system gate for the NDDeviceCore PORTABLE C
#                    cores ($ND_REPOS/NDDeviceCore - the same .c that
#                    runs in the RP2350 NDModulE firmware) against the REAL
#                    ND-120 CPU + bus RTL. Boots a hand-assembled BPUN off
#                    the DMA floppy ('1560&', the proven loader, so this
#                    gate does NOT depend on SINTRAN), which IOX-writes a
#                    string to the nd_lineprinter core at 0430 and polls
#                    its status register. PASS = the exact bytes landed in
#                    the sim capture backend. ~12 min (one compile + run).

.PHONY: test-audit verify-devicecore-c-only test-demodma test-floppy-core-iox test-floppy-core-boot test-tape-core test test-full test-tape test-dma-rtl test-dma-xcheck test-floppy-boot test-floppy-stdin test-smd-boot test-instr test-democore

test: test-audit
	@bash tests/run_all_tests.sh

# Coverage audit: every *_tb.v must be runnable from its own sim/Makefile and
# registered in tests/run_all_tests.sh. The three orphans it found on
# 09-AUG-2026 are fixed (DECODE_DGA_COMM got a build rule; the Basys3 and
# QMTECH mem-test benches got Makefiles, a TB_RESULT verdict and registry
# entries), so this now gates - a new testbench that nothing runs fails the
# build instead of quietly rotting.
test-audit:
	@./tests/audit_testbenches.sh

test-full: test
# Storage failure reporting, the SLOW half: the card-goes-silent case, whose
# only terminator is sd_writer.v's TO_DATA read watchdog (2,000,000 sdclk =
# 148 ms simulated, measured 09-AUG-2026). TO_DATA is a real device timeout,
# so it is not shortened to suit a testbench - the case lives here instead.
# The other seven failure modes run in the fail-fast tier as test-nds-errors.
	@echo "==== storage gate: card-goes-silent reason code ===="
	$(MAKE) -C SD-FAT/sim test-nds-errors-slow
	@echo "==== system gate: sim/ latch-vs-FF golden compare ===="
	$(MAKE) -C sim compare
	cmp sim/trace_ff.csv    sim/golden/trace_ff_golden.csv
	cmp sim/trace_latch.csv sim/golden/trace_latch_golden.csv
	@echo "==== system gate: runSim FF console vs golden ===="
# golden/console_ff_golden.log was recorded while the C device models still
# printed their IDENT/interrupt trace unconditionally. Those prints are OFF by
# default now (they drowned a 400$ load - see docs/BUG-tape400-sd-level12-storm.md),
# so this gate - and ONLY this gate - compiles them back in to match the golden.
# Normal runs stay quiet. If you re-record the golden, drop the define.
# NOTE: -DDEBUG_INTERRUPT is exactly right and -DDEBUG_BIF=1 is NOT: the latter
# also emits the BAPR/BIOXE bus trace, which the golden does not contain.
# VERILOG_TAPE=0 is now EXPLICIT: the runSim default is the Verilog ND_TAPE_400/
# SD stack, but this golden was recorded against the C device models, so this
# gate opts into them on purpose (until the golden is re-recorded on Verilog).
	$(MAKE) -C runSim compile USE_LATCHES=0 VERILOG_TAPE=0 EXTRA_CFLAGS="-DSCRIPT_INPUT -DSCRIPT_CMD_GOLDEN -DDEBUG_INTERRUPT" >/dev/null
	cd runSim && ./obj_dir/VND120_TOP </dev/null > /tmp/nd120_console_check.log 2>&1; \
	  cmp /tmp/nd120_console_check.log golden/console_ff_golden.log
	@echo "==== system gate: Tang vtest (boot + deposit + readback) ===="
	$(MAKE) -C fpga/tang-nano-20k/sim vtest
	$(MAKE) test-floppy-stdin
	$(MAKE) test-smd-boot
	$(MAKE) test-democore
	$(MAKE) test-instr-argument
	@echo ""
	@echo "===================================================================="
	@echo "  FULL SUITE PASSED (units + goldens + vtest)"
	@echo "===================================================================="

# Filter that strips the C device models' debug prints, keeping console text
TAPE_FILTER = grep -vaE '^(PaperTape|FloppyPIO object|IDENT LVL|No device found|WTF|\[0\] FloppyPIO|Callback LVL|Clearing|Generating|Setting|\[binload\] (settling|streaming|injector|byte)|VerilogTape|Floppy PIO)'

test-tape:
	@echo "==== system gate: 400\$$ tape boot, C model vs Verilog device ===="
	$(MAKE) -C runSim clean >/dev/null
	$(MAKE) -C runSim compile USE_LATCHES=0 VERILOG_TAPE=0 EXTRA_CFLAGS="-DSCRIPT_INPUT -DSCRIPT_CMD_TAPE400" >/dev/null
	cd runSim && ND120_BINLOAD_CHECK=001000:8 ./obj_dir/VND120_TOP </dev/null > /tmp/nd120_tape_c.log 2>&1
	$(MAKE) -C runSim clean >/dev/null
	$(MAKE) -C runSim compile USE_LATCHES=0 VERILOG_TAPE=1 EXTRA_CFLAGS="-DSCRIPT_INPUT -DSCRIPT_CMD_TAPE400" >/dev/null
	cd runSim && ND120_BINLOAD_CHECK=001000:8 ./obj_dir/VND120_TOP </dev/null > /tmp/nd120_tape_v.log 2>&1
	# Landmark gate: both runs must load AND EXECUTE the program (the
	# banner only prints if the loaded code runs). A byte-diff of the
	# consoles is impossible: the C model's debug prints glue onto the
	# console text mid-line.
	for L in "Words read   054731" \
	         "INSTRUCTION  VERIFY" \
	         "PROGRAM NAME  : INSTRUCTION-B" \
	         "The command HELP gives you a list of the commands."; do \
	  grep -qa "$$L" /tmp/nd120_tape_c.log || { echo "C-model run missing: $$L"; exit 1; }; \
	  grep -qa "$$L" /tmp/nd120_tape_v.log || { echo "Verilog run missing: $$L"; exit 1; }; \
	done
	# The Verilog run must NOT contain the C papertape (proves the swap)
	! grep -qa "PaperTape" /tmp/nd120_tape_v.log
	grep -a "RAM check" /tmp/nd120_tape_c.log > /tmp/nd120_tape_c_ram.txt
	grep -a "RAM check" /tmp/nd120_tape_v.log > /tmp/nd120_tape_v_ram.txt
	cmp /tmp/nd120_tape_c_ram.txt /tmp/nd120_tape_v_ram.txt
	@echo ""
	@echo "===================================================================="
	@echo "  TAPE GATE PASSED (Verilog tape-400 = C model, INSTRUCTION-B boots)"
	@echo "===================================================================="

test-floppy-boot:
	@echo "==== system gate: 1560& floppy mass boot (autoload -> RAM) ===="
	python3 tests/gen_fboot_img.py /tmp/nd120_fboot.img /tmp/nd120_fboot_exp.txt
	$(MAKE) -C runSim clean >/dev/null
	$(MAKE) -C runSim compile USE_LATCHES=0 VERILOG_TAPE=1 SD_STORAGE=0 EXTRA_CFLAGS="-DSCRIPT_INPUT -DSCRIPT_CMD_FBOOT" >/dev/null
	cd runSim && ND120_FLOPPY_IMG=/tmp/nd120_fboot.img ND120_BINLOAD_CHECK=002000:16 ./obj_dir/VND120_TOP </dev/null > /tmp/nd120_fboot.log 2>&1
	grep -a "RAM check" /tmp/nd120_fboot.log > /tmp/nd120_fboot_got.txt
	cat /tmp/nd120_fboot_got.txt
	# words 0-2 = the loaded program; word at index 10 = 000077, the
	# value the program STORES when it RUNS (the preload background
	# fills the other cells, so a full-line compare is meaningless)
	awk '{ exit !($$5=="170477" && $$6=="004011" && $$7=="151000" && $$15=="000077") }' /tmp/nd120_fboot_got.txt
	@echo ""
	@echo "===================================================================="
	@echo "  FLOPPY BOOT GATE PASSED (1560& BPUN-booted and EXECUTED the program)"
	@echo "===================================================================="

# The interactive (typed-input) path: the SAME binary make run-floppy runs
# (no SCRIPT_INPUT), fed "1560&" through a pipe so all six chars sit in the
# stdin buffer at once - worst-case typing/paste. The harness must hold
# them until the '#' prompt and pace them one per gap, or MOPC (no RX
# FIFO) drops chars and the boot goes to a garbage address (the
# interactive-hang bug). Same RAM proof as test-floppy-boot.
test-floppy-stdin:
	@echo "==== system gate: interactive stdin 1560& floppy boot ===="
	python3 tests/gen_fboot_img.py /tmp/nd120_fstdin.img /tmp/nd120_fstdin_exp.txt
	$(MAKE) -C runSim clean >/dev/null
	$(MAKE) -C runSim compile USE_LATCHES=0 VERILOG_TAPE=1 SD_STORAGE=0 >/dev/null
	cd runSim && printf '1560&' | ND120_FLOPPY_IMG=/tmp/nd120_fstdin.img ND120_BINLOAD_CHECK=002000:16 ND120_MAX_CNT=120000000 ./obj_dir/VND120_TOP > /tmp/nd120_fstdin.log 2>&1
	grep -a "RAM check" /tmp/nd120_fstdin.log > /tmp/nd120_fstdin_got.txt
	cat /tmp/nd120_fstdin_got.txt
	awk '{ exit !($$5=="170477" && $$6=="004011" && $$7=="151000" && $$15=="000077") }' /tmp/nd120_fstdin_got.txt
	@echo ""
	@echo "===================================================================="
	@echo "  STDIN FLOPPY BOOT GATE PASSED (piped 1560& booted and EXECUTED)"
	@echo "===================================================================="

test-smd-boot:
	@echo "==== system gate: 1540& SMD mass boot (boot handshake -> RAM) ===="
	python3 tests/gen_fboot_img.py /tmp/nd120_sboot.img /tmp/nd120_sboot_exp.txt
	$(MAKE) -C runSim clean >/dev/null
	$(MAKE) -C runSim compile USE_LATCHES=0 VERILOG_TAPE=1 SD_STORAGE=0 EXTRA_CFLAGS="-DSCRIPT_INPUT -DSCRIPT_CMD_SBOOT" >/dev/null
	# ND120_MAX_CNT is what ENDS the run: Run120's main loop is while(true) and
	# the BINLOAD RAM check only prints after the loop exits. Without it this
	# gate never terminated (it ran for six hours) even though the boot itself
	# finishes in milliseconds of simulated time. Same value as the floppy
	# stdin gate above.
	cd runSim && ND120_SMD_IMG=/tmp/nd120_sboot.img ND120_BINLOAD_CHECK=002000:16 ND120_MAX_CNT=120000000 ./obj_dir/VND120_TOP </dev/null > /tmp/nd120_sboot.log 2>&1
	grep -a "RAM check" /tmp/nd120_sboot.log > /tmp/nd120_sboot_got.txt
	cat /tmp/nd120_sboot_got.txt
	# loaded program + the 000077 it stores when it RUNS (see the
	# floppy gate note about the preload background)
	awk '{ exit !($$5=="170477" && $$6=="004011" && $$7=="151000" && $$15=="000077") }' /tmp/nd120_sboot_got.txt
	@echo ""
	@echo "===================================================================="
	@echo "  SMD BOOT GATE PASSED (1540& BPUN-booted and EXECUTED the program)"
	@echo "===================================================================="

# NDDeviceCore character-device RTL equivalence gate (Axis A of
# ../../NDDeviceCore/docs/rtl-gate-plan.md). The portable C99 nd_lineprinter
# core is registered on the C-model bus path (simDevices/NDDeviceCoreAdapter)
# at IOX 0430-0433, and an ND-100 program hand-assembled by
# tests/gen_democore_img.py drives it: write control (activate), then per
# character write +1 / poll +2 bit 3. The gate PASSES only when every byte
# arrives in the sim nd_char_dev capture backend, which can only happen if the
# real CPU executed real IOX cycles through the real bus RTL into our core.
DEMOCORE_TEXT = NDCORE

test-democore:
	@echo "==== system gate: NDDeviceCore nd_lineprinter vs the real ND-120 RTL ===="
	python3 tests/gen_democore_img.py /tmp/nd120_democore.img $(DEMOCORE_TEXT)
	$(MAKE) -C runSim clean >/dev/null
	$(MAKE) -C runSim compile USE_LATCHES=0 VERILOG_TAPE=1 SD_STORAGE=0 DEVICECORE=1 EXTRA_CFLAGS="-DSCRIPT_INPUT -DSCRIPT_CMD_FBOOT" >/dev/null
	cd runSim && ND120_FLOPPY_IMG=/tmp/nd120_democore.img \
	             ND120_DEMOCORE_EXPECT=$(DEMOCORE_TEXT) \
	             ND120_BINLOAD_CHECK=002000:16 \
	             ./obj_dir/VND120_TOP </dev/null > /tmp/nd120_democore.log 2>&1
	grep -a "democore" /tmp/nd120_democore.log
	# The core really is ours (address/ident/level printed by addDevicesCore)
	grep -qa "NDDeviceCore nd_lineprinter registered: IOX 000430-000433 ident 003 level 10" /tmp/nd120_democore.log
	# ... and the CPU really drove it over the bus
	grep -qa "\[democore\] RESULT: PASS" /tmp/nd120_democore.log
	! grep -qa "\[democore\] RESULT: FAIL" /tmp/nd120_democore.log
	@echo ""
	@echo "===================================================================="
	@echo "  DEVICECORE GATE PASSED (portable nd_lineprinter driven by real RTL)"
	@echo "===================================================================="

# verify-devicecore-c-only - PROVE no Verilog IO device was elaborated
#
# When we validate a PORTABLE C device core, no Verilog IO device may exist on
# the bus: two devices on one IOX window race per cycle, the failure looks like
# intermittent wrong data rather than an error, and a PASS could mean we graded
# the Verilog core's answers instead of ours.
#
# The Makefile $(error) in runSim/Makefile and the #error in
# NDDeviceCoreAdapter.cpp both block the bad build, but both trust a FLAG. This
# target trusts EVIDENCE: it inspects the symbol table verilator actually
# generated and fails if any device instance is present.
#
# WHAT TO LOOK AT - two plausible sources were tried and REJECTED, because a
# check that cannot fail is worse than no check at all:
#   - the FDISK_ / TAPE_ backend PORTS on ND120_TOP: present even when every
#     device is excluded. Proves nothing.
#   - VND120_TOP__Syms.h instance names: verilator INLINES these small modules,
#     so they never appear even in a full device build. This one silently
#     "passed" the default build - caught only by running the negative test.
# What DOES work: ND120_CORE.v wraps each device in a named generate block
# (:353 gen_tape, :396 gen_floppy, :496 gen_smd, :302 gen_bus_slave,
# :598 gen_dma_master) with a gen_no_* else-branch. Signals of an instantiated
# device therefore appear in the root header as __DOT__gen_<x>__DOT__... and
# vanish entirely when INCLUDE_<X>=0. The gen_no_* names cannot false-positive
# because the patterns below anchor on __DOT__ either side.
DEVICE_GEN_RE = __DOT__gen_(bus_slave|tape|floppy|smd|dma_master)__DOT__
ROOT_HDR      = runSim/obj_dir/VND120_TOP___024root.h

verify-devicecore-c-only:
	@echo "---- verifying NO Verilog IO device was elaborated ----"
	@test -f $(ROOT_HDR) || \
	    { echo "FAIL: no elaborated model ($(ROOT_HDR)) - build runSim first"; exit 1; }
	@if grep -qE "$(DEVICE_GEN_RE)" $(ROOT_HDR); then \
	    echo "FAIL: Verilog IO device(s) ARE instantiated in this build:"; \
	    grep -oE "$(DEVICE_GEN_RE)" $(ROOT_HDR) | sort -u | sed 's/^/        /'; \
	    echo "      A C-device gate built like this proves NOTHING (both cores"; \
	    echo "      claim the same IOX window and race). Rebuild VERILOG_TAPE=0."; \
	    exit 1; \
	fi
	@echo "     OK: zero device generate blocks - our C core is alone on the bus"

# test-floppy-core-iox - the CHEAPEST possible gate for a portable C device.
#
# Ronny's idea (20-JUL-2026): before attempting any boot, drive the core with
# PURE IOX straight from the OPCOM console. `IO/` issues a real bus IOX cycle
# through IOXX1 - the SAME microcode routine the `&` loaders and the IOX
# instruction use - so this exercises the C core over the real bus RTL with no
# BPUN, no bootstrap and no DMA anywhere in the picture.
#
# `IO/` syntax (empirical - nothing documents it):
#   <octal>IO/     issue a cycle. NO SPACE: space/@ RESETS MOPC.
#                  Direction is address PARITY: even = read, odd = write.
#   OPR/<octal>CR  load the operand register FIRST - that is where write data
#                  comes from. `<octal>OPR/` only DISPLAYS, and
#                  `1563IO/4005CR` (deposit-after-slash) just prints '?'.
#
# The sequence below is the autoload handshake from
# NDDeviceCore/docs/floppy-autoload-microcode-contract.md, executed by hand
# against a REAL diskette.
FLOPPYCORE_IMG ?= FLOPPY.IMG

# test-demodma - the C BUS MASTER pipe-cleaner. Proves nd_bus_hal's DMA
# primitives (NDCoreShim.cpp) drive real memory cycles through the real bus
# arbiter, with NO disk geometry, NO BPUN and NO boot path in the way - so a
# DMA failure here is a DMA failure and nothing else.
#
# nd_demo_dma (IOX 0500-0507, ident 077, level 11) is driven from OPCOM IO/:
#   WRITE 4 words to 010000, then READ them back and checksum them.
# The write pattern (052525 ^ a ^ a<<7) is predictable, so RAM is verified
# against a known-good image AND the read-back checksum is verified against the
# core's own fold. The read path is what exercises the "latch data across the
# whole window" gotcha - a broken master reads all-ones -> 0x0000 -> a WRONG
# checksum, not a crash.
#
# REGISTER MAP (parity = direction, even=read odd=write):
#   W +1 addrlo  W +3 control  W +5 addrhi  W +7 count+GO
#   R +0 status  R +2 checksum R +4 xfered  R +6 error
test-demodma:
	@echo "==== system gate: C bus master (nd_demo_dma DMA pipe-cleaner) ===="
	$(MAKE) -C runSim clean >/dev/null
	$(MAKE) -C runSim compile USE_LATCHES=0 VERILOG_TAPE=0 SD_STORAGE=0 \
	        DEVICECORE=1 DEVICECORE_DEMODMA=1 >/dev/null
	# LAYER 3: prove no Verilog IO device (and no Verilog DMA master) exists
	$(MAKE) verify-devicecore-c-only
	# WRITE phase, then READ-BACK phase (see the register map above)
	cd runSim && ( ulimit -f 512000; \
	    printf 'OPR/2\r0503IO/\rOPR/10000\r0501IO/\rOPR/0\r0505IO/\rOPR/100004\r0507IO/\r0500IO/\r0504IO/\rOPR/0\r0503IO/\rOPR/10000\r0501IO/\rOPR/0\r0505IO/\rOPR/100004\r0507IO/\r0500IO/\r0504IO/\r0502IO/\r' | \
	    ND120_BINLOAD_CHECK=010000:4 ND120_MAX_CNT=120000000 \
	    ./obj_dir/VND120_TOP > /tmp/nd120_demodma.log 2>&1 )
	grep -a "demodma\|shim\|RAM check" /tmp/nd120_demodma.log
	# The core on the bus is OURS, at the parity-correct 8-address window
	grep -qa "nd_demo_dma registered: IOX 000500-000507 ident 077 level 11" /tmp/nd120_demodma.log
	# The 4 written words are the predictable pattern (052525 ^ a ^ a<<7)
	grep -qa "RAM check @010000: 042525 042724 042127 042326" /tmp/nd120_demodma.log
	# The bus master ran real cycles with no timeout and no IOX collision
	grep -qa "bus master: 8 cycles, 0 timeouts, 0 IOX collisions" /tmp/nd120_demodma.log
	# The read-back checksum matches the core's fold over those 4 words (000126).
	# A read path that sampled at the BDRY edge would read 0x0000 -> wrong sum.
	grep -qa "0502IO/000126" /tmp/nd120_demodma.log
	# NEGATIVE: the master must never have been starved or wedged
	! grep -qa "DMA TIMEOUT" /tmp/nd120_demodma.log
	@echo ""
	@echo "===================================================================="
	@echo "  DEMO-DMA GATE PASSED (C bus master wrote AND read real ND-120 RAM"
	@echo "  through the real arbiter, driven by real CPU IOX cycles)"
	@echo "===================================================================="

test-floppy-core-iox:
	@echo "==== system gate: portable nd_floppy_dma driven by OPCOM IO/ ===="
	$(MAKE) -C runSim clean >/dev/null
	$(MAKE) -C runSim compile USE_LATCHES=0 VERILOG_TAPE=0 SD_STORAGE=0 \
	        DEVICECORE=1 DEVICECORE_FLOPPY=1 >/dev/null
	# LAYER 3: prove no Verilog IO device exists before believing ANY result
	$(MAKE) verify-devicecore-c-only
	cd runSim && printf 'OPR/4005\r1563IO/\r1562IO/\r1560IO/\r1562IO/\r' | \
	    ND120_FLOPPYCORE_IMG=$(FLOPPYCORE_IMG) \
	    ND120_CORE_TRACE=1 ND120_MAX_CNT=200000000 \
	    ./obj_dir/VND120_TOP > /tmp/nd120_floppycore_iox.log 2>&1
	grep -a "ndcore\|floppycore" /tmp/nd120_floppycore_iox.log
	# The core on the bus really is OURS
	grep -qa "nd_floppy_dma registered: IOX 001560-001567 ident 021 level 11" /tmp/nd120_floppycore_iox.log
	# RAM was empty - nothing was pre-deposited behind the CPU's back
	grep -qa "no BPUN pre-deposit" /tmp/nd120_floppycore_iox.log
	# The CPU's IOX write of 004005 reached us and was decoded as DVACT
	grep -qa "FLP control 004005   (DVACT - autoload activate)" /tmp/nd120_floppycore_iox.log
	grep -qa "FLP autoload ENTER" /tmp/nd120_floppycore_iox.log
	# ... we fetched from the REAL diskette and raised ready-for-transfer
	grep -qa "FLP autoload refill: 512 words from byte pos 0" /tmp/nd120_floppycore_iox.log
	grep -qa "FLP status  100010  RFT=1" /tmp/nd120_floppycore_iox.log
	# ... and served the real BPUN leader's first byte '0' (060 octal)
	grep -qa "FLP autoload word\[0\] = 000060  low=060 '0'" /tmp/nd120_floppycore_iox.log
	# NEGATIVE: autoload is pure IOX - the bus master must never be reached
	! grep -qa "NO BUS MASTER YET" /tmp/nd120_floppycore_iox.log
	# NEGATIVE: no media error
	! grep -qa "autoload FAIL" /tmp/nd120_floppycore_iox.log
	@echo ""
	@echo "===================================================================="
	@echo "  FLOPPY-CORE IOX GATE PASSED (real CPU + real bus + real diskette,"
	@echo "  portable C core, no boot / no BPUN / no DMA)"
	@echo "===================================================================="

# test-tape-core - `400$$` papertape boot through the PORTABLE nd_tape400 core.
#
# The C sibling of test-tape: same program, same landmarks, same RAM check, but
# the device answering IOX 0400-0403 is the portable nd_tape400.c that also runs
# on the RP2350 - with NO Verilog device and NO C++ PaperTape on the bus.
#
# `400$$` uses the SAME microcode character-loader path as `1560&` (ETLO1):
# control +3 = 004005 (DVACT), poll +2 bit 3 (RFT), read +0. So a green
# test-tape-core and a green floppy IOX gate are two devices proving one
# contract - see NDDeviceCore/docs/floppy-autoload-microcode-contract.md.
#
# The tape image defaults to BOOT.BPUN (Ronny, 20-JUL-2026; not 8.3-legal, but
# nothing requires 8.3 and NDModulE's FatFs has FF_USE_LFN=3). This gate points
# it at INSTRUCTION-B.BPUN so it can reuse test-tape's PROVEN landmarks - the
# banner only prints if the loaded code actually RAN.
TAPECORE_IMG ?= INSTRUCTION-B.BPUN

test-tape-core:
	@echo "==== system gate: 400\$$ papertape boot via PORTABLE nd_tape400 ===="
	$(MAKE) -C runSim clean >/dev/null
	$(MAKE) -C runSim compile USE_LATCHES=0 VERILOG_TAPE=0 SD_STORAGE=0 \
	        DEVICECORE=1 DEVICECORE_TAPE=1 \
	        EXTRA_CFLAGS="-DSCRIPT_INPUT -DSCRIPT_CMD_TAPE400" >/dev/null
	# LAYER 3: prove no Verilog IO device exists before believing ANY result
	$(MAKE) verify-devicecore-c-only
	cd runSim && ND120_TAPECORE_IMG=$(TAPECORE_IMG) \
	             ND120_BINLOAD_CHECK=001000:8 \
	             ./obj_dir/VND120_TOP </dev/null > /tmp/nd120_tapecore.log 2>&1
	grep -a "tapecore" /tmp/nd120_tapecore.log
	# The core on the bus really is OURS ...
	grep -qa "nd_tape400 registered: IOX 000400-000403 ident 002 level 12" /tmp/nd120_tapecore.log
	# ... and the legacy C++ model is NOT there (it prints on construction)
	! grep -qa "PaperTape object created" /tmp/nd120_tapecore.log
	# The CPU loaded AND EXECUTED the program off our tape (the banner only
	# prints if the loaded code runs) - same landmarks as test-tape.
	for L in "Words read   054731" \
	         "INSTRUCTION  VERIFY" \
	         "PROGRAM NAME  : INSTRUCTION-B" \
	         "The command HELP gives you a list of the commands."; do \
	  grep -qa "$$L" /tmp/nd120_tapecore.log || { echo "MISSING landmark: $$L"; exit 1; }; \
	done
	grep -a "RAM check" /tmp/nd120_tapecore.log
	@echo ""
	@echo "===================================================================="
	@echo "  TAPE-CORE GATE PASSED (400\$$ booted INSTRUCTION-B through the"
	@echo "  portable nd_tape400 - real CPU, real bus, no Verilog device)"
	@echo "===================================================================="

# test-floppy-core-boot - the REAL `1560&` autoload boot through the portable C
# floppy core, against a REAL diskette image.
#
# This is the end-to-end proof that the C autoload byte server drives the ND-120
# microcode BPUN loader: the CPU reads the stream, loads it, and JUMPS to it -
# the booted program then programs our controller for DMA, which is how we know
# it really executed. Full annotated trace + the 143-word dump:
#   NDDeviceCore/docs/floppy-1560-boot-trace.md
#
# EXPECTED END STATE: the booted program hangs polling status 100004 (RFT=0,
# active=1) waiting for a DMA completion. That is CORRECT for today - the C bus
# master does not exist yet (plan phase 4). This gate asserts the boot, NOT the
# DMA. When the bus master lands, this gate should still pass unchanged.
#
# WHY THE NEGATIVE CHECKS MATTER (learned the hard way, 20-JUL-2026): obj_dir is
# shared with the Verilog-floppy work. A bare re-run picked up SOMEONE ELSE'S
# binary and produced a clean-looking log that proved nothing.
# verify-devicecore-c-only did NOT catch it - it only proves no VERILOG device
# was elaborated, which was also true of their build. Asserting the registration
# line, and that the legacy C++ FloppyPIO is absent, is what pins the binary
# down to OURS. Never trust a run that has not made both assertions.
FLOPPYCORE_BOOT_IMG ?= FLOPPY.IMG

test-floppy-core-boot:
	@echo "==== system gate: 1560& autoload boot via PORTABLE nd_floppy_dma ===="
	$(MAKE) -C runSim clean >/dev/null
	$(MAKE) -C runSim compile USE_LATCHES=0 VERILOG_TAPE=0 SD_STORAGE=0 \
	        DEVICECORE=1 DEVICECORE_FLOPPY=1 \
	        EXTRA_CFLAGS="-DSCRIPT_INPUT -DSCRIPT_CMD_FBOOT" >/dev/null
	# LAYER 3: prove no Verilog IO device exists before believing ANY result
	$(MAKE) verify-devicecore-c-only
	# ulimit -f 512000 = hard 500 MB cap on the log; a runaway is a bug, so fail
	# rather than fill the disk.
	cd runSim && ( ulimit -f 512000; \
	    ND120_FLOPPYCORE_IMG=$(FLOPPYCORE_BOOT_IMG) \
	    ND120_CORE_TRACE=1 ND120_MAX_CNT=400000000 \
	    ./obj_dir/VND120_TOP </dev/null > /tmp/nd120_fbootgate.log 2>&1 )
	# --- BINARY IDENTITY: this run really is OUR core, and only our core ---
	grep -qa "nd_floppy_dma registered: IOX 001560-001567 ident 021 level 11" /tmp/nd120_fbootgate.log
	! grep -qa "FloppyPIO object created" /tmp/nd120_fbootgate.log
	# RAM was empty - the program came off the diskette, not a pre-deposit
	grep -qa "no BPUN pre-deposit" /tmp/nd120_fbootgate.log
	# --- THE AUTOLOAD CONTRACT (ETLO1): DVACT -> poll RFT -> read data ---
	grep -qa "FLP control 004005   (DVACT - autoload activate)" /tmp/nd120_fbootgate.log
	grep -qa "FLP autoload ENTER" /tmp/nd120_fbootgate.log
	grep -qa "FLP autoload refill: 512 words from byte pos 0" /tmp/nd120_fbootgate.log
	# First byte of the REAL diskette's BPUN leader: '0' == 060 octal
	grep -qa "FLP autoload word\[0\] = 000060  low=060 '0'" /tmp/nd120_fbootgate.log
	# --- THE BOOT COMPLETED: exit-on-GO after exactly one 1024-byte sector ---
	grep -qa "FLP autoload EXIT after 143 words (byte pos 1024)" /tmp/nd120_fbootgate.log
	# --- THE LOADED CODE RAN: these IOX writes are the BOOTED PROGRAM, not the
	#     microcode - it is programming our controller for a DMA at 000072.
	grep -qa "FLP-GO a=58" /tmp/nd120_fbootgate.log
	# NEGATIVE: no media error anywhere
	! grep -qa "autoload FAIL" /tmp/nd120_fbootgate.log
	@echo ""
	@echo "===================================================================="
	@echo "  FLOPPY-CORE BOOT GATE PASSED (1560& loaded AND executed a program"
	@echo "  off a real diskette through the portable nd_floppy_dma core)"
	@echo "===================================================================="

test-dma-rtl:
	@echo "==== system gate: DMA master vs the real arbiter + RAM ===="
	$(MAKE) -C runSim clean >/dev/null
	$(MAKE) -C runSim compile USE_LATCHES=0 VERILOG_TAPE=1 EXTRA_CFLAGS="-DSCRIPT_INPUT" >/dev/null
	cd runSim && ND120_DMA_TEST=010000:32 ./obj_dir/VND120_TOP </dev/null > /tmp/nd120_dma_rtl.log 2>&1
	grep -a "dmatest" /tmp/nd120_dma_rtl.log
	grep -qa "\[dmatest\] RESULT: PASS" /tmp/nd120_dma_rtl.log
	@echo ""
	@echo "===================================================================="
	@echo "  DMA RTL GATE PASSED (real arbiter granted, real RAM read+written)"
	@echo "===================================================================="

test-dma-xcheck:
	@echo "==== system gate: OPCOM deposit <-> DMA read cross-check ===="
	$(MAKE) -C runSim clean >/dev/null
	$(MAKE) -C runSim compile USE_LATCHES=0 VERILOG_TAPE=1 EXTRA_CFLAGS="-DSCRIPT_INPUT -DSCRIPT_CMD_DMAXCHECK" >/dev/null
	cd runSim && ND120_DMA_XCHECK=1 ./obj_dir/VND120_TOP </dev/null > /tmp/nd120_dma_xcheck.log 2>&1
	grep -a "dmaxcheck" /tmp/nd120_dma_xcheck.log
	grep -qa "\[dmaxcheck\] RESULT: PASS" /tmp/nd120_dma_xcheck.log
	@echo ""
	@echo "===================================================================="
	@echo "  DMA XCHECK GATE PASSED (OPCOM-written word read back over DMA)"
	@echo "===================================================================="

# Instruction-verify area gate: boots INSTRUCTION-B, types the area command,
# records the golden-format trace and compares against the ND-110 reference
# (tests/instruction-verify/README.md). Heavy (~15-25 min sim per area).
#
# Validated areas (golden trace delivered by the ND-110 side AND passing the
# architectural gate). 13 of 15 areas; the two missing:
#  - 48-BITS-FLOATING is N/A on this machine - the DELILAH PROM microcode
#    implements the 32-bit float option (docs/48bit-float-not-configured.md).
#    Its golden gate (first-400 window) happens to pass because the window
#    ends before the float instructions run, but the deep area can never
#    pass; 32-BITS-FLOATING is the float gate here.
#  - RUN is not gated. Its level-14 livelock and the FIDBO status-fence
#    swap were fixed 15-JUL-2026 (commit 3acef36), after which RUN in runSim
#    handled IOX-ERROR and reached LEVEL 13 / ARGUMENT == END OF TEST ==
#    (docs/RUN-level14-livelock-analysis.md). No error count was committed
#    and no pass pattern exists for it, so it is neither here nor in
#    tests/run_all_tests.sh.
INSTR_AREAS = ARGUMENT STACK BYTE-STRING MEMORY-REFERENCE SEQUENCE \
              REGISTER-OPERATIONS BIT-OPERATIONS SHIFT-INSTRUCTIONS \
              32-BITS-FLOATING BCD ND100-24BIT ND100-CX PRIVILEGED

# `make test-instr-<AREA>` runs one area; `make test-instr` runs the full
# validated sweep (~1.5h). test-full runs only ARGUMENT as a smoke gate.
test-instr-%:
	@echo "==== system gate: instruction-verify $* vs ND-110 golden ===="
	bash tests/instruction-verify/run_area_test.sh $* | tee /tmp/nd120_iverify_$*_gate.log
	grep -q "TB_RESULT: PASS" /tmp/nd120_iverify_$*_gate.log

test-instr: $(addprefix test-instr-,$(INSTR_AREAS))
	@echo "==== all $(words $(INSTR_AREAS)) instruction-verify areas PASSED ===="
