# ND-120 Vivado Lint-Only Script
# Usage: vivado -mode batch -source vivado_lint.tcl
# Much faster than full build -- just runs synthesis + linter

source [file join [file dirname [file normalize [info script]]] paths.tcl]   ;# repo + Vivado project paths
set project_dir $b3_project_dir

puts "============================================"
puts " ND-120 Vivado Linter"
puts "============================================"

if {[file exists "${project_dir}/ND3202D.xpr"]} {
    open_project "${project_dir}/ND3202D.xpr"
} else {
    puts "ERROR: Project not found"
    exit 1
}

# Run synthesis with linter
reset_run synth_1
set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} -value {-lint} -objects [get_runs synth_1]
launch_runs synth_1 -jobs 4
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
puts "\nLint status: $synth_status"

# Reset the synth options back to normal
set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} -value {} -objects [get_runs synth_1]

close_project
exit 0
