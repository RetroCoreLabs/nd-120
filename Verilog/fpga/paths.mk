# ND-120 FPGA - local path settings, included by every board Makefile:
#
#   include $(dir $(abspath $(lastword $(MAKEFILE_LIST))))../paths.mk
#
# The rule: no machine-specific folder is written into a tracked file.
#   * Paths INSIDE the repository are worked out at run time from where the
#     script or Makefile sits.
#   * Paths OUTSIDE the repository (tool installs, the Basys3 Vivado project,
#     other repositories) are the named variables below. Each person sets them
#     in Verilog/fpga/local.mk - untracked; copy local.mk.example to start -
#     or in the environment. Under make, a value on the command line
#     (make ND120_VIVADO=...) wins over local.mk, and local.mk (:=) wins over
#     the environment.
#
# What this file does:
#   1. loads local.mk if it exists (-include: a missing file is not an error);
#   2. exports the variables, so the scripts make starts can read them;
#   3. names them in WSLENV - a Windows program (powershell.exe, cmd.exe)
#      started from WSL only sees the variables WSLENV lists;
#   4. when ND120_VIVADO_LICENSE is set and XILINXD_LICENSE_FILE is not,
#      passes it to Vivado as XILINXD_LICENSE_FILE.
#
# Tool variables left unset fall back to the tool on PATH (each Makefile says
# how). Required folders left unset make the script that needs them stop with
# an error naming the variable.

ND120_FPGA_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

-include $(ND120_FPGA_DIR)/local.mk

export ND120_VIVADO ND120_VIVADO_LICENSE ND120_GOWIN ND120_QUARTUS ND120_OSS_CAD ND120_BASYS3_PROJECT ND_REPOS

ifneq ($(strip $(ND120_VIVADO_LICENSE)),)
XILINXD_LICENSE_FILE ?= $(ND120_VIVADO_LICENSE)
export XILINXD_LICENSE_FILE
endif

ND120_WSLENV := ND120_VIVADO:ND120_VIVADO_LICENSE:ND120_GOWIN:ND120_QUARTUS:ND120_OSS_CAD:ND120_BASYS3_PROJECT:ND_REPOS:XILINXD_LICENSE_FILE
export WSLENV := $(if $(WSLENV),$(WSLENV):)$(ND120_WSLENV)
