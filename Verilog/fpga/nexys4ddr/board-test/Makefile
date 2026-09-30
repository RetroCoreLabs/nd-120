# Nexys 4 DDR board check - same build API as the board folders
#
#   make        build the bitstream + JTAG-program
#   make build  build only (no board needed)
#   make clean  remove build outputs
#
# Vivado path: ND120_VIVADO from local.mk at the repository root (python3
# configure.py writes it); make VIVADO=... overrides for one run.

include $(dir $(abspath $(lastword $(MAKEFILE_LIST))))../../../../paths.mk

CMD     = cmd.exe /c

all:
	@$(call nd120_require,$(ND120_NEED_VIVADO),make all)
	$(CMD) "$(VIVADO)" -mode batch -source build.tcl

build:
	@$(call nd120_require,$(ND120_NEED_VIVADO),make build)
	$(CMD) "$(VIVADO)" -mode batch -source build.tcl -tclargs -noburn

clean:
	rm -f board_test.bit util.rpt timing.rpt vivado*.jou vivado*.log
	rm -rf .Xil

.PHONY: all build clean
