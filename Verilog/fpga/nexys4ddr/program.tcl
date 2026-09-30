# ---------------------------------------------------------------------------
# Program an ALREADY-BUILT bitstream onto the Nexys 4 DDR over JTAG.
#
#   vivado -mode batch -source program.tcl
#   vivado -mode batch -source program.tcl -tclargs <path-to-.bit>
#
# WHY THIS EXISTS SEPARATELY from build.tcl. build.tcl programs the board at the
# end unless given -noburn, which means "just flash what I already built" would
# otherwise cost a full re-synthesis - about ten minutes to repeat work that is
# already sitting on disk. This does only the programming, in seconds.
#
# VOLATILE. This writes the FPGA's configuration RAM over JTAG; it does not
# touch the QSPI flash. A power cycle restores whatever was flashed before, so
# the worst case of a bad bitstream is "power the board off and on again".
#
# The board must be visible to Windows, not attached to WSL - usbipd hands the
# FTDI device to one or the other, and Vivado cannot see it while WSL holds it.
# Run ./usb-attach.sh --detach first if the console has been in use from Linux.
# ---------------------------------------------------------------------------

# The bitstream lives in the build folder, $ND120_BUILD_DIR/nexys4ddr (local.mk
# at the repository root, written by configure.py).
# A bitstream named on the command line (a downloaded release, say) needs no
# local settings at all; only the default needs the build folder.
source [file join [file dirname [file normalize [info script]]] .. paths.tcl]
if {[llength $argv] > 0} {
    set bit [lindex $argv 0]
} else {
    set bit [file join [nd120_board_dir nexys4ddr "program.tcl"] nd120_nexys4ddr.bit]
}

if {![file exists $bit]} {
    puts "ERROR: no bitstream at $bit"
    puts "       build one first: make build   (or: vivado -mode batch -source build.tcl -tclargs -noburn)"
    exit 1
}

puts "BITSTREAM: $bit"
puts "MODIFIED:  [clock format [file mtime $bit] -format {%Y-%m-%d %H:%M:%S}]"

open_hw_manager
connect_hw_server
open_hw_target

set dev [lindex [get_hw_devices xc7a100t*] 0]
if {$dev eq ""} {
    puts "ERROR: no xc7a100t found on the JTAG chain."
    puts "       Is the board powered, and is its USB attached to Windows rather than WSL?"
    close_hw_manager
    exit 1
}

current_hw_device $dev
set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
puts "PROGRAMMED (JTAG, volatile - a power cycle restores the flashed image)"
close_hw_manager
