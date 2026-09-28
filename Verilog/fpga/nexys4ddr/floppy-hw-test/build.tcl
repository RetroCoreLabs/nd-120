# Floppy HW test (self-checking, with contention injector) for the Nexys 4 DDR (floppy_hwtest_top) - same in-memory
# flow as ../sd-fat-test/build.tcl.
#   vivado -mode batch -source build.tcl              # build + JTAG program
#   vivado -mode batch -source build.tcl -tclargs -noburn
# Purpose and output format: see the header of floppy_hwtest_top.v and
# ../HANDOFF-floppy-dma-investigation.md (retired, git c4896a4).

set part xc7a100tcsg324-1
set srcdir [file dirname [file normalize [info script]]]
set vroot  [file normalize [file join $srcdir .. .. ..]]  ;# Verilog/

set noburn 0
foreach a $argv { if {$a eq "-noburn"} { set noburn 1 } }

set sdfat [file join $vroot SD-FAT circuit]
set tsrc  [file join $vroot fpga tang-nano-20k sd-fat-test src]

create_project -in_memory -part $part

read_verilog [list \
    [file join $srcdir floppy_hwtest_top.v] \
    [file join $tsrc uart_tx.v] \
    [file join $vroot fpga nexys4ddr ddr2 nd_ddr2_port.v] \
    [file join $vroot fpga nexys4ddr ddr2 nd_ddr2_storage.v] \
    [file join $sdfat nds_sync.v] \
    [file join $sdfat nd_storage_engine.v] \
    [file join $sdfat nd_storage_mount.v] \
    [file join $sdfat nd_storage_cache.v] \
    [file join $sdfat nd_storage_fatchk.v] \
    [file join $sdfat nd_storage.v] \
    [file join $sdfat sd_file_reader.v] \
    [file join $sdfat sd_writer.v] \
    [file join $sdfat nd_storage_floppy_adapter.v] \
    [file join $vroot ND-BUS-DEVICES FLOPPY-DMA circuit ND_FLOPPY_DMA.v] \
    [file join $vroot ND-BUS-DEVICES DMA circuit ND_DMA_MASTER.v] ]

set migxci [file join $vroot fpga nexys4ddr ddr2-test ip ddr ddr.xci]
if {![file exists $migxci]} {
    puts "ERROR: MIG core not generated: $migxci"
    exit 1
}
read_ip $migxci

read_xdc [file join $srcdir floppy_hwtest.xdc]

# nd_storage `include "sd_fat_features.vh" / "nd_storage_status.vh"
synth_design -top floppy_hwtest_top -part $part \
    -include_dirs [list $sdfat] \
    -verilog_define SDFAT_STORAGE_CHECK

# Same CDC treatment as the ND-120 build: pairwise datapath-only bounds
# between the three user domains (see ../build.tcl for the reasoning).
set _ccpu [get_clocks -quiet -of_objects [get_pins mmcm/CLKOUT0]]
set _cst  [get_clocks -quiet -of_objects [get_pins mmcm/CLKOUT1]]
set _cui  [get_clocks -quiet clk_pll_i]
if {[llength $_ccpu] && [llength $_cst] && [llength $_cui]} {
    foreach {src dst lim} [list \
        $_ccpu $_cst 37.000  $_cst $_ccpu 80.000 \
        $_cst  $_cui 13.300  $_cui $_cst 37.000 \
        $_ccpu $_cui 13.300  $_cui $_ccpu 80.000] {
        set_max_delay -datapath_only -from $src -to $dst $lim
    }
    puts "CDC datapath-only bounds applied."
} else {
    puts "WARNING: could not resolve one of the user clocks - crossings untimed."
    puts "  cpu=$_ccpu stor=$_cst ui=$_cui"
}

opt_design
place_design
phys_opt_design
route_design

report_timing_summary -file [file join $srcdir timing.rpt]
puts "TIMING: WNS [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]"

write_bitstream -force [file join $srcdir floppy_hwtest.bit]

if {$noburn} {
    puts "=== FLOPPY HW TEST BUILD COMPLETE (not programmed) ==="
    exit 0
}

open_hw_manager
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices xc7a100t*] 0]
current_hw_device $dev
set_property PROGRAM.FILE [file join $srcdir floppy_hwtest.bit] $dev
program_hw_devices $dev
puts "PROGRAMMED (JTAG)"
close_hw_manager
puts "=== FLOPPY HW TEST BUILD COMPLETE ==="
