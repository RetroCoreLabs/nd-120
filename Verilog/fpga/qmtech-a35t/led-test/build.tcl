# Minimal in-memory Vivado flow for the QMTECH XC7A35T LED smoke test.
# Synthesise, implement, generate + JTAG-program the bitstream (volatile).
#   vivado -mode batch -source build.tcl
# JTAG transport: Xilinx Platform Cable USB II on the board's 6-pin header
# (board powered separately via Mini USB).

set part xc7a35tcsg325-1
set srcdir [file dirname [file normalize [info script]]]
# Outputs go to $ND120_BUILD_DIR/qmtech-a35t/led-test (local.mk at the
# repository root, written by configure.py), and Vivado works there.
source [file join $srcdir .. .. paths.tcl]
set outdir [nd120_board_dir qmtech-a35t/led-test]
cd $outdir

create_project -in_memory -part $part

read_verilog [file join $srcdir led_test_top.v]
read_xdc [file join $srcdir led_test.xdc]

synth_design -top led_test_top -part $part
opt_design
place_design
route_design

report_utilization      -file [file join $outdir util.rpt]
report_timing_summary   -file [file join $outdir timing.rpt]

set bit [file join $outdir led_test.bit]
write_bitstream -force $bit
puts "BITSTREAM: $bit"

# ---- program over JTAG (volatile; power-cycle wipes it) ----
# Pass "-tclargs skip_program" to build the bitstream without a board attached.
if {[lsearch $argv "skip_program"] < 0} {
    open_hw_manager
    connect_hw_server
    open_hw_target
    set dev [lindex [get_hw_devices xc7a35t*] 0]
    current_hw_device $dev
    set_property PROGRAM.FILE $bit $dev
    program_hw_devices $dev
    puts "PROGRAMMED (JTAG)"
    close_hw_manager
} else {
    puts "skip_program: bitstream built, not programmed"
}

puts "=== LED-TEST BUILD COMPLETE ==="
