# Program FPGA via JTAG and/or SPI flash
# Usage: vivado -mode batch -source flash.tcl -tclargs [jtag_only|jtag_and_flash]

source [file join [file dirname [file normalize [info script]]] paths.tcl]   ;# repo + Vivado project paths
set output_dir $b3_output_dir
set top_module "ND120_TOP"
set bit_file "${output_dir}/${top_module}.bit"
set ltx_file "${output_dir}/${top_module}.ltx"
set mode [lindex $argv 0]

if {![file exists $bit_file]} {
    puts "ERROR: Bitstream not found: $bit_file"
    exit 1
}

open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target

set hw [get_hw_devices xc7a35t_0]
current_hw_device $hw

# Set bitstream on device — needed for both JTAG and indirect SPI programming
set_property PROGRAM.FILE $bit_file $hw
if {[file exists $ltx_file]} {
    set_property PROBES.FILE      $ltx_file $hw
    set_property FULL_PROBES.FILE $ltx_file $hw
    puts "Probes: $ltx_file"
} else {
    set_property PROBES.FILE      {} $hw
    set_property FULL_PROBES.FILE {} $hw
    puts "WARNING: No .ltx found at $ltx_file — ILA probes will not load"
}

if {$mode eq "jtag_and_flash"} {
    # First program JTAG so the FPGA has a valid config
    puts "=== PROGRAMMING FPGA (JTAG) ==="
    program_hw_devices $hw
    refresh_hw_device $hw
    puts "FPGA programmed via JTAG"

    puts "\n=== PROGRAMMING SPI FLASH ==="
    set mcs_file "${output_dir}/${top_module}.mcs"
    write_cfgmem -force -format mcs -interface SPIx4 -size 4 \
        -loadbit "up 0x0 $bit_file" $mcs_file

    # Create cfgmem and set ALL properties before programming
    create_hw_cfgmem -hw_device $hw -mem_dev [lindex [get_cfgmem_parts {s25fl032p-spi-x1_x2_x4}] 0]
    set cfgmem [get_property PROGRAM.HW_CFGMEM $hw]

    set_property PROGRAM.FILES                  [list $mcs_file] $cfgmem
    set_property PROGRAM.PRM_FILE               {} $cfgmem
    set_property PROGRAM.ADDRESS_RANGE          {use_file} $cfgmem
    set_property PROGRAM.UNUSED_PIN_TERMINATION {pull-none} $cfgmem
    set_property PROGRAM.BLANK_CHECK            0 $cfgmem
    set_property PROGRAM.ERASE                  1 $cfgmem
    set_property PROGRAM.CFG_PROGRAM            1 $cfgmem
    set_property PROGRAM.VERIFY                 1 $cfgmem
    set_property PROGRAM.CHECKSUM               0 $cfgmem

    # Generate and load the indirect-programming (SPI proxy) bitstream.
    # Without this the FPGA can't bridge JTAG to SPI and flash programming
    # fails with "Failure to set flash parameters" (Labtools 27-3347).
    create_hw_bitstream -hw_device $hw [get_property PROGRAM.HW_CFGMEM_BITFILE $hw]
    program_hw_devices $hw

    program_hw_cfgmem -hw_cfgmem $cfgmem
    puts "SPI flash programmed"

    boot_hw_device $hw
    puts "FPGA rebooted from flash"
} else {
    puts "=== PROGRAMMING FPGA (JTAG only) ==="
    program_hw_devices $hw
    puts "FPGA programmed via JTAG (volatile)"
}

close_hw_target
disconnect_hw_server
close_hw_manager

puts "\n=== DONE ==="
exit 0
