# ND-120 FPGA timing constraints
# Read by vivado_build.tcl AFTER synthesis and AFTER nd120_basys3.xdc (the
# pin/clock XDC), so the primary clock 'sys_clk' already exists. (Until
# 30-SEP-2026 the script added it to a Vivado project's constraint set,
# implementation-only, PROCESSING_ORDER LATE - the same order.)
#
# Clock architecture (see ND120_TOP.v, 2026-07-06):
#   sys_clk  = 100 MHz Basys3 pin. Clocks ONLY the POR, 7-seg display, heartbeat
#              counter, and the ILA / debug hub.
#   clk_cpu  = MMCM CLKOUT0 (~16.67 MHz). Clocks the ENTIRE ND-120 CPU + bus core
#              (also feeds CLOCK_1/CLOCK_2 / the OSC inputs).
#
# As of 2026-07-06 the POR (clk_cpu) and ILA/dbg_hub (clk_cpu) were moved into the
# CPU domain, so the ONLY remaining crossing is CPU state -> 7-seg display (pure
# observation, human-readable, timing-irrelevant). Declaring the two domains
# asynchronous makes that crossing a non-timed path.
#
# Reference clocks BY NAME: the earlier '-of_objects [get_pins .../CLKOUT0]' form
# returned an empty object at constraint-eval time, so the group silently never
# applied. The MMCM CLKOUT0 net is clk_cpu_pre, which Vivado auto-derives as the
# generated clock named 'clk_cpu_pre'.
set_clock_groups -asynchronous \
  -group [get_clocks sys_clk] \
  -group [get_clocks clk_cpu_pre]
