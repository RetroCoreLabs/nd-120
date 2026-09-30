# Program nd120_nexys4ddr.bit over JTAG, nothing else. TCK kept at 5 MHz
# (same rule as ila_capture.tcl - faster TCK corrupts uploads).
set srcdir [file dirname [file normalize [info script]]]
# The bitstream, probes file and captures live in the build folder,
# $ND120_BUILD_DIR/nexys4ddr (local.mk at the repository root, written by
# configure.py) - never in this source folder.
source [file join $srcdir .. paths.tcl]
set outdir [nd120_board_dir nexys4ddr]
open_hw_manager
connect_hw_server
open_hw_target
set_property PARAM.FREQUENCY 5000000 [current_hw_target]
set dev [lindex [get_hw_devices xc7a100t*] 0]
current_hw_device $dev
set_property PROGRAM.FILE [file join $outdir nd120_nexys4ddr.bit] $dev
# no probes file for a plain build
set_property PROBES.FILE {} $dev
program_hw_devices $dev
puts "PROGRAMMED (JTAG, plain)"
close_hw_manager
