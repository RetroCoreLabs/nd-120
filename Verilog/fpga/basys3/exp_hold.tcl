source [file join [file dirname [file normalize [info script]]] paths.tcl]   ;# repo + Vivado project paths
open_checkpoint $b3_routed_dcp
puts "SETUP_WNS [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]"
puts "HOLD_WHS [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]"
set hp [get_timing_paths -max_paths 4000 -nworst 1 -hold -slack_lesser_than 0]
puts "HOLD_FAILING [llength $hp]"
set ila 0; set other 0; array set ol {}
foreach p $hp {
  set dp [get_property ENDPOINT_PIN $p]
  if {[string match "*u_ila_0*" $dp] || [string match "*dbg_hub*" $dp]} { incr ila } else {
    incr other
    set ol("[format %.3f [get_property SLACK $p]] [get_property STARTPOINT_PIN $p] -> $dp") 1
  }
}
puts "HOLD_ILA $ila  HOLD_OTHER $other"
puts "==== non-ILA hold fails ===="
foreach k [lsort [array names ol]] { puts "  $k" }
close_project
exit 0
