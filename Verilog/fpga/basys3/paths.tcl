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
# The one path OUTSIDE the repository is the build folder: ND120_BUILD_DIR,
# taken from the environment or, when it is not set there, from local.mk at
# the repository root (written by configure.py; ../paths.tcl reads it, so the
# Vivado console needs nothing extra). Everything the Basys3 build writes
# goes to <ND120_BUILD_DIR>/basys3/. To point one console session somewhere
# else:
#   set ::env(ND120_BUILD_DIR) {<folder>}
#
# Since 30-SEP-2026 the Basys3 build is a non-project flow like the other
# Vivado boards: there is no Vivado project any more, and ND120_BASYS3_PROJECT
# (the old ND3202D.xpr folder) is read by nothing.
#
# Variables this file sets (all prefixed b3_ so they cannot collide with a
# script's own names):
#   b3_here         this folder (Verilog/fpga/basys3)
#   b3_verilog_dir  the Verilog/ folder of this checkout
#   b3_build_dir    <ND120_BUILD_DIR>/basys3 - every output of the build
#   b3_output_dir   the same folder (the name the older scripts use)
#   b3_logdir       <build>/logs - ILA captures and experiment reports
#   b3_synth_dcp    <build>/post_synth.dcp - the synthesized design (the
#                   checkpoint a build without full_synth starts from)
#   b3_routed_dcp   <build>/ND120_TOP_routed.dcp
#   b3_bit          <build>/ND120_TOP.bit
#   b3_ltx          <build>/ND120_TOP.ltx (ILA probes)

set b3_here        [file dirname [file normalize [info script]]]
set b3_verilog_dir [file normalize [file join $b3_here .. ..]]

# Shared helpers: reads local.mk at the repository root (the environment
# wins), and stops with the one "missing setting" message.
source [file join $b3_here .. paths.tcl]

set b3_build_dir   [nd120_board_dir basys3 "the Basys3 scripts"]
set b3_output_dir  $b3_build_dir
set b3_logdir      [file join $b3_build_dir logs]
file mkdir $b3_logdir
set b3_synth_dcp   [file join $b3_build_dir post_synth.dcp]
set b3_routed_dcp  [file join $b3_build_dir ND120_TOP_routed.dcp]
set b3_bit         [file join $b3_build_dir ND120_TOP.bit]
set b3_ltx         [file join $b3_build_dir ND120_TOP.ltx]
