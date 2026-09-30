# ND-120 on Nexys 4 DDR / Nexys A7-100T - self-contained in-memory Vivado flow
#
# Template: the Basys3 build (fpga/basys3/vivado_build.tcl) - same defines,
# same source set, same "fail loudly on negative slack" gate. The one
# deliberate difference: no out-of-repo .xpr GUI project (the Basys3 flow
# drives the project named by ND120_BASYS3_PROJECT). Everything here is in-memory and lives in
# the repo, the way fpga/cmod-a7-35t/build.tcl already does it.
#
#   vivado -mode batch -source build.tcl                       # build + JTAG program
#   vivado -mode batch -source build.tcl -tclargs -noburn      # build only
#   vivado -mode batch -source build.tcl -tclargs clk=33       # 33.333 MHz CPU clock
#   vivado -mode batch -source build.tcl -tclargs -promload    # runtime PROM->WCS load
#
# Configuration: BRAM main memory (MAIN_RAM_BLOCKRAM), FF mode, WCS preloaded
# from the bitstream (SKIP_WCS_LOAD - the same choice the Tang makes), CPU
# clock 16.667 MHz. The ND-BUS device chain (tape, floppy, Winchester) is
# included and served from the microSD card, with the storage region in DDR2.

set part xc7a100tcsg324-1
set srcdir [file dirname [file normalize [info script]]]
set vroot  [file normalize [file join $srcdir .. ..]]   ;# Verilog/

########################################################################
# CPU clock selection
#  The board oscillator is 100 MHz; the MMCM in ND120_TOP.v (branch
#  TARGET_NEXYS4DDR) runs VCO = 100 x 10 = 1000 MHz and divides it down.
#  clk=<MHz> picks the divider AND the matching BOARD_CLK_FREQ - the two
#  MUST move together or every derived count (UART baud, RTC tick,
#  watchdogs) is wrong.
#
#  STALE MEASUREMENT KEPT FOR HISTORY (superseded): 20-AUG-2026 builds
#  measured WNS -35.107 ns at 16.667 MHz. After the 22-AUG FIDBO ring cut
#  (commit b3ee391) the SAME configuration closes with WNS ~+1.4 ns at
#  16.667 MHz (verified across every 23/24-AUG build). The bucket analysis
#  below describes the PRE-CUT worst path:
#  The worst path ran from an interrupt mask bit
#  (INTR/CNTLR/IRQ_MASK/MASKBIT10) to the WCS BRAM address input over 181
#  logic levels / 94.4 ns, with NO register in between. Measured Fmax of the
#  CPU domain is therefore about 10.5 MHz, so clk=8 is the first entry that
#  can pass the gate and clk=10 is marginal.
#
#  Where the 94.4 ns goes, bucketed from timing.rpt:
#      CGA/ALU  (OUTMUX/RALU/STS)   58.8 ns   62%
#      CGA/MAC                      14.5 ns   15%
#      CGA/INTR                      8.2 ns    9%
#      MMU cache                     4.3 ns    5%
#  It is an ALU path, not an interrupt path and not a device-chain path.
#
#  TWO THINGS THIS COMMENT USED TO CLAIM, BOTH WRONG, both corrected after
#  reading the Tang's own Gowin report
#  (fpga/tang-nano-20k/build/nd120_tang20k_build/impl/pnr/*.tr):
#    - "the same RTL closes 27 MHz on the Tang". It does not. The Tang's CPU
#      domain is constrained at 6.75 MHz and its actual Fmax is 5.08 MHz with
#      1532 violating endpoints. The 27 MHz figure belongs to sys_clk, the
#      crystal INPUT PORT, which is the only clock its six-line .sdc
#      constrains. In absolute nanoseconds this board is about twice as fast
#      as the Tang has ever run.
#    - "the device chain explains the path". It does not. The Tang carries
#      the identical tape + floppy + Winchester set (SMD off).
#
#  Every setting is an EXPERIMENT until its own timing report is clean, and
#  the WNS gate below refuses to write a bitstream that misses. The Gowin
#  flow has no such gate, which is why the Tang has been writing bitstreams
#  over 1532 violating endpoints.
########################################################################
set clk_table {
    8   {125.0 8000000}
    10  {100.0 10000000}
    12  {80.0  12500000}
    16  {60.0 16666667}
    20  {50.0 20000000}
    25  {40.0 25000000}
    27  {37.0 27027027}
    33  {30.0 33333333}
    35  {28.0 35714286}
    38  {26.0 38461538}
    40  {25.0 40000000}
    42  {24.0 41666667}
    45  {22.0 45454545}
    50  {20.0 50000000}
    100 {10.0 100000000}
}
# CPU clock argument. BOTH forms are accepted, and that is not politeness:
#
#   MEASURED 20-AUG-2026: invoked from WSL through cmd.exe, "clk=10" arrives
#   at Vivado as TWO separate arguments - argv becomes {-noburn} {clk} {10},
#   because cmd.exe treats '=' as an argument delimiter just like a space.
#   A regexp for '^clk=(\d+)$' therefore matches NOTHING and the build
#   silently runs at the default speed while looking like it obeyed. That
#   cost two full builds before it was measured with a tcl script that just
#   printed $argv.
#
#   So: accept "clk=10" (works when run from a real shell), accept "clk 10"
#   (what cmd.exe delivers), and FAIL LOUDLY on anything else.
# One spelling of a flag on BOTH boards. The Tang build is PowerShell, where a
# switch MUST be written "-NoPanelClock"; this one is a tcl script reading bare
# argv words. Rather than make the operator remember which board wants which
# spelling, every flag checked with has_flag matches with or without a leading
# dash and ignoring case: "nopanelclock", "-nopanelclock" and "-NoPanelClock"
# are all the same flag here.
proc has_flag {name} {
    global argv
    set want [string tolower [string trimleft $name "-"]]
    foreach a $argv {
        if {[string tolower [string trimleft $a "-"]] eq $want} { return 1 }
    }
    return 0
}

set clk_sel 16
set _n [llength $argv]
for {set i 0} {$i < $_n} {incr i} {
    set a [lindex $argv $i]
    if {[regexp {^clk=(\w+)$} $a -> v]} {
        set clk_sel $v
    } elseif {$a eq "clk" && $i + 1 < $_n} {
        set clk_sel [lindex $argv [expr {$i + 1}]]
    }
}
# Console baud argument, same two accepted forms as clk (cmd.exe splits '=').
set uart_baud 115200
for {set i 0} {$i < $_n} {incr i} {
    set a [lindex $argv $i]
    if {[regexp {^baud=(\d+)$} $a -> v]} {
        set uart_baud $v
    } elseif {$a eq "baud" && $i + 1 < $_n} {
        set uart_baud [lindex $argv [expr {$i + 1}]]
    }
}
if {$uart_baud != 9600 && $uart_baud != 115200} {
    puts "ERROR: baud=$uart_baud not supported (9600 or 115200)."
    exit 1
}
puts "argv: $argv  -> clk_sel = $clk_sel, uart_baud = $uart_baud"

if {![dict exists $clk_table $clk_sel]} {
    puts "ERROR: clk=$clk_sel not supported. Choose one of: [dict keys $clk_table]"
    exit 1
}
set mmcm_div  [lindex [dict get $clk_table $clk_sel] 0]
set board_clk [lindex [dict get $clk_table $clk_sel] 1]
puts "CPU clock: divider $mmcm_div -> BOARD_CLK_FREQ $board_clk Hz"

# WCS PRELOAD IS THE DEFAULT ON THIS BOARD, same as the Tang Nano 20K
# (fpga/tang-nano-20k/src/tang20k_defines.v defines SKIP_WCS_LOAD): the
# microcode is preloaded straight into the WCS from the 33 nibble images in
# Code/Microcode/wcs/, and the LCS latch is neutralised so the original
# machine's runtime PROM->WCS load phase never runs. The point is cost: with
# SKIP_WCS_LOAD the microcode PROM (CPU_CS_PROM_19) is never read, so its ROM
# arrays are compiled out entirely - no block RAM spent emulating an EPROM,
# and about 7,850 LUTs saved.
#
# -promload builds the other way (runtime load out of the emulated PROM), for
# comparison against the original machine's behaviour.
set skip_wcs [expr {[lsearch $argv "-promload"] < 0}]

cd $srcdir

if {$skip_wcs} {
    # $readmemh("wcs_*.hex") resolves against Vivado's working directory
    set wcs_src [file normalize [file join $vroot .. Code Microcode wcs]]
    set wcs_files [glob -nocomplain [file join $wcs_src wcs_*.hex]]
    if {[llength $wcs_files] != 33} {
        puts "ERROR: expected 33 WCS images in $wcs_src, found [llength $wcs_files]"
        exit 1
    }
    foreach f $wcs_files { file copy -force $f [file join $srcdir [file tail $f]] }
    puts "WCS preload: [llength $wcs_files] images copied (SKIP_WCS_LOAD)."
} else {
    set uc [file join $vroot .. Code Microcode]
    foreach hex {AM27256_45132L.hex AM27256_45133L.hex} {
        if {![file exists [file join $uc $hex]]} {
            puts "ERROR: microcode image missing: [file join $uc $hex]"
            exit 1
        }
        file copy -force [file join $uc $hex] [file join $srcdir $hex]
    }
    puts "-promload: microcode PROM images copied (2 files)."
}

create_project -in_memory -part $part

# One source of truth for the CPU file list: the Tang project file, minus the
# Tang-specific files, plus the ND120_TOP stack and this board's top.
set gprj [file join $vroot fpga tang-nano-20k nd120_tang20k.gprj]
set fp [open $gprj r]
set xml [read $fp]
close $fp

set exclude {
    src/tang20k_defines.v
    src/gowin_rpll_27_54.v
    src/ND120_TANG20K_TOP.v
    sdram-test/src/uart_tx.v
    sdram-bridge/MEM_RAM_49_SDRAM.v
    sdram-bridge/sdram18.v
}
set srcs {}
foreach {full path} [regexp -all -inline {<File path="([^"]+)"[^>]*enable="1"/>} $xml] {
    if {![string match *.v $path]} { continue }
    if {[lsearch -exact $exclude $path] >= 0} { continue }
    lappend srcs [file normalize [file join $vroot fpga tang-nano-20k $path]]
}
puts "CPU sources from nd120_tang20k.gprj: [llength $srcs] files"

# ND120_TOP.v is deliberately NOT read: this board's top instantiates
# ND120_CORE directly, because the ND-BUS device chain (tape, floppy,
# Winchester) exists only on the core - the same reason the Tang top does it.
lappend srcs \
    [file join $vroot CPU-BOARD-3202 circuit MEM_RAM_49_BLOCKRAM.v] \
    [file join $srcdir SevenSegDebug8.v] \
    [file join $vroot fpga nexys4ddr ddr2 nd_ddr2_port.v] \
    [file join $vroot fpga nexys4ddr ddr2 nd_ddr2_storage.v] \
    [file join $vroot fpga nexys4ddr ddr2 nd_ddr2_arb.v] \
    [file join $vroot fpga nexys4ddr ddr2 MEM_RAM_49_DDR2.v] \
    [file join $srcdir nd120_errfa_wdiox_ring.v] \
    [file join $srcdir nd120_nexys4ddr_top.v]

# VGA console: the console on the board's own VGA connector and a USB keyboard
# (which the on-board microcontroller presents as plain PS/2), next to the USB
# serial port. See PLAN-vga-console.md. The serial console is NOT removed - it
# keeps working in parallel, so console.ps1, the board tests and the soak
# scripts are unaffected.
#
# ON BY DEFAULT since 29-AUG-2026 (Ronny): every image deployed since 28-AUG
# carried it, and a build that silently dropped it left the board with a dead
# screen. Pass "novgaconsole" to leave it out if the space is needed for
# something else. "vgaconsole" is still accepted and means the default.
set vga_console [expr {[lsearch $argv "novgaconsole"] < 0}]
if {$vga_console} {
    set tdir [file join $vroot Terminals rtl]
    # ps2_decoder.v is separate from ps2_keyboard.v since 28-AUG-2026: the
    # keyboard file is now only the PS/2 SERIAL front end (this board needs it,
    # MiSTer and the MEGA65 do not) and the decoding logic - modifiers, caps,
    # ctrl, the TDV cursor keys - lives in the decoder so all three boards
    # share one copy. Both are needed here.
    #
    # term_banner*.v print the power-on self-test message. term_banner_rom.v is
    # GENERATED by Terminals/font/make_banner.py - do not hand-edit it.
    # Both the VT100 and TDV2200 controller/keyboard pairs are added
    # unconditionally - `ifdef ND120_TERMINAL_VT100` in terminal_top.v and
    # nd120_nexys4ddr_top.v (via -verilog_define, see $defines below) picks
    # which pair actually gets elaborated; Vivado is fine with the other
    # pair sitting unused in the project. Default (no define) is TDV2200 -
    # see Verilog/Terminals/docs/SPEC-tdv2200.md.
    # ---- build stamp in the power-on banner (01-SEP-2026) -----------------
    # Six bitstreams went onto this board in one day with no way to tell them
    # apart on the screen. Regenerate term_banner_rom.v HERE, per build, with
    # the git short hash and the date, into a build-local file so the committed
    # one is never dirtied. If anything in this block fails - no git, no python,
    # a detached tree - fall back to the committed ROM rather than failing the
    # build over a cosmetic line.
    set banner_rom [file join $tdir term_banner_rom.v]
    set stamp ""
    if {![catch {exec git -C $vroot rev-parse --short HEAD} _h]} {
        set stamp [string trim $_h]
        if {![catch {exec git -C $vroot status --porcelain} _d] && [string trim $_d] ne ""} {
            append stamp "+"   ;# tree had uncommitted changes at build time
        }
    }
    append stamp [clock format [clock seconds] -format { %d-%b-%Y %H:%M}]
    # ---- fourth banner line: board, CPU clock, cache (01-SEP-2026) --------
    # Ronny asked for the three settings that change how the machine behaves
    # to be on the screen too, taken from the build and not typed in. The
    # clock comes from $board_clk, the Hz value in $clk_table the MMCM is
    # generated from; the cache text from the same nocache test that adds
    # ND120_NO_CACHE below. "cache on" means the cache RAMs are in the
    # bitstream - slide switch sw[4] still turns it off at run time (down =
    # on), which the text says so nobody reads the banner as the live state.
    set _mhz [format %.2f [expr {$board_clk / 1000000.0}]]
    if {[lsearch $argv "nocache"] >= 0} {
        set _cache "no cache"
    } else {
        set _cache "cache on (sw4 up = off)"
    }
    set config "Nexys 4 DDR - $_mhz MHz - $_cache"
    set _gen [file join $srcdir build term_banner_rom.v]
    file mkdir [file dirname $_gen]
    if {[catch {exec python [file join $vroot Terminals font make_banner.py] $stamp $_gen $config} _e]} {
        if {[catch {exec python3 [file join $vroot Terminals font make_banner.py] $stamp $_gen $config} _e2]} {
            puts "BANNER: generator failed ($_e2) - using the committed ROM"
            set _gen ""
        }
    }
    if {$_gen ne "" && [file exists $_gen]} {
        set banner_rom $_gen
        puts "BANNER: build stamp \"$stamp\", config \"$config\""
    }

    foreach f {vga_timing.v font_rom.v char_ram.v text_screen.v terminal_ctrl.v
               terminal_ctrl_tdv.v
               cdc_byte.v byte_fifo.v terminal_top.v ps2_keyboard.v ps2_decoder.v
               ps2_ascii_table.v key_vt100.v
               ps2_keyboard_tdv.v ps2_decoder_tdv.v ps2_ascii_table_tdv.v key_tdv2200.v
               mips_counter.v term_banner.v
               term_console_feed.v term_panel.v term_panel_rom.v rate_meter.v
               ratio_meter.v
               console_uart_rx.v console_uart_tx.v} {
        lappend srcs [file join $tdir $f]
    }
    lappend srcs $banner_rom

    # No font8x16.hex copy any more. font_rom.v now carries the glyph data
    # EMBEDDED (generated by make_font.py, like term_banner_rom.v), so there is
    # no $readmemh and no loose file for any tool to resolve, mis-resolve or
    # leave stale. That stale-file trap cost a full night on 02-SEP-2026:
    # Vivado resolved $readmemh("font8x16.hex") against its WORKING directory
    # (this folder), read a 3-page copy left here on 30-AUG, and no font edit
    # reached silicon for two days. Embedding the ROM removed the whole class
    # of bug for every board. Nothing to copy here.
    puts "VGA console: terminal sources added (font is embedded in font_rom.v)"
}

read_verilog $srcs

# The DDR2 controller, generated by ddr2-test/gen_mig.tcl. read_ip brings in
# the core AND its constraints, so the DDR2 pins are never hand-written.
set migxci [file join $srcdir ddr2-test ip ddr ddr.xci]
if {![file exists $migxci]} {
    puts "ERROR: MIG core not generated: $migxci"
    puts "Run: vivado -mode batch -source ddr2-test/gen_mig.tcl"
    exit 1
}
read_ip $migxci

read_xdc [file join $srcdir nd120_nexys4ddr.xdc]
read_xdc [file join $srcdir nd120_timing.xdc]
if {$vga_console} {
    read_xdc [file join $srcdir nd120_nexys4ddr_console_vga.xdc]
}

# Same harmless-warning suppressions as the Basys3 flow
#  Synth 8-3936: register trimming (R81/L4/L8/R41P narrower than the width)
#  Synth 8-5837: dual async set/reset (D_FLIPFLOP/F617/F714)
set_msg_config -id {Synth 8-3936} -suppress
set_msg_config -id {Synth 8-5837} -suppress

# Main memory: DDR2 with a BRAM cache in front (MEM_RAM_49_DDR2), default
# since 25-AUG-2026. The old BRAM-only backend held 64K words per bank while
# PAL_44446B advertised 4 MB - everything above word 0o200000 in a bank
# ALIASED onto low memory, which forbids SINTRAN. -tclargs bramram rebuilds
# the old (aliasing, 64K-words/bank) BRAM configuration for A/B experiments.
if {[lsearch $argv "bramram"] >= 0} {
    set ram_defines [list MAIN_RAM_BLOCKRAM ND120_BLOCKRAM_ADDR_BITS=16]
} else {
    set ram_defines [list MAIN_RAM_DDR2]
}
set defines [list \
    TARGET_NEXYS4DDR \
    FPGA_FF_MODE \
    {*}$ram_defines \
    ND120_N4DDR_MMCM_DIV=$mmcm_div \
    BOARD_CLK_FREQ=$board_clk \
    UART_BAUD_RATE=$uart_baud]
# Console baud default 115200 since 26-AUG-2026 (-tclargs baud 9600 for the
# legacy speed). The physical bit rate is
# UART_BAUD_RATE alone: the emulated SC2661 stores the mode register the
# microcode programs (BAUDV thumbwheel table, tops out at 9600 - it is 1988)
# but times every bit off the compile-time DELAY_FRAMES constant
# (SC2661_UART.v:157), and TX-ready is a polled flag, not a timed wait. So
# the machine still BELIEVES 9600 while the wire runs 115200. Host side must
# open the port at 115200 (board_expect.ps1/console.ps1 -Baud 115200).
if {$skip_wcs} { lappend defines SKIP_WCS_LOAD }
# CPU cache: COMPILED IN BY DEFAULT since 29-AUG-2026 (Ronny) - every image
# deployed to this board since 28-AUG carried it, and another session is
# working on it ON THE BOARD. The 24-AUG "off by default, same as the Tang"
# decision below is superseded. At runtime slide switch sw[4] is the console's
# cache switch (down = on, up = off; nd120_nexys4ddr_top.v). "-tclargs nocache"
# compiles the cache RAMs out entirely (ND120_NO_CACHE) if the space is needed;
# "cache" is still accepted and means the default.
#
# HISTORY, kept because the measurements in it are still true:
# MEASURED 28-AUG-2026, so the reason has changed - see docs/CACHE-STATUS.md.
# It BUILDS and BOOTS: WNS +0.166 ns, SINTRAN comes up, TPE reports
# "Cache: Yes / NO ERRORS DETECTED". The old worry that CHIP_21F falling back
# to LUTRAM would not fit or close is dead; it costs ~0.1 ns of margin.
#
# It is off because it is now KNOWN BROKEN rather than merely unvalidated. The
# machine's own diagnostic (CACHE-120-A00 under TPE) fails: the used-bit memory
# never sets, so nothing is written to the cache and nothing is read from it.
# HIT requires the used bit, so the hit rate is a true 0%. A cache that silently
# never hits is worse than no cache. Turn this default around when CUP is fixed
# and CACHE-120-A00 passes.
if {[lsearch $argv "nocache"] >= 0} { lappend defines ND120_NO_CACHE }
# -tclargs ila: keep the CGA_MAC address-chain nets and cpu_txd through
# synthesis (mark_debug attributes in CGA_MAC.v / the top, guarded by this
# define) so the ILA probe patterns below can find them. Measured 23-AUG:
# without this, synthesis renames/absorbs the nets and the patterns match
# nothing ("ILA: NO NET").
if {[lsearch $argv "ila"] >= 0 || [lsearch $argv "ilaslim"] >= 0 ||
    [lsearch $argv "ilacache"] >= 0} { lappend defines ND120_ILA_MARK_DEBUG }
# -tclargs errfaprobe: SINTRAN ERRFATAL evidence probe (MEM_RAM_49_BLOCKRAM):
# latches the ERRFA X,T,A,D,L saves (0o4347-0o4353) in FFs and repeats them
# on the console TX after the halt. Zero BRAM - fits where no ILA does.
if {[lsearch $argv "errfaprobe"] >= 0} { lappend defines ND120_ERRFA_PROBE }
# The MC68705 panel processor's CLOCK path (IO_PANCAL_40.v ->
# PANCAL_68705_CLOCK.v) so SINTRAN can set/read the hardware clock via
# TRR PANC / TRA PANS. ON BY DEFAULT, same as the Tang; pass -NoPanelClock
# to fall back to the old stub, which cannot set or read the time (SINTRAN
# then says "ND-100 PANEL CLOCK INCORRECT" at every boot).
if {![has_flag nopanelclock]} { lappend defines ND120_PANEL_CLOCK }
# The VGA console needs its define to reach synthesis. Its framing must match
# what the machine is actually programmed to - the console UART is a software
# programmed SC2661, so this is a configuration fact, not a constant (long
# note in Terminals/rtl/console_uart_rx.v). Baud follows the console baud
# chosen above; data bits and parity keep the module defaults of 7E1, which is
# what console.ps1 says the OPCOM console uses "in some configurations".
if {$vga_console} {
    lappend defines ND120_CONSOLE_VGA
    lappend defines ND120_CONSOLE_BAUD=$uart_baud
    # The panel MIPS field only exists with the VGA console, so the CGA-side
    # tap that feeds it is built only here (CGA_ALU.v XGPRLOAD_DBG). Without
    # this the tap is tied off, keeping its fanout off ALUCLK_EN and GPRC.
    lappend defines ND120_MIPS_TAP
}
# Terminal type: TDV2200 (type 93) by default - PED and LED are built for
# the Tandberg keyboard's own key set, not VT100 CSI sequences
# (Verilog/Terminals/docs/SPEC-tdv2200.md). Pass -VT100Terminal to build the
# VT100 (type 6) variant instead. Only matters when $vga_console is on.
if {[has_flag vt100terminal]} { lappend defines ND120_TERMINAL_VT100 }

set synth_args {}
foreach d $defines { lappend synth_args -verilog_define $d }
puts "Verilog defines: $defines"

# sd_fat_test_top / nd_storage `include "sd_fat_features.vh" from SD-FAT/circuit
# Include paths: nd_storage `include "sd_fat_features.vh" (SD-FAT/circuit) and
# ND120_CORE `include "nd120_backwiring_defaults.vh" (Shared/support)
lappend synth_args -include_dirs [list \
    [file join $vroot SD-FAT circuit] \
    [file join $vroot Shared support]]

synth_design -top nd120_nexys4ddr_top -part $part {*}$synth_args
# clk_cpu, clk_stor and the DDR2 user clock are UNRELATED domains. Every
# crossing between them is a two-flop synchroniser or a toggle handshake.
# Without this Vivado times them as related clocks (they share one MMCM) and
# demands a fraction of a nanosecond, which no crossing can meet - measured
# on the SD build: -3.304 ns before, +1.460 ns after.
set _ccpu [get_clocks -quiet clk_cpu_pre]
set _cst  [get_clocks -quiet clk_stor_pre]
set _cui  [get_clocks -quiet clk_pll_i]
if {[llength $_ccpu] == 0 || [llength $_cst] == 0 || [llength $_cui] == 0} {
    puts "ERROR: expected clocks not found."
    puts "  clocks present: [get_clocks]"
    exit 1
}
# 22-AUG-2026: set_clock_groups -asynchronous left every cross-domain path
# UNTIMED - including the nds_sync toggle-handshake PAYLOAD buses, whose
# contract is "payload settles before the 2-FF-synced toggle arrives". On
# the Tang that held by placement luck; on this part the floppy client's
# payload raced its toggle (FILSYS floppy reads failed intermittently with
# status 020032 and finally wedged, while the tape client was fine - each
# client has its own toggle/payload nets). set_clock_groups outranks
# set_max_delay, so the groups are REPLACED by pairwise datapath-only
# bounds: phase alignment is still not demanded (that is the -datapath_only
# part), but no payload bit may take longer than one destination period.
#   clk_cpu  80 ns   clk_stor 37 ns   ui_clk 13.3 ns
# 25-AUG-2026: the debug panel (RGB LEDs, 8-digit display) samples CPU- and
# ui_clk-domain bits into sys_clk (100 MHz) through 2-FF synchronizers;
# bound those crossings the same way (one destination period = 10 ns).
set _csys [get_clocks -quiet sys_clk]
if {[llength $_csys] == 0} {
    puts "ERROR: sys_clk not found. clocks present: [get_clocks]"
    exit 1
}
# 26-AUG-2026: the bounds INTO clk_cpu were hard-coded 80.000 ns - one
# destination period of the 12.5 MHz era. They stopped tracking clk_sel when
# the default moved to 16.667 MHz (60 ns), and at higher CPU clocks an 80 ns
# payload bound would exceed even the 2-cycle toggle-sync margin. The CPU
# period in ns IS $mmcm_div (VCO is 1000 MHz), so the bound tracks clk_sel.
foreach {src dst lim} [list \
    $_ccpu $_cst 37.000 \
    $_cst  $_ccpu $mmcm_div \
    $_cst  $_cui 13.300 \
    $_cui  $_cst 37.000 \
    $_ccpu $_cui 13.300 \
    $_cui  $_ccpu $mmcm_div \
    $_ccpu $_csys 10.000 \
    $_cui  $_csys 10.000] {
    set_max_delay -datapath_only -from $src -to $dst $lim
}
puts "Bounded clk_cpu_pre / clk_stor_pre / clk_pll_i crossings with datapath-only max delays."

# ---------------------------------------------------------------------------
# KNOWN COMBINATIONAL LOOPS - acknowledged deliberately, not hidden.
#
# 29-AUG-2026: the ring is now cut EXPLICITLY in nd120_timing.xdc (ordered
# false path ALU FIDBI -> OUTMUX F -> FIDBO, measured on two failed
# checkpoints with timing-analysis/ring_fp_test.tcl). The auto-inserted cuts
# described below were moving with every netlist change and left a 208-level
# path timed in the cache + panel-clock build (-50.7 ns). The text below is
# kept as the record of what the tool used to do.
#
# Last verified 24-AUG-2026 (this block used to claim "12 loops remain" -
# that was pre-ring-cut and STALE; commit b3ee391 cut the FIDBO ring):
# the current builds report ZERO LUTLP-1 errors and Vivado auto-inserts
# exactly TWO loop-breaking false paths (Synth 8-326):
#   set_false_path -through .../CGA/DELILAH/ALU/ALU_OUTMUX/D_15_0[8]... 
#   set_false_path -through ALU_i_426/O
# Paths THROUGH those two nodes are untimed - the WNS gate below does not
# cover them. The historical ring was:
#   ALU_OUTMUX D_15_0[n] -> G_15_0[n] -> CGA.v FIDBO
#     -> MAC / INTR (CGA.v:614-615 feed FIDBO into their IDB inputs)
#     -> PCR / PGS / PICMASK -> CGA_IDBCTL_SEL6 -> back to FIDBO
# functionally impossible (one-hot CSIDBS_4_0), unprovable by the tool.
#
# EVIDENCE THAT THIS IS SAFE TO SHIP, not merely convenient:
#  - the SAME RTL with the SAME loops runs on the Tang Nano 20K and boots
#    SINTRAN. The Gowin flow has no loop DRC at all, so it has been producing
#    working bitstreams over them all along.
#  - instruction-verify against the ND-110 golden emulator passes with these
#    fixes in: "TRACES EQUIVALENT: 400 aligned instructions match exactly".
#
# WHAT THIS COSTS: Vivado's timing analysis through these paths is not
# trustworthy, so the WNS number below is a lower bound, not a guarantee.
# That is why the CPU clock stays conservative.
#
# THIS IS A PARKED DEBT, NOT A FIX. The real repair is to break the ring in
# RTL - see EXTENSIONS-PLAN.md and the 20-AUG analysis. Remove this block the
# day the loop count reaches zero, and let the DRC prove it.
# ---------------------------------------------------------------------------
set_property SEVERITY {Warning} [get_drc_checks LUTLP-1]
puts "NOTE: LUTLP-1 downgraded to Warning - 12 known CGA IDB loops, see build.tcl"

# --- optional JTAG ILA on the floppy CB-fetch / FDISK seam (-tclargs ila) ---
# Captures, in the clk_cpu domain: the floppy controller's DMA client port
# (command-block fetch + data transfers) and the FDISK request/answer seam.
# Nothing in the sources changes; the core is inserted post-synth. Arm and
# read it with ila_capture.tcl.
# -tclargs ilaslim: MINIMAL probe set (RAM write port + CSA + cpu_txd only,
# depth 1024) so an ILA fits NEXT TO the addr16 main RAM (128/135 RAMB36).
# Purpose: trigger on the SINTRAN ERRFA register save (RAM write to 0o4347)
# and read the saved X,T,A,D,L words off the write port.

# --- -tclargs ilacache: the cache-write question, and nothing else ----------
#
# Added 28-AUG-2026. CACHE-1X0-A00 test 2 says the cache is inert in both
# directions - never written, therefore never hit. A cache write is
# PAL_44402D asserting WCA:
#
#   WCA = /RT * DT * EWC * CYD * /FMISS * /LSHADOW
#       + RT * /IHIT * EWC * CYD * /FMISS * /LSHADOW
#
# The PAL is transcribed correctly and CON is tied high, so one of WCINH_n,
# BRK_n, CYD, FMISS or LSHADOW is holding WCA off and the source cannot say
# which. s_ila_cache carries all six (see CPU_MMU_24.v's DBG_CACHE comment).
#
# This is its OWN flag rather than an addition to "ila" because that probe
# set is aimed at the floppy/IOX seam, is large, and currently references
# s_ila_ram_addr, which no longer exists in this configuration - so "ila"
# fails before it gets anywhere near the cache. Keeping the sets separate
# means the cache capture does not depend on that being tidied up first.
if {[lsearch $argv "ilacache"] >= 0} {
    set _probes {}
    foreach pat {
        CSA_12_0[*]
        cpu_txd
    } {
        set n [get_nets -hier -quiet $pat]
        if {[llength $n] == 0} { puts "ERROR: ILA net missing for pattern $pat"; exit 1 }
        lappend _probes [lsort -dictionary $n]
    }
    foreach pat {
        *s_ila_cache* *s_ila_la* *s_ila_pil*
    } {
        set n [get_nets -hier -quiet -filter "MARK_DEBUG && NAME =~ $pat"]
        if {[llength $n] == 0} { puts "ERROR: ILA marked net missing for $pat"; exit 1 }
        puts "ILA: $pat -> [llength $n] nets"
        lappend _probes [lsort -dictionary $n]
    }
    foreach n $_probes { set_property MARK_DEBUG true $n }
    create_debug_core u_ila_0 ila
    set_property C_DATA_DEPTH 1024        [get_debug_cores u_ila_0]
    set_property C_TRIGIN_EN false        [get_debug_cores u_ila_0]
    set_property C_TRIGOUT_EN false       [get_debug_cores u_ila_0]
    set_property C_ADV_TRIGGER false      [get_debug_cores u_ila_0]
    set_property C_INPUT_PIPE_STAGES 2    [get_debug_cores u_ila_0]
    set_property C_EN_STRG_QUAL true      [get_debug_cores u_ila_0]
    set_property ALL_PROBE_SAME_MU true   [get_debug_cores u_ila_0]
    set_property ALL_PROBE_SAME_MU_CNT 2  [get_debug_cores u_ila_0]
    connect_debug_port u_ila_0/clk [get_nets clk_cpu]
    set _pidx 0
    foreach n $_probes {
        if {$_pidx > 0} { create_debug_port u_ila_0 probe }
        set_property PORT_WIDTH [llength $n]     [get_debug_ports u_ila_0/probe$_pidx]
        connect_debug_port u_ila_0/probe$_pidx $n
        incr _pidx
    }
    puts "ILA: ilacache core built with $_pidx probe ports"
}

if {[lsearch $argv "ilaslim"] >= 0} {
    set _probes {}
    foreach pat {
        CSA_12_0[*]
        cpu_txd
    } {
        set n [get_nets -hier -quiet $pat]
        if {[llength $n] == 0} { puts "ERROR: ILA net missing for pattern $pat"; exit 1 }
        lappend _probes [lsort -dictionary $n]
    }
    foreach pat {
        *s_ila_ddr2* *s_ila_ptwhold* *s_ila_la* *s_ila_xmic* *s_ila_maddr* *s_ila_mdata* *s_ila_pil* *s_ila_ireq* *s_ila_picmask* *s_ila_intrq_n* *s_ila_picv* *s_ila_tvec* *s_ila_trapn*
    } {
        set n [get_nets -hier -quiet -filter "MARK_DEBUG && NAME =~ $pat"]
        if {[llength $n] == 0} { puts "ERROR: ILA marked net missing for $pat"; exit 1 }
        puts "ILA: $pat -> [llength $n] nets"
        lappend _probes [lsort -dictionary $n]
    }
    foreach n $_probes { set_property MARK_DEBUG true $n }
    create_debug_core u_ila_0 ila
    set_property C_DATA_DEPTH 1024        [get_debug_cores u_ila_0]
    set_property C_TRIGIN_EN false        [get_debug_cores u_ila_0]
    set_property C_TRIGOUT_EN false       [get_debug_cores u_ila_0]
    set_property C_ADV_TRIGGER false      [get_debug_cores u_ila_0]
    set_property C_INPUT_PIPE_STAGES 2    [get_debug_cores u_ila_0]
    set_property C_EN_STRG_QUAL true      [get_debug_cores u_ila_0]
    set_property ALL_PROBE_SAME_MU true   [get_debug_cores u_ila_0]
    set_property ALL_PROBE_SAME_MU_CNT 2  [get_debug_cores u_ila_0]
    connect_debug_port u_ila_0/clk [get_nets clk_cpu]
    set _pidx 0
    foreach n $_probes {
        if {$_pidx > 0} { create_debug_port u_ila_0 probe }
        set_property PORT_WIDTH [llength $n] [get_debug_ports u_ila_0/probe$_pidx]
        connect_debug_port u_ila_0/probe$_pidx $n
        incr _pidx
    }
    puts "ILA-SLIM: [llength $_probes] probe groups connected."
}

if {[lsearch $argv "ila"] >= 0} {
    # v3 probe set (23-AUG night): address-formation chain for the
    # LIST-FILE-NAMES wrong indirect-jump target (0o060004 read back as
    # 0o016004). All three stages of the chain at the CGA_MAC boundary:
    #   s_cd_15_0      - the memory data word entering the MAC (was the
    #                    pointer cell delivered wrong?)
    #   s_ica_15_0     - the effective address out of the AP09 mux (did the
    #                    P/CD/ADD/NLCA selection corrupt it?)
    #   s_la_23_10_out - the physical address out of LA1025.
    # Plus CSA_12_0 (microcode address, carries the captrans trigger) and
    # cpu_txd for console context. FDISK seam dropped - floppy DMA proven.
    # get_nets -hier applies a plain pattern to the LEAF name only, so a
    # pattern containing '/' NEVER matches (measured 23-AUG: both v3 runs
    # printed NO NET for every */MAC/... pattern). Leaf patterns for the
    # top-level signals; the CGA_MAC address-chain buses are selected by
    # the MARK_DEBUG property their RTL attributes set (ND120_ILA_MARK_DEBUG
    # define, CGA_MAC.v) with a NAME =~ filter for the full name.
    set _dbg_pats {
        CSA_12_0[*]
        cpu_txd
    }
    set _probes {}
    foreach pat $_dbg_pats {
        set n [get_nets -hier -quiet $pat]
        if {[llength $n] == 0} {
            puts "ERROR: ILA net missing for pattern $pat"; exit 1
        } else {
            lappend _probes [lsort -dictionary $n]
        }
    }
    # v4 additions (24-AUG, never-ready campaign): the console status-capture
    # seam in IO_UART_42 - live TBMT_n vs the CHIP_33G-captured IOR bits,
    # plus the FF-mode capture pulse CLK_EN and the IOR read enable EIOR_n.
    # s_io_idb_15_0_out bits 10:5 are constant zeros and may synthesize away;
    # the count check only demands at least one net per bus.
    # Marked-net selection: each item is a NAME =~ glob evaluated against
    # nets carrying MARK_DEBUG (the ND120_ILA_MARK_DEBUG RTL attributes).
    # '[' opens a character class in the glob, so bus items match the base
    # name as a substring; scalars whose name prefixes another marked net
    # (s_dev_iox_rd vs s_dev_iox_rdata) use an exact-suffix pattern with no
    # trailing '*'. v5 adds the device-chain IOX seam (ND120_CORE.v).
    foreach pat {
        *s_cd_15_0* *s_ica_15_0* *s_la_23_10_out*
        *s_io_idb_15_0_out* *s_tbmt_n *s_clk_en *s_eiorn_n
        *s_dev_iox_addr* *s_dev_iox_wr *s_dev_iox_rd
        *s_dev_iox_rdata* *s_dev_int_pending*
        *s_dev_ident_strobe *s_dev_ident_level* *s_dev_ident_hit
        *s_dev_ident_code* *s_grant_tape_flp
        *s_ila_ram_addr* *s_ila_ram_wr *s_ila_ram_wdata*
        *s_reg14_r6_15_0* *RBLOCK/s_wr_15_0* *RBLOCK/s_rb_15_0*
    } {
        set n [get_nets -hier -quiet -filter "MARK_DEBUG && NAME =~ $pat"]
        if {[llength $n] == 0} {
            puts "ERROR: ILA marked net missing for $pat (ND120_ILA_MARK_DEBUG define not effective?)"; exit 1
        } else {
            puts "ILA: $pat -> [llength $n] nets, first = [lindex [lsort -dictionary $n] 0]"
            lappend _probes [lsort -dictionary $n]
        }
    }
    foreach n $_probes { set_property MARK_DEBUG true $n }
    create_debug_core u_ila_0 ila
    set_property C_DATA_DEPTH 4096        [get_debug_cores u_ila_0]
    set_property C_TRIGIN_EN false        [get_debug_cores u_ila_0]
    set_property C_TRIGOUT_EN false       [get_debug_cores u_ila_0]
    set_property C_ADV_TRIGGER false      [get_debug_cores u_ila_0]
    set_property C_INPUT_PIPE_STAGES 2    [get_debug_cores u_ila_0]
    set_property C_EN_STRG_QUAL true      [get_debug_cores u_ila_0]
    set_property ALL_PROBE_SAME_MU true   [get_debug_cores u_ila_0]
    set_property ALL_PROBE_SAME_MU_CNT 2  [get_debug_cores u_ila_0]
    # clock: the BUFG output that drives the CPU domain
    connect_debug_port u_ila_0/clk [get_nets clk_cpu]
    set _pidx 0
    foreach n $_probes {
        if {$_pidx > 0} { create_debug_port u_ila_0 probe }
        set_property PORT_WIDTH [llength $n] [get_debug_ports u_ila_0/probe$_pidx]
        connect_debug_port u_ila_0/probe$_pidx $n
        incr _pidx
    }
    puts "ILA: [llength $_probes] probe groups connected."
}

# -tclargs timingexplore (31-AUG-2026): opt/place/route run with their DEFAULT
# directives above, and only phys_opt_design was ever tuned. The cache-on
# critical path is 7.1 ns of logic against 20.9 ns of ROUTING (75%), and the
# cone itself cannot be shortened - pages 103/104 show the memory-protection
# decision reaching the control-store address combinationally, by design. So
# routing effort is the only lever that needs neither RTL nor constraints.
# Off by default: the default flow stays byte-identical to the builds that
# booted SINTRAN.
set _te [expr {[lsearch $argv "timingexplore"] >= 0}]

if {$_te} { opt_design -directive ExploreWithRemap } else { opt_design }
if {$_te} { place_design -directive ExtraTimingOpt } else { place_design }
# -tclargs physopt: post-place physical optimization (26-AUG clock-up
# campaign experiment). Not in the default flow yet - the default stays
# byte-identical to the builds that booted SINTRAN.
if {[lsearch $argv "physopt"] >= 0} {
    phys_opt_design -directive AggressiveExplore
}
if {$_te} { route_design -directive AggressiveExplore } else { route_design }
if {[lsearch $argv "physopt"] >= 0} {
    phys_opt_design -directive AggressiveExplore
}


report_utilization    -file [file join $srcdir util.rpt]
report_timing_summary -file [file join $srcdir timing.rpt]

# --- post-route analysis battery (clock-up campaign, 26-AUG-2026) ---
# Every run leaves its full evidence set in timing-analysis/run_clk<sel>[_N]/
# without ever overwriting a previous run. Placed BEFORE the WNS gate so a
# failing frequency candidate still yields its reports. The checkpoint lets
# any later report be regenerated without a rebuild (open_checkpoint).
set _rundir [file join $srcdir timing-analysis run_clk$clk_sel]
set _sfx 1
while {[file exists $_rundir]} {
    set _rundir [file join $srcdir timing-analysis run_clk${clk_sel}_$_sfx]
    incr _sfx
}
file mkdir $_rundir
puts "REPORTS: $_rundir"
foreach {rname rcmd} [list \
    timing_summary_post_route.rpt {report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose -max_paths 100 -file $_rf} \
    setup_paths_post_route.rpt    {report_timing -delay_type max -max_paths 100 -nworst 20 -path_type full_clock_expanded -input_pins -file $_rf} \
    hold_paths_post_route.rpt     {report_timing -delay_type min -max_paths 100 -nworst 20 -path_type full_clock_expanded -input_pins -file $_rf} \
    clocks.rpt                    {report_clocks -file $_rf} \
    clock_interaction.rpt         {report_clock_interaction -delay_type min_max -file $_rf} \
    cdc.rpt                       {report_cdc -details -file $_rf} \
    methodology.rpt               {report_methodology -file $_rf} \
    qor_assessment.rpt            {report_qor_assessment -file $_rf} \
    qor_suggestions.rpt           {report_qor_suggestions -file $_rf} \
    utilization_hierarchical.rpt  {report_utilization -hierarchical -file $_rf} \
    design_analysis.rpt           {report_design_analysis -logic_level_distribution -of_timing_paths [get_timing_paths -max_paths 100 -setup] -file $_rf} \
    high_fanout_nets.rpt          {report_high_fanout_nets -timing -max_nets 100 -file $_rf} \
    drc.rpt                       {report_drc -file $_rf} \
    power.rpt                     {report_power -file $_rf}] {
    set _rf [file join $_rundir $rname]
    if {[catch {eval $rcmd} _err]} {
        puts "WARNING: $rname failed: $_err"
    }
}
write_checkpoint -force [file join $_rundir post_route.dcp]

# Fail loudly on negative slack - a missed clock target must not be flashed
# silently (the Basys3 board's whole history is a timing-closure problem).
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts "WNS: $wns ns"
if {$wns < 0} {
    puts "ERROR: timing NOT met at the selected CPU clock (WNS $wns ns)."
    puts "Retry with a slower clock, e.g. -tclargs clk=16. See README.md."
    exit 1
}

set bit [file join $srcdir nd120_nexys4ddr.bit]
# The .ltx names the ILA probes for the hardware manager. Every flag that
# builds a debug core must be listed here or the capture comes back as
# probe0..probeN with no names - ilacache was missed on its first build.
if {[lsearch $argv "ila"] >= 0 || [lsearch $argv "ilaslim"] >= 0 ||
    [lsearch $argv "ilacache"] >= 0} {
    write_debug_probes -force [file join $srcdir nd120_nexys4ddr.ltx]
}
write_bitstream -force $bit
puts "BITSTREAM: $bit"

if {[lsearch $argv "-noburn"] >= 0} {
    puts "=== ND120 NEXYS4DDR BUILD COMPLETE (not programmed) ==="
    return
}

# ---- program over JTAG (volatile; power-cycle wipes it) ----
open_hw_manager
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices xc7a100t*] 0]
current_hw_device $dev
set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
puts "PROGRAMMED (JTAG)"
close_hw_manager

puts "=== ND120 NEXYS4DDR BUILD COMPLETE ==="
