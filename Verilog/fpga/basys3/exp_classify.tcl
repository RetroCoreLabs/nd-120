# Classify the 39 MHz failing endpoints: how many originate from the inverted-clock
# UART (CHIP_32H/regDataOut etc.) vs elsewhere, and how many are half-cycle.
# No resynth. ~40s.
source [file join [file dirname [file normalize [info script]]] paths.tcl]   ;# repo + Vivado project paths
set dcp $b3_routed_dcp
open_checkpoint $dcp
create_clock -period 25.6 -name sys_clk [get_ports sysclk]

set paths [get_timing_paths -max_paths 4000 -nworst 1 -setup -slack_lesser_than 0]
puts "\n==== total failing setup endpoints @25.6ns: [llength $paths] ===="

set uart 0; set halfcycle 0; set uart_half 0; set other 0
array set dst_mod {}
foreach p $paths {
    set sp [get_property STARTPOINT_PIN $p]
    set req [get_property REQUIREMENT $p]
    set isuart [string match "*UART*" $sp]
    set ishalf [expr {$req < 20.0}]
    if {$isuart} { incr uart } else { incr other }
    if {$ishalf} { incr halfcycle }
    if {$isuart && $ishalf} { incr uart_half }
    # tally destination top-level block
    set dp [get_property ENDPOINT_PIN $p]
    set mod "other"
    foreach m {MEM/RAMC BIF/BCTL MAC MMU CGA/DELILAH IO/UART CS/} {
        if {[string match "*$m*" $dp]} { set mod $m; break }
    }
    if {[info exists dst_mod($mod)]} { incr dst_mod($mod) } else { set dst_mod($mod) 1 }
}
puts "  from UART source        : $uart"
puts "  from non-UART source    : $other"
puts "  half-cycle (req<20ns)   : $halfcycle"
puts "  UART AND half-cycle     : $uart_half"
puts "\n  failing endpoints by DESTINATION block:"
foreach m [array names dst_mod] { puts "    $m : $dst_mod($m)" }

# Also: what does the design look like if we IGNORE the UART source entirely?
# (proxy for 'if we constrain UART->core as false/multicycle')
set worst_non_uart 999
foreach p $paths {
    set sp [get_property STARTPOINT_PIN $p]
    if {![string match "*UART*" $sp]} {
        set s [get_property SLACK $p]
        if {$s < $worst_non_uart} { set worst_non_uart $s }
    }
}
puts "\n==== worst NON-UART slack @25.6ns: $worst_non_uart ns ===="
puts "(this is the WNS we'd have if UART->core paths were constrained away)"
close_project
exit 0
