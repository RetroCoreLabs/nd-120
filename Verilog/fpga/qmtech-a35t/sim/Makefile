# Testbenches for the QMTECH XC7A35T board's own RTL
# Full path: Verilog/fpga/qmtech-a35t/sim/Makefile
#
#   make test-storage-bram   the nd_storage region port contract
#   make                     everything here
#   make clean
#
# Registered in Verilog/tests/run_all_tests.sh - every testbench in the tree
# must be reachable from there or baselined with a reason.

IVERILOG = iverilog -g2012
RTL      = ../rtl

all: test-storage-bram

# nd_storage_bram: the region behind nd_storage's mem_* port. On this board it
# is block RAM rather than a slice of the big memory, so it is board-specific
# RTL with a protocol contract, and the contract is what this checks.
test-storage-bram: nd_storage_bram_tb.v $(RTL)/nd_storage_bram.v
	$(IVERILOG) -o tb_storage_bram nd_storage_bram_tb.v $(RTL)/nd_storage_bram.v
	vvp tb_storage_bram

clean:
	rm -f tb_storage_bram *.vcd

.PHONY: all test-storage-bram clean
