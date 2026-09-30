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
#   5. adds targets to the Makefile that includes it (never the default):
#        make check-config   configure.py --check: what is set, what is missing
#        make fresh-build    (board Makefiles) clone the current commit into
#                            ND120_FRESH_DIR, configure it, build it there

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

# ---- the build folder ------------------------------------------------------------
# Every board writes EVERYTHING - bitstream, reports, timing-analysis runs,
# checkpoints, copied microcode, and the tool's own log, journal and .Xil -
# to $(ND120_BUILD_DIR)/<board>/. There is no default: a board target names
# ND120_BUILD_DIR in its nd120_require line and stops when it is not set.
ND120_BUILD_HOST = $(call nd120_hostpath,$(ND120_BUILD_DIR))
ND120_BOARD_DIR  = $(ND120_BUILD_HOST)/$(ND120_BOARD)

# What every Vivado board target needs.
ND120_VIVADO_NEEDS = $(ND120_NEED_VIVADO) ND120_BUILD_DIR

# $(call nd120_vivado,TCL,TCLARGS): Vivado in batch mode on TCL (a file in the
# board folder), started IN the board's build folder, so vivado.log,
# vivado.jou and .Xil land there too.
nd120_vivado = $(call nd120_run,$(VIVADO),$(ND120_BOARD_DIR),-mode batch -source '$(call nd120_toolpath,$(VIVADO),$(abspath $(1)))' -log vivado.log -journal vivado.jou$(if $(strip $(2)), -tclargs $(2)))

# make clean: the board's build folder, when ND120_BUILD_DIR is set.
nd120_clean_board = $(if $(strip $(ND120_BUILD_DIR)),rm -rf '$(ND120_BOARD_DIR)',@echo "ND120_BUILD_DIR is not set - no build folder to remove")

# ---- make check-config ---------------------------------------------------------
# Keep the including Makefile's default target: rules defined here must not
# become the default.
_nd120_default_goal := $(.DEFAULT_GOAL)

check-config:
	@$(if $(ND120_PYTHON),,echo "nd-120: Python 3 is needed - install python3" && exit 1;) '$(ND120_PYTHON)' '$(ND120_ROOT)/configure.py' --check

# ---- make fresh-build (board Makefiles) -------------------------------------------
# Proves a board builds from nothing but the repository. It clones the
# CURRENT COMMIT (uncommitted edits are NOT included - commit first) into the
# empty folder ND120_FRESH_DIR, runs configure.py there non-interactively
# with the same tool settings (Vivado, Gowin, Quartus, oss-cad-suite,
# w64devkit, licence) but a build folder INSIDE the clone, then runs this
# board's build target in the clone. Never runs by itself.
#   make fresh-build ND120_FRESH_DIR=<empty folder, absolute path>
# A board Makefile sets ND120_FRESH_TARGET (before including this file) to
# its build-only target; ND120_FRESH_ARGS passes extra make arguments to it,
# e.g. make fresh-build ND120_FRESH_DIR=... ND120_FRESH_ARGS="CLK=33".
# The folder must be one the build tools can reach: on a Windows drive for
# Vivado/Gowin started from WSL (the clone's own settings check says so).
# configure.py in the clone runs git submodule update --init, so the
# submodules are fetched from their remotes; ND120_FRESH_CONFIGURE_ARGS adds
# arguments to that configure.py run (e.g. --skip-submodules for a board that
# needs none - only the MEGA65 build uses the m2m submodule).
ifneq ($(strip $(ND120_BOARD)),)
ND120_FRESH_TARGET ?= all
ND120_FRESH_REL    := $(patsubst $(ND120_ROOT)/%,%,$(CURDIR))
ND120_FRESH_HOST    = $(call nd120_hostpath,$(ND120_FRESH_DIR))
# The inner make is named through this variable, not as $(MAKE) in the
# recipe: GNU make RUNS a line that names $(MAKE) even under make -n, and a
# dry run must not start a build in a clone the dry run never made.
_nd120_submake = $(MAKE)

fresh-build:
	@$(call nd120_require,ND120_FRESH_DIR,make fresh-build)
	@case '$(ND120_FRESH_HOST)' in /*) ;; *) \
	  echo "nd-120: ND120_FRESH_DIR must be an absolute path (got '$(ND120_FRESH_DIR)')."; exit 1;; esac
	@case '$(ND120_FRESH_HOST)/' in '$(ND120_ROOT)'/*) \
	  echo "nd-120: ND120_FRESH_DIR is inside this checkout - pick a folder outside it."; exit 1;; esac
	@test -z "$$(ls -A '$(ND120_FRESH_HOST)' 2>/dev/null)" || { \
	  echo "nd-120: ND120_FRESH_DIR ($(ND120_FRESH_DIR)) is not empty - fresh-build needs an empty folder."; exit 1; }
	@test -z "$$(git -C '$(ND120_ROOT)' status --porcelain --untracked-files=no)" || \
	  echo "nd-120: NOTE - this checkout has uncommitted changes; they are NOT in the clone."
	sha=$$(git -C '$(ND120_ROOT)' rev-parse HEAD) && \
	  echo "== fresh-build: cloning commit $$sha into $(ND120_FRESH_HOST)" && \
	  git clone --quiet --no-checkout '$(ND120_ROOT)' '$(ND120_FRESH_HOST)' && \
	  git -C '$(ND120_FRESH_HOST)' checkout --quiet --detach "$$sha"
	cd '$(ND120_FRESH_HOST)' && env -u ND120_BUILD_DIR -u ND120_FRESH_DIR '$(ND120_PYTHON)' configure.py --non-interactive $(ND120_FRESH_CONFIGURE_ARGS) \
	  --set 'ND120_BUILD_DIR=$(ND120_FRESH_HOST)/build' \
	  $(foreach v,ND120_VIVADO ND120_VIVADO_LICENSE ND120_GOWIN ND120_QUARTUS ND120_OSS_CAD_SUITE ND120_W64DEVKIT,$(if $($(v)),--set '$(v)=$($(v))'))
	env -u ND120_BUILD_DIR -u ND120_FRESH_DIR $(_nd120_submake) -C '$(ND120_FRESH_HOST)/$(ND120_FRESH_REL)' $(ND120_FRESH_TARGET) $(ND120_FRESH_ARGS)
	@echo "== fresh-build: done - the output is in $(ND120_FRESH_HOST)/build/$(ND120_BOARD)/"

.PHONY: fresh-build
endif

.PHONY: check-config

.DEFAULT_GOAL := $(_nd120_default_goal)
