# ============================================================================
# QMTECH XC7A35T - ND-120 timing constraints
# Full path: Verilog/fpga/qmtech-a35t/nd120_timing.xdc
#
# THIS FILE IS DELIBERATELY ALMOST EMPTY. Read why before adding anything.
#
# The four CPU-side clocks are GENERATED clocks: they are created by synthesis
# from the MMCM in rtl/nd120_qmtech_top.v, so they DO NOT EXIST when this file
# is read (read_xdc runs before synth_design in build.tcl). Any `get_clocks`
# here returns empty, and a constraint built from it silently does nothing.
#
# MEASURED, 04-SEP-2026, first build of this board: this file previously held
# a `set_clock_groups -asynchronous` guarded by `get_clocks -quiet`. The guard
# found nothing, the else-branch ran, and NO clock relationship was applied at
# all. The result was two failing paths from clk_stor into clk_cpu with a
# **required time of 1.000 ns** - the tool treating two unrelated clocks as
# synchronous - for a build whose every clock domain was otherwise clean
# (clk_cpu +5.255 ns over 27698 endpoints, clk_stor +11.475 over 11113,
# clk2x +10.949 over 351). WNS -2.137 ns, and none of it real.
#
# So every clock relationship for this board lives in build.tcl, applied AFTER
# synth_design where the generated clocks exist, exactly as the Nexys does
# (fpga/nexys4ddr/build.tcl:439 onwards). Do not move them back here.
#
# The same trap in the other direction: the Tang ran for months with a .sdc
# that was one create_clock line and described no crossing at all. Its storage
# data buses were timed against a 0.000 ns requirement and were 24 of the 25
# worst setup paths in the build. Two constraint lines took that build from
# -260.076 ns over 398 endpoints to -6.489 ns over 24.
# ============================================================================

# Nothing here. See build.tcl, section "clock relationships".
