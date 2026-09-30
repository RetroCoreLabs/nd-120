# ND-120 on MEGA65 (R3/R4/R5/R6) - standard board-folder build API (see ../README.md)
#
#   make all BOARD=r6      # firmware ROM, Vivado -> <build>/r6/nd120_mega65_r6.bit, then the .cor
#   make all BOARD=r3
#   make cor BOARD=r6      # just pack an existing .bit into <build>/r6/nd120_mega65_r6.cor
#   make rom               # just the QNICE firmware (CORE/m2m-rom/m2m-rom.rom)
#   make toolchain         # one-off: qasm/qasm2rom + monitor.rom in the submodule, coretool (fetched)
#   make fresh-build ND120_FRESH_DIR=<empty folder> [ND120_FRESH_ARGS="BOARD=r3"]
#                          # clone this commit there, configure it, `make toolchain all`
#                          # in the clone - proves the build
#                          # needs nothing outside the repo
#
# Run from WSL (bash + gcc for the QNICE toolchain, python3 for coretool;
# Vivado is reached through cmd.exe interop). There is no MEGA65 on this
# desk, so `load`/`flash` do not exist as actions: the deliverable is the
# .cor a friend copies to an SD card and flashes from the MEGA65's own menu.
#
# <build> is $(ND120_BUILD_DIR)/mega65: EVERY Vivado output - .bit, .cor,
# reports, timing-analysis runs, checkpoints, the banner stamp, and Vivado's
# own log and .Xil (it is started there) - goes there, per revision.
# Still written inside the checkout: the QNICE firmware ROM
# (CORE/m2m-rom/m2m-rom.rom, built by the framework's make_rom.sh in place)
# and the one-off host tools (make toolchain: qasm in the submodule, coretool
# in tools/). All three are gitignored.
#
# Vivado path: make VIVADO=..., else ND120_VIVADO; build folder:
# ND120_BUILD_DIR; both from local.mk at the repository root (python3
# configure.py writes it). The framework's own
# projects were written by 2022.2 (m2m/CORE/CORE-R6.xpr) - build.tcl reads
# the sources directly and never opens those projects.

ND120_FRESH_TARGET := toolchain all
ND120_BOARD := mega65
include $(dir $(abspath $(lastword $(MAKEFILE_LIST))))../../../paths.mk

BOARD  ?= r6
OUT     = $(ND120_BOARD_DIR)/$(BOARD)
QNICE   = m2m/M2M/QNICE

# The .cor packer: MEGA65's `coretool` (mega65-tools, GPL-3.0 - fetched, not
# vendored, into the gitignored tools/). It writes the hardware-model byte the
# MEGA65 flash menu checks ("Core hardware model mismatch!" otherwise) and
# knows mega65r5/r6; the older `bit2core` C tool in the QNICE submodule does
# not. Pinned to a commit so a rebuild packs the same header.
CORETOOL_COMMIT = 7cbc0fc8bf5c5f8302f1e428010c51e42bb1e03d
CORETOOL_URL    = https://raw.githubusercontent.com/MEGA65/mega65-tools/$(CORETOOL_COMMIT)/src/tools/coretool
CORETOOL        = tools/coretool.py

# Name/version stamped into the .cor header (shown in the MEGA65 flash menu).
# The version is the SAME stamp build.tcl put in the on-screen banner (git
# hash + date, written to <build>/<board>/banner_stamp.txt at synthesis), so
# the flash menu and the banner always name the same build. HEAD at packing
# time is not that: another session's commit landed between synthesis and
# packing on 02-SEP-2026 and the first .cor named a build it was not.
CORE_NAME  ?= ND-120 SINTRAN III
CORE_VER   ?= $(shell cat '$(OUT)/banner_stamp.txt' 2>/dev/null || echo unknown)

# The settings are checked before the firmware ROM is built.
all: check-settings-vivado rom
	@mkdir -p '$(OUT)'
	$(call nd120_run,$(VIVADO),$(OUT),-mode batch -source '$(call nd120_toolpath,$(VIVADO),$(CURDIR)/build.tcl)' -log vivado.log -nojournal -tclargs board $(BOARD))
	$(MAKE) cor BOARD=$(BOARD)

check-settings-vivado:
	@$(call nd120_require,$(ND120_VIVADO_NEEDS),make all)
	@test -f $(QNICE)/assembler/qasm.c || { \
	  echo "nd-120: the MiSTer2MEGA65 submodule (Verilog/fpga/mega65/m2m) is not checked out."; \
	  echo "  Fix: from the repository root run   python3 configure.py   (it runs git submodule update --init)"; exit 1; }

check-settings-cor:
	@$(call nd120_require,ND120_BUILD_DIR,make cor)

# Pack the bitstream for the chosen revision. --target names the model byte;
# coretool also checks the FPGA part inside the .bit against it.
cor: check-settings-cor $(OUT)/nd120_mega65_$(BOARD).cor

$(OUT)/nd120_mega65_$(BOARD).cor: $(OUT)/nd120_mega65_$(BOARD).bit $(CORETOOL)
	python3 $(CORETOOL) --build $@ --force --target mega65$(BOARD) \
		--bit $< --bit-name "$(CORE_NAME)" --bit-version "$(CORE_VER)"
	python3 $(CORETOOL) --verify $@

# The M2M "Shell" firmware for the QNICE soft CPU, baked into the bitstream
# (CORE/vhdl/globals.vhd: QNICE_FIRMWARE_M2M). Regenerated whenever the
# assembly source or the vdrive/ROM counts in globals.vhd change.
rom: CORE/m2m-rom/m2m-rom.rom

CORE/m2m-rom/m2m-rom.rom: CORE/m2m-rom/m2m-rom.asm CORE/vhdl/globals.vhd $(QNICE)/assembler/qasm
	cd CORE/m2m-rom && bash ./make_rom.sh

# One-off host tools. The framework's make-toolchain.sh also builds a C
# compiler and an emulator we do not need.
toolchain: $(QNICE)/assembler/qasm $(QNICE)/monitor/monitor.rom $(CORETOOL)

$(QNICE)/assembler/qasm: $(QNICE)/assembler/qasm.c $(QNICE)/assembler/qasm2rom.c
	cd $(QNICE) && gcc assembler/qasm.c -o assembler/qasm && gcc assembler/qasm2rom.c -o assembler/qasm2rom -std=c99

$(QNICE)/monitor/monitor.rom: $(QNICE)/assembler/qasm
	cd $(QNICE)/monitor && bash ./compile_and_distribute.sh

$(CORETOOL):
	@mkdir -p tools
	curl -sSL -o $@ $(CORETOOL_URL)
	@grep -q "MEGA65target(\"mega65r6\"" $@ || { echo "coretool download looks wrong"; rm -f $@; exit 1; }
	@echo "coretool fetched from mega65-tools @ $(CORETOOL_COMMIT)"

# "flash load:" and not "load flash:" - a line starting with `load` is GNU
# make's directive for loading a shared object, and it says so in a way that
# takes a minute to decode ("flash:: cannot open shared object file").
flash load:
	@echo "mega65: no board here - nothing to load. Build with 'make all BOARD=r6' and send the .cor."
	@exit 1

# The build folder, plus build/ here from builds before 30-SEP-2026.
clean:
	$(nd120_clean_board)
	rm -rf build

.PHONY: all cor rom toolchain load flash clean check-settings-vivado check-settings-cor
