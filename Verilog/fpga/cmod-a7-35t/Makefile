# ND-120 on Cmod A7-35T - standard board-folder build API (see ../README.md)
#
#   make              build the bitstream + JTAG-program (Vivado on the Windows host)
#   make build        build only (no board needed)
#   make clean        remove build outputs
#   make check-config show the local settings and what is missing
#
# Everything the build writes goes to $(ND120_BUILD_DIR)/cmod-a7-35t/ -
# bitstream, reports, routed checkpoint, the copied microcode images, and
# Vivado's own vivado.log, vivado.jou and .Xil (Vivado is started there).
#
# Vivado path: ND120_VIVADO, and the build folder: ND120_BUILD_DIR, both from
# local.mk at the repository root (python3 configure.py writes it); override
# Vivado for one run with
#   make VIVADO="<your Vivado install>\bin\vivado.bat"
# Each target checks the settings it needs first and stops with a message
# naming the missing one.
# From a Windows shell, run the tcl directly instead (it reads local.mk too):
#   vivado -mode batch -source <checkout>\Verilog\fpga\cmod-a7-35t\build.tcl [-tclargs -noburn]

ND120_BOARD := cmod-a7-35t
include $(dir $(abspath $(lastword $(MAKEFILE_LIST))))../../../paths.mk

all:
	@$(call nd120_require,$(ND120_VIVADO_NEEDS),make all)
	$(call nd120_vivado,build.tcl)

build:
	@$(call nd120_require,$(ND120_VIVADO_NEEDS),make build)
	$(call nd120_vivado,build.tcl,-noburn)

# The build folder, plus what builds from before 30-SEP-2026 left in this
# folder (they wrote here).
clean:
	$(nd120_clean_board)
	rm -f nd120_cmod.bit util.rpt timing.rpt top5_paths.rpt paths.rpt \
	      worst_paths.txt tight_setup_hold_pins.txt nd120_cmod_routed.dcp \
	      AM27256_45132L.hex AM27256_45133L.hex wcs_*.hex \
	      vivado*.jou vivado*.log build.log query.log
	rm -rf .Xil

.PHONY: all build clean
