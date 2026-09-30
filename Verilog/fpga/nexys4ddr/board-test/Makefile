# Nexys 4 DDR board check - same build API as the board folders
#
#   make        build the bitstream + JTAG-program
#   make build  build only (no board needed)
#   make clean  remove build outputs
#
# Everything the build writes goes to $(ND120_BUILD_DIR)/nexys4ddr/board-test/
# (Vivado is started there, so its log, journal and .Xil land there too).
# Vivado path: ND120_VIVADO, build folder: ND120_BUILD_DIR, both from local.mk
# at the repository root (python3 configure.py writes it); make VIVADO=...
# overrides Vivado for one run.

ND120_FRESH_TARGET := build
ND120_BOARD := nexys4ddr/board-test
include $(dir $(abspath $(lastword $(MAKEFILE_LIST))))../../../../paths.mk

all:
	@$(call nd120_require,$(ND120_VIVADO_NEEDS),make all)
	$(call nd120_vivado,build.tcl)

build:
	@$(call nd120_require,$(ND120_VIVADO_NEEDS),make build)
	$(call nd120_vivado,build.tcl,-noburn)

# The build folder, plus what builds from before 30-SEP-2026 left here.
clean:
	$(nd120_clean_board)
	rm -f board_test.bit util.rpt timing.rpt vivado*.jou vivado*.log
	rm -rf .Xil

.PHONY: all build clean
