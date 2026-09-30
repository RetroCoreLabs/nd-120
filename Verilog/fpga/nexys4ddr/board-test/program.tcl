# Program the existing board_test.bit over JTAG (volatile). No rebuild.
#   vivado -mode batch -source program.tcl
set srcdir [file dirname [file normalize [info script]]]
# The bitstream, probes file and captures live in the build folder,
# $ND120_BUILD_DIR/nexys4ddr/board-test (local.mk at the repository root, written by
# configure.py) - never in this source folder.
source [file join $srcdir .. .. paths.tcl]
set outdir [nd120_board_dir nexys4ddr/board-test]
set bit [file join $outdir board_test.bit]
if {![file exists $bit]} { puts "ERROR: $bit not found - build first"; exit 1 }
open_hw_manager
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices xc7a100t*] 0]
current_hw_device $dev
set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
puts "PROGRAMMED: $bit"
close_hw_manager
