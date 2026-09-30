# Nexys 4 DDR board check - self-contained in-memory Vivado flow
#
#   vivado -mode batch -source build.tcl                     # build + JTAG program
#   vivado -mode batch -source build.tcl -tclargs -noburn    # build only
#
# Everything it writes goes to $ND120_BUILD_DIR/nexys4ddr/board-test (local.mk
# at the repository root, written by configure.py).
#
# Nothing from the ND-120 design is compiled here - only this test top and the
# two UART modules it reuses. If this build fails, the problem is the board or
# the toolchain, not the CPU.

set part xc7a100tcsg324-1
set srcdir [file dirname [file normalize [info script]]]
set vroot  [file normalize [file join $srcdir .. .. ..]]   ;# Verilog/
source [file join $srcdir .. .. paths.tcl]
set outdir [nd120_board_dir nexys4ddr/board-test]
cd $outdir

create_project -in_memory -part $part

read_verilog [list \
    [file join $srcdir board_test_top.v] \
    [file join $vroot fpga tang-nano-20k sd-fat-test src uart_tx.v] \
    [file join $vroot fpga tang-nano-20k sd-fat-test src uart_rx.v]]

read_xdc [file join $srcdir board_test.xdc]

synth_design -top board_test_top -part $part
opt_design
place_design
route_design

report_utilization    -file [file join $outdir util.rpt]
report_timing_summary -file [file join $outdir timing.rpt]

set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts "WNS: $wns ns"
if {$wns < 0} {
    puts "ERROR: timing NOT met (WNS $wns ns). A trivial design missing timing"
    puts "means something is wrong with the constraints or the tool setup."
    exit 1
}

set bit [file join $outdir board_test.bit]
write_bitstream -force $bit
puts "BITSTREAM: $bit"

if {[lsearch $argv "-noburn"] >= 0} {
    puts "=== BOARD CHECK BUILD COMPLETE (not programmed) ==="
    return
}

open_hw_manager
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices xc7a100t*] 0]
current_hw_device $dev
set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
puts "PROGRAMMED (JTAG)"
close_hw_manager

puts "=== BOARD CHECK COMPLETE ==="
