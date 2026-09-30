# Write the bitstream from a finished post-route checkpoint of build.tcl,
# without re-running synthesis and implementation. Used when a run got all
# the way through timing (WNS/WHS >= 0) and then stopped at write_bitstream
# for a reason that is not the netlist - the LUTLP-1 DRC severity the first
# full builds hit on 02-SEP-2026. Same DRC handling as build.tcl.
#
#   vivado -mode batch -source bit_from_checkpoint.tcl -tclargs board r6 [run_N]
set srcdir [file dirname [file normalize [info script]]]
set board [lindex $argv 1]
set run   [expr {[llength $argv] > 2 ? [lindex $argv 2] : ""}]
# The build folder: $ND120_BUILD_DIR/mega65/<board> (local.mk at the
# repository root, written by configure.py), where build.tcl left the runs.
source [file join $srcdir .. paths.tcl]
set outdir [nd120_board_dir mega65/$board "bit_from_checkpoint.tcl"]
cd $outdir
if {$run eq ""} {
    set runs [lsort -dictionary [glob -directory [file join $outdir timing-analysis] -type d run*]]
    set run [file tail [lindex $runs end]]
}
set dcp [file join $outdir timing-analysis $run post_route.dcp]
puts "checkpoint: $dcp"
open_checkpoint $dcp
# constraints added to CORE/CORE.xdc after the checkpoint was written apply
# here too (the same file the full flow reads), so a repaired constraint can
# be checked against the finished placement without re-implementing
read_xdc [file join $srcdir CORE CORE.xdc]
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
puts "WNS: $wns ns"
puts "WHS: $whs ns"
if {$wns >= 0 && $whs < 0} {
    # Setup is met and only hold is short: pad the offending paths (the
    # first R6 run's hold fixer had spent its budget on a phantom path
    # that CORE.xdc has since false-pathed, and gave up 21 ps short on a
    # real one). Post-route phys_opt keeps the routing and re-routes only
    # what it touched; route_design afterwards is the incremental cleanup.
    puts "hold short by $whs ns with setup met - running phys_opt_design -hold_fix"
    phys_opt_design -hold_fix
    route_design
    set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
    set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
    puts "WNS: $wns ns"
    puts "WHS: $whs ns"
}
if {$wns < 0 || $whs < 0} {
    puts "ERROR: the checkpoint does not meet timing (WNS $wns, WHS $whs). No bitstream."
    exit 1
}
report_timing_summary -file [file join $outdir timing_from_checkpoint.rpt]
set_property SEVERITY {Warning} [get_drc_checks LUTLP-1]
set bit [file join $outdir nd120_mega65_$board.bit]
write_bitstream -force $bit
puts "BITSTREAM: $bit"
