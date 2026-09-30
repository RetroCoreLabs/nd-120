# ND-120 on Basys3 - standard board-folder build API (see ../README.md)
#
#   make              build the bitstream (FULL ~1h resynth; no programming)
#   make reuse        build reusing the last synthesized design (impl only)
#   make load         program the FPGA over JTAG (volatile)
#   make flash        program JTAG + SPI flash (persistent)
#   make lint         synthesis with -lint only
#   make check-config show the local settings and what is missing
#   make fresh-build ND120_FRESH_DIR=<empty folder>
#                     clone this commit there, configure it, run `make` (full
#                     synthesis, no programming) in the clone - proves the build
#                     needs nothing outside the repo
#
# Non-project Vivado flow (vivado_build.tcl, since 30-SEP-2026): the source
# list (nd120_basys3_sources.txt) and the constraints (nd120_basys3.xdc +
# nd120_timing.xdc) are in this folder, and EVERYTHING the build writes -
# bitstream, reports, checkpoints, copied microcode, logs, Vivado's .Xil -
# goes to $(ND120_BUILD_DIR)/basys3/.
#
# From WSL the targets go through the PowerShell wrappers (Vivado lives on
# the Windows host; the wrappers add the licence lookup, the log archive and
# the microcode check summary). On Linux without WSL they start Vivado
# directly, in the build folder. On Windows, call the .ps1 scripts directly:
#   .\vivado_build.ps1 [-ReuseSynth] [-Program] ; .\flash.ps1 [-Quick]
#
# Local settings (build folder, vivado.bat, licence) come from local.mk at the
# repository root - python3 configure.py writes it. paths.mk there loads it
# and passes the variables on to the PowerShell wrappers (through WSLENV from
# WSL). Each target checks the settings it needs first and stops with a
# message naming the missing one.

ND120_FRESH_TARGET := all
ND120_BOARD := basys3
include $(dir $(abspath $(lastword $(MAKEFILE_LIST))))../../../paths.mk

PS =powershell.exe -NoProfile -ExecutionPolicy Bypass -File

ifeq ($(ND120_WSL),1)
B3_BUILD = $(PS) vivado_build.ps1 -VivadoPath '$(VIVADO)'
B3_REUSE = $(PS) vivado_build.ps1 -ReuseSynth -VivadoPath '$(VIVADO)'
B3_LOAD  = $(PS) flash.ps1 -Quick -VivadoPath '$(VIVADO)'
B3_FLASH = $(PS) flash.ps1 -VivadoPath '$(VIVADO)'
B3_LINT  = $(PS) vivado_build.ps1 -LintOnly -VivadoPath '$(VIVADO)'
else
B3_BUILD = $(call nd120_vivado,vivado_build.tcl,full_synth skip_program)
B3_REUSE = $(call nd120_vivado,vivado_build.tcl,skip_program)
B3_LOAD  = $(call nd120_vivado,flash.tcl,jtag_only)
B3_FLASH = $(call nd120_vivado,flash.tcl,jtag_and_flash)
B3_LINT  = $(call nd120_vivado,vivado_lint.tcl)
endif

all:
	@$(call nd120_require,$(ND120_VIVADO_NEEDS),make all)
	$(B3_BUILD)

reuse:
	@$(call nd120_require,$(ND120_VIVADO_NEEDS),make reuse)
	$(B3_REUSE)

load:
	@$(call nd120_require,$(ND120_VIVADO_NEEDS),make load)
	$(B3_LOAD)

flash:
	@$(call nd120_require,$(ND120_VIVADO_NEEDS),make flash)
	$(B3_FLASH)

lint:
	@$(call nd120_require,$(ND120_VIVADO_NEEDS),make lint)
	$(B3_LINT)

# The build folder, plus logs/ that builds before 30-SEP-2026 left here.
clean:
	$(nd120_clean_board)
	rm -rf logs .Xil

.PHONY: all reuse load flash lint clean
