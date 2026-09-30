# ENDGAME TEST (no resynth, ~45s): apply the full candidate constraint set at
# 39 MHz and see if the design closes.
#   1. UART treated as quasi-static peripheral (false_path boundary)
#   2. Multicycle-2 on the deep microcycle-spanning paths into the bus arbiter
#      (s_osc, once/cycle) and MAC (MCLK, once/cycle) - they settle over the
#      microcycle, not one state.
# If WNS >= 0 here, we have the recipe: 39 MHz clock + these constraints.
source [file join [file dirname [file normalize [info script]]] paths.tcl]   ;# repo + Vivado project paths
set dcp $b3_routed_dcp
open_checkpoint $dcp
create_clock -period 25.6 -name sys_clk [get_ports sysclk]

# --- 1. UART boundary ---
set uart_ffs [get_cells -hierarchical -filter {NAME =~ *IO/UART* && REF_NAME =~ FD*}]
set_false_path -from $uart_ffs
set_false_path -to   $uart_ffs
puts "UART ffs boundaried: [llength $uart_ffs]"

# --- 2. Multicycle on the arbiter + MAC destinations (once-per-microcycle capture) ---
set arb [get_cells -hierarchical -regexp -filter {NAME =~ ".*(PAL_44801_UBARB|PAL_44803_URAMA).*" && REF_NAME =~ "FD.*"}]
set mac [get_cells -hierarchical -regexp -filter {NAME =~ ".*MAC.*CALC.*" && REF_NAME =~ "FD.*"}]
puts "arbiter regs: [llength $arb]   MAC calc regs: [llength $mac]"
set deep [concat $arb $mac]
if {[llength $deep] > 0} {
    set_multicycle_path 2 -setup -to $deep
    set_multicycle_path 1 -hold  -to $deep
}

set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts "\n==== WNS @25.6ns with UART boundary + MC2(arbiter,MAC): $wns ns ===="

puts "\n==== 20 worst remaining paths ===="
foreach p [get_timing_paths -max_paths 20 -nworst 1 -setup] {
    set slk [get_property SLACK $p]
    set req [get_property REQUIREMENT $p]
    set src [get_property STARTPOINT_PIN $p]
    set dst [get_property ENDPOINT_PIN $p]
    puts [format "  slack=%7s req=%6s  %s  ->  %s" $slk $req $src $dst]
}
set remain [get_timing_paths -max_paths 4000 -nworst 1 -setup -slack_lesser_than 0]
puts "\n==== remaining failing endpoints: [llength $remain] ===="
close_project
exit 0
