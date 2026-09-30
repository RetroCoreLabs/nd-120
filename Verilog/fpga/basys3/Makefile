# ND-120 on Basys3 - standard board-folder build API (see ../README.md)
#
#   make            build the bitstream (FULL ~1h resynth; Vivado on the Windows host)
#   make reuse      build reusing the existing synth_1 checkpoint (impl only)
#   make load       program the FPGA over JTAG (volatile)
#   make flash      program JTAG + SPI flash (persistent)
#   make lint       run vivado_lint.tcl only
#
# Runs from WSL by delegating to the PowerShell wrappers (Vivado lives on the
# Windows host). On Windows, call the .ps1 scripts directly:
#   .\vivado_build.ps1 [-ReuseSynth] [-Program] ; .\flash.ps1 [-Quick]
#
# Local paths (Vivado project folder, vivado.bat, licence) come from
# ../local.mk - copy ../local.mk.example. ../paths.mk loads it and passes the
# variables on to the PowerShell wrappers (through WSLENV from WSL).

include $(dir $(abspath $(lastword $(MAKEFILE_LIST))))../paths.mk

PS =powershell.exe -NoProfile -ExecutionPolicy Bypass -File

all:
	$(PS) vivado_build.ps1

reuse:
	$(PS) vivado_build.ps1 -ReuseSynth

load:
	$(PS) flash.ps1 -Quick

flash:
	$(PS) flash.ps1

lint:
	$(PS) vivado_build.ps1 -LintOnly

.PHONY: all reuse load flash lint
