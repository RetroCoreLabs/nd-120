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
# folder holding ND3202D.xpr). It comes from ND120_BASYS3_PROJECT, taken from
# the environment or, when it is not set there, from local.mk at the
# repository root (written by configure.py; ../paths.tcl reads it, so the
# Vivado console needs nothing extra). To point one console session
# somewhere else:
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

# Shared helpers: reads local.mk at the repository root (the environment
# wins), and stops with the one "missing setting" message.
source [file join $b3_here .. paths.tcl]

nd120_require ND120_BASYS3_PROJECT "the Basys3 scripts"

set b3_project_dir [file normalize [nd120_host_path [nd120_setting ND120_BASYS3_PROJECT]]]
set b3_output_dir  [file join $b3_project_dir output]
set b3_routed_dcp  [file join $b3_project_dir ND3202D.runs impl_1 ND120_TOP_routed.dcp]
set b3_bit         [file join $b3_output_dir ND120_TOP.bit]
set b3_ltx         [file join $b3_output_dir ND120_TOP.ltx]
