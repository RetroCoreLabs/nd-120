# ND-120 Vivado Lint-Only Script
# Usage: vivado -mode batch -source vivado_lint.tcl
# Much faster than full build -- just runs synthesis with the linter.
#
# Since 30-SEP-2026 (non-project flow) this is vivado_build.tcl with the lint
# flag: the same source list, include path and defines, synth_design -lint,
# then stop. Its log and .Xil land in the build folder,
# <ND120_BUILD_DIR>/basys3, like the build's.

set argv [list lint]
set argc 1
source [file join [file dirname [file normalize [info script]]] vivado_build.tcl]
