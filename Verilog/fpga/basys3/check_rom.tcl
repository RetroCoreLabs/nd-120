# Check if microcode ROM has actual data after synthesis
# Usage: vivado -mode batch -source check_rom.tcl -nojournal -nolog

source [file join [file dirname [file normalize [info script]]] paths.tcl]   ;# repo + build folder paths
# The synthesized design: <build>/post_synth.dcp, written by a full_synth run
# of vivado_build.tcl (there is no Vivado project since 30-SEP-2026).
if {![file exists $b3_synth_dcp]} {
    puts "ERROR: no synthesized design at $b3_synth_dcp - run vivado_build.tcl with full_synth first"
    exit 1
}
open_checkpoint $b3_synth_dcp

set fp [open "${b3_output_dir}/rom_content_check.txt" w]
puts $fp "=== Microcode ROM Content Check ==="
puts $fp "Date: [clock format [clock seconds]]"
puts $fp ""

# Find all cells that contain rom_lo or rom_hi in their name
foreach pattern {*rom_lo* *rom_hi*} {
    set cells [get_cells -hierarchical -quiet -filter "NAME =~ $pattern"]
    puts $fp "Pattern: $pattern -> [llength $cells] cells"
    foreach c $cells {
        set ref [get_property REF_NAME $c]
        puts $fp "  $c  (type: $ref)"
        # Try to read INIT values if it's a LUT or BRAM
        foreach prop {INIT INIT_00 INIT_01} {
            set val [get_property -quiet $prop $c]
            if {$val ne ""} {
                puts $fp "    $prop = $val"
            }
        }
    }
    puts $fp ""
}

# Also check for any RAM256X1S cells (LUT RAM) under the PROM hierarchy
puts $fp "=== LUT RAM cells under PROM ==="
set prom_cells [get_cells -hierarchical -quiet -filter "NAME =~ *PROM*"]
puts $fp "PROM hierarchy cells: [llength $prom_cells]"
foreach c $prom_cells {
    set ref [get_property REF_NAME $c]
    puts $fp "  $c  (type: $ref)"
    set init [get_property -quiet INIT $c]
    if {$init ne ""} {
        # Only show first 64 chars to keep it readable
        set show [string range $init 0 63]
        set all_zero [string match *0000000000000000* $init]
        puts $fp "    INIT = ${show}... (all_zero: $all_zero)"
    }
}

close $fp
close_design

puts ""
puts "Results: ${b3_output_dir}/rom_content_check.txt"
exit 0
