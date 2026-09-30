# ND-120 on QMTECH XC7A35T - standard board-folder build API (see ../README.md)
#
#   make                   build the full ND-120 bitstream (no board needed)
#   make load              build + program over JTAG (volatile; Platform Cable USB II)
#   make flash             (not implemented yet - no SPI-flash flow for this board)
#   make test              build a stage test bitstream: TEST=led-test|mem-test
#   make test-load         ...and program it
#   make sim               run the mem-test iverilog testbench
#   make lint              Verilator lint of the full design (fast, no Vivado)
#   make clean             remove generated bitstreams/reports
#   make check-config      show the local settings and what is missing
#   make fresh-build ND120_FRESH_DIR=<empty folder>
#                          clone this commit there, configure it, run `make` in
#                          the clone - proves the build needs nothing outside the repo
#
# The full build (build.tcl in this directory) was written 04-SEP-2026 and has
# NEVER BEEN RUN. The two stage tests predate it and have never run on the
# board either - see HANDOFF-qmtech-a35t-bringup.md.
#
# Vivado runs on the Windows host; from WSL this delegates via powershell.exe.
# Everything the builds write goes to $(ND120_BUILD_DIR)/qmtech-a35t/ (the stage
# tests to .../qmtech-a35t/<test>/), and Vivado is started there.
# Vivado path: ND120_VIVADO, build folder: ND120_BUILD_DIR, both from local.mk
# at the repository root (python3 configure.py writes it); each target checks
# them first. On Windows, run the tcl directly (it reads local.mk too):
#   vivado -mode batch -source <checkout>\Verilog\fpga\qmtech-a35t\build.tcl [-tclargs -noburn]

ND120_BOARD := qmtech-a35t
include $(dir $(abspath $(lastword $(MAKEFILE_LIST))))../../../paths.mk

TEST = mem-test

# A stage test's build.tcl, started in <build>/qmtech-a35t/<test>.
qm_test = $(call nd120_run,$(VIVADO),$(ND120_BOARD_DIR)/$(TEST),-mode batch -source '$(call nd120_toolpath,$(VIVADO),$(CURDIR)/$(TEST)/build.tcl)' -log vivado.log -journal vivado.jou$(if $(1), -tclargs $(1)))

# ---- full ND-120 build -----------------------------------------------------
all:
	@$(call nd120_require,$(ND120_VIVADO_NEEDS),make all)
	$(call nd120_vivado,build.tcl,-noburn)

load:
	@$(call nd120_require,$(ND120_VIVADO_NEEDS),make load)
	$(call nd120_vivado,build.tcl)

flash:
	@echo "flash: not implemented for qmtech-a35t yet (JTAG-volatile only;"
	@echo "       add an .mcs/SPI flow against the N25Q064A when wanted)"; exit 1

# ---- Verilator lint --------------------------------------------------------
# Catches the syntax, connectivity and width errors that would otherwise cost
# a Vivado elaboration pass. Verilator must come from WSL: the oss-cad-suite
# verilator on the Git Bash PATH is broken on this machine.
#
# Two files are named explicitly rather than found through -y:
#   rtl/lint_stubs.v          hollow MMCME2_BASE and BUFG. Verilator has no
#                             UNISIM library, and without these it stops at
#                             the clocking and never reaches the CPU. NOT in
#                             build.tcl - Vivado must use the real primitives.
#   SD-FAT/circuit/nds_sync.v holds modules nds_sync_pulse and nds_sync_level,
#                             neither of which matches the file name, so -y
#                             (which searches by file name) cannot find them.
#
# Clean result as of 04-SEP-2026: 0 errors, 281 modules, no warning in any
# file of this board's own.
lint:
	verilator --lint-only -Wno-fatal \
	    --top-module nd120_qmtech_top \
	    +define+FPGA_FF_MODE \
	    +define+MAIN_RAM_SDRAM +define+ND_SDRAM_PACK16 +define+ND_SDRAM_DQ16 \
	    +define+ND_SDRAM_REFRESH_US=7 \
	    +define+ND_STORAGE_NO_CACHE +define+ND_STORAGE_DISCS_UNCACHED \
	    +define+SDFAT_NO_LFN +define+ND120_PANEL_CLOCK +define+SKIP_WCS_LOAD \
	    +define+BOARD_CLK_FREQ=20000000 +define+UART_BAUD_RATE=115200 \
	    -I../../SD-FAT/circuit -I../../Shared/support \
	    -y rtl -y ../.. \
	    -y ../../CPU-BOARD-3202/circuit -y ../../DECODE-GateArray/DGA/circuit \
	    -y ../../DELILAH-CPU/CGA/circuit -y ../../DELILAH-CPU/CGA_ALU/circuit \
	    -y ../../DELILAH-CPU/CGA_DCD/circuit -y ../../DELILAH-CPU/CGA_IDBCTL/circuit \
	    -y ../../DELILAH-CPU/CGA_INTR/circuit -y ../../DELILAH-CPU/CGA_MAC/circuit \
	    -y ../../DELILAH-CPU/CGA_MIC/circuit -y ../../DELILAH-CPU/CGA_TESTMUX/circuit \
	    -y ../../DELILAH-CPU/CGA_TRAP/circuit -y ../../DELILAH-CPU/CGA_WRF/circuit \
	    -y ../../ND-BUS-DEVICES/BUS-IF/circuit -y ../../ND-BUS-DEVICES/DMA/circuit \
	    -y ../../ND-BUS-DEVICES/FLOPPY-DMA/circuit -y ../../ND-BUS-DEVICES/SMD/circuit \
	    -y ../../ND-BUS-DEVICES/TAPE-400/circuit -y ../../ND-BUS-DEVICES/WINCHESTER/circuit \
	    -y ../../PAL -y ../../SD-FAT/circuit \
	    -y ../../Shared/logisim -y ../../Shared/ndlib -y ../../Shared/support \
	    -y ../tang-nano-20k/sdram-bridge \
	    rtl/lint_stubs.v ../../SD-FAT/circuit/nds_sync.v rtl/nd120_qmtech_top.v

# ---- stage tests (led-test, mem-test) --------------------------------------
test:
	@$(call nd120_require,$(ND120_VIVADO_NEEDS),make test)
	$(call qm_test,skip_program)

test-load:
	@$(call nd120_require,$(ND120_VIVADO_NEEDS),make test-load)
	$(call qm_test)

sim:
	cd mem-test/sim && iverilog -g2012 -DNO_MMCM -o tb qmtech_mem_test_tb.v \
	    ../qmtech_mem_test_top.v \
	    ../../../basys3/mem-test/msg_printer.v \
	    ../../../basys3/mem-test/uart_tx.v \
	    ../../../../CPU-BOARD-3202/circuit/MEM_RAM_49.v \
	    ../../../../Shared/support/SIP1M9.v && vvp tb

# The build folder, plus what builds from before 30-SEP-2026 left here.
clean:
	$(nd120_clean_board)
	rm -f nd120_qmtech.bit util.rpt util_synth.rpt timing.rpt \
	      wcs_*.hex AM27256_4513*.hex vivado*.jou vivado*.log build.log
	rm -f led-test/*.bit led-test/*.rpt mem-test/*.bit mem-test/*.rpt \
	      mem-test/sim/tb mem-test/sim/*.vcd
	rm -rf .Xil led-test/.Xil mem-test/.Xil

.PHONY: all load flash lint test test-load sim clean
