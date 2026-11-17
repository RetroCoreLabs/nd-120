# Testbenches for the Azure card (X930613-001) board blocks.
#
#   make                  build and run every testbench here
#   make test-console     the PCIe console block (nd_pcie_console)
#   make test-storage     the PC-served disk block (nd_pcie_storage) in front
#                         of the MiSTer storage backend (nd_storage_hps)
#   make test-bar         the PC path: PCIe wrapper -> window split -> blocks
#   make clean
#
# Run from WSL/Linux with iverilog on PATH. No Quartus needed.

SHELL := /bin/bash
.DELETE_ON_ERROR:

IVERILOG ?= iverilog
VVP      ?= vvp
RTL       = ../rtl
TERM      = ../../../Terminals/rtl
MISTER    = ../../mister/rtl
SDFAT     = ../../../SD-FAT/circuit

IVFLAGS = -g2012 -Wall

.PHONY: all test-console test-storage test-bar clean

all: test-console test-storage test-bar
	@echo "Azure card: all testbenches passed"

test-console: nd_pcie_console_tb.vvp
	@$(VVP) $< | tee nd_pcie_console_tb.log
	@grep -q "TB_RESULT: PASS" nd_pcie_console_tb.log || { echo "nd_pcie_console_tb FAILED"; exit 1; }

nd_pcie_console_tb.vvp: nd_pcie_console_tb.v $(RTL)/nd_pcie_console.v $(TERM)/console_uart_tx.v $(TERM)/console_uart_rx.v
	$(IVERILOG) $(IVFLAGS) -o $@ $^

test-storage: nd_pcie_storage_tb.vvp
	@$(VVP) $< | tee nd_pcie_storage_tb.log
	@grep -q "TB_RESULT: PASS" nd_pcie_storage_tb.log || { echo "nd_pcie_storage_tb FAILED"; exit 1; }

nd_pcie_storage_tb.vvp: nd_pcie_storage_tb.v pc_storage_model.v $(RTL)/nd_pcie_storage.v $(MISTER)/nd_storage_hps.v
	$(IVERILOG) $(IVFLAGS) -I$(SDFAT) -o $@ $^

# The PC's path into the board: PCIe wrapper (simulation version) -> window
# split -> both blocks.
test-bar: pcie_bar_bus_tb.vvp
	@$(VVP) $< | tee pcie_bar_bus_tb.log
	@grep -q "TB_RESULT: PASS" pcie_bar_bus_tb.log || { echo "pcie_bar_bus_tb FAILED"; exit 1; }

pcie_bar_bus_tb.vvp: pcie_bar_bus_tb.v $(RTL)/pcie_hip_wrap.v $(RTL)/pcie_bar_bus.v $(RTL)/nd_pcie_console.v $(RTL)/nd_pcie_storage.v
	$(IVERILOG) $(IVFLAGS) -DND120_AZURE_SIM_PCIE -o $@ $^

clean:
	rm -f *.vvp *.log *.vcd
