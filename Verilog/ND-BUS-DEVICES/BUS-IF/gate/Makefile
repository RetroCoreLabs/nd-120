# ND-BUS SEAM GATE - the authoritative Verilog seam (ND_BUS_SLAVE.v) driven
# against the REAL portable C device cores, in Verilator. No CPU, no hardware.
# Prints "TB_RESULT: PASS" so it slots into the machine-checkable test convention.
#
#   make            - verilate + build + run the gate
#   make clean
#
# Toolchain: a normal `verilator` on PATH (WSL/Linux). On the Windows oss-cad-
# suite the perl `verilator` wrapper is broken - use the real binary + its
# bundled python + w64devkit gcc (ND120_OSS_CAD_SUITE and ND120_W64DEVKIT name
# the folders those two are installed in; ND_REPOS the folder that holds the
# other ND checkouts):
#   export VERILATOR_ROOT=$ND120_OSS_CAD_SUITE/share/verilator
#   export PATH="$ND120_OSS_CAD_SUITE/lib:$ND120_W64DEVKIT/bin:$ND120_OSS_CAD_SUITE/bin:$PATH"
#   make VERILATOR=verilator_bin.exe NDDEVICECORE=$ND_REPOS/NDModulE/lib/NDDeviceCore

VERILATOR ?= verilator

# The portable C device cores. INTENDED to be the nd-120 submodule at
# Verilog/ND-BUS-DEVICES/portable once it is wired; until then override to the
# populated NDModulE copy (see the header above).
NDDEVICECORE ?= ../../portable

RTL   := ../circuit/ND_BUS_SLAVE.v
CORES := $(NDDEVICECORE)/src/nd_device.c \
         $(NDDEVICECORE)/src/nd_char.c \
         $(NDDEVICECORE)/src/nd_lineprinter.c

.PHONY: test clean
test:
	$(VERILATOR) --cc --exe --build -j 4 \
	  -CFLAGS "-I$(NDDEVICECORE)/include" \
	  --top-module ND_BUS_SLAVE $(RTL) \
	  nd_bus_gate.cpp $(CORES) -o nd_bus_gate
	./obj_dir/nd_bus_gate

clean:
	rm -rf obj_dir
