# ND-120 on Nexys 4 DDR / Nexys A7-100T - standard board-folder build API
# (see ../README.md)
#
#   make              build the bitstream + JTAG-program (Vivado on the Windows host)
#   make build        build only (no board needed)
#   make load         JTAG-program the already-built bitstream - VOLATILE
#                     (seconds; configuration RAM only, a power cycle restores
#                     whatever the QSPI flash holds)
#   make flash        write the already-built bitstream to QSPI flash -
#                     PERMANENT (survives power cycles; boots the board from it)
#   make CLK=33       build at 33.333 MHz instead of the default 16.667 MHz
#   make CACHE=0      compile the CPU cache RAMs out (ON by default; at runtime
#                     sw[4] up turns the cache off without a rebuild)
#   make VGACONSOLE=0 leave out the VGA console + USB keyboard (ON by default;
#                     only drop it if the chip space is needed for something else)
#   make PANELCLOCK=0 leave out the MC68705/MM58274 panel clock (ON by default;
#                     only drop it if the chip space is needed for something else -
#                     without it SINTRAN says "ND-100 PANEL CLOCK INCORRECT" at
#                     every boot and cannot keep time, see docs/panel-clock-68705.md)
#   make clean        remove build outputs
#
# Vivado path: ND120_VIVADO from local.mk at the repository root (python3
# configure.py writes it); override for one run with
#   make VIVADO="<your Vivado install>\bin\vivado.bat"
# Each target checks the settings it needs first; make check-config shows them.
# From a Windows shell, run the tcl directly instead:
#   vivado -mode batch -source build.tcl [-tclargs -noburn clk=33 -skipwcs]

include $(dir $(abspath $(lastword $(MAKEFILE_LIST))))../../../paths.mk

CMD     = cmd.exe /c
CLK    ?= 16
PANELCLOCK ?= 1
VGACONSOLE ?= 1
CACHE ?= 1
ARGS    = clk=$(CLK)
ifeq ($(CACHE),0)
ARGS   += nocache
endif
ifeq ($(VGACONSOLE),0)
ARGS   += novgaconsole
endif
ifeq ($(PANELCLOCK),0)
ARGS   += -NoPanelClock
endif

all:
	@$(call nd120_require,$(ND120_NEED_VIVADO),make all)
	$(CMD) "$(VIVADO)" -mode batch -source build.tcl -tclargs $(ARGS)

build:
	@$(call nd120_require,$(ND120_NEED_VIVADO),make build)
	$(CMD) "$(VIVADO)" -mode batch -source build.tcl -tclargs $(ARGS) -noburn

# Volatile: JTAG into configuration RAM, seconds. program.tcl refuses politely
# if there is no bitstream - it never triggers a rebuild.
load:
	@$(call nd120_require,$(ND120_NEED_VIVADO),make load)
	$(CMD) "$(VIVADO)" -mode batch -source program.tcl

# Permanent: QSPI config flash, survives power cycles. See flash.tcl.
flash:
	@$(call nd120_require,$(ND120_NEED_VIVADO),make flash)
	$(CMD) "$(VIVADO)" -mode batch -source flash.tcl

clean:
	rm -f nd120_nexys4ddr.bit util.rpt timing.rpt \
	      AM27256_45132L.hex AM27256_45133L.hex wcs_*.hex \
	      vivado*.jou vivado*.log
	rm -rf .Xil

.PHONY: all build load flash clean
