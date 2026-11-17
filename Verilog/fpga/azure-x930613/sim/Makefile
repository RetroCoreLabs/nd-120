# Testbenches for the Azure card (X930613-001) board blocks.
#
#   make                  build and run every testbench here
#   make test-console     the PCIe console block (nd_pcie_console)
#   make test-storage     the PC-served disk block (nd_pcie_storage) in front
#                         of the MiSTer storage backend (nd_storage_hps)
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

.PHONY: all test-console test-storage clean

all: test-console test-storage
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

clean:
	rm -f *.vvp *.log *.vcd
