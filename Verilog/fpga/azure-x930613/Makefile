# ND-120 on the Microsoft Azure FPGA card (X930613-001) - standard board-folder build API (see ../README.md)
#
# The Azure card port is in the planning phase - no Quartus project exists yet.
# Placeholders so this folder answers to the same commands as every other
# board; they will delegate to a Quartus project once the PCIe host bridge
# and clocking plan land. See docs/00-plan.md.

# `make check-config` (from paths.mk) shows the local settings, as in every
# board folder.
include $(dir $(abspath $(lastword $(MAKEFILE_LIST))))../../../paths.mk

all load flash:
	@echo "azure-x930613: no build yet - the port is in the planning phase."
	@echo "See docs/00-plan.md (card facts, PCIe console blocker, open decisions)."
	@exit 1

.PHONY: all load flash
