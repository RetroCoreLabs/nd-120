# Minimal in-memory Vivado flow for the QMTECH XC7A35T standalone memory test.
# Synthesise, implement, generate + JTAG-program the bitstream (volatile).
#   vivado -mode batch -source build.tcl
# Reuses the Basys3 mem-test's msg_printer/uart_tx (TX is internal/ILA-only
# here - the board has no UART) and the shared MEM_RAM_49/SIP1M9 sources.

set part xc7a35tcsg325-1
set srcdir [file dirname [file normalize [info script]]]
# Outputs go to $ND120_BUILD_DIR/qmtech-a35t/mem-test (local.mk at the
# repository root, written by configure.py), and Vivado works there.
source [file join $srcdir .. .. paths.tcl]
set outdir [nd120_board_dir qmtech-a35t/mem-test]
cd $outdir
set b3dir  [file join $srcdir .. .. basys3 mem-test]

create_project -in_memory -part $part

# msg_printer.v uses $bits -> needs SystemVerilog dialect
read_verilog -sv [file join $b3dir msg_printer.v]
read_verilog [list \
    [file join $srcdir qmtech_mem_test_top.v] \
    [file join $b3dir uart_tx.v] \
    [file join $srcdir .. .. .. CPU-BOARD-3202 circuit MEM_RAM_49.v] \
    [file join $srcdir .. .. .. Shared support SIP1M9.v] ]

read_xdc [file join $srcdir mem_test.xdc]

synth_design -top qmtech_mem_test_top -part $part
opt_design
place_design
route_design

report_utilization      -file [file join $outdir util.rpt]
report_timing_summary   -file [file join $outdir timing.rpt]

set bit [file join $outdir qmtech_mem_test.bit]
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

puts "=== MEM-TEST BUILD COMPLETE ==="
