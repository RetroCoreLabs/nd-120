# ND-120 Basys3 - shared path setup for every Tcl script in this folder.
#
# Each script in Verilog/fpga/basys3/ starts with
#   source [file join [file dirname [file normalize [info script]]] paths.tcl]
# so it works the same from a batch run (vivado -mode batch -source x.tcl)
# and from the Vivado Tcl console (source x.tcl).
#
# Paths INSIDE the repository are worked out from where this file sits - no
# drive letter or checkout location is written anywhere.
#
# The one path OUTSIDE the repository is the Basys3 Vivado GUI project (the
# folder holding ND3202D.xpr). It comes from the environment variable
# ND120_BASYS3_PROJECT, taken from the environment or, when it is not set
# there, from Verilog/fpga/local.mk (copy local.mk.example to local.mk and
# fill it in - this file reads it, so the Vivado console needs nothing
# extra). To point one console session somewhere else:
#   set ::env(ND120_BASYS3_PROJECT) {<folder holding ND3202D.xpr>}
#
# Variables this file sets (all prefixed b3_ so they cannot collide with a
# script's own names):
#   b3_here         this folder (Verilog/fpga/basys3)
#   b3_verilog_dir  the Verilog/ folder of this checkout
#   b3_logdir       Verilog/fpga/basys3/logs (created if missing; gitignored)
#   b3_project_dir  the Vivado project folder (ND120_BASYS3_PROJECT)
#   b3_output_dir   <project>/output - bitstream, probes file, reports
#   b3_routed_dcp   <project>/ND3202D.runs/impl_1/ND120_TOP_routed.dcp
#   b3_bit          <project>/output/ND120_TOP.bit
#   b3_ltx          <project>/output/ND120_TOP.ltx (ILA probes)

set b3_here        [file dirname [file normalize [info script]]]
set b3_verilog_dir [file normalize [file join $b3_here .. ..]]
set b3_logdir      [file join $b3_here logs]
file mkdir $b3_logdir

# A script started straight from the Vivado console has not been through make,
# so read Verilog/fpga/local.mk here as well. Only plain "NAME := value" lines
# for ND120_* / ND_REPOS are taken, and a value already in the environment wins.
set b3_localmk [file join $b3_here .. local.mk]
if {[file exists $b3_localmk]} {
    set _fh [open $b3_localmk r]
    foreach _line [split [read $_fh] "\n"] {
        if {[regexp {^\s*(ND120_[A-Za-z0-9_]+|ND_REPOS)\s*[:?]?=(.*)$} $_line -> _name _val]} {
            set _val [string trim $_val]
            if {![info exists ::env($_name)] || $::env($_name) eq ""} {
                set ::env($_name) $_val
            }
        }
    }
    close $_fh
    unset -nocomplain _fh _line _name _val
}

if {![info exists ::env(ND120_BASYS3_PROJECT)] || [string trim $::env(ND120_BASYS3_PROJECT)] eq ""} {
    puts "ERROR: ND120_BASYS3_PROJECT is not set."
    puts "       It must name the folder that holds the Basys3 Vivado project ND3202D.xpr."
    puts "       Copy Verilog/fpga/local.mk.example to Verilog/fpga/local.mk and set it there,"
    puts "       or set it in the environment."
    # error, not exit: exit would close a Vivado GUI session that sourced this.
    # In batch mode the uncaught error ends the run.
    error "ND120_BASYS3_PROJECT is not set - see Verilog/fpga/local.mk.example"
}

set b3_project_dir [file normalize $::env(ND120_BASYS3_PROJECT)]
set b3_output_dir  [file join $b3_project_dir output]
set b3_routed_dcp  [file join $b3_project_dir ND3202D.runs impl_1 ND120_TOP_routed.dcp]
set b3_bit         [file join $b3_output_dir ND120_TOP.bit]
set b3_ltx         [file join $b3_output_dir ND120_TOP.ltx]
