# Arm, wait, and read in ONE session. Arming in one vivado batch run and
# reading in another does not work: hw_ila properties are software-side and
# re-initialise per session, so the second run cannot tell an armed core from
# a never-armed one.
set srcdir [file dirname [file normalize [info script]]]
# The bitstream, probes file and captures live in the build folder,
# $ND120_BUILD_DIR/nexys4ddr (local.mk at the repository root, written by
# configure.py) - never in this source folder.
source [file join $srcdir .. paths.tcl]
set outdir [nd120_board_dir nexys4ddr]
set secs   [lindex $argv 0]
if {$secs eq ""} { set secs 120 }

open_hw_manager
connect_hw_server
open_hw_target
set_property PARAM.FREQUENCY 5000000 [current_hw_target]
set dev [lindex [get_hw_devices xc7a100t*] 0]
current_hw_device $dev
set_property PROBES.FILE [file join $outdir nd120_nexys4ddr.ltx] $dev
refresh_hw_device -quiet $dev

set ila [lindex [get_hw_ilas] 0]
set p_cache [lindex [get_hw_probes *s_ila_cache* -of_objects $ila] 0]
puts "PROBE: $p_cache"

set_property CONTROL.TRIGGER_POSITION 256 $ila
set_property CONTROL.CAPTURE_MODE ALWAYS $ila
# bit 5 = WCA_n, active low. Trigger on a cache write actually happening.
set_property TRIGGER_COMPARE_VALUE eq8'bxx0xxxxx $p_cache
run_hw_ila $ila
puts "ARMED_WCA - now run the test; polling for ${secs}s"
flush stdout

for {set i 0} {$i < $secs} {incr i} {
    after 1000
    set st [get_property STATUS.CORE_STATUS $ila]
    if {$i % 10 == 0} { puts "  t=${i}s status=$st"; flush stdout }
    if {[string equal -nocase $st "FULL"]} { break }
}
set st [get_property STATUS.CORE_STATUS $ila]
puts "FINAL_STATUS: $st"
puts "SAMPLE_COUNT: [get_property STATUS.SAMPLE_COUNT $ila]"
if {[string equal -nocase $st "FULL"]} {
    display_hw_ila_data [upload_hw_ila_data $ila]
    write_hw_ila_data -csv_file -force [file join $outdir ila_cache.csv] [current_hw_ila_data]
    puts "WCA_FIRED - wrote ila_cache.csv"
} else {
    puts "WCA_NEVER_FIRED - WCA_n did not go low in ${secs}s of the test running"
}
