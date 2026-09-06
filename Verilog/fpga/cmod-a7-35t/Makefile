# ND-120 on Cmod A7-35T - standard board-folder build API (see ../README.md)
#
#   make            build the bitstream + JTAG-program (Vivado on the Windows host)
#   make build      build only (no board needed)
#   make clean      remove build outputs
#
# Vivado path: the same install the Basys3 flow uses
# (F:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat); override with
#   make VIVADO="D:\Xilinx\...\vivado.bat"
# From a Windows shell, run the tcl directly instead:
#   cd E:\Dev\Repos\Ronny\nd-120\Verilog\fpga\cmod-a7-35t
#   vivado -mode batch -source build.tcl [-tclargs -noburn]

VIVADO ?= F:\\AMDDesignTools\\2026.1\\Vivado\\bin\\vivado.bat
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
