# ND-120 timing-constraint exploration (NO re-synthesis).
# Opens the already-routed checkpoint and dumps everything needed to design the
# generated-clock + multicycle-path constraints. Runs in ~1-2 minutes.
#
# Usage (from Verilog\fpga\basys3):
#   vivado -mode batch -source timing_explore.tcl
# Outputs land in .\logs\ (readable from WSL).

source [file join [file dirname [file normalize [info script]]] paths.tcl]   ;# repo + Vivado project paths
set dcp $b3_routed_dcp
set logdir $b3_logdir

if {![file exists $dcp]} {
    puts "ERROR: routed checkpoint not found: $dcp"
    exit 1
}
puts "Opening routed checkpoint (no resynth): $dcp"
open_checkpoint $dcp

# --- 1. All clocks Vivado currently knows about ---
puts "\n===== report_clocks ====="
report_clocks -file "${logdir}/explore_clocks.rpt"

# --- 2. The CYC derived-clock nets: who drives them, and are they clocks? ---
puts "\n===== CYC derived-clock net drivers ====="
set fp [open "${logdir}/explore_cyc_clocks.rpt" w]
foreach cname {ALUCLK MCLK MACLK CLK UCLK} {
    puts $fp "==== $cname ===="
    # The clock net (post-BUFG) and its BUFG driver
    set nets [get_nets -quiet -hierarchical -filter "NAME =~ *CYC*${cname}_BUFG*"]
    puts $fp "  clock nets: $nets"
    foreach n $nets {
        set drv [get_pins -quiet -of_objects [get_nets $n] -filter {DIRECTION == OUT}]
        puts $fp "    driver pin: $drv"
    }
    # The FF that generates it (aluclk_pa etc.) - find the reg feeding the BUFG input
    set bufg [get_cells -quiet -hierarchical -filter "NAME =~ *CYC*${cname}_BUFG_inst*"]
    puts $fp "  BUFG cell: $bufg"
    if {[llength $bufg] > 0} {
        set bin [get_pins -quiet -of_objects $bufg -filter {DIRECTION == IN && IS_CLOCK == 0}]
        puts $fp "  BUFG input pin: $bin"
        set src_net [get_nets -quiet -of_objects $bin]
        set src_drv [get_pins -quiet -of_objects $src_net -filter {DIRECTION == OUT}]
        puts $fp "  BUFG input driven by (the pulse FF Q): $src_drv"
    }
    # How many registers does this clock actually clock?
    set loads [get_pins -quiet -of_objects [get_nets $nets] -filter {IS_CLOCK == 1 && DIRECTION == IN}]
    puts $fp "  clocks [llength $loads] register clock pins"
    puts $fp ""
}
close $fp
puts "Wrote ${logdir}/explore_cyc_clocks.rpt"

# --- 3. The sysclk BUFG source pin (needed as -source for generated clocks) ---
puts "\n===== sysclk source pin ====="
set fp [open "${logdir}/explore_sysclk.rpt" w]
set sbufg [get_cells -quiet -hierarchical -filter {NAME =~ *sysclk_IBUF_BUFG_inst*}]
puts $fp "sysclk BUFG cell: $sbufg"
puts $fp "sysclk BUFG /O pin: [get_pins -quiet -of_objects $sbufg -filter {DIRECTION==OUT}]"
close $fp

# --- 4. Fuller failing-path list (100 paths) so I can see ALL the clusters ---
puts "\n===== report_timing_summary (100 paths) ====="
report_timing_summary -max_paths 100 -nworst 100 -delay_type max \
    -file "${logdir}/explore_timing_100.rpt"

# --- 5. Clock interaction: which clock-domain crossings exist ---
report_clock_interaction -file "${logdir}/explore_clock_interaction.rpt"

puts "\n=== EXPLORE COMPLETE - reports in ${logdir}/ ==="
close_project
exit 0
