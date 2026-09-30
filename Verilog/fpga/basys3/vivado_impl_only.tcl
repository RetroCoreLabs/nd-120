# Quick rebuild: implementation + bitstream + JTAG + flash (skips synthesis)
# Usage: vivado -mode batch -source vivado_impl_only.tcl
#
# Since 30-SEP-2026 (non-project flow) this is vivado_build.tcl without
# full_synth: it opens the last synthesized design (<build>/post_synth.dcp,
# written by a full_synth run), implements it, writes the bitstream and
# programs JTAG + SPI flash - what this script did against the old project.
# Everything lands in the build folder, <ND120_BUILD_DIR>/basys3.

set argv [list]
set argc 0
source [file join [file dirname [file normalize [info script]]] vivado_build.tcl]
