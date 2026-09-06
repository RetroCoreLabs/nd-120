# ND-120 on Cmod A7-35T - self-contained in-memory Vivado flow
# (mem-test/sd-fat-test pattern: no .xpr project needed, unlike the Basys3
# main build which drives a GUI project on F:).
#
#   vivado -mode batch -source build.tcl                    # build + JTAG program
#   vivado -mode batch -source build.tcl -tclargs -noburn   # build only
#
# Configuration: BRAM main memory (MAIN_RAM_BLOCKRAM, Basys3-equivalent),
# FF mode, runtime WCS load from the PROM images, clk_cpu = 27 MHz
# (TARGET_CMOD_A7 MMCM branch in ND120_TOP.v - the Tang Nano 20K's full
# CPU speed). If 27 MHz does not close timing, add
#   -verilog_define ND120_CMOD_MMCM_DIV=56.0
# to synth_design below for 13.5 MHz (and change BOARD_CLK_FREQ to match!).

set part xc7a35tcpg236-1
set srcdir [file dirname [file normalize [info script]]]
set vroot  [file normalize [file join $srcdir .. ..]]   ;# Verilog/

# ---- microcode ------------------------------------------------------------
# WCS PRELOAD IS THE DEFAULT since 04-SEP-2026, matching the Tang, the Nexys
# and every board that closes timing. The microcode is loaded straight into
# the WCS from the 33 nibble images in Code/Microcode/wcs/ and the machine's
# runtime PROM-to-WCS load phase never runs, so CPU_CS_PROM_19 is never read
# and its ROM is not built at all.
#
# WHY IT CHANGED. The first run of this script (04-SEP-2026) placed and routed
# but MISSED TIMING BY 95.488 ns at 27 MHz - 5133 of 18465 endpoints failing,
# TNS -397,669 ns. The Inter Clock Table was EMPTY, so the clock groups were
# doing their job and every violation was real logic depth inside the CPU
# domain. The worst path ran 233 logic levels and 132.169 ns (71% of it
# routing) from the cycle-control FSM to `CPU/CS/PROM/regData_reg[14]` - the
# microcode PROM's own data register. A 132 ns path does not close at any
# clock this board would run: it needs a period longer than 132 ns, under
# 7.6 MHz, so the README's "fall back to 13.5 MHz" would not have saved it
# either. This build was the only one left still carrying the runtime PROM
# load. -promload keeps the old behaviour for anyone who wants to measure it.
set skip_wcs [expr {[lsearch $argv "-promload"] < 0}]
if {$skip_wcs} {
    # $readmemh("wcs_*.hex") resolves against Vivado's working directory in
    # this in-memory flow, so the images are copied next to this script.
    set wcs_src   [file normalize [file join $vroot .. Code Microcode wcs]]
    set wcs_files [glob -nocomplain [file join $wcs_src wcs_*.hex]]
    if {[llength $wcs_files] != 33} {
        puts "ERROR: expected 33 WCS images in $wcs_src, found [llength $wcs_files]"
        exit 1
    }
    foreach f $wcs_files { file copy -force $f [file join $srcdir [file tail $f]] }
    cd $srcdir
    puts "WCS preload: [llength $wcs_files] images copied (SKIP_WCS_LOAD)."
} else {
    # Microcode PROM images: $readmemh("AM27256_4513xL.hex") in CPU_CS_PROM_19.v
    # resolves against Vivado's working directory - copy them next to us and cd.
    set uc [file join $vroot .. Code Microcode]
    foreach hex {AM27256_45132L.hex AM27256_45133L.hex} {
        if {![file exists [file join $uc $hex]]} {
            puts "ERROR: microcode image missing: [file join $uc $hex]"
            exit 1
        }
        file copy -force [file join $uc $hex] [file join $srcdir $hex]
    }
    cd $srcdir
    puts "-promload: microcode PROM images copied (2 files)."
}

create_project -in_memory -part $part

# One source of truth for the CPU file list: the Tang project file, minus
# the Tang-specific files, plus the ND120_TOP stack and this board's top.
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

lappend srcs \
    [file join $vroot ND120_TOP.v] \
    [file join $vroot CPU-BOARD-3202 circuit MEM_RAM_49_BLOCKRAM.v] \
    [file join $vroot Shared support SevenSegDebug.v] \
    [file join $srcdir nd120_cmod_top.v]

read_verilog $srcs

read_xdc [file join $srcdir nd120_cmod.xdc]
read_xdc [file join $srcdir nd120_timing.xdc]

# Same harmless-warning suppressions as the Basys3 flow
set_msg_config -id {Synth 8-3936} -suppress
set_msg_config -id {Synth 8-5837} -suppress

# Verilog include search path. The ND-BUS device controllers include
# "nd_storage_status.vh" (SD-FAT/circuit) and ND120_CORE includes
# "nd120_backwiring_defaults.vh" (Shared/support). Both headers were added to
# the tree AFTER this script was first written (13-JUL-2026), so without these
# two directories synthesis stops with "cannot open include file" followed by a
# cascade of undefined-macro errors in ND_FLOPPY_DMA.v. These are the same two
# paths the Nexys and MEGA65 builds pass (fpga/nexys4ddr/build.tcl:429).
synth_design -top nd120_cmod_top -part $part \
    -include_dirs [list [file join $vroot SD-FAT circuit] \
                        [file join $vroot Shared support]] \
    -verilog_define TARGET_CMOD_A7 \
    -verilog_define FPGA_FF_MODE \
    -verilog_define MAIN_RAM_BLOCKRAM \
    -verilog_define BOARD_CLK_FREQ=27000000 \
    -verilog_define UART_BAUD_RATE=115200 \
    {*}[expr {$skip_wcs ? [list -verilog_define SKIP_WCS_LOAD] : [list]}]
opt_design
place_design
route_design

report_utilization    -file [file join $srcdir util.rpt]
report_timing_summary -file [file join $srcdir timing.rpt]

# Save the routed checkpoint BEFORE the timing gate. A build that misses
# timing exits below, and without this there is nothing left to interrogate:
# the 04-SEP-2026 failure could only report its single worst path, so
# answering "do the other 5132 failing endpoints share a cause?" would have
# cost a second hour-long run. Open it with:
#   open_checkpoint nd120_cmod_routed.dcp
#   report_timing -max_paths 50 -slack_lesser_than 0 -file paths.rpt
write_checkpoint -force [file join $srcdir nd120_cmod_routed.dcp]

# Fail loudly on negative slack - a 27 MHz miss must not be flashed silently
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts "WNS: $wns ns"
if {$wns < 0} {
    puts "ERROR: timing NOT met at 27 MHz (WNS $wns ns)."
    puts "Fallback: -verilog_define ND120_CMOD_MMCM_DIV=56.0 (13.5 MHz)"
    puts "and BOARD_CLK_FREQ=13500000. See README.md."
    exit 1
}

set bit [file join $srcdir nd120_cmod.bit]
write_bitstream -force $bit
puts "BITSTREAM: $bit"

if {[lsearch $argv "-noburn"] >= 0} {
    puts "=== ND120 CMOD BUILD COMPLETE (not programmed) ==="
    return
}

# ---- program over JTAG (volatile; power-cycle wipes it) ----
open_hw_manager
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices xc7a35t*] 0]
current_hw_device $dev
set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
puts "PROGRAMMED (JTAG)"
close_hw_manager

puts "=== ND120 CMOD BUILD COMPLETE ==="
