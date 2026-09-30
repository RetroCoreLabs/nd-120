# ND-120 - local settings for every Makefile that needs one.
#
# Include it from any Makefile in the tree, with the number of ../ that
# reaches the repository root, e.g. from Verilog/fpga/<board>/Makefile:
#
#   ND120_BOARD := <board>        # board Makefiles only, BEFORE the include
#   include $(dir $(abspath $(lastword $(MAKEFILE_LIST))))../../../paths.mk
#
# The rule: no machine-specific folder is written into a tracked file.
#   * Paths INSIDE the repository are worked out at run time from where the
#     script or Makefile sits.
#   * Paths OUTSIDE the repository (tool installs, the build folder, other
#     repositories) are the named variables in local.mk.example, kept in
#     local.mk at the repository root - written by configure.py, never
#     committed.
#
# Which value wins, the same rule in every reader (this file, paths.ps1,
# paths.tcl, configure.setting()):
#   make NAME=value on the command line  >  the environment  >  local.mk.
#
# What this file does:
#   1. loads local.mk (-include: a missing file is not an error by itself -
#      only a target that NEEDS a setting stops, see nd120_require);
#   2. exports the variables, so the scripts make starts can read them, and
#      names them in WSLENV - a Windows program (powershell.exe, cmd.exe)
#      started from WSL only sees the variables WSLENV lists;
#   3. when ND120_VIVADO_LICENSE is set and XILINXD_LICENSE_FILE is not,
#      passes it to Vivado as XILINXD_LICENSE_FILE;
#   4. gives every Makefile the same helpers:
#        $(call nd120_require,NAMES,what)  first line of a recipe: checks the
#                                           settings THAT target needs before
#                                           any work, stops with one message
#        $(call nd120_hostpath,PATH)       X:\... -> /mnt/x/... in WSL
#        $(call nd120_winpath,PATH)        a path as a Windows program needs it
#        $(call nd120_run,TOOL,DIR,ARGS)   run TOOL with DIR as working folder
#                                           (a Windows TOOL from WSL goes
#                                           through Verilog/fpga/run_tool.ps1)
#        ND120_BOARD_DIR                   $(ND120_BUILD_DIR)/$(ND120_BOARD)
#   5. adds a target to the Makefile that includes it (never the default):
#        make check-config   configure.py --check: what is set, what is missing

ND120_ROOT     := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
ND120_LOCAL_MK := $(ND120_ROOT)/local.mk
ND120_FPGA_DIR := $(ND120_ROOT)/Verilog/fpga

# Every name local.mk.example documents.
ND120_VARS := ND120_BUILD_DIR ND120_VIVADO ND120_VIVADO_LICENSE ND120_GOWIN \
              ND120_QUARTUS ND120_OSS_CAD_SUITE ND120_W64DEVKIT ND_REPOS \
              ND120_ILA_CSV ND120_ORACLE_DIR ND120_SIM_WSLDIR ND120_FRESH_DIR \
              ND120_BASYS3_PROJECT

# The environment wins over local.mk: remember what came from the
# environment, read local.mk, then put the environment values back. (A
# command-line value needs nothing - make already ranks it above both.)
$(foreach v,$(ND120_VARS),$(if $(filter environment%,$(origin $(v))),$(eval _nd120_env_$(v) := $$($(v)))))
-include $(ND120_LOCAL_MK)
$(foreach v,$(ND120_VARS),$(if $(_nd120_env_$(v)),$(eval $(v) := $$(_nd120_env_$(v)))))

export $(ND120_VARS)

ifneq ($(strip $(ND120_VIVADO_LICENSE)),)
XILINXD_LICENSE_FILE ?= $(ND120_VIVADO_LICENSE)
export XILINXD_LICENSE_FILE
endif

# ND120_RUN_DIR / ND120_RUN_TOOL carry nd120_run's arguments to run_tool.ps1.
_nd120_empty :=
_nd120_space := $(_nd120_empty) $(_nd120_empty)
ND120_WSLENV := $(subst $(_nd120_space),:,$(strip $(ND120_VARS))):XILINXD_LICENSE_FILE:ND120_RUN_DIR:ND120_RUN_TOOL
export WSLENV := $(if $(WSLENV),$(WSLENV):)$(ND120_WSLENV)

# ---- where am I --------------------------------------------------------------
ND120_WSL := $(shell grep -qsi microsoft /proc/version && echo 1)
ND120_PYTHON ?= $(or $(shell command -v python3 2>/dev/null),$(shell command -v python 2>/dev/null))

_nd120_drives := $(foreach d,A B C D E F G H I J K L M N O P Q R S T U V W X Y Z \
                               a b c d e f g h i j k l m n o p q r s t u v w x y z,$(d):%)

# A stored path as this shell opens it. local.mk may hold X:\... (written by
# configure.py in a Windows shell, or a Windows tool); in WSL that becomes
# /mnt/x/... Paths with spaces are not supported in make.
nd120_hostpath = $(if $(and $(ND120_WSL),$(filter $(_nd120_drives),$(1))),$(shell wslpath -u '$(1)'),$(1))

# A path as a Windows program needs it: from WSL through wslpath -w.
nd120_winpath = $(if $(and $(ND120_WSL),$(filter-out $(_nd120_drives),$(1))),$(shell wslpath -w '$(1)'),$(1))

# A Windows program: vivado.bat, gw_sh.exe, ...
nd120_is_wintool = $(filter %.bat %.BAT %.exe %.EXE %.cmd %.CMD,$(1))

# A path argument for TOOL: Windows form when TOOL is a Windows program
# started from WSL, else unchanged.
nd120_toolpath = $(if $(and $(ND120_WSL),$(call nd120_is_wintool,$(1))),$(call nd120_winpath,$(2)),$(2))

# $(call nd120_run,TOOL,DIR,ARGS): run TOOL with DIR as its working folder,
# so everything the tool writes next to itself (Vivado's vivado.log, .jou,
# .Xil) lands in the build folder. A Windows program started from WSL goes
# through run_tool.ps1 (powershell.exe), which also picks up the Windows user's
# XILINXD_LICENSE_FILE when nothing else set it.
nd120_run = $(if $(and $(ND120_WSL),$(call nd120_is_wintool,$(1))),\
	ND120_RUN_DIR='$(call nd120_winpath,$(2))' ND120_RUN_TOOL='$(1)' powershell.exe -NoProfile -ExecutionPolicy Bypass -File '$(call nd120_winpath,$(ND120_FPGA_DIR)/run_tool.ps1)' $(3),\
	cd '$(2)' && '$(1)' $(3))

# ---- the settings check ---------------------------------------------------------
# $(call nd120_require,NAMES,what): put it as the FIRST line of a recipe. It
# runs when make is about to run that recipe (also under make -n), BEFORE any
# of the target's own commands, and checks only the settings that target
# names. On a problem configure.py prints one block - which variable, what it
# is for, where local.mk is expected, the command that fixes it - and make
# stops with one line. The wording lives in configure.py (require_message) and
# is repeated word for word in paths.ps1 and paths.tcl.
#
# The values are passed as NAME=value because a $(shell) in GNU make before 4.4
# does not see what make exported (a command-line value would be missed).
nd120_require = $(if $(strip $(1)),$(_nd120_require_check))
_nd120_require_check = $(if $(ND120_PYTHON),,$(error nd-120: Python 3 is needed to check the local settings - install python3))$(if $(filter ok,$(shell $(ND120_PYTHON) '$(ND120_ROOT)/configure.py' --require $(foreach v,$(1),'$(v)=$($(v))') --for '$(2)' && echo ok)),,$(error nd-120: stopped before doing any work - see above))

# The Vivado program for the Vivado boards: make VIVADO=<program> for one run,
# else ND120_VIVADO. ND120_NEED_VIVADO is what such a target passes to
# nd120_require - nothing when VIVADO came from the command line.
VIVADO ?= $(ND120_VIVADO)
ND120_NEED_VIVADO = $(if $(filter command line,$(origin VIVADO)),,ND120_VIVADO)

ND120_BUILD_HOST = $(call nd120_hostpath,$(ND120_BUILD_DIR))
ND120_BOARD_DIR  = $(ND120_BUILD_HOST)/$(ND120_BOARD)

# ---- make check-config ---------------------------------------------------------
# Keep the including Makefile's default target: rules defined here must not
# become the default.
_nd120_default_goal := $(.DEFAULT_GOAL)

check-config:
	@$(if $(ND120_PYTHON),,echo "nd-120: Python 3 is needed - install python3" && exit 1;) '$(ND120_PYTHON)' '$(ND120_ROOT)/configure.py' --check

.PHONY: check-config

.DEFAULT_GOAL := $(_nd120_default_goal)
