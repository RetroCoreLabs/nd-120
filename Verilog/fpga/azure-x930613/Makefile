# ND-120 on the Microsoft Azure FPGA card (X930613-001) - standard board-folder build API (see ../README.md)
#
# The Quartus project is nd120_azure.qpf / .qsf (file list: files.qip). It
# does not build yet, on purpose: the PCIe hard block is not generated, no
# pin is assigned, and a bitstream needs a paid Quartus Prime Standard
# licence. See docs/00-plan.md. The machine itself is tested in Verilator:
#   make -C sim all          the board blocks (iverilog)
#   make -C sim vtest        boots to OPCOM over the simulated PCIe console
#   make -C sim vtest-disk   boots a floppy image served by the PC

# `make check-config` (from paths.mk) shows the local settings, as in every
# board folder.
include $(dir $(abspath $(lastword $(MAKEFILE_LIST))))../../../paths.mk

all load flash:
	@echo "azure-x930613: no bitstream build yet - the PCIe block and pins are"
	@echo "not done, and Quartus needs a paid licence. See docs/00-plan.md."
	@echo "The machine runs in Verilator: make -C sim vtest"
	@exit 1

.PHONY: all load flash
