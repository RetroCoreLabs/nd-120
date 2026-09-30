# ND-120 on Cmod A7-35T - standard board-folder build API (see ../README.md)
#
#   make            build the bitstream + JTAG-program (Vivado on the Windows host)
#   make build      build only (no board needed)
#   make clean      remove build outputs
#
# Vivado path: ND120_VIVADO from ../local.mk (copy ../local.mk.example), else
# vivado on the Windows PATH; override for one run with
#   make VIVADO="<your Vivado install>\bin\vivado.bat"
# From a Windows shell, run the tcl directly instead:
#   cd Verilog\fpga\cmod-a7-35t        (inside your checkout)
#   vivado -mode batch -source build.tcl [-tclargs -noburn]

include $(dir $(abspath $(lastword $(MAKEFILE_LIST))))../paths.mk

VIVADO ?= $(or $(ND120_VIVADO),vivado)
CMD     = cmd.exe /c

all:
	$(CMD) "$(VIVADO)" -mode batch -source build.tcl

build:
	$(CMD) "$(VIVADO)" -mode batch -source build.tcl -tclargs -noburn

clean:
	rm -f nd120_cmod.bit util.rpt timing.rpt top5_paths.rpt paths.rpt \
	      worst_paths.txt tight_setup_hold_pins.txt nd120_cmod_routed.dcp \
	      AM27256_45132L.hex AM27256_45133L.hex wcs_*.hex \
	      vivado*.jou vivado*.log build.log query.log
	rm -rf .Xil

.PHONY: all build clean
