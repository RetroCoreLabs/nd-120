# DECISIVE TEST (no resynth, ~40s): if we put a timing boundary around the UART
# (treat it as the quasi-static peripheral it is) AND run at 39 MHz, does the
# design close? Applies false_path from/to the UART flops and reports WNS.
# false_path here is an UPPER BOUND on the benefit; the real design would use
# set_multicycle_path, but this tells us if the UART is the whole story.
source [file join [file dirname [file normalize [info script]]] paths.tcl]   ;# repo + Vivado project paths
set dcp $b3_routed_dcp
set logdir $b3_logdir
open_checkpoint $dcp
create_clock -period 25.6 -name sys_clk [get_ports sysclk]

# All flip-flops inside the UART instance (the inverted-clock domain).
set uart_ffs [get_cells -hierarchical -filter {NAME =~ *IO/UART* && REF_NAME =~ FD*}]
puts "\n==== UART flip-flops found: [llength $uart_ffs] ===="

# Baseline WNS at 39 MHz (before boundary)
set wns0 [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts "WNS @25.6ns BEFORE UART boundary: $wns0 ns"

# Put a timing boundary around the UART both directions.
set_false_path -from $uart_ffs
set_false_path -to   $uart_ffs

set wns1 [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts "WNS @25.6ns AFTER  UART boundary: $wns1 ns"

# If still negative, show the 15 worst REMAINING paths so we see what else is there.
puts "\n==== 15 worst REMAINING paths (UART boundary applied, 25.6ns) ===="
foreach p [get_timing_paths -max_paths 15 -nworst 1 -setup] {
    set slk [get_property SLACK $p]
    set req [get_property REQUIREMENT $p]
    set src [get_property STARTPOINT_PIN $p]
    set dst [get_property ENDPOINT_PIN $p]
    puts [format "  slack=%7s req=%6s  %s  ->  %s" $slk $req $src $dst]
}
set remain [get_timing_paths -max_paths 4000 -nworst 1 -setup -slack_lesser_than 0]
puts "\n==== remaining failing endpoints (UART boundary, 25.6ns): [llength $remain] ===="
close_project
exit 0
