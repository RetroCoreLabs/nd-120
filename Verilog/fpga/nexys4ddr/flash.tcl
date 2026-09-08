# ---------------------------------------------------------------------------
# Write an ALREADY-BUILT bitstream into the Nexys 4 DDR's QSPI config flash.
# PERMANENT: the image survives a power cycle - this is what "deploy" means.
#
#   vivado -mode batch -source flash.tcl
#   vivado -mode batch -source flash.tcl -tclargs <path-to-.bit>
#
# The volatile counterpart is program.tcl (JTAG into configuration RAM,
# seconds, gone at power-off). Use that while iterating; use this to leave an
# image on the board.
#
# FLASH PART: the Nexys 4 DDR carries a Spansion S25FL128S (128 Mbit, QSPI).
# The exact Vivado cfgmem part NAME varies between Vivado releases, so instead
# of hard-coding one this script asks the running Vivado for every cfgmem part
# matching s25fl128 and uses the first one - and prints what it picked, so a
# wrong pick is visible in the log rather than silent.
#
# INTERFACE = SPIx1. build.tcl writes an x1 bitstream (it does NOT set
# BITSTREAM.Config.SPI_buswidth 4), so the flash image must be SPIx1 to match -
# an SPIx4 write_cfgmem refuses an x1 bitstream ("SPI_BUSWIDTH ... set to 1 ...
# has to be 4", 08-SEP-2026). x1 is the board's universal master-SPI config
# mode: it always boots, with no SPI_Fall_Edge / ConfigRate tuning. The only
# cost is ~1-2 s more at power-on than x4 would be. To go faster, make build.tcl
# emit an x4 bitstream (SPI_buswidth 4 + SPI_Fall_Edge YES + a ConfigRate) AND
# switch the -interface below back to SPIx4 - the two must move together.
#
# After flashing, the FPGA is booted from the new image (boot_hw_device), so
# the board is running it immediately - no power cycle needed to check.
#
# The board must be attached to Windows, not WSL (usbipd) - same rule as
# program.tcl.
# ---------------------------------------------------------------------------

set srcdir [file dirname [file normalize [info script]]]
set bit [file join $srcdir nd120_nexys4ddr.bit]
if {[llength $argv] > 0} {
    set bit [lindex $argv 0]
}

if {![file exists $bit]} {
    puts "ERROR: no bitstream at $bit"
    puts "       build one first: make build   (or: vivado -mode batch -source build.tcl -tclargs -noburn)"
    exit 1
}

puts "BITSTREAM: $bit"
puts "MODIFIED:  [clock format [file mtime $bit] -format {%Y-%m-%d %H:%M:%S}]"

# --- 1. bitstream -> flash image (.mcs) ------------------------------------
set mcs [file rootname $bit].mcs
write_cfgmem -force -format mcs -size 16 -interface SPIx1 \
    -loadbit "up 0x0 $bit" -file $mcs
puts "FLASH IMAGE: $mcs"

# --- 2. find the board and the flash part ----------------------------------
open_hw_manager
connect_hw_server
open_hw_target
# Same 5 MHz TCK rule as program_only.tcl / ila_capture.tcl - faster TCK
# corrupts uploads on this board.
set_property PARAM.FREQUENCY 5000000 [current_hw_target]

set dev [lindex [get_hw_devices xc7a100t*] 0]
if {$dev eq ""} {
    puts "ERROR: no xc7a100t found on the JTAG chain."
    puts "       Is the board powered, and is its USB attached to Windows rather than WSL?"
    close_hw_manager
    exit 1
}
current_hw_device $dev

# The wildcard "s25fl128*" ALSO matches the S25FL128L family (a different,
# sibling chip sharing the same numeric prefix) - matching "s25fl128*" alone
# picked "s25fl128l-spi-x1_x2_x4" here on 01-SEP-2026 even though the board's
# real chip is an S25FL128S, and Vivado refused to program it ("Part selected
# s25fl128l, but part s25fl128sxxxxxx0 detected"). Require the lowercase "s"
# explicitly, and prefer the exact "xxxxxx0" device-ID variant this board's
# chip reports (fall back to "xxxxxx1" - the two only differ in an OTP/lock
# feature Vivado does not need to know to program the flash).
set parts [get_cfgmem_parts -filter {NAME =~ "s25fl128sxxxxxx0-spi-x1_x2_x4" || NAME =~ "s25fl128sxxxxxx0-spi-x1_x2_x4_x8"}]
if {[llength $parts] == 0} {
    set parts [get_cfgmem_parts -filter {NAME =~ "s25fl128s*x1_x2_x4*"}]
}
if {[llength $parts] == 0} {
    puts "ERROR: this Vivado has no cfgmem part matching s25fl128s - list them with"
    puts "       get_cfgmem_parts and put the right one here."
    close_hw_manager
    exit 1
}
set part [lindex $parts 0]
puts "FLASH PART: [get_property NAME $part] (s25fl128s match)"

# --- 3. program the flash ---------------------------------------------------
set cfgmem [create_hw_cfgmem -hw_device $dev $part]
set_property PROGRAM.FILES [list $mcs] $cfgmem
set_property PROGRAM.ADDRESS_RANGE {use_file} $cfgmem
set_property PROGRAM.BLANK_CHECK 0 $cfgmem
set_property PROGRAM.ERASE 1 $cfgmem
set_property PROGRAM.CFG_PROGRAM 1 $cfgmem
set_property PROGRAM.VERIFY 1 $cfgmem
create_hw_bitstream -hw_device $dev [get_property PROGRAM.HW_CFGMEM_BITFILE $dev]
program_hw_devices $dev
program_hw_cfgmem $cfgmem

# --- 4. boot the FPGA from the freshly written flash ------------------------
boot_hw_device $dev
puts "FLASHED (QSPI, permanent - survives power cycles; board is running it now)"
close_hw_manager
