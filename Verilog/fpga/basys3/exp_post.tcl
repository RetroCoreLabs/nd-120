# Post-build classify (no resynth, ~40s): open the NEW routed checkpoint and
# break down the remaining setup failures so we bundle the exact fixes into one
# more build. Also lists all clocks and any clk_cpu<->sys_clk crossings.
source [file join [file dirname [file normalize [info script]]] paths.tcl]   ;# repo + Vivado project paths
set dcp $b3_routed_dcp
open_checkpoint $dcp

puts "\n==== clocks ===="
foreach c [get_clocks] {
    puts [format "  %-16s period=%s" [get_property NAME $c] [get_property PERIOD $c]]
}

set paths [get_timing_paths -max_paths 4000 -nworst 1 -setup -slack_lesser_than 0]
puts "\n==== total failing setup endpoints: [llength $paths] ===="

set ila 0; set other 0
array set otherlist {}
foreach p $paths {
    set dp [get_property ENDPOINT_PIN $p]
    if {[string match "*u_ila_0*" $dp] || [string match "*dbg_hub*" $dp]} {
        incr ila
    } else {
        incr other
        set src [get_property STARTPOINT_PIN $p]
        set key "[get_property SLACK $p] : $src -> $dp"
        set otherlist($key) 1
    }
}
puts "  ILA/dbg_hub endpoints : $ila"
puts "  NON-ILA endpoints     : $other"
puts "\n==== all NON-ILA failing paths (the real ones) ===="
foreach k [lsort [array names otherlist]] { puts "  $k" }

# For the worst non-ILA path, show source & dest clocks (is it a CDC?)
foreach p $paths {
    set dp [get_property ENDPOINT_PIN $p]
    if {![string match "*u_ila_0*" $dp] && ![string match "*dbg_hub*" $dp]} {
        set sc [get_property STARTPOINT_CLOCK $p]
        set ec [get_property ENDPOINT_CLOCK $p]
        puts "\n  worst non-ILA: src_clk=$sc  dst_clk=$ec  slack=[get_property SLACK $p]"
        break
    }
}
close_project
exit 0
