# Find actual post-synthesis net names for debug probes
# Usage: vivado -mode batch -source find_nets.tcl

source [file join [file dirname [file normalize [info script]]] paths.tcl]   ;# repo + build folder paths
# The synthesized design: <build>/post_synth.dcp, written by a full_synth run
# of vivado_build.tcl (there is no Vivado project since 30-SEP-2026).
if {![file exists $b3_synth_dcp]} {
    puts "ERROR: no synthesized design at $b3_synth_dcp - run vivado_build.tcl with full_synth first"
    exit 1
}
open_checkpoint $b3_synth_dcp

set fp [open "${b3_output_dir}/net_search.txt" w]

foreach pattern {
    *wca_12_0*
    *s_wca*
    *WCA*
    *w_12_0*
    *s_w_12*
    *bmem*
    *BMEM*
    *clirq*
    *CLIRQ*
    *FIDBO*
    *fidbo*
    *s_cpu_cd*
    *cd_15_0*
    *CD_15_0*
    *powfail*
    *closc*
    *power_on*
    *s_mr_n*
    *MR_n*
    *closc*
    *CLOSC*
    *s_pwcl*
    *pwcl*
    *sys_rst*
    *regPowerOn*
    *PROM*regData*
    *PROM*IDB*
    *prom_out*
    *s_debug_fidbo*
} {
    set nets [get_nets -quiet -hierarchical $pattern]
    set count [llength $nets]
    puts $fp "=== $pattern === ($count nets)"
    foreach n $nets {
        puts $fp "  $n"
    }
    puts $fp ""
}

close $fp
close_design

puts "Results written to ${b3_output_dir}/net_search.txt"
exit 0
