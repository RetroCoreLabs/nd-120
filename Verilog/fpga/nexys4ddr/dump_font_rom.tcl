# Dump the font ROM BRAM INIT strings from a placed checkpoint so the actual
# silicon page->data mapping can be reconstructed and compared to the hex.
# The timing-analysis runs live in the build folder, $ND120_BUILD_DIR/nexys4ddr.
source [file join [file dirname [file normalize [info script]]] .. paths.tcl]
set outdir [nd120_board_dir nexys4ddr]
open_checkpoint [file join $outdir timing-analysis run_clk33_5 post_route.dcp]

set fh [open [file join $outdir dump_font_rom.txt] w]

# Every BRAM cell. Report name + type; we grep the font ones out in python.
set cells [get_cells -hier -filter {PRIMITIVE_GROUP == BLOCKRAM || REF_NAME =~ RAMB*}]
puts $fh "=== ALL BRAM CELLS ==="
foreach c $cells {
    puts $fh "CELL $c REF [get_property REF_NAME $c]"
}

# For any cell whose name mentions FONT or s_rom, dump every INIT_* / INITP_*.
puts $fh "=== FONT ROM INIT DUMP ==="
foreach c $cells {
    if {[string match -nocase *FONT* $c] || [string match -nocase *s_rom* $c]} {
        puts $fh "BEGINCELL $c REF [get_property REF_NAME $c] LOC [get_property LOC $c]"
        set props [list_property $c]
        foreach p $props {
            if {[string match INIT_* $p] || [string match INITP_* $p] || $p eq "READ_WIDTH_A" || $p eq "READ_WIDTH_B" || $p eq "RAM_MODE" || $p eq "DOA_REG"} {
                puts $fh "$p [get_property $p $c]"
            }
        }
        puts $fh "ENDCELL"
    }
}
close $fh
puts "DONE dump_font_rom.txt"
