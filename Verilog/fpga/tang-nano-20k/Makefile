# ND-120 on Tang Nano 20K - DUAL-TOOLCHAIN build (see README.md "Two build flows")
#
# Gowin EDA (gw_sh on the Windows host via gowin_build.ps1) is the flow that
#   builds the full-CPU bitstream today - every variant incl. fast20, and the
#   released Tang bitstreams.
# OSS CAD Suite (yosys + nextpnr-himbaechel + gowin_pack), Linux/WSL, built
#   the full CPU on 12-JUL-2026 but no longer places it: with the storage
#   stack in, synthesis needs 22254-22626 LUT4 of 20736 (107-109%, measured
#   28-SEP-2026 with the CI's oss-cad-suite). `make check` (netlist gates)
#   still runs on it, in CI too. See README.md "Two build flows".
#
# Both flows compile the SAME ordered file list (nd120_tang20k.gprj) with the
# SAME defines file first (src/tang20k_defines.v) - one source of truth.
#
#   make [VARIANT=slow|crawl|full]   OSS bitstream -> build/nd120_tang20k_oss-<variant>.fs
#   make check [VARIANT=...]         netlist gates: IO_sdram_dq tristate + latch census
#   make load / flash [VARIANT=...]  program the OSS bitstream (SRAM / config flash)
#
#   make gowin [VARIANT=...]         Gowin bitstream via powershell gowin_build.ps1
#   make load-gowin / flash-gowin    program the Gowin bitstream
#
#   make sim                         iverilog unit tbs (sdram-bridge + sdram-test)
#   make clean                       remove build/
#
# VARIANT selects the clocking (default slow, same as always):
#   slow  = CPU 6.75 MHz / SDRAM 13.5 MHz  (TANG_SLOW_BRINGUP)
#   crawl = CPU 3.375 MHz / SDRAM 6.75 MHz (TANG_CRAWL_BRINGUP, mechanism probe)
#   full  = CPU 27 MHz / SDRAM 54 MHz      (target speed; needs timing closure)
# Selection is via TANG_VARIANT_* pre-defines consumed by src/tang20k_defines.v
# - no file editing, both toolchains use the same mechanism.

# Local settings (ND120_GOWIN for `make gowin`, ND120_OSS_CAD_SUITE for the
# OSS flow) come from local.mk at the repository root - python3 configure.py
# writes it. paths.mk loads it and passes it on to gowin_build.ps1 (through
# WSLENV from WSL). `make check-config` shows every setting.
include $(dir $(abspath $(lastword $(MAKEFILE_LIST))))../../../paths.mk

# auto-add the oss-cad-suite tools to PATH when present: ND120_OSS_CAD_SUITE
# (local.mk), else the default install folder ~/oss-cad-suite. make OSS_CAD=...
# still overrides both for one run. When none of them exists the tools come
# from PATH (the CI runner installs yosys that way).
OSS_CAD ?= $(or $(call nd120_hostpath,$(ND120_OSS_CAD_SUITE)),$(HOME)/oss-cad-suite)
ifneq ($(wildcard $(OSS_CAD)/bin),)
export PATH := $(OSS_CAD)/bin:$(PATH)
endif

# bash for 'set -o pipefail' (the PnR rule needs it - see there); and
# .DELETE_ON_ERROR so a failed recipe never leaves a half-written artifact
# behind for the next run to mistake for a good one.
SHELL := /bin/bash
.DELETE_ON_ERROR:

TOP    = ND120_TANG20K_TOP
DEVICE = GW2AR-LV18QN88C8/I7
FAMILY = GW2A-18C
BOARD  = tangnano20k
BUILD  = build
GPRJ   = nd120_tang20k.gprj

VARIANT ?= slow
ifeq ($(VARIANT),slow)
  VDEFS =
else ifeq ($(VARIANT),crawl)
  VDEFS = -DTANG_VARIANT_CRAWL
else ifeq ($(VARIANT),full)
  VDEFS = -DTANG_VARIANT_FULL
else
  $(error VARIANT must be slow, crawl or full)
endif

# CACHE: 0 (default) = CPU cache compiled out (src/tang20k_defines.v defines
# ND120_NO_CACHE - that file stays the default-off authority). CACHE=1
# pre-defines ND120_FORCE_CACHE, which suppresses ND120_NO_CACHE so the five
# cache memories + used-bit PAL are synthesized. WARNING: this does not
# currently fit the GW2AR-18 - a live cache needs 28330 logic cells against
# the part's 20736 (measured 25-AUG-2026). The knob exists so the cache
# option is symmetric across every build flow and so anyone attacking the
# fit problem has it. Same mechanism as gowin_build.ps1 -Cache.
CACHE ?= 0
ifeq ($(CACHE),1)
  VDEFS += -DND120_FORCE_CACHE
endif

# One source of truth: the ordered .v list from the Gowin project file
# (src/tang20k_defines.v is first; yosys keeps `defines across a single
# read_verilog file list, same as the Gowin ordered compilation unit).
SRCS := $(shell grep -o '<File path="[^"]*"' $(GPRJ) | sed 's/<File path="//;s/"//' | grep '\.v$$')

# The SD-FAT sources `include "sd_fat_features.vh" - give yosys the path.
# (Gowin EDA resolves includes from the file list's own directories.)
# Shared/support holds nd120_backwiring_defaults.vh, included by BOTH
# BACKWIRING_PROM.v (same dir) and ND120_CORE.v (Verilog root) - the latter is
# why the path has to be explicit here.
INCS = -I../../SD-FAT/circuit -I../../Shared/support

OSS_BASE  = $(BUILD)/nd120_tang20k_oss-$(VARIANT)
FS_OSS    = $(OSS_BASE).fs
FS_GOWIN  = $(BUILD)/nd120_tang20k_build/impl/pnr/nd120_tang20k_build.fs

PS = powershell.exe -NoProfile -ExecutionPolicy Bypass -File

all: $(FS_OSS)

$(BUILD):
	mkdir -p $(BUILD)

# WCS preload: $readmemh("wcs_XXC.hex") resolves against the yosys cwd (this
# dir). The canonical source is Code/Microcode/wcs; refresh local copies.
wcs-hex:
	@test -f ../../../Code/Microcode/wcs/wcs_16C.hex || { \
	  echo "WCS preload images missing - run Code/Microcode/gen_wcs_image.py"; exit 1; }
	@cp -u ../../../Code/Microcode/wcs/wcs_*.hex .

# ---- OSS flow: yosys -> nextpnr-himbaechel -> gowin_pack -------------------
# attrmap -remove init: GW2A FFs power up per their SET/RESET type; Gowin
# EDA effectively ignores conflicting `reg = ...` initializers, but yosys
# dfflegalize HARD-ERRORS on init != async-set value. Stripping FF init
# attributes (memory $readmemh contents are $meminit cells - unaffected)
# reproduces the silicon/vendor behavior. Power-up-0 logic (the POR chain)
# matches the GW2A default FF state, so nothing depends on the inits.
$(OSS_BASE).json: $(SRCS) $(GPRJ) | $(BUILD)
	$(MAKE) wcs-hex
	yosys -l $(OSS_BASE)-synth.log -p "read_verilog $(INCS) $(VDEFS) $(SRCS); hierarchy -top $(TOP); proc; attrmap -remove init; synth_gowin -top $(TOP) -json $@"

# package pins + SDRAM pseudo-pins (nextpnr does not auto-connect the
# embedded SDRAM the way Gowin EDA does - same trick as sdram-test)
$(BUILD)/oss.cst: src/nd120_tang20k.cst sdram-test/src/sdram_pins_oss.cst | $(BUILD)
	cat $^ > $@

# 'rm -f $@' + pipefail are LOAD-BEARING, do not drop them (14-JUL-2026):
# nextpnr writes nothing when it fails, and `| tee` hides its exit status, so
# the old `test -f $@` passed against a PREVIOUS run's file. A failed PnR then
# reported success and `make load` flashed a stale bitstream - measured here as
# a 2-day-old .fs presented as a fresh build.
$(OSS_BASE)_pnr.json: $(OSS_BASE).json $(BUILD)/oss.cst
	rm -f $@
	set -o pipefail; nextpnr-himbaechel --json $(OSS_BASE).json \
	    --write $@ \
	    --device $(DEVICE) \
	    --vopt family=$(FAMILY) \
	    --vopt cst=$(BUILD)/oss.cst 2>&1 | tee $(OSS_BASE)-pnr.log
	@test -f $@

$(FS_OSS): $(OSS_BASE)_pnr.json
	gowin_pack -d $(FAMILY) -o $@ $(OSS_BASE)_pnr.json
	@echo "OSS bitstream: $(FS_OSS)"

# ---- netlist gates (fast; run after any RTL change, before hardware) -------
# 1. tristate integrity: IO_sdram_dq must stay a real inout driven only by
#    $tribuf cells (the yosys silent-collapse class that burned the SD pads)
# 2. latch census: FPGA_FF_MODE builds must contain no inferred latches
check: | $(BUILD)
	$(MAKE) wcs-hex
	yosys -q -p "read_verilog $(INCS) $(VDEFS) $(SRCS); hierarchy -top $(TOP); proc; opt -fast; tribuf; write_json $(BUILD)/tristate-$(VARIANT).json"
	python3 sd-fat-test/sim/check_tristate.py $(BUILD)/tristate-$(VARIANT).json $(TOP) IO_sdram_dq | tee $(BUILD)/tristate-$(VARIANT).log
	@grep -q "TB_RESULT: PASS" $(BUILD)/tristate-$(VARIANT).log
	yosys -q -p "read_verilog $(INCS) $(VDEFS) $(SRCS); hierarchy -top $(TOP); proc; opt -fast; select -assert-none t:\$$dlatch t:\$$dlatchsr; select -clear" \
	  && echo "LATCH GATE: PASS (no inferred latches)" \
	  || { echo "LATCH GATE: FAIL - inferred latches present"; exit 1; }

# ---- Gowin EDA flow (backup; Windows host) ---------------------------------
gowin:
	@$(call nd120_require,ND120_GOWIN,make gowin)
	$(PS) gowin_build.ps1 -Variant $(VARIANT)

# ---- programming ------------------------------------------------------------
load: $(FS_OSS)
	openFPGALoader -b $(BOARD) $(FS_OSS)

flash: $(FS_OSS)
	openFPGALoader -b $(BOARD) -f $(FS_OSS)

load-gowin:
	@test -f $(FS_GOWIN) || { echo "No Gowin bitstream at $(FS_GOWIN) - run 'make gowin' first"; exit 1; }
	openFPGALoader -b $(BOARD) $(FS_GOWIN)

flash-gowin:
	@test -f $(FS_GOWIN) || { echo "No Gowin bitstream at $(FS_GOWIN) - run 'make gowin' first"; exit 1; }
	openFPGALoader -b $(BOARD) -f $(FS_GOWIN)

# ---- USB / serial -----------------------------------------------------------
# Attach the Tang's FTDI to WSL, fix raw-USB + /dev/ttyUSB* permissions.
# Run after every board power cycle / replug (usbipd detaches on power loss).
usb:
	./usb-attach.sh

# ---- sims -------------------------------------------------------------------
sim:
	$(MAKE) -C sdram-bridge/sim test
	$(MAKE) -C sdram-test/sim test

clean:
	rm -rf $(BUILD)
	$(MAKE) -C sdram-bridge/sim clean
	$(MAKE) -C sdram-test/sim clean

.PHONY: all check gowin load flash load-gowin flash-gowin sim clean wcs-hex
