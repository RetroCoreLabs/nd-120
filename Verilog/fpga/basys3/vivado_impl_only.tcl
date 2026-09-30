# Quick rebuild: implementation + bitstream + JTAG + flash (skips synthesis)
# Usage: vivado -mode batch -source vivado_impl_only.tcl

source [file join [file dirname [file normalize [info script]]] paths.tcl]   ;# repo + Vivado project paths
set project_dir $b3_project_dir
set output_dir "${project_dir}/output"
set top_module "ND120_TOP"

open_project "${project_dir}/ND3202D.xpr"

puts "\n=== IMPLEMENTATION + BITSTREAM (skipping synthesis) ==="
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 12
wait_on_run impl_1

set bit_file "${project_dir}/ND3202D.runs/impl_1/${top_module}.bit"
if {[file exists $bit_file]} {
    file copy -force $bit_file "${output_dir}/${top_module}.bit"
    puts "Bitstream: ${output_dir}/${top_module}.bit"
} else {
    puts "ERROR: No bitstream generated"
    close_project
    exit 1
}

puts "\n=== PROGRAMMING FPGA (JTAG) ==="
open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target
set hw [get_hw_devices xc7a35t_0]
current_hw_device $hw
set_property PROGRAM.FILE "${output_dir}/${top_module}.bit" $hw
program_hw_devices $hw
puts "FPGA programmed via JTAG"

puts "\n=== PROGRAMMING SPI FLASH ==="
set mcs_file "${output_dir}/${top_module}.mcs"
write_cfgmem -force -format mcs -interface SPIx4 -size 4 \
    -loadbit "up 0x0 ${output_dir}/${top_module}.bit" $mcs_file

create_hw_cfgmem -hw_device $hw [lindex [get_cfgmem_parts {s25fl032p-spi-x1_x2_x4}] 0]
set hw_cfgmem [get_property PROGRAM.HW_CFGMEM $hw]
set_property PROGRAM.ADDRESS_RANGE  {use_file} $hw_cfgmem
set_property PROGRAM.FILES          [list $mcs_file] $hw_cfgmem
set_property PROGRAM.PRM_FILE       {} $hw_cfgmem
set_property PROGRAM.UNUSED_PIN_TERMINATION {pull-none} $hw_cfgmem
set_property PROGRAM.BLANK_CHECK    0 $hw_cfgmem
set_property PROGRAM.ERASE          1 $hw_cfgmem
set_property PROGRAM.CFG_PROGRAM    1 $hw_cfgmem
set_property PROGRAM.VERIFY         1 $hw_cfgmem
set_property PROGRAM.CHECKSUM       0 $hw_cfgmem

# Generate and load the indirect-programming (SPI proxy) bitstream
create_hw_bitstream -hw_device $hw [get_property PROGRAM.HW_CFGMEM_BITFILE $hw]
program_hw_devices $hw

program_hw_cfgmem -hw_cfgmem $hw_cfgmem
puts "SPI flash programmed"

boot_hw_device $hw
puts "FPGA rebooted from flash"

close_hw_target
disconnect_hw_server
close_hw_manager

close_project
puts "\n=== DONE ==="
exit 0
