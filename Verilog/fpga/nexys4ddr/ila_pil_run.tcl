# ---------------------------------------------------------------------------
# Capture PIL across a real interrupt-level change (build.tcl -tclargs ilacache).
#
# THE QUESTION. Ronny reports that when a test program walks levels 2,3,4,5,6,
# the on-screen panel's ACTIVE LEVEL row lights ALL SIXTEEN segments on every
# change instead of the one level in use.
#
# Three explanations have already died - a PIL clock-domain transient, the
# frame_tick/decay ratio in term_panel, and an accumulation theory. All three
# were reasoned from the source and none was ever measured, which is the whole
# problem: Verilator settles values once per clock, so an intra-cycle transient
# does not exist there at all.
#
# There is also a real chance the row is simply built on the wrong signal. The
# MC68705 panel's ACTIVE LEVEL field shows ACTLV - an accumulated one-hot word
# the microcode sends with LDPANC 0x0A - not PIL. Our row uses PIL.
#
# This script separates those two. Arm on PIL leaving 0 and look at what the
# bus actually does across a level change:
#   - if PIL steps cleanly 2 -> 3 -> 4 with no intermediate codes, the transient
#     theory is dead for good and the row's SOURCE is the fault;
#   - if PIL walks through codes the CPU never ran at, the synchroniser story
#     was right and the gate that was flashed did not go far enough.
#
# Run the TPE INSTRUCTION test (INSTRUCTION-C03) - Ronny's own answer for which
# program drives the levels.
#
#   -tclargs <seconds>
#
# Written 29-AUG-2026.
# ---------------------------------------------------------------------------

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
if {$ila eq ""} { puts "ERROR: no hw_ila found"; exit 1 }
set p_pil [lindex [get_hw_probes *s_ila_pil* -of_objects $ila] 0]
if {$p_pil eq ""} { puts "ERROR: s_ila_pil probe not found"; exit 1 }

# Centre the window so we see BEFORE and AFTER the level leaves 0 - the
# interesting part is the handful of samples around the change, not what
# happens a thousand cycles later.
set_property CONTROL.TRIGGER_POSITION 512 $ila
set_property CONTROL.CAPTURE_MODE ALWAYS $ila
# PIL != 0. Anything other than level 0 is a level change worth seeing.
set_property TRIGGER_COMPARE_VALUE neq4'b0000 $p_pil
run_hw_ila $ila
puts "ARMED on PIL != 0 - run the TPE INSTRUCTION test now; polling ${secs}s"
flush stdout

for {set i 0} {$i < $secs} {incr i} {
    after 1000
    set st [get_property STATUS.CORE_STATUS $ila]
    if {$i % 10 == 0} { puts "  t=${i}s status=$st"; flush stdout }
    if {[string equal -nocase $st "FULL"]} { break }
}
set st [get_property STATUS.CORE_STATUS $ila]
puts "FINAL_STATUS: $st"
if {[string equal -nocase $st "FULL"]} {
    display_hw_ila_data [upload_hw_ila_data $ila]
    write_hw_ila_data -csv_file -force [file join $outdir ila_pil.csv] [current_hw_ila_data]
    puts "PIL_CAPTURED - wrote ila_pil.csv"
} else {
    puts "PIL_NEVER_LEFT_ZERO - the machine stayed on level 0 for ${secs}s"
}
