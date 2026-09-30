source [file join [file dirname [file normalize [info script]]] paths.tcl]   ;# repo + Vivado project paths
open_checkpoint $b3_routed_dcp
puts "CLKSCAN_START"
foreach c [get_cells -hierarchical -filter {REF_NAME == BUFG}] {
    set onet [get_nets -quiet -of [get_pins -quiet -of $c -filter {DIRECTION==OUT}]]
    puts "BUFG_NET $c => $onet"
}
set cpuclk [get_clocks clk_cpu_pre]
puts "CPUCLK_SRC [get_property SOURCE_PINS $cpuclk]"
puts "CLKSCAN_END"
close_project
exit 0
