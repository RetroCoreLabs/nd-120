# Find actual post-synthesis net names for debug probes
# Usage: vivado -mode batch -source find_nets.tcl

source [file join [file dirname [file normalize [info script]]] paths.tcl]   ;# repo + Vivado project paths
set project_dir $b3_project_dir
open_project "${project_dir}/ND3202D.xpr"
open_run synth_1

set fp [open "${project_dir}/output/net_search.txt" w]

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
close_project

puts "Results written to ${project_dir}/output/net_search.txt"
exit 0
