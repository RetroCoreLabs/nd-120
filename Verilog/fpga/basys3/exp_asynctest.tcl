source [file join [file dirname [file normalize [info script]]] paths.tcl]   ;# repo + Vivado project paths
open_checkpoint $b3_routed_dcp
puts "BEFORE_WNS [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]"
set g1 [get_clocks -quiet sys_clk]
set g2 [get_clocks -quiet clk_cpu_pre]
puts "RESOLVE sys_clk=[llength $g1]  clk_cpu_pre=[llength $g2]"
set_clock_groups -asynchronous -group [get_clocks sys_clk] -group [get_clocks clk_cpu_pre]
puts "AFTER_ASYNC_WNS [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]"
set rem [get_timing_paths -max_paths 4000 -nworst 1 -setup -slack_lesser_than 0]
puts "REMAINING_FAILING [llength $rem]"
# classify remaining
set ila 0; set other 0
foreach p $rem {
  set dp [get_property ENDPOINT_PIN $p]
  if {[string match "*u_ila_0*" $dp] || [string match "*dbg_hub*" $dp]} { incr ila } else { incr other }
}
puts "REMAIN_ILA $ila  REMAIN_OTHER $other"
close_project
exit 0
