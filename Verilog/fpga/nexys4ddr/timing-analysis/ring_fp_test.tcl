set_param tcl.collectionResultDisplayLimit 0
# The timing-analysis runs live in the build folder, $ND120_BUILD_DIR/nexys4ddr.
source [file join [file dirname [file normalize [info script]]] .. .. paths.tcl]
open_checkpoint [file join [nd120_board_dir nexys4ddr] timing-analysis run_clk16_6 post_route.dcp]
set pi [get_pins -hier -filter {NAME =~ *DELILAH/ALU/FIDBI_15_0[*]}]
set pf [get_pins -hier -filter {NAME =~ *DELILAH/ALU/ALU_OUTMUX/OUTMUX_IDBS/IDBS_R*/F_15_0[*]} -quiet]
set nf [get_nets -hier -filter {NAME =~ *DELILAH/ALU/ALU_OUTMUX/OUTMUX_IDBS/IDBS_R*/F_15_0[*]} -quiet]
set po [get_pins -hier -filter {NAME =~ *DELILAH/ALU/FIDBO_15_0_OUT[*]}]
puts "pins in [llength $pi]  F pins [llength $pf]  F nets [llength $nf]  out [llength $po]"
puts "F pin sample: [lrange $pf 0 2]"
set p [get_timing_paths -max_paths 1 -setup]
puts "BEFORE: WNS [get_property SLACK $p] levels [get_property LOGIC_LEVELS $p]"
if {[llength $pf] > 0} {
    set_false_path -through $pi -through $pf -through $po
    set p [get_timing_paths -max_paths 1 -setup]
    puts "AFTER-3pin : WNS [get_property SLACK $p]  [get_property STARTPOINT_PIN $p] -> [get_property ENDPOINT_PIN $p] levels [get_property LOGIC_LEVELS $p]"
    set p [get_timing_paths -max_paths 1 -setup -group clk_cpu_pre]
    puts "AFTER-3pin CPU domain: WNS [get_property SLACK $p]  [get_property STARTPOINT_PIN $p] -> [get_property ENDPOINT_PIN $p] levels [get_property LOGIC_LEVELS $p]"
    reset_timing
} else { puts "NO F PINS" }
if {[llength $nf] > 0} {
    set_false_path -through $pi -through $nf -through $po
    set p [get_timing_paths -max_paths 1 -setup]
    puts "AFTER-3net : WNS [get_property SLACK $p]  [get_property STARTPOINT_PIN $p] -> [get_property ENDPOINT_PIN $p] levels [get_property LOGIC_LEVELS $p]"
}
puts "RING_FP_TEST DONE"
