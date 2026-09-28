#!/bin/bash
###############################################################################
# ND120 - global unit-test runner
#
# Runs every self-checking testbench in the repo, FAIL-FAST: the first
# failing test aborts the whole run with a loud banner and exit code 1.
#
# Invoked by:   make test        (from Verilog/)
#               make test-full   (adds the heavy system-level gates)
#
# A test fails when ANY of these hold:
#   - its make target exits nonzero
#   - its output contains a FAIL line
#   - its output does not contain the required pass pattern
#
# Registry format:  <dir relative to Verilog/> :: <make target> :: <pass regex>
# Add every new testbench here (and keep the pass pattern strict - a test
# that can pass silently is a test that can fail silently).
###############################################################################
set -u

VERILOG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$VERILOG_ROOT" || exit 1

REGISTRY=(
  # --- meta: the suite checks itself first ---------------------------------
  # Every testbench in the tree must be reached by an entry below, or be
  # baselined in tests/tb_catalog.py with a reason. Fails when a new testbench
  # is written and never registered - the drift that left 9 testbenches
  # unreachable before 08-AUG-2026.
  "tests :: test-tb-catalog :: TB_RESULT: PASS"
  # The silicon path must be flip-flop mode on every board. "no fucking
  # latches i fucking told you" had to be said repeatedly; a latch-mode
  # silicon build invalidates whatever it was measuring, so the rule lives in
  # a check instead of in someone's memory.
  "tests :: test-no-latches :: TB_RESULT: PASS"
  # one microcode, everywhere: every PROM-image copy matches Code/Microcode
  # (dated exceptions only) - the 895f360 sim-vs-board split detector
  "tests :: test-microcode-sync :: TB_RESULT: PASS"
  # every relative link in tracked markdown resolves (dead-link gate)
  "tests :: test-docs-check :: TB_RESULT: PASS"
  # --- Terminal core (board-independent console: screen + keyboard) ---------
  # 800x600@60 VGA timing: counts a whole frame and checks pixels, lines, both
  # sync widths and the polarity. A wrong polarity is a monitor saying "no
  # signal" with nothing else to go on, so it is checked rather than eyeballed.
  "Terminals/sim :: test-vga-timing :: TB_RESULT: PASS"
  # Stage A glass TTY: printable characters, CR/LF/BS/HT/FF, wrap at column 80
  # (the 80th character IS written) and the hardware scroll - top_row advances
  # and the newly exposed bottom line comes back blank.
  "Terminals/sim :: test-terminal-ctrl :: TB_RESULT: PASS"
  # PS/2 keyboard: 11-bit framing, odd parity (a bad frame is DROPPED - a
  # corrupted scancode can leave shift stuck on), press-vs-release, shift,
  # caps-lock-on-letters-only, ctrl. It does NOT prove the scancode->ASCII
  # table, which can only be checked by typing on a real keyboard.
  "Terminals/sim :: test-ps2-keyboard :: TB_RESULT: PASS"
  # Console UART loopback, run at BOTH framings the machine can be programmed
  # to (7E1 and 8N1). The 7-bit path shifts the byte down out of the top of the
  # register - the step that silently mangles every character if DATA_BITS is
  # wrong, which on hardware looks like "the terminal shows garbage" with
  # nothing to point at.
  "Terminals/sim :: test-console-uart :: TB_RESULT: PASS"
  # The whole console loop end to end, board pins removed: a byte serialized
  # by a stand-in machine survives framing, deserialization, the clock-domain
  # crossing, the control state machine and the address arithmetic to land in
  # the right character cell - and a PS/2 key press comes back out of the
  # machine's own receiver as the right character, THROUGH the idle-high AND
  # merge. Every piece passing alone proves nothing about them being wired the
  # right way round, which is what costs a bitstream build and a trip to the
  # hardware.
  "Terminals/sim :: test-console-loop :: TB_RESULT: PASS"
  # The pixel pipeline, checked EVERY pixel of four frames (1,920,000) against
  # a model built independently in the testbench from the same font file. Not a
  # spot check: this module is a 2-clock fetch pipeline, the hardware-scroll row
  # mapping and the cursor/attribute inversion at once, and each fails in a way
  # that looks almost right - a pipeline off by one just shifts the picture.
  # The testbench also counts the pixels it compared and FAILS if the count is
  # short, because the first version scanned a window inside vertical blanking
  # and cheerfully reported "0 wrong" over zero pixels.
  "Terminals/sim :: test-text-screen :: TB_RESULT: PASS"
  # The power-on message sender. Checks the properties that hold whatever the
  # text says rather than re-listing the message (the message is generated, and
  # a second copy is a second thing to forget): it never offers the 0x00
  # terminator - a REGRESSION, the first version registered `valid` and leaked
  # the NUL for one cycle - it honours backpressure, and it goes silent forever
  # once done, so it can never collide with the machine's own output later.
  "Terminals/sim :: test-banner :: TB_RESULT: PASS"
  # The operator panel. Checks properties rather than comparing a rendered
  # frame - a model of the renderer would just repeat the renderer's own
  # misunderstandings. Bounded region on all four sides (a region-maths error
  # silently eats the console text above it), zero pixels claimed when disabled,
  # and the level afterglow both FADES and EXPIRES. That last one is a
  # regression test: the first decay constant took 28 minutes, which would have
  # shown every level permanently lit and looked entirely plausible.
  "Terminals/sim :: test-panel :: TB_RESULT: PASS"
  # the panel's MIPS counter - window arithmetic, idle clear, saturation
  # (30-AUG-2026, with the MIPS field on the panel)
  "Terminals/sim :: test-mips-counter :: TB_RESULT: PASS"
  # the VT100 key-sequence expander - every marker byte-exact against its
  # DEC sequence, incl. the two-digit ESC[nn~ form and a FIFO burst
  "Terminals/sim :: test-key-vt100 :: TB_RESULT: PASS"
  # TDV2200 (type 93, default terminal, 31-AUG-2026) key-sequence expander -
  # every ESC[nn_ marker byte-exact, incl. zero-padding and a FIFO burst
  "Terminals/sim :: test-key-tdv2200 :: TB_RESULT: PASS"
  # TDV2200 PS/2 -> ASCII path end to end: bare C0 bytes for arrows/Home/
  # Delete (no marker at all, unlike VT100), ESC[nn_ markers for F-keys
  "Terminals/sim :: test-ps2-keyboard-tdv :: TB_RESULT: PASS"
  # TDV2200 display controller - C0 table, DLE binary cursor addressing
  # (both encodings), EOT/EM erase, and the REAL captured PED-at-type-93
  # startup sequence replayed byte-exact (DCS soft-key blocks skipped
  # without leaking to the screen, zero-padded CUP, ED)
  "Terminals/sim :: test-terminal-ctrl-tdv :: TB_RESULT: PASS"
  # --- MiSTer core ----------------------------------------------------------
  # The board-specific console glue, NOT the terminal core (that is above). The
  # three things tested here exist only on this board and each fails in a way
  # that still looks plausible on a screen: the toggle->strobe edge detector on
  # hps_io's ps2_key, the pressed/release polarity flip, and the source
  # priority between banner, machine and local echo. The echo check types a
  # 'q' specifically because the banner text contains no 'q' - the first
  # version typed 's', found one in the banner's own word "this", and would
  # have passed with the echo path completely dead.
  "fpga/mister/sim :: test-console :: TB_RESULT: PASS"
  # CPU liveness probe printed on the MiSTer console (ND120_DIAG_PRINT).
  # DIAGNOSTIC SCAFFOLDING - retire this entry together with the module once
  # the MiSTer CPU runs. Checked because a probe that misformats its own
  # fields sends the debugging the wrong way, which the MIPS tap already did.
  "fpga/mister/sim :: test-diag-print :: TB_RESULT: PASS"
  # Microcode trace buffer and STERR error-number catcher, same scaffolding.
  # The Quartus-only RAM sections (QUARTUS_RAM_INFER) vs the plain-Verilog
  # model every other toolchain runs. NOT scaffolding - this one stays. Only
  # the MiSTer build compiles those sections, so a divergence is invisible to
  # every normal simulation and appears only as a board that will not boot.
  # On 01-SEP-2026 the predecessor arm (an altsyncram megafunction, deleted
  # since) shipped outdata_reg_a="CLOCK0", giving the WCS a two-clock read
  # (altsyncram registers the address as well): every microinstruction
  # arrived a clock late and a nested microsubroutine return popped the wrong
  # address.
  # Split in two 28-SEP-2026 so each testbench runs from its own sim/ folder:
  # the WCS pair (IDT6168A_20_equiv_tb) and the main-memory pair
  # (MEM_RAM_49_BLOCKRAM_equiv_tb). Each arm must also pass its own read-back
  # self-check - two arms can agree on a wrong answer.
  "Shared/support/sim :: test-quartus-ram-equiv :: TB_RESULT: PASS"
  "CPU-BOARD-3202/circuit/sim :: test-mem-ram-equiv :: TB_RESULT: PASS"
  "fpga/mister/sim :: test-csa-trace :: TB_RESULT: PASS"
  "fpga/mister/sim :: test-csa-trig :: TB_RESULT: PASS"
  "fpga/mister/sim :: test-sterr :: TB_RESULT: PASS"
  # The MiSTer storage backend (nd_storage_hps) against the client contract
  # and a signal-level model of the HPS block interface. NOT scaffolding. Only
  # this board has it, so nothing else in the suite would notice it breaking.
  "fpga/mister/sim :: test-storage-hps :: TB_RESULT: PASS"
  # ...and the whole MiSTer storage subsystem at the controller seams: two
  # floppy adapters, two Winchester adapters, the tape adapter. Slot
  # separation for drive 1 / unit 1, which no other board has ever built.
  "fpga/mister/sim :: test-storage-devices :: TB_RESULT: PASS"
  # a back-to-back 115200 burst of the SINTRAN boot lines through the MiSTer
  # receiver + console glue + TDV controller at 40 MHz and at the Nexys 139.7
  # MHz: every byte must reach the screen (02-SEP-2026)
  "fpga/mister/sim :: test-console-burst :: TB_RESULT: PASS"
  "fpga/mister/sim :: test-console-burst-fast :: TB_RESULT: PASS"
  # no reset ordering of nd_storage_hps's two clock domains hangs a read
  # (the automount stuck-R root-cause: the reset CDC is exonerated)
  "fpga/mister/sim :: test-storage-reset :: TB_RESULT: PASS"
  # the console keyboard path end to end (the board-wiring seam the per-module
  # tests miss): key expander -> serializer, and a full PS/2 scancode -> byte
  "fpga/mister/sim :: test-kbd-uart :: TB_RESULT: PASS"
  "fpga/mister/sim :: test-kbd-chain :: TB_RESULT: PASS"
  # the console serial line across the two clock domains: the CPU's SC2661 on
  # the 20 MHz CPU clock (with nd120.qsf's UART defines) into the 7E1
  # console_uart_rx on the 40 MHz pixel clock - five bytes, incl. a CR with
  # software parity in bit 7 (console_bridge_tb, registered 28-SEP-2026)
  "fpga/mister/sim :: test-console-bridge :: TB_RESULT: PASS"
  # --- MEGA65 core glue (02-SEP-2026) ---------------------------------------
  # the MEGA65 keyboard scan -> PS/2 events, checked THROUGH the shared TDV
  # decoder against the C64 keycaps (2" 6& :[ ;] + @ * = ...), ctrl, caps
  # latch, cursor and function keys
  "fpga/mega65/sim :: test-keys :: TB_RESULT: PASS"
  # the console glue: scan -> screen and machine seam, banner priority, and
  # the framework's video shape (de == !(hblank|vblank), RGB black outside de)
  "fpga/mega65/sim :: test-console :: TB_RESULT: PASS"
  # the storage backend on MiSTer2MEGA65's virtual drives (byte-wide buffer
  # bus, QNICE-firmware-style strobes): the same 8 checks as the MiSTer's
  # test-storage-hps, against vdrives_model.v
  "fpga/mega65/sim :: test-storage-vdrives :: TB_RESULT: PASS"
  # ...and the whole storage subsystem on it: two floppy drives, two
  # Winchester units and the tape on their adapters over nd_storage_vdrives
  # (the MiSTer's test-storage-devices on the vdrives backend; registered
  # 28-SEP-2026 - it had a Makefile rule but no registry entry)
  "fpga/mega65/sim :: test-storage-devices :: TB_RESULT: PASS"
  # the R3 HyperRAM backend: nd_ddr2_port's contract on an Avalon-MM master,
  # burst and single-beat fallback, random waitrequest/latency slave model
  "fpga/mega65/sim :: test-avalon-port :: TB_RESULT: PASS"
  # --- QMTECH XC7A35T -------------------------------------------------------
  # nd_storage_bram: the region behind nd_storage's mem_* port. Every other
  # board puts that region in a big memory (SDRAM on the Tang, DDR2 on the
  # Nexys); this one cannot, because the 16-bit SDRAM bridge mode has no
  # 32-bit full-location access, so the region is a block RAM instead. That
  # makes it board-specific RTL carrying a protocol contract, and this bench
  # is what stands between a mistake in it and a disc that reads rubbish on
  # silicon. Checks the whole contract: readback over every word, done being
  # exactly one cycle, busy never dropping mid-operation, rdata HELD after
  # done (the engine reads it late), a write not disturbing rdata, and
  # back-to-back operations at the tightest legal spacing.
  "fpga/qmtech-a35t/sim :: test-storage-bram :: TB_RESULT: PASS"
  # --- Shared support chips -------------------------------------------------
  "Shared/support/sim :: test-ram      :: ALL PASS"
  "Shared/support/sim :: test-uart     :: TB_RESULT: PASS"
  "Shared/support/sim :: test-uart-txabort :: TB_RESULT: PASS"
  "Shared/support/sim :: test-uart-txint :: TB_RESULT: PASS"
  # RX overrun regression (31-AUG-2026, PED keyboard-input investigation):
  # a CPU read landing mid-shift used to see a torn value matching neither
  # byte of a back-to-back pair. See SC2661_RX_OVERRUN_tb.v.
  "Shared/support/sim :: test-uart-rxoverrun :: TB_RESULT: PASS"
  # exhaustive 74245 transceiver gate: guards the removal of the shared
  # 'internalBus' helper that closed a combinational loop on the FIDB bus
  "Shared/support/sim :: test-74245   :: TB_RESULT: PASS"
  # BusDriver16 full contract (FIDBO bus driver, on the same loop)
  "DELILAH-CPU/CGA/sim :: test-busdriver16-full :: TB_RESULT: PASS"
  # Freeze register that captures the trap-logic inputs at the edge that
  # latched a page fault. Runs BOTH build modes; a wrong-cycle capture would
  # send a hardware investigation somewhere wrong with false authority.
  "DELILAH-CPU/CGA/sim :: test-pf-capture :: TB_RESULT: PASS"
  "Shared/support/sim :: test-am29833a :: TB_RESULT: PASS"
  # parity CONVENTION gate: ~^data is what the chip calls correct, and the
  # inverted bit must always fault (policy: parity computed, never stored)
  "Shared/support/sim :: test-am29833a-parity :: TB_RESULT: PASS"
  "Shared/support/sim :: test-am29c821 :: TB_RESULT: PASS"
  "Shared/support/sim :: test-7464x    :: TB_RESULT: PASS"
  "Shared/support/sim :: test-ffen     :: TB_RESULT: PASS"
  # --- ndlib _EN clock-enable equivalence tbs (base vs _EN, late-EN teeth) -
  "Shared/support/sim :: test-scanrst-en :: TB_RESULT: PASS"
  "Shared/support/sim :: test-scanset-en :: TB_RESULT: PASS"
  "Shared/support/sim :: test-sr44-en    :: TB_RESULT: PASS"
  "Shared/support/sim :: test-m169c-en   :: TB_RESULT: PASS"
  "Shared/support/sim :: test-f924-en    :: TB_RESULT: PASS"
  "Shared/support/sim :: test-inrprom  :: TB_RESULT: PASS"
  "Shared/support/sim :: test-fifo     :: TB_RESULT: PASS"
  "Shared/support/sim :: test-idt6168a :: TB_RESULT: PASS"
  # --- backlog burn-down: previously orphaned tbs, verified passing, registered 27-AUG-2026 ---
  "Shared/support/sim :: test-am29841       :: TB_RESULT: PASS"
  "Shared/support/sim :: test-am29861a      :: TB_RESULT: PASS"
  "Shared/support/sim :: test-am29c821-func :: TB_RESULT: PASS"
  "Shared/support/sim :: test-am9150        :: TB_RESULT: PASS"
  "Shared/support/sim :: test-am9150-clk    :: TB_RESULT: PASS"
  "Shared/support/sim :: test-ims1403       :: TB_RESULT: PASS"
  "Shared/support/sim :: test-sevenseg      :: TB_RESULT: PASS"
  "Shared/support/sim :: test-tmm2018d      :: TB_RESULT: PASS"
  "Shared/support/sim :: test-74139         :: TB_RESULT: PASS"
  "Shared/support/sim :: test-74241         :: TB_RESULT: PASS"
  "Shared/support/sim :: test-74244         :: TB_RESULT: PASS"
  "Shared/support/sim :: test-74273         :: TB_RESULT: PASS"
  "Shared/support/sim :: test-74373         :: TB_RESULT: PASS"
  "Shared/support/sim :: test-74374         :: TB_RESULT: PASS"
  "Shared/support/sim :: test-74393         :: TB_RESULT: PASS"
  "Shared/support/sim :: test-74521         :: TB_RESULT: PASS"
  "Shared/support/sim :: test-74534         :: TB_RESULT: PASS"
  "Shared/support/sim :: test-74646-func    :: TB_RESULT: PASS"
  "Shared/support/sim :: test-74648-func    :: TB_RESULT: PASS"
  "Shared/logisim/sim :: test-dffsimple     :: TB_RESULT: PASS"
  "Shared/logisim/sim :: test-dff           :: TB_RESULT: PASS"
  "Shared/logisim/sim :: test-jkff          :: TB_RESULT: PASS"
  "Shared/logisim/sim :: test-mux2          :: TB_RESULT: PASS"
  "Shared/logisim/sim :: test-mux2en        :: TB_RESULT: PASS"
  "Shared/logisim/sim :: test-mux4          :: TB_RESULT: PASS"
  "Shared/logisim/sim :: test-mux8          :: TB_RESULT: PASS"
  "Shared/logisim/sim :: test-muxbus2       :: TB_RESULT: PASS"
  "Shared/logisim/sim :: test-tff           :: TB_RESULT: PASS"
  "Shared/ndlib/sim   :: test-a02           :: TB_RESULT: PASS"
  "Shared/ndlib/sim   :: test-bd4tu         :: TB_RESULT: PASS"
  "Shared/ndlib/sim   :: test-dffen         :: TB_RESULT: PASS"
  "Shared/ndlib/sim   :: test-f924en        :: TB_RESULT: PASS"
  "Shared/ndlib/sim   :: test-jkffen        :: TB_RESULT: PASS"
  "Shared/ndlib/sim   :: test-l4            :: TB_RESULT: PASS"
  "Shared/ndlib/sim   :: test-latch         :: TB_RESULT: PASS"
  "Shared/ndlib/sim   :: test-m169c         :: TB_RESULT: PASS"
  "Shared/ndlib/sim   :: test-m169cen       :: TB_RESULT: PASS"
  "Shared/ndlib/sim   :: test-mux21l        :: TB_RESULT: PASS"
  "Shared/ndlib/sim   :: test-mux21lp       :: TB_RESULT: PASS"
  "Shared/ndlib/sim   :: test-mux24p        :: TB_RESULT: PASS"
  "Shared/ndlib/sim   :: test-mux31lp       :: TB_RESULT: PASS"
  "Shared/ndlib/sim   :: test-mux34p        :: TB_RESULT: PASS"
  "Shared/ndlib/sim   :: test-mux41p        :: TB_RESULT: PASS"
  "Shared/ndlib/sim   :: test-mux81         :: TB_RESULT: PASS"
  "Shared/ndlib/sim   :: test-nd38ghp       :: TB_RESULT: PASS"
  "Shared/ndlib/sim   :: test-nd38glp       :: TB_RESULT: PASS"
  "Shared/ndlib/sim   :: test-r41p          :: TB_RESULT: PASS"
  "Shared/ndlib/sim   :: test-r41pen        :: TB_RESULT: PASS"
  "Shared/ndlib/sim   :: test-r81p          :: TB_RESULT: PASS"
  "Shared/ndlib/sim   :: test-r81en         :: TB_RESULT: PASS"
  "Shared/ndlib/sim   :: test-rmuxgates     :: TB_RESULT: PASS"
  "Shared/ndlib/sim   :: test-scanffen      :: TB_RESULT: PASS"
  "Shared/ndlib/sim   :: test-scanrst       :: TB_RESULT: PASS"
  "Shared/ndlib/sim   :: test-scanrsten     :: TB_RESULT: PASS"
  "Shared/ndlib/sim   :: test-scanset       :: TB_RESULT: PASS"
  "Shared/ndlib/sim   :: test-scanseten     :: TB_RESULT: PASS"
  "Shared/ndlib/sim   :: test-sr44          :: TB_RESULT: PASS"
  "Shared/ndlib/sim   :: test-sr44en        :: TB_RESULT: PASS"
  # --- PALs -------------------------------------------------------------
  "PAL/sim :: test-all :: RESULT: PASS"
  # provenance gate: no PAL may drive an output its PALASM listing does not
  # define, nor drop one it does (the "invented signal" detector)
  "PAL/sim :: test-pal-provenance :: TB_RESULT: PASS"
  # 44306A (21G, MMUCTL): all 1024 input combinations vs a PALASM-derived
  # golden, plus the named EIPL/EIPU asymmetry check - EIPL's third term must
  # stay LSHADOW*WRITE with NO DOUBLE (the 29-JUL-2026 PPN-map-unwritten bug)
  "PAL/sim :: test-pal44306a :: TB_RESULT: PASS"
  # --- PAL _EN clock-enable equivalence tbs (base vs _EN, exhaustive+LFSR) -
  "PAL/sim :: test-44402d-en :: TB_RESULT: PASS"
  "PAL/sim :: test-44403c-en :: TB_RESULT: PASS"
  "PAL/sim :: test-44404c-en :: TB_RESULT: PASS"
  "PAL/sim :: test-44407a-en :: TB_RESULT: PASS"
  "PAL/sim :: test-44408b-en :: TB_RESULT: PASS"
  "PAL/sim :: test-44511a-en :: TB_RESULT: PASS"
  # --- sheet-45 address-decode PALs (base + _D mirror vs PALASM golden) ----
  "PAL/sim :: test-44445b-d :: TB_RESULT: PASS"
  "PAL/sim :: test-44446b-d :: TB_RESULT: PASS"
  # --- CPU board sheets -------------------------------------------------
  "CPU-BOARD-3202/sim         :: test-reqgnt   :: TB_RESULT: PASS"
  # --- backlog burn-down: previously orphaned tbs, verified passing, registered 27-AUG-2026 ---
  "CPU-BOARD-3202/sim         :: test-bdrv7           :: TB_RESULT: PASS"
  "CPU-BOARD-3202/sim         :: test-bifdpath9       :: TB_RESULT: PASS"
  "CPU-BOARD-3202/sim         :: test-ppnlbd14-latch  :: TB_RESULT: PASS"
  "CPU-BOARD-3202/sim         :: test-ppnlbd14-ff     :: TB_RESULT: PASS"
  "CPU-BOARD-3202/sim         :: test-csctl18         :: TB_RESULT: PASS"
  "CPU-BOARD-3202/sim         :: test-prom19          :: TB_RESULT: PASS"
  "CPU-BOARD-3202/sim         :: test-csr26           :: TB_RESULT: PASS"
  "CPU-BOARD-3202/sim         :: test-hit27           :: TB_RESULT: PASS"
  "CPU-BOARD-3202/sim         :: test-ptidb30         :: TB_RESULT: PASS"
  "CPU-BOARD-3202/sim         :: test-wca31           :: TB_RESULT: PASS"
  "CPU-BOARD-3202/sim         :: test-cmddec34-latch  :: TB_RESULT: PASS"
  "CPU-BOARD-3202/sim         :: test-cmddec34-ff     :: TB_RESULT: PASS"
  "CPU-BOARD-3202/sim         :: test-iodcd38-latch   :: TB_RESULT: PASS"
  "CPU-BOARD-3202/sim         :: test-iodcd38-ff      :: TB_RESULT: PASS"
  "CPU-BOARD-3202/sim         :: test-ioreg41-latch   :: TB_RESULT: PASS"
  "CPU-BOARD-3202/sim         :: test-ioreg41-ff      :: TB_RESULT: PASS"
  "CPU-BOARD-3202/sim         :: test-iouart42-latch  :: TB_RESULT: PASS"
  "CPU-BOARD-3202/sim         :: test-iouart42-ff     :: TB_RESULT: PASS"
  "CPU-BOARD-3202/circuit/sim :: test-cyctermd :: RESULT: PASS"
  "CPU-BOARD-3202/circuit/sim :: test-ccd      :: RESULT: PASS"
  "CPU-BOARD-3202/circuit/sim :: test-memaddr  :: TB_RESULT: PASS"
  "CPU-BOARD-3202/circuit/sim :: test-memchain :: TB_RESULT: PASS"
  "CPU-BOARD-3202/circuit/sim :: test-memchain-blockram :: TB_RESULT: PASS"
  "CPU-BOARD-3202/circuit/sim :: test-memchain-sim :: TB_RESULT: PASS"
  "CPU-BOARD-3202/circuit/sim :: test-cs-rwcs  :: TB_RESULT: PASS"
  # microcycle timing golden gate: walks NORMAL/SHORT/SLOW/FETCH/FORM/TRAP/
  # RWCS/LCS/BRK through the real cycle PALs and diffs every clock and strobe
  # against CPU_CYCLE_TIMELINE.golden - a moved edge fails loudly
  "CPU-BOARD-3202/circuit/sim :: test-cycle-timeline :: TB_RESULT: PASS"
  # sheet-20 CS transceivers: the 74PCT373 capture on ECSL~'s falling edge.
  # Its checks 4 and 5 change the source data under a closed latch, so a
  # pass-through implementation (which is what the RTL had) fails loudly.
  "CPU-BOARD-3202/circuit/sim :: test-cs-tcv :: TB_RESULT: PASS"
  # full RWCS microcycle: the control-store word must still be on the IDB at
  # the TERM edge, where ALUCLK writes the A register. This was the TRA CS
  # (150017) reproducer and it went GREEN on 08-AUG-2026 when the sheet-20
  # capture was added - registered that same day, as promised.
  "CPU-BOARD-3202/circuit/sim :: test-cs-rwcs-cycle :: TB_RESULT: PASS"
  # CYCFSM strobe contract under a stretched memory grant (rewritten
  # 27-AUG-2026; the old bench's 41 failures were its own artifacts). Pins:
  # delayed grant stretches state d, held grant stretches state e, CYD/EORF
  # elongate but every strobe rises exactly ONCE per TERM-anchored cycle.
  "CPU-BOARD-3202/circuit/sim :: test-cycstretch :: TB_RESULT: PASS"
  "CPU-BOARD-3202/circuit/sim :: test-blockram :: TB_RESULT: PASS"
  # address-SPACE integrity gate: the BLOCKRAM backend must span the full
  # 64K-word logical space (the 24-AUG-2026 LIST-FILE-NAMES runaway was
  # ADDR_BITS=15 wrapping addresses >= 0o100000 onto low memory); the
  # 16-bit address-bit walk also catches dropped/swapped address bits
  "CPU-BOARD-3202/circuit/sim :: test-blockram-space :: TB_RESULT: PASS"
  # the same gate with the MiSTer's three-slot array (01-SEP-2026)
  "CPU-BOARD-3202/circuit/sim :: test-blockram-space-3banks :: TB_RESULT: PASS"
  "CPU-BOARD-3202/circuit/sim :: test-ddr2ram   :: TB_RESULT: PASS"
  "CPU-BOARD-3202/circuit/sim :: test-ddr2arb   :: TB_RESULT: PASS"
  "CPU-BOARD-3202/circuit/sim :: test-memchain-ddr2 :: TB_RESULT: PASS"
  "CPU-BOARD-3202/circuit/sim :: test-blockram-errfa :: TB_RESULT: PASS"
  "fpga/nexys4ddr/sim :: test-wdiox-ring :: TB_RESULT: PASS"
  "CPU-BOARD-3202/circuit/sim :: test-cdlbd    :: TB_RESULT: PASS"
  "CPU-BOARD-3202/circuit/sim :: test-bdlbd    :: TB_RESULT: PASS"
  "CPU-BOARD-3202/circuit/sim :: test-memdata  :: TB_RESULT: PASS"
  "CPU-BOARD-3202/circuit/sim :: test-cycen    :: TB_RESULT: PASS"
  "CPU-BOARD-3202/circuit/sim :: test-acal     :: TB_RESULT: PASS"
  "CPU-BOARD-3202/circuit/sim :: test-memparity :: TB_RESULT: PASS"
  "CPU-BOARD-3202/circuit/sim :: test-memerror  :: TB_RESULT: PASS"
  "CPU-BOARD-3202/circuit/sim :: test-mmupt-replay :: TB_RESULT: PASS"
  "CPU-BOARD-3202/circuit/sim :: test-mmupt        :: TB_RESULT: PASS"
  # committed access to a ZERO page-table entry must dispatch the page-fault
  # trap (MA forced to vector 0001 at the mid-cycle MACLK strobe) - the unit
  # gate for hypothesis H1 of PLAN-zero-read-nonresident-page.md (git
  # 043c460), through the
  # real cycle PALs + PT RAM + BRKDET + TVGEN + IPOS with real BRK/TRAP
  # feedback; both build modes
  "CPU-BOARD-3202/circuit/sim :: test-pgf-committed    :: TB_RESULT: PASS"
  "CPU-BOARD-3202/circuit/sim :: test-pgf-committed-ff :: TB_RESULT: PASS"
  # BD -> memory bank decode (ND3202D.v:533). The bank bits were tapped from
  # what the board DRIVES instead of what the bus CARRIES, so every incoming
  # DMA write decoded to BANK0 and SINTRAN's segment load landed one bank below
  # the page the MMU resolved - the CPU then fetched zeros and died in
  # ERRFATAL. Cannot be a Verilator boot test: MEM_RAM_49_SIM.v has all three
  # banks, so a misdirected bank still finds memory there.
  "CPU-BOARD-3202/circuit/sim :: test-bdbank           :: TB_RESULT: PASS"
  # MMU shadow memory read-modify-write: PT status bank, bank shifting,
  # shared-WMAP_n isolation, trap-handler PTE update. Sync + async read models.
  "CPU-BOARD-3202/circuit/sim :: test-mmupt-rmw    :: TB_RESULT: PASS"
  # MMU top sheet: the WMAP_n shadow write strobe (LSHADOW & WRITE & CYD),
  # the PTIDB/PPNX bus merges and PAL_44306A acting on the real RAM. Includes
  # a 256-combination sweep proving no write strobe can coincide with a
  # disabled transceiver. Sync + async read models.
  "CPU-BOARD-3202/circuit/sim :: test-mmu24-shadow :: TB_RESULT: PASS"
  # Every one of the 2048 page-table entries (32 tables x 64 VPNs): REX
  # write + IDB read-back + translation, then a SEX pass for the full
  # 16-bit PPN, then a fault-and-fix cycle on the entry SINTRAN dies on
  # (APIT 007, virtual page 0o32). Physical pages are spread by an odd
  # stride so a wrongly-formed index yields a visibly wrong page rather
  # than a plausible neighbour. Catches the EIPL failure mode, where the
  # status bank looks perfect while the PPN map was never written.
  # Added 17-AUG-2026.
  "CPU-BOARD-3202/circuit/sim :: test-mmu24-allentries :: TB_RESULT: PASS"
  # Sheet 28 PPN<->IDB transceiver pair: two INDEPENDENT byte enables
  # (10B /G = EIPU_n, 9B /G = EIPL_n), shared DIR = ESTOF_n, and a disabled
  # driver that puts 0 on the bus. Caught the missing output gating that let
  # the sheet echo its own inputs onto both buses every cycle.
  "CPU-BOARD-3202/circuit/sim :: test-mmuppnx      :: TB_RESULT: PASS"
  # The -DND120_NO_CACHE contract: with the cache memories omitted the
  # sheet must contribute nothing to the CD bus, never claim a hit, never
  # write a cache address, and REPORT the cache as disabled.
  "CPU-BOARD-3202/circuit/sim :: test-mmucache-nocache :: TB_RESULT: PASS"
  "CPU-BOARD-3202/circuit/CPU_CS_TCV_20/sim :: test-tcv :: Testbench Complete"
  # --- gate arrays --------------------------------------------------------
  "DECODE-GateArray/DGA/sim :: test-f595        :: Testbench Complete"
  # --- DGA standard cells: F091/F103/F571 comb + F617 async-FF (both
  #     ACTIVE_ASYNC params) + CPU_STOC_35 exhaustive -----------------------
  "DECODE-GateArray/DGA/sim :: test-fcells      :: TB_RESULT: PASS"
  "DECODE-GateArray/DGA/sim :: test-f617        :: TB_RESULT: PASS"
  "DECODE-GateArray/DGA/sim :: test-f714        :: TB_RESULT: PASS"
  # DECODE_DGA_IDBS enable decoder + panel PRQ/VAL FSM (both build modes)
  "DECODE-GateArray/DGA/sim :: test-dga-idbs    :: TB_RESULT: PASS"
  # DECODE_DGA_POW power-up/MCL/RTC/TOUT sheet (5 builds: plain, VERILATOR_SIM,
  # +RTC_SIM_20MS, FPGA_FF_MODE+BOARD_CLK_FREQ, VERILATOR_SIM+FPGA_FF_MODE)
  "DECODE-GateArray/DGA/sim :: test-dga-pow     :: TB_RESULT: PASS"
  # --- backlog burn-down: previously orphaned tbs, verified passing, registered 27-AUG-2026 ---
  "DECODE-GateArray/DGA/sim :: test-dga-top     :: TB_RESULT: PASS"
  "DECODE-GateArray/DGA/sim :: test-f924        :: TB_RESULT: PASS"
  "CPU-BOARD-3202/circuit/sim :: test-stoc      :: TB_RESULT: PASS"
  # --- CPU-board Tier-3: RAMC grant chain / LBDIF delays (2 modes) /
  #     PANCAL stub contract / MMU cache HIT-gate (3 modes, teeth=ungated) --
  "CPU-BOARD-3202/circuit/sim :: test-ramc      :: TB_RESULT: PASS"
  "CPU-BOARD-3202/circuit/sim :: test-lbdif     :: TB_RESULT: PASS"
  "CPU-BOARD-3202/circuit/sim :: test-pancal    :: TB_RESULT: PASS"
  # IO_PANCAL_40 + ND120_PANEL_CLOCK: MC68705/MM58274 clock path (PANCAL_68705_CLOCK)
  # through a real FIFO_8BIT + the DGA VAL/RIWR handshake, latch and FF builds
  "CPU-BOARD-3202/circuit/sim :: test-pancal-clock    :: TB_RESULT: PASS"
  "CPU-BOARD-3202/circuit/sim :: test-pancal-clock-ff :: TB_RESULT: PASS"
  "CPU-BOARD-3202/circuit/sim :: test-mmucache  :: TB_RESULT: PASS"
  # Cache subsystem coherence (CACHE_25+HIT_27+glue, 2 modes): real-tag
  # hit/refill/write paths PLUS the two demonstrated defects (DMA write
  # never invalidates; CCLR_n does not clear the Am9150 used bits)
  "CPU-BOARD-3202/circuit/sim :: test-mmucache-dma :: TB_RESULT: PASS"
  # BIF_BCTL_SYNC_8 delay-tap pipeline (AM29C821 x2 + PD1/PD3 kills)
  "CPU-BOARD-3202/circuit/sim :: test-bifsync   :: TB_RESULT: PASS"
  # BIF_DPATH_LDBCTL_12 LBC PAL trio (44303B/44302B/44304E, FF+latch modes)
  "CPU-BOARD-3202/circuit/sim :: test-ldbctl    :: TB_RESULT: PASS"
  # BIF_DPATH_PESPEA_13 PEA/PES error registers (plain + FF strobe modes)
  "CPU-BOARD-3202/circuit/sim :: test-pespea    :: TB_RESULT: PASS"
  # MEM_ADEC_45 real sheet-45 DUT (UCADEC/UBADEC PALs + BLRQ/RLRQ flags,
  # plain + FPGA_FF_MODE _D-mirror builds)
  "CPU-BOARD-3202/circuit/sim :: test-adec      :: TB_RESULT: PASS"
  "CPU-BOARD-3202/circuit/sim :: test-pt-stale  :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA/sim      :: test-busdriver16 :: Testbench Complete"
  # CGA_DCD sheet 10 (p.75) DVACCN + VACCN decode: exhaustive CSCOMM x CSMIS x
  # LCSN x PONI x VEX x LSHADOW x INTRQN sweep, EMCLN=0 and EMCLN=1 passes,
  # golden re-derived from the drawing's gate labels (34.3/35.3, 37.2/37.3,
  # ND2). Two builds: plain + FPGA_FF_MODE.
  "DELILAH-CPU/CGA_DCD/sim  :: test-dcd-vacc    :: TB_RESULT: PASS"
  # --- backlog burn-down: previously orphaned tbs, verified passing, registered 27-AUG-2026 ---
  "DELILAH-CPU/CGA_DCD/sim  :: test-dcd-idbs-enables :: TB_RESULT: PASS"
  # CGA_TESTMUX Verilator tb: 25 directed vectors on the TM0-TM4 test mux
  "DELILAH-CPU/CGA_TESTMUX/sim :: test-testmux  :: TB_RESULT: PASS"
  # --- backlog burn-down: previously orphaned tbs, verified passing, registered 27-AUG-2026 ---
  "DELILAH-CPU/CGA_TESTMUX/sim :: test-testmux-iv :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_MIC/sim  :: test-masel-basic :: PASS"
  # --- CGA_MIC counter/select tbs (CSEL+INCOUNT dual build modes) ----------
  "DELILAH-CPU/CGA_MIC/sim  :: test-mic-csel    :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_MIC/sim  :: test-mic-incount :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_MIC/sim  :: test-mic-iinc    :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_MIC/sim  :: test-mic-ipos    :: TB_RESULT: PASS"
  # --- CGA_MIC Tier-3: return stack family + WCAREG/CONDREG (dual modes) ---
  "DELILAH-CPU/CGA_MIC/sim  :: test-mic-stackbit   :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_MIC/sim  :: test-mic-stackbit12 :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_MIC/sim  :: test-mic-stack      :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_MIC/sim  :: test-mic-wcareg     :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_MIC/sim  :: test-mic-condreg    :: TB_RESULT: PASS"
  # --- CGA_MIC Tier-5: MASEL repeat register (dual modes, SC5/SC6 pinned) --
  "DELILAH-CPU/CGA_MIC/sim  :: test-mic-repeat     :: TB_RESULT: PASS"
  # --- backlog burn-down: previously orphaned tbs, verified passing, registered 27-AUG-2026 ---
  "DELILAH-CPU/CGA_MIC/sim  :: test-mic-top        :: TB_RESULT: PASS"
  # --- CGA_MAC_DECODE exhaustive decode check (both build modes, Issue-C
  #     GATES_5 regression tooth: SPT/SAPT mutual exclusion) ---------------
  "DELILAH-CPU/CGA_MAC/sim  :: test-decode      :: TB_RESULT: PASS"
  # --- CGA_MAC_FASTADD per-stage-exhaustive adder check (both build modes) -
  "DELILAH-CPU/CGA_MAC/sim  :: test-fastadd     :: TB_RESULT: PASS"
  # --- CGA_MAC_ADD Tier-4: PRP 4-way selector + CDS sign-extension + adder
  #     vs an independent golden model (both build modes) -------------------
  "DELILAH-CPU/CGA_MAC/sim  :: test-mac-add     :: TB_RESULT: PASS"
  # --- CGA_MAC_PTSEL exhaustive SELPTN table + JK set/clear/hold/toggle
  #     (Issue-C flop; both build modes) ------------------------------------
  "DELILAH-CPU/CGA_MAC/sim  :: test-ptsel       :: TB_RESULT: PASS"
  # --- CGA_MAC SEGPT family (three builds each: plain / FPGA_FF_MODE /
  #     USE_TRANSPARENT_LATCHES - the define that switches L4/L8) -----------
  "DELILAH-CPU/CGA_MAC/sim  :: test-segpt-seg   :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_MAC/sim  :: test-segpt-xpt   :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_MAC/sim  :: test-segpt-pcr   :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_MAC/sim  :: test-segpt       :: TB_RESULT: PASS"
  # --- CGA_MAC Tier-3: APOS increment/CALCA (3 modes) / LASEL 2^19 sweep ---
  "DELILAH-CPU/CGA_MAC/sim  :: test-apos-inc    :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_MAC/sim  :: test-apos-calca  :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_MAC/sim  :: test-lasel       :: TB_RESULT: PASS"
  # --- CGA_MAC Tier-4: AP09 ICA wired-OR mux + CALCA + incrementer (3 modes)
  "DELILAH-CPU/CGA_MAC/sim  :: test-mac-ap09    :: TB_RESULT: PASS"
  # --- CGA_MAC Tier-4: LA1025 LA23-10 wired-OR merge + ECCRHIN (3 modes) ---
  "DELILAH-CPU/CGA_MAC/sim  :: test-mac-la1025  :: TB_RESULT: PASS"
  # --- CGA_IDBCTL / CGA_WRF Tier-1 tbs (PGSREG dual, LR16 triple modes) ----
  "DELILAH-CPU/CGA_IDBCTL/sim :: test-idbctl-sel6   :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_IDBCTL/sim :: test-idbctl-pgsreg :: TB_RESULT: PASS"
  # --- backlog burn-down: previously orphaned tbs, verified passing, registered 27-AUG-2026 ---
  "DELILAH-CPU/CGA_IDBCTL/sim :: test-idbctl        :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_WRF/sim    :: test-wrf-sel16     :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_WRF/sim    :: test-wrf-lr16      :: TB_RESULT: PASS"
  # --- CGA_WRF Tier-5: DR16 WR-qualified register (dual modes) -------------
  "DELILAH-CPU/CGA_WRF/sim    :: test-wrf-dr16      :: TB_RESULT: PASS"
  # --- CGA_WRF Tier-4: RBLOCK parent register-file wiring (triple modes) ---
  "DELILAH-CPU/CGA_WRF/sim    :: test-wrf-rblock    :: TB_RESULT: PASS"
  # --- backlog burn-down: previously orphaned tbs, verified passing, registered 27-AUG-2026 ---
  "DELILAH-CPU/CGA_WRF/sim    :: test-wrf-preg      :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_WRF/sim    :: test-wrf           :: TB_RESULT: PASS"
  # --- CGA_ALU small mux/swap exhaustive tbs (SWAP dual build modes) -------
  "DELILAH-CPU/CGA_ALU/sim  :: test-alu-swap    :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_ALU/sim  :: test-alu-sel7    :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_ALU/sim  :: test-alu-sel8    :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_ALU/sim  :: test-alu-mux216l :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_ALU/sim  :: test-alu-rmux    :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_ALU/sim  :: test-alu-logop   :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_ALU/sim  :: test-alu-smux    :: TB_RESULT: PASS"
  # --- backlog burn-down: previously orphaned tbs, verified passing, registered 27-AUG-2026 ---
  "DELILAH-CPU/CGA_ALU/sim  :: test-alu-gpr         :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_ALU/sim  :: test-alu-outmux-idbs :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_ALU/sim  :: test-alu-top         :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_ALU/sim  :: test-cpu-alu-ralu    :: TB_RESULT: PASS"
  # SHIFT: full 2^20 exhaustive incl. every serial-input combination
  "DELILAH-CPU/CGA_ALU/sim  :: test-alu-shift   :: TB_RESULT: PASS"
  # --- CGA_ALU Tier-3 register tbs (dual modes; QREG teeth = the MPY bug) --
  "DELILAH-CPU/CGA_ALU/sim  :: test-alu-dbr     :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_ALU/sim  :: test-alu-qreg    :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_ALU/sim  :: test-alu-sts     :: TB_RESULT: PASS"
  # --- CGA_ALU Tier-5: ARG register (dual modes, exhaustive load sweep) ----
  "DELILAH-CPU/CGA_ALU/sim  :: test-alu-arg     :: TB_RESULT: PASS"
  # --- CGA_ALU Tier-4: OUTMUX parent netlist (dual modes, selector wiring) -
  "DELILAH-CPU/CGA_ALU/sim  :: test-alu-outmux  :: TB_RESULT: PASS"
  # --- CGA_ALU Tier-4: ALU controller (3 modes; teeth = the historical
  #     SSEL edge-capture bug - ROT/ZIN-right/LIN shifts ran as plain) ------
  "DELILAH-CPU/CGA_ALU/sim  :: test-alu-contr   :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_INTR/sim :: test-irsrc        :: TB_RESULT: PASS"
  # --- CGA_INTR gate-level unit tbs (iverilog, teeth-checked) -----------
  "DELILAH-CPU/CGA_INTR/sim :: iv-CGA_INTR_CNTLR_CLR_CLRBIT         :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_INTR/sim :: test-intr-vecgen                     :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_INTR/sim :: iv-CGA_INTR_CNTLR_VECGEN_PTY_PTYENC  :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_INTR/sim :: iv-CGA_INTR_CNTLR_VECGEN_PTY         :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_INTR/sim :: iv-CGA_INTR_CNTLR_VECGEN_CMP_MAGCMP  :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_INTR/sim :: iv-CGA_INTR_CNTLR_VECGEN_CMP         :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_INTR/sim :: iv-CGA_INTR_CNTLR_VECGEN_STAT_SBIT   :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_INTR/sim :: iv-CGA_INTR_CNTLR_VECGEN_STAT        :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_INTR/sim :: iv-CGA_INTR_CNTLR_VECGEN_ISMUX       :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_INTR/sim :: iv-CGA_INTR_CNTLR_VECGEN_OSMUX       :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_INTR/sim :: iv-CGA_INTR_CNTLR_VECGEN_VHR         :: TB_RESULT: PASS"
  # --- backlog burn-down: previously orphaned tbs, verified passing, registered 27-AUG-2026 ---
  "DELILAH-CPU/CGA_INTR/sim :: test-intr-irsrc                      :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_INTR/sim :: iv-CGA_INTR_CNTLR_IRQ_REG_RQBIT      :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_INTR/sim :: test-rqbitv2                         :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_INTR/sim :: iv-CGA_INTR_CNTLR_IRQ_REG            :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_INTR/sim :: iv-CGA_INTR_CNTLR_IRQ_MASK_MASKBIT   :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_INTR/sim :: iv-CGA_INTR_CNTLR_IRQ_MASK           :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_INTR/sim :: iv-CGA_INTR_CNTLR_IRQ_MREQ           :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_INTR/sim :: iv-CGA_INTR_CNTLR_IRQ                :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_INTR/sim :: iv-CGA_INTR_CNTLR_IRGEL_VMUX         :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_INTR/sim :: iv-CGA_INTR_CNTLR_IRGEL_HIGEL        :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_INTR/sim :: iv-CGA_INTR_CNTLR_IRGEL_LOGEL        :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_INTR/sim :: iv-CGA_INTR_CNTLR_IRGEL_HIRL         :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_INTR/sim :: iv-CGA_INTR_CNTLR_IRGEL_LORL         :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_INTR/sim :: iv-CGA_INTR_CNTLR_IRGEL              :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_INTR/sim :: iv-CGA_INTR_CNTLR_MDCD              :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_INTR/sim :: iv-CGA_INTR_CNTLR_CLR               :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_INTR/sim :: iv-CGA_INTR_CNTLR                   :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_INTR/sim :: iv-CGA_INTR_CNTLR_seq               :: TB_RESULT: PASS"
  # --- CGA_TRAP gate-level unit tbs (iverilog, teeth-checked) -----------
  "DELILAH-CPU/CGA_TRAP/sim :: iv-CGA_TRAP_TBUF      :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_TRAP/sim :: iv-CGA_TRAP_BRKDET    :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_TRAP/sim :: iv-CGA_TRAP_TVGEN_P2  :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_TRAP/sim :: iv-CGA_TRAP_TVGEN     :: TB_RESULT: PASS"
  # Exhaustive sweep of ALL 524288 input combinations of CGA_TRAP_TVGEN
  # (vacc ifetch iind iwrite intrq pan poni dstop_n ftrap_n vtrap_n ipcr ipt),
  # checking TVEC_3_0/PVIOL/RESTR against a spec-derived golden. The older
  # CGA_TRAP_TVGEN tb checks 5 directed vectors plus a 6000-vector random
  # soak - about 1% of the space - so a term needing a specific multi-input
  # coincidence could hide there. Added 17-AUG-2026.
  "DELILAH-CPU/CGA_TRAP/sim :: iv-CGA_TRAP_TVGEN_exhaustive :: TB_RESULT: PASS"
  "DELILAH-CPU/CGA_TRAP/sim :: iv-CGA_TRAP           :: TB_RESULT: PASS"
  # CGA_TRAP + CGA_IDBCTL_PGSREG driven together: every page-table protection
  # outcome asserts BOTH the trap vector AND the resulting PGS word, against the
  # ND-110 semantics (page fault vs protect violation, PGS PM/FETCH bits,
  # PGS[11:0]=pagetable<<6|VPN, ring violation vs ring-down).
  "DELILAH-CPU/CGA_TRAP/sim :: test-trap-pgs-paging  :: TB_RESULT: PASS"
  # --- Tang Nano 20K SDRAM stack ---------------------------------------
  "fpga/tang-nano-20k/sdram-bridge/sim :: test :: TB_RESULT: PASS"
  "fpga/tang-nano-20k/sdram-bridge/sim :: test-pack16 :: TB_RESULT: PASS"
  "fpga/tang-nano-20k/sdram-bridge/sim :: test-pack16-part :: TB_RESULT: PASS"
  "fpga/tang-nano-20k/sdram-bridge/sim :: test-storage-port :: TB_RESULT: PASS"
  # the MiSTer's 16-bit module shape (ND_SDRAM_DQ16), same bridge, same replay
  "fpga/tang-nano-20k/sdram-bridge/sim :: test-dq16 :: TB_RESULT: PASS"
  "fpga/tang-nano-20k/sdram-test/sim   :: test :: TB_RESULT: PASS"
  "fpga/tang-nano-20k/sdram18-test/sim :: test :: TB_RESULT: PASS"
  # --- SD-FAT library + Tang Nano 20K SD test ---------------------------
  "SD-FAT/sim                         :: test-writer    :: TB_RESULT: PASS"
  "SD-FAT/sim                         :: test-writer-div1 :: TB_RESULT: PASS"
  "SD-FAT/sim                         :: test-nds-cdc   :: TB_RESULT: PASS"
  "SD-FAT/sim                         :: test-nds-engine :: TB_RESULT: PASS"
  "SD-FAT/sim                         :: test-nds-write :: TB_RESULT: PASS"
  "SD-FAT/sim                         :: test-nds-mount :: TB_RESULT: PASS"
  # Same stack on the 4-bit DAT bus. CMD55 must carry the card's PUBLISHED
  # RCA (the reader exports it from CMD3); the card model refuses RCA 0
  # once CMD3 has run, as real silicon does. Guards the fault that made
  # USE_4BIT=1 read garbage on the Tang while simulating clean.
  "SD-FAT/sim                         :: test-nds-mount-4bit :: TB_RESULT: PASS"
  "SD-FAT/sim                         :: test-nds-ticks :: TB_RESULT: PASS"
  # Client bus slice continuity. nd_storage_devices hands nd_storage its
  # per-client ports as five hand-written flat concatenations, and nothing
  # else checks that a client actually got a slice in each one - a forgotten
  # slice is a silent tie to zero that elaborates, simulates and synthesises
  # cleanly. That is exactly how the Winchester's buf_rdata went missing and
  # every disc WRITE quietly stored zeros (10-AUG-2026). Teeth-proven: with
  # the fix reverted this fails on client 6 and only client 6.
  "SD-FAT/sim                         :: test-nds-clientbus :: TB_RESULT: PASS"
  "SD-FAT/sim                         :: test-nds-fatchk-unit :: TB_RESULT: PASS"
  "SD-FAT/sim                         :: test-nds-fatchk :: TB_RESULT: PASS"
  "SD-FAT/sim                         :: test-storage   :: TB_RESULT: PASS"
  "SD-FAT/sim                         :: test-nds-tape  :: TB_RESULT: PASS"
  "SD-FAT/sim                         :: test-nds-floppy :: TB_RESULT: PASS"
  # PARKED 11-AUG-2026, was: SD-FAT/sim :: test-nds-smd :: TB_RESULT: PASS
  # The target builds nd_storage_disc_adapter_tb.vvp from
  # nd_storage_disc_adapter_tb.v - a file that has NEVER been tracked in git.
  # It was renamed to nd_storage_smd_adapter_tb.v in commit b8dd72d
  # (10-AUG-2026) and neither the Makefile target nor this line followed, so
  # the entry could not build. Nobody saw it because the FIRST registry entry
  # (test-tb-catalog) was itself red, which aborted the whole fail-fast run
  # before reaching this line.
  #
  # The replacement bench does elaborate but reports 3036 errors, so it cannot
  # be registered either - see ORPHAN_BASELINE in tests/tb_catalog.py and the
  # by-hand target test-nds-smdadapter in SD-FAT/sim/Makefile. This is the SMD
  # controller workstream, handed to another session; do not edit ND_SMD.v or
  # nd_storage_smd_adapter.v here. Restore this line the day it goes green.
  "SD-FAT/sim                         :: test-nds-cache :: TB_RESULT: PASS"
  "SD-FAT/sim                         :: test-nds-cachepath :: TB_RESULT: PASS"
  # Failure reporting: every way a storage op can fail must COMPLETE, with
  # err=1 and the right reason code (SD-FAT/circuit/nd_storage_status.vh).
  # No card, missing file, never-opened client, past end of image, broken
  # FAT chain, frozen mem port - read AND write. The eighth mode, "the card
  # goes silent", is in test-nds-errors-slow (run by `make test-full`): its
  # only terminator is sd_writer.v's TO_DATA watchdog, 148 ms of simulated
  # time for one case, and TO_DATA is a real device timeout that must not be
  # shortened to suit a testbench.
  "SD-FAT/sim                         :: test-nds-errors :: TB_RESULT: PASS"
  # --- backlog burn-down: previously orphaned tbs, verified passing, registered 27-AUG-2026 ---
  "SD-FAT/sim                         :: test-nds-devices     :: TB_RESULT: PASS"
  "SD-FAT/sim                         :: test-nds-discadapter :: TB_RESULT: PASS"
  "SD-FAT/sim                         :: test-nds-mountfsm    :: TB_RESULT: PASS"
  "SD-FAT/sim                         :: test-nds-synclevel   :: TB_RESULT: PASS"
  "SD-FAT/sim                         :: test-sd-cardctrl     :: TB_RESULT: PASS"
  "SD-FAT/sim                         :: test-fat-check       :: TB_RESULT: PASS"
  "SD-FAT/sim                         :: test-fat-freescan    :: TB_RESULT: PASS"
  "SD-FAT/sim                         :: test-fat-rewrite     :: TB_RESULT: PASS"
  # --- board memory-test benches ---------------------------------------
  # Found by `make test-audit` 09-AUG-2026: both existed with no Makefile at
  # all, so nothing could run them. They build and pass; they were simply
  # invisible. Both boards are secondary targets (Basys3 has an open BLOCKRAM
  # item, the QMTECH A35T bring-up is paused), which is exactly why an
  # unattended gate is worth having - nobody is exercising them by hand.
  "fpga/basys3/mem-test/sim           :: test-basys3-memtest :: TB_RESULT: PASS"
  "fpga/qmtech-a35t/mem-test/sim      :: test-qmtech-memtest :: TB_RESULT: PASS"
  "fpga/tang-nano-20k/sd-fat-test/sim :: test-dumper    :: TB_RESULT: PASS"
  # Streaming diagnostics (menu 8 BLOCK / 9 SECTOR / R RANGE / N) on a
  # 327680-byte file - five times the tool's 64 KB dump buffer, so menu 2
  # cannot reach it. The RANGE case is the one that matters for SINTRAN
  # segment handling: 70 CONSECUTIVE blocks (280 sectors) read as one run,
  # with the reported block count, sector count and word checksum all
  # checked against the image model. Also the read-only gate: the DEFAULT
  # build must offer no writing command and put no CMD24/CMD25 on the
  # card. ~2 min under iverilog.
  # PARKED 11-AUG-2026, was:
  #   fpga/tang-nano-20k/sd-fat-test/sim :: test-block :: TB_RESULT: PASS
  # RED, and NOT caused by that day's CPU-board work: BLOCK_SRCS names only
  # SD-FAT circuit files, the card model, uart_tx/uart_rx and status_printer -
  # no CPU-BOARD-3202 source is in the build at all. The bench reaches the
  # range read, the card model logs "ACMD6 bus width -> 4-bit", and the next
  # line is "ERROR: SD READ FAILED AT SECTOR 000000A1", 0 blocks read.
  # blockdump.img is present (8 MB, 10-AUG) but BIG.BPUN, which
  # make_block_image.sh builds it from, is absent from the tree.
  # It went unnoticed because the FIRST registry entry was itself red, which
  # aborted this fail-fast run before it ever got here. Storage lane, not the
  # CPU lane. Restore this line the day it goes green.
  "fpga/tang-nano-20k/sd-fat-test/sim :: test-verilator :: TB_RESULT: PASS"
  "fpga/tang-nano-20k/sd-fat-test/sim :: test-verilator-fat32 :: TB_RESULT: PASS"
  "fpga/tang-nano-20k/sd-fat-test/sim :: test-verilator-fat32big :: TB_RESULT: PASS"
  "fpga/tang-nano-20k/sd-fat-test/sim :: test-tristate  :: TB_RESULT: PASS"
  "fpga/tang-nano-20k/sd-fat-test/sim :: test-errtexts  :: TB_RESULT: PASS"
  # --- ND-100 external bus devices --------------------------------------
  "ND-BUS-DEVICES/BUS-IF/sim :: test-bus-slave :: TB_RESULT: PASS"
  "ND-BUS-DEVICES/FLOPPY/sim :: test-floppy-pio :: TB_RESULT: PASS"
  # --- backlog burn-down: previously orphaned tbs, verified passing, registered 27-AUG-2026 ---
  "ND-BUS-DEVICES/FLOPPY/sim :: test-floppy-ioxmap :: TB_RESULT: PASS"
  "ND-BUS-DEVICES/DMA/sim    :: test-dma-master :: TB_RESULT: PASS"
  "ND-BUS-DEVICES/DMA/sim    :: test-dma-stale-capture :: TB_RESULT: PASS"
  # --- backlog burn-down: previously orphaned tbs, verified passing, registered 27-AUG-2026 ---
  "ND-BUS-DEVICES/DMA/sim    :: test-dma-reset-pend    :: TB_RESULT: PASS"
  "ND-BUS-DEVICES/FLOPPY-DMA/sim :: test-floppy-dma :: TB_RESULT: PASS"
  "ND-BUS-DEVICES/FLOPPY-DMA/sim :: test-floppy-boot :: TB_RESULT: PASS"
  "ND-BUS-DEVICES/FLOPPY-DMA/sim :: test-floppy-iox :: TB_RESULT: PASS"
  "ND-BUS-DEVICES/FLOPPY-DMA/sim :: test-floppy-p2 :: TB_RESULT: PASS"
  "ND-BUS-DEVICES/FLOPPY-DMA/sim :: test-floppy-sdfat :: TB_RESULT: PASS"
  "ND-BUS-DEVICES/TAPE-400/sim :: test-tape400  :: TB_RESULT: PASS"
  "ND-BUS-DEVICES/SMD/sim    :: test-smd        :: TB_RESULT: PASS"
  "ND-BUS-DEVICES/SMD/sim    :: test-smd-iox    :: TB_RESULT: PASS"
  "ND-BUS-DEVICES/SMD/sim    :: test-smd-p2     :: TB_RESULT: PASS"
  "ND-BUS-DEVICES/SMD/sim    :: test-smd-ecc    :: TB_RESULT: PASS"
  "ND-BUS-DEVICES/SMD/sim    :: test-smd-err    :: TB_RESULT: PASS"
  "ND-BUS-DEVICES/WINCHESTER/sim :: test-wd-iox :: TB_RESULT: PASS"
  "ND-BUS-DEVICES/WINCHESTER/sim :: test-wd-adapter :: TB_RESULT: PASS"
  "ND-BUS-DEVICES/WINCHESTER/sim :: test-wd-oracle :: TB_RESULT: PASS"
  "ND-BUS-DEVICES/WINCHESTER/sim :: test-wd-bus :: TB_RESULT: PASS"
  "ND-BUS-DEVICES/WINCHESTER/sim :: test-wd-wcsweep :: TB_RESULT: PASS"
  "ND-BUS-DEVICES/WINCHESTER/sim :: test-wd-dmapath :: TB_RESULT: PASS"
  "ND-BUS-DEVICES/WINCHESTER/sim :: test-wd-storage :: TB_RESULT: PASS"
  "ND-BUS-DEVICES/WINCHESTER/sim :: test-wd-storage-sdram :: TB_RESULT: PASS"
  # Same block read/write matrix with ND_STORAGE_DISCS_UNCACHED, which forces
  # CACHE_MASK to zero. A cached client enters the engine at C_LOOK, a direct
  # one jumps straight to C_SEC_GO - two different routes to the same 4-sector
  # split, so both need their own gate.
  "ND-BUS-DEVICES/WINCHESTER/sim :: test-wd-storage-uncached :: TB_RESULT: PASS"
  # An operation must stay readable as ACTIVE long enough for a guest to see
  # it. Guards the RTZ completion delay against being shortened back to the
  # 8-tick fast path, which made the File System Investigator read 060011
  # where the nd100x oracle reads 060005.
  "ND-BUS-DEVICES/WINCHESTER/sim :: test-wd-rtz :: TB_RESULT: PASS"
  # --- backlog burn-down: previously orphaned tbs, verified passing, registered 27-AUG-2026 ---
  "ND-BUS-DEVICES/WINCHESTER/sim :: test-wd-decode :: TB_RESULT: PASS"
  # M3 compare reads the sector, compares it against ND memory, and leaves the
  # memory address register ADVANCED by the word count. M3 used to share the
  # do-nothing stub with M2 and M5, so the register read back holding whatever
  # the guest had loaded - and SINTRAN reads it back after every operation.
  # That is what made the '20500&' boot re-issue block 0 seven times and print
  # TRANSFER ERROR while every status word looked perfect.
  "ND-BUS-DEVICES/WINCHESTER/sim :: test-wd-compare :: TB_RESULT: PASS"
  "ND-BUS-DEVICES/WINCHESTER/sim :: test-wd-boothang :: TB_RESULT: PASS"
  "ND-BUS-DEVICES/WINCHESTER/sim :: test-wd-ticks :: TB_RESULT: PASS"
)
# NOT in the registry (run manually, documented reasons):
#   DECODE-GateArray/DGA/sim test-f595-transparency - FAILS BY DESIGN on the
#     current F595 FPGA branch (lagging FF; the transparent-latch fix was
#     REVERTED 19-JUL after a comb loop on silicon). It pinpoints the
#     divergence; register it only if/when F595's FPGA branch is made a
#     zero-latency transparent latch again.
#   DELILAH-CPU/CGA_MIC/sim test-masel-cycle / test-masel-iw - exploratory
#     race-documentation tbs with EXPECTED FAIL lines; not strict pass/fail.
#   Verilog/sim make compare, runSim golden, fpga vtest - heavy system gates,
#     run via `make test-full`.
#   Verilog make test-democore - the NDDeviceCore RTL EQUIVALENCE GATE
#     (portable C99 nd_lineprinter driven by the real ND-120 CPU + bus RTL,
#     verdict line "[democore] RESULT: PASS"). Deliberately NOT in this
#     registry: it is a ~12 min runSim compile+run, and this registry is the
#     fast per-testbench sweep behind plain `make test`. It is registered in
#     the heavy sweep instead - see `test-full` in Verilog/Makefile.
#   fpga/tang-nano-20k/sd-fat-test/sim test-system - pure-iverilog version of
#     the SD full-system test (same plan as the registered test-verilator);
#     iverilog needs 30-60 min for it, so it is a manual gate only.

scream() {
  echo ""
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "!!!                                                              !!!"
  echo "!!!   TEST FAILED - RUN ABORTED                                  !!!"
  echo "!!!   dir:    $1"
  echo "!!!   target: $2"
  echo "!!!   reason: $3"
  echo "!!!                                                              !!!"
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo ""
  echo "--- last 40 lines of output -------------------------------------"
  tail -40 "$LOG"
  echo "------------------------------------------------------------------"
  exit 1
}

LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

total=0
t0=$SECONDS
for entry in "${REGISTRY[@]}"; do
  dir="$(echo "$entry"  | awk -F' *:: *' '{print $1}')"
  tgt="$(echo "$entry"  | awk -F' *:: *' '{print $2}')"
  pat="$(echo "$entry"  | awk -F' *:: *' '{print $3}')"
  total=$((total+1))
  printf "%-46s %-16s " "$dir" "$tgt"

  if ! make -s -C "$dir" "$tgt" >"$LOG" 2>&1; then
    echo "FAILED (exit code)"
    scream "$dir" "$tgt" "make target exited nonzero"
  fi
  if grep -qE '(^|[^A-Za-z])FAIL' "$LOG"; then
    echo "FAILED (FAIL in output)"
    scream "$dir" "$tgt" "output contains a FAIL line"
  fi
  if ! grep -q "$pat" "$LOG"; then
    echo "FAILED (no pass marker)"
    scream "$dir" "$tgt" "required pass pattern not found: '$pat'"
  fi
  echo "ok"
done

echo ""
echo "===================================================================="
echo "  ALL $total TESTS PASSED   ($((SECONDS-t0)) s)"
echo "===================================================================="
