# EXPERIMENT (no resynth): re-time the routed design at ~39 MHz to measure how
# much of the -40ns WNS is fixed simply by slowing the CPU/sys_clk to original
# ND speed (25.6 ns/state), vs how much is genuine multi-state depth needing
# set_multicycle_path. Routing/placement stay as-is (optimized for 100 MHz), so
# this is a logic-DEPTH check, not a final number - but it decisively tells us
# whether the frequency move is the lever.
#
# Usage (from Verilog\fpga\basys3):
#   vivado -mode batch -source exp_slowclk.tcl   (or .\run_tcl.ps1 exp_slowclk.tcl)

source [file join [file dirname [file normalize [info script]]] paths.tcl]   ;# repo + Vivado project paths
set dcp $b3_routed_dcp
set logdir $b3_logdir
open_checkpoint $dcp

# Try several CPU clock periods so we can bracket where timing closes.
#   10.0 ns  = 100.0 MHz (current, for reference)
#   25.6 ns  =  39.06 MHz (original ND OSC target)
#   40.0 ns  =  25.0 MHz
#   80.0 ns  =  12.5 MHz
foreach {per mhz} {10.0 100 25.6 39 40.0 25 80.0 12.5} {
    # Override the primary clock period on the sysclk port. This re-derives the
    # MMCM-generated clocks proportionally is NOT automatic here, but the CPU
    # datapath is analyzed on sys_clk, so this captures the datapath payoff.
    create_clock -period $per -name sys_clk [get_ports sysclk]
    set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
    puts "PERIOD ${per}ns (~${mhz}MHz):  WNS = ${wns} ns"
}

# Full diagnostic at the ND-target 25.6 ns (39 MHz).
create_clock -period 25.6 -name sys_clk [get_ports sysclk]

# How many endpoints still fail at 39 MHz? (scopes the multicycle work)
set failing [get_timing_paths -max_paths 4000 -nworst 1 -setup -slack_lesser_than 0]
puts "\n==== At 25.6 ns (39 MHz): [llength $failing] failing setup endpoints ===="

# The 15 worst paths: slack + is-it-half-cycle + source/dest, so I can classify.
puts "\n==== 15 worst paths at 25.6 ns ===="
foreach p [get_timing_paths -max_paths 15 -nworst 1 -setup] {
    set slk [get_property SLACK $p]
    set req [get_property REQUIREMENT $p]
    set src [get_property STARTPOINT_PIN $p]
    set dst [get_property ENDPOINT_PIN $p]
    puts [format "  slack=%7s req=%6s  %s  ->  %s" $slk $req $src $dst]
}

report_timing_summary -max_paths 30 -nworst 30 -delay_type max \
    -file "${logdir}/exp_slowclk_25p6.rpt"
puts "\nWrote ${logdir}/exp_slowclk_25p6.rpt"
close_project
exit 0
