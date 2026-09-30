# ND-120 on Cmod A7-35T - standard board-folder build API (see ../README.md)
#
#   make            build the bitstream + JTAG-program (Vivado on the Windows host)
#   make build      build only (no board needed)
#   make clean      remove build outputs
#
# Vivado path: ND120_VIVADO from local.mk at the repository root (python3
# configure.py writes it); override for one run with
#   make VIVADO="<your Vivado install>\bin\vivado.bat"
# Each target checks the settings it needs first; make check-config shows them.
# From a Windows shell, run the tcl directly instead:
#   cd Verilog\fpga\cmod-a7-35t        (inside your checkout)
#   vivado -mode batch -source build.tcl [-tclargs -noburn]

include $(dir $(abspath $(lastword $(MAKEFILE_LIST))))../../../paths.mk

CMD     = cmd.exe /c

all:
	@$(call nd120_require,$(ND120_NEED_VIVADO),make all)
	$(CMD) "$(VIVADO)" -mode batch -source build.tcl

build:
	@$(call nd120_require,$(ND120_NEED_VIVADO),make build)
	$(CMD) "$(VIVADO)" -mode batch -source build.tcl -tclargs -noburn

clean:
	rm -f nd120_cmod.bit util.rpt timing.rpt top5_paths.rpt paths.rpt \
	      worst_paths.txt tight_setup_hold_pins.txt nd120_cmod_routed.dcp \
	      AM27256_45132L.hex AM27256_45133L.hex wcs_*.hex \
	      vivado*.jou vivado*.log build.log query.log
	rm -rf .Xil

.PHONY: all build clean
