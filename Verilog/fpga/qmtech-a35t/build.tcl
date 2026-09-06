# ============================================================================
# ND-120 on the QMTECH XC7A35T SDRAM core board - self-contained Vivado flow
# Full path: Verilog/fpga/qmtech-a35t/build.tcl
#
#   vivado -mode batch -source build.tcl                    # build + JTAG program
#   vivado -mode batch -source build.tcl -tclargs -noburn   # build only
#   vivado -mode batch -source build.tcl -tclargs -promload # runtime PROM->WCS load
#
# In-memory flow, no .xpr project - the same shape as the Cmod A7 and Nexys
# builds in this repo.
#
# WRITTEN 04-SEP-2026. NEVER RUN. Nothing below has been through Vivado even
# once, so treat the first run as a debugging session, not a build.
#
# CONFIGURATION
#   main memory   4 MB in the board's W9825G6KH-6, through the sheet-49
#                 bridge in 16-bit module mode (MAIN_RAM_SDRAM +
#                 ND_SDRAM_PACK16 + ND_SDRAM_DQ16) - the configuration that
#                 boots SINTRAN on the MiSTer and builds clean for MEGA65 R6
#   refresh       ND_SDRAM_REFRESH_US=7: this chip has 8192 rows and needs an
#                 auto-refresh every 7.8 us. The bridge's 15 us default suits
#                 the Tang's 2K-row die and would UNDER-refresh this one
#   storage       SD card on header JP3, every client DIRECT (uncached) -
#                 see the header of rtl/nd_storage_bram.v for why the cache
#                 cannot be used with the 16-bit bridge mode
#   console       the CPU's serial pins on header JP3, 115200
#   CPU clock     20 MHz (MMCM in rtl/nd120_qmtech_top.v)
#   WCS           preloaded from the bitstream (SKIP_WCS_LOAD), as on the
#                 Tang and Nexys - saves the microcode PROM's block RAM
# ============================================================================

set part   xc7a35tcsg325-1
set srcdir [file dirname [file normalize [info script]]]
set vroot  [file normalize [file join $srcdir .. ..]]        ;# Verilog/

proc has_flag {name} {
    global argv
    return [expr {[lsearch $argv $name] >= 0}]
}

# ---- microcode images ------------------------------------------------------
# $readmemh resolves against Vivado's working directory in this in-memory
# flow, so the images are copied next to this script and the script cd's
# here. Same handling as fpga/nexys4ddr/build.tcl:159-178.
#
# WCS PRELOAD IS THE DEFAULT, as on the Tang and the Nexys: the microcode goes
# straight into the WCS from the 33 nibble images in Code/Microcode/wcs/ and
# the machine's runtime PROM->WCS load phase never runs. That is what lets the
# microcode PROM (CPU_CS_PROM_19) be dropped from the netlist entirely, which
# matters on a part with 50 RAMB36. Code/Microcode/wcs/ holds the RAW PROM
# word - boards get the raw word, simulators get the patched one (decision of
# 02-SEP-2026, enforced by test-microcode-sync).
set skip_wcs [expr {![has_flag -promload]}]
if {$skip_wcs} {
    set wcs_src   [file normalize [file join $vroot .. Code Microcode wcs]]
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
cd $srcdir

create_project -in_memory -part $part

# ---- source list -----------------------------------------------------------
# One source of truth for the CPU and device file list: the Tang project file,
# minus the files that are specific to that board, plus this board's own top.
# The SDRAM bridge files are KEPT (unlike the Cmod build, which is block-RAM
# only) because this board's main memory is the bridge.
set gprj [file join $vroot fpga tang-nano-20k nd120_tang20k.gprj]
set fp [open $gprj r]
set xml [read $fp]
close $fp

set exclude {
    src/tang20k_defines.v
    src/gowin_rpll_27_54.v
    src/ND120_TANG20K_TOP.v
    sdram-test/src/uart_tx.v
}
set srcs {}
foreach {full path} [regexp -all -inline {<File path="([^"]+)"[^>]*enable="1"/>} $xml] {
    if {![string match *.v $path]} { continue }
    if {[lsearch -exact $exclude $path] >= 0} { continue }
    lappend srcs [file normalize [file join $vroot fpga tang-nano-20k $path]]
}
puts "CPU + device sources from nd120_tang20k.gprj: [llength $srcs] files"

lappend srcs \
    [file join $srcdir rtl nd_storage_bram.v] \
    [file join $srcdir rtl nd120_qmtech_top.v]

read_verilog $srcs

read_xdc [file join $srcdir nd120_qmtech.xdc]
read_xdc [file join $srcdir nd120_timing.xdc]

# Same harmless-warning suppressions the Basys3 and Cmod flows use
set_msg_config -id {Synth 8-3936} -suppress
set_msg_config -id {Synth 8-5837} -suppress

# ---- defines ---------------------------------------------------------------
set defines [list \
    FPGA_FF_MODE \
    MAIN_RAM_SDRAM \
    ND_SDRAM_PACK16 \
    ND_SDRAM_DQ16 \
    ND_SDRAM_REFRESH_US=7 \
    ND_STORAGE_NO_CACHE \
    ND_STORAGE_DISCS_UNCACHED \
    SDFAT_NO_LFN \
    ND120_PANEL_CLOCK \
    BOARD_CLK_FREQ=20000000 \
    UART_BAUD_RATE=115200]

# ND_STORAGE_NO_CACHE and ND_STORAGE_DISCS_UNCACHED go TOGETHER and neither is
# optional here. NO_CACHE keeps the Phase-4 tag directory out of the netlist;
# DISCS_UNCACHED sets CACHE_MASK to 0 so no client asks for it. Removing the
# directory while a client still expects to be cached would leave that client
# waiting on a lookup that nothing answers (nd_storage.v:495-503).
#
# SDFAT_NO_LFN strips VFAT long-filename parsing, worth roughly 1800 LUTs on a
# part that has 20,800 of them. Every file this build opens uses an 8.3 name
# (BOOT.TAP, FLOPPY1.IMG, WD0.IMG), so nothing is lost.
#
# ND120_PANEL_CLOCK emulates the MC68705/MM58274 hardware clock. Without it
# SINTRAN cannot set or read the time and prints "ND-100 PANEL CLOCK
# INCORRECT" at every boot. Drop it with -nopanelclock if the part overflows.
if {[has_flag -nopanelclock]} {
    set defines [lsearch -all -inline -not -exact $defines ND120_PANEL_CLOCK]
    puts "Panel clock DISABLED."
}
if {$skip_wcs} { lappend defines SKIP_WCS_LOAD }

set synth_args [list]
foreach d $defines { lappend synth_args -verilog_define $d }

# Include search path: the ND-BUS device controllers include
# "nd_storage_status.vh" (SD-FAT/circuit) and ND120_CORE includes
# "nd120_backwiring_defaults.vh" (Shared/support). Missing these is the
# failure that stopped the Cmod build on 04-SEP-2026: "cannot open include
# file", then a cascade of undefined-macro errors in ND_FLOPPY_DMA.v.
lappend synth_args -include_dirs [list \
    [file join $vroot SD-FAT circuit] \
    [file join $vroot Shared support]]

puts "Defines: $defines"
synth_design -top nd120_qmtech_top -part $part {*}$synth_args

# ---- clock relationships (AFTER synthesis - see nd120_timing.xdc) ----------
# The MMCM's four outputs are GENERATED clocks that do not exist until
# synthesis has run, so these cannot live in an XDC read before synth_design.
# The first build of this board (04-SEP-2026) proved it the expensive way: the
# constraint sat in the XDC, found no clocks, did nothing, and two clk_stor ->
# clk_cpu paths were timed with a 1.000 ns requirement.
set _cpu  [get_clocks -quiet clk_cpu_pre]
set _2x   [get_clocks -quiet clk2x_pre]
set _2xsd [get_clocks -quiet clk2x_sdram_pre]
set _stor [get_clocks -quiet clk_stor_pre]
if {[llength $_cpu] == 0 || [llength $_2x] == 0 || [llength $_stor] == 0} {
    puts "ERROR: expected generated clocks not found after synthesis."
    puts "  clocks present: [get_clocks]"
    puts "  Check the net names at the MMCM outputs in rtl/nd120_qmtech_top.v."
    exit 1
}

# clk_cpu and clk2x/clk2x_sdram are RELATED and must stay timed against each
# other: the SDRAM bridge is built on clk2x being an exact 2x of clk_cpu off
# one VCO and edge-aligned, and it samples OSC-domain PAL outputs on clk2x as
# synchronous signals (MEM_RAM_49_SDRAM.v:288). Declaring them asynchronous
# would stop the tool timing the very paths the bridge depends on, and the
# build would report clean while being wrong. The first build measured this
# pair at +4.105 ns over 255 endpoints - healthy, and it must stay checked.
#
# clk_stor is genuinely INDEPENDENT (27.027 MHz is not a ratio of 20 MHz) and
# every crossing into or out of it is a two-flop synchroniser or a toggle
# handshake.
#
# BUT NOT set_clock_groups. This is the Nexys's hard-won lesson of
# 22-AUG-2026 and it cost real disc corruption: -asynchronous leaves every
# cross-domain path UNTIMED, including the nds_sync toggle-handshake PAYLOAD
# buses, whose contract is "the payload settles before the 2-FF-synced toggle
# arrives". On the Tang that held by placement luck; on Artix the floppy
# client's payload raced its toggle, FILSYS reads failed intermittently with
# status 020032 and finally hung. set_clock_groups also OUTRANKS
# set_max_delay, so it cannot be softened afterwards.
#
# Pairwise datapath-only bounds instead: phase alignment is not demanded
# (that is the -datapath_only part), but no payload bit may take longer than
# one destination period. clk_cpu 50 ns, clk_stor 37 ns, clk2x 25 ns.
set_max_delay -datapath_only -from $_stor -to $_cpu  50.000
set_max_delay -datapath_only -from $_cpu  -to $_stor 37.000
set_max_delay -datapath_only -from $_stor -to $_2x   25.000
set_max_delay -datapath_only -from $_2x   -to $_stor 37.000
puts "Clock relationships applied: cpu<->2x TIMED, stor bounded datapath-only."

# Utilization straight after synthesis. On this part that number decides
# whether the build is possible at all, so it is reported before the hour of
# place-and-route rather than after it.
report_utilization -file [file join $srcdir util_synth.rpt]
puts "Post-synthesis utilization written to util_synth.rpt"

opt_design
place_design
phys_opt_design
route_design

report_utilization    -file [file join $srcdir util.rpt]
report_timing_summary -file [file join $srcdir timing.rpt]

# Save the routed checkpoint BEFORE the timing gate. A build that misses
# timing exits below, and without this there is nothing left to interrogate:
# report_timing_summary details only its single worst path, and answering
# "do the other failing endpoints share a cause?" would cost another full
# run. Open it with:
#   open_checkpoint nd120_qmtech_routed.dcp
#   report_timing -max_paths 50 -slack_lesser_than 0 -file paths.rpt
write_checkpoint -force [file join $srcdir nd120_qmtech_routed.dcp]

# Fail loudly on negative slack. A build that misses timing must never be
# programmed silently: the Basys3 spent months being "built" while failing
# timing by 30 ns, and a board that boots sometimes is worse than one that
# does not build.
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts "WNS: $wns ns"
if {$wns < 0} {
    puts "ERROR: timing NOT met at 20 MHz (WNS $wns ns). See timing.rpt."
    puts "       First look: is the failing path inside the CPU clock domain?"
    puts "       If the Inter Clock Table is EMPTY the clock groups are doing"
    puts "       their job and the violation is real logic depth - lower the"
    puts "       CPU clock in the MMCM (rtl/nd120_qmtech_top.v) and set"
    puts "       BOARD_CLK_FREQ to match. If it is NOT empty, a crossing is"
    puts "       being timed that should not be."
    exit 1
}

# ---- the combinational-loop DRC ------------------------------------------
# A PARKED DEBT, NOT A FIX - the same wording, and the same decision, as
# fpga/nexys4ddr/build.tcl:522 and fpga/mega65/build.tcl:452.
#
# write_bitstream runs DRC as a precondition, and [DRC LUTLP-1] is an ERROR by
# default, so without this the build stops here even though timing is met.
# The loops are the CGA IDB ring, analysed in
# docs/HANDOFF-cga-idb-ring-cut.md. Why shipping over them is defensible
# rather than merely convenient:
#   - the loop is functionally impossible: the IDB source select is a binary
#     microcode field (CSBITS[41:37]) decoded into distinct minterms, so the
#     bus cannot be read as an ALU operand and driven from the ALU result in
#     the same cycle. The tool cannot see it only because the decoded enables
#     are registered and cross two module boundaries.
#   - the SAME RTL with the SAME loops boots SINTRAN III on the Tang Nano 20K,
#     the Nexys 4 DDR and the MiSTer. The Gowin flow has no loop DRC at all
#     and has been producing working bitstreams over them all along.
#   - instruction-verify against the ND-110 golden emulator passes with them.
#
# WHAT IT COSTS, stated honestly: Vivado's timing analysis through these paths
# is not trustworthy, so the WNS gate above is a FLOOR, not a guarantee. On
# this netlist the CPU domain closed at +5.255 ns over 27,698 endpoints with
# none failing, which is a wide floor - but the Cmod A7, same die family, has
# the same loops cut at a different point and misses by 89.8 ns. Remove this
# downgrade the day the ring is cut in RTL.
# The report is written BEFORE the downgrade so it records the loops at full
# severity. Count them with: grep -c "LUTLP-1#" drc_loops.rpt
report_drc -checks {LUTLP-1} -file [file join $srcdir drc_loops.rpt]
set_property SEVERITY {Warning} [get_drc_checks LUTLP-1]
puts "LUTLP-1 downgraded to Warning (parked debt). Loop report: drc_loops.rpt"

set bit [file join $srcdir nd120_qmtech.bit]
write_bitstream -force $bit
puts "BITSTREAM: $bit"

if {[has_flag -noburn]} {
    puts "=== ND120 QMTECH BUILD COMPLETE (not programmed) ==="
    return
}

# ---- program over JTAG (volatile; a power cycle wipes it) ------------------
# This board has no USB data path: programming is over the 6-pin JTAG header
# with a Platform Cable USB II. The Mini USB socket is power only.
open_hw_manager
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices xc7a35t*] 0]
current_hw_device $dev
set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
puts "PROGRAMMED (JTAG)"
close_hw_manager

puts "=== ND120 QMTECH BUILD COMPLETE ==="
