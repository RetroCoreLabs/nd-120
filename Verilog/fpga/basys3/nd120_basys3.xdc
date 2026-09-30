########################################################################
#  nd120_basys3.xdc - the Basys3 pin map and board constraints.
#
#  Copied BYTE FOR BYTE on 30-SEP-2026 from the Basys3 Vivado GUI project
#  (ND3202D.srcs/constrs_2/new/constraints.xdc, 113 lines), the constraint
#  set both synth_1 and impl_1 used. Until then this file existed ONLY
#  inside that project, outside the repository, so no other machine could
#  build the board. The project's other set, constrs_1 (a 36-line UART-only
#  stub whose clock is named clk_100MHz), was read by no run and is not
#  carried over.
#
#  In the project this file was USED_IN = implementation only (never by
#  synthesis), with nd120_timing.xdc after it (PROCESSING_ORDER LATE).
#  vivado_build.tcl keeps exactly that: it reads both AFTER synth_design,
#  this one first. Everything below is the original, unchanged.
########################################################################

########################################################################
#  Basys3 (xc7a35tcpg236-1) constraints for ND-120
#  Pin assignments from Digilent Basys3 Master XDC
########################################################################

########################################################################
#  Clock - 100 MHz onboard oscillator
########################################################################
set_property -dict {PACKAGE_PIN W5 IOSTANDARD LVCMOS33} [get_ports sysclk]
create_clock -period 10.000 -name sys_clk [get_ports sysclk]

########################################################################
#  Slide Switches (active high: UP=1, DOWN=0)
#  SW0 (V17) = btn1 : sys_rst_n (UP=released, DOWN=in reset)
#  SW1 (V16) = btn2 : 7-seg display select
#  SW3 (W17) = btn3 : CPU clock speed (DOWN=100MHz, UP=12.5MHz)
#
#  NOTE: SW2 (W16) = PUDC_B — reserved config pin, do not use
#        SW5 (V15) = 1.8V config bank — cannot use as LVCMOS33
#        SW3 (W17) = Bank 14, VCCO=3.3V — safe
########################################################################
set_property -dict {PACKAGE_PIN V17 IOSTANDARD LVCMOS33} [get_ports btn1]
set_property -dict {PACKAGE_PIN V16 IOSTANDARD LVCMOS33} [get_ports btn2]
set_property -dict {PACKAGE_PIN W17 IOSTANDARD LVCMOS33} [get_ports btn3]

########################################################################
#  LEDs (active HIGH: 1=ON)
#  LD0 (rightmost) through LD15 (leftmost)
#  RIGHT: LD0-5 = CPU status + heartbeat
#  LEFT:  LD11-15 = Cycle state {CC0,CC1,CC2,CC3,TERM}
########################################################################
set_property -dict {PACKAGE_PIN U16 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN E19 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN U19 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN V19 IOSTANDARD LVCMOS33} [get_ports {led[3]}]
set_property -dict {PACKAGE_PIN W18 IOSTANDARD LVCMOS33} [get_ports {led[4]}]
set_property -dict {PACKAGE_PIN U15 IOSTANDARD LVCMOS33} [get_ports {led[5]}]
set_property -dict {PACKAGE_PIN U14 IOSTANDARD LVCMOS33} [get_ports {led[6]}]
set_property -dict {PACKAGE_PIN V14 IOSTANDARD LVCMOS33} [get_ports {led[7]}]
set_property -dict {PACKAGE_PIN V13 IOSTANDARD LVCMOS33} [get_ports {led[8]}]
set_property -dict {PACKAGE_PIN V3 IOSTANDARD LVCMOS33} [get_ports {led[9]}]
set_property -dict {PACKAGE_PIN W3 IOSTANDARD LVCMOS33} [get_ports {led[10]}]
set_property -dict {PACKAGE_PIN U3 IOSTANDARD LVCMOS33} [get_ports {led[11]}]
set_property -dict {PACKAGE_PIN P3 IOSTANDARD LVCMOS33} [get_ports {led[12]}]
set_property -dict {PACKAGE_PIN N3 IOSTANDARD LVCMOS33} [get_ports {led[13]}]
set_property -dict {PACKAGE_PIN P1 IOSTANDARD LVCMOS33} [get_ports {led[14]}]
set_property -dict {PACKAGE_PIN L1 IOSTANDARD LVCMOS33} [get_ports {led[15]}]

########################################################################
#  USB-UART (directly on Basys3 board) via FTDI FT2232HQ to USB port.
#  FIXED 2026-07-07: pins were SWAPPED (uartRx=A18, uartTx=B18), which broke
#  serial in BOTH directions (nothing typed reached the FPGA, nothing sent
#  reached the PC). Basys3 standard: RsRx (FPGA input) = B18, RsTx (FPGA
#  output) = A18. So uartRx must be B18 and uartTx must be A18.
########################################################################
set_property -dict {PACKAGE_PIN B18 IOSTANDARD LVCMOS33} [get_ports uartRx]
set_property -dict {PACKAGE_PIN A18 IOSTANDARD LVCMOS33} [get_ports uartTx]

########################################################################
#  7-Segment Display (active LOW segments and anodes)
#  Shows MIC address (SW1=OFF) or MAC address (SW1=ON)
########################################################################
set_property -dict {PACKAGE_PIN W7 IOSTANDARD LVCMOS33} [get_ports {seg[0]}]
set_property -dict {PACKAGE_PIN W6 IOSTANDARD LVCMOS33} [get_ports {seg[1]}]
set_property -dict {PACKAGE_PIN U8 IOSTANDARD LVCMOS33} [get_ports {seg[2]}]
set_property -dict {PACKAGE_PIN V8 IOSTANDARD LVCMOS33} [get_ports {seg[3]}]
set_property -dict {PACKAGE_PIN U5 IOSTANDARD LVCMOS33} [get_ports {seg[4]}]
set_property -dict {PACKAGE_PIN V5 IOSTANDARD LVCMOS33} [get_ports {seg[5]}]
set_property -dict {PACKAGE_PIN U7 IOSTANDARD LVCMOS33} [get_ports {seg[6]}]

set_property -dict {PACKAGE_PIN U2 IOSTANDARD LVCMOS33} [get_ports {an[0]}]
set_property -dict {PACKAGE_PIN U1 IOSTANDARD LVCMOS33} [get_ports {an[1]}]
set_property -dict {PACKAGE_PIN T1 IOSTANDARD LVCMOS33} [get_ports {an[2]}]
set_property -dict {PACKAGE_PIN R2 IOSTANDARD LVCMOS33} [get_ports {an[3]}]

########################################################################
#  Configuration
########################################################################
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]

########################################################################
#  Combinational loops from original gate-level design
#  ALLOW_COMBINATORIAL_LOOPS: suppresses error during opt/place
#  LUTLP-1 severity: downgrades DRC check from Critical Warning to Warning
########################################################################
set_property ALLOW_COMBINATORIAL_LOOPS true [get_nets -hierarchical -quiet -filter {NAME =~ *CPU_BOARD*}]
set_property SEVERITY {Warning} [get_drc_checks LUTLP-1]

########################################################################
#  REMOVED 2026-07-06: the SW3/btn3 100/12.5 MHz BUFGMUX_CTRL mux was deleted
#  (ND120_TOP.v now generates a single ~16.67 MHz clk_cpu; there is no CLKOUT1).
#  The stale clock-groups below referenced the removed CLKOUT1 and failed with
#  CRITICAL WARNING [12-4739], leaving NO clock grouping in effect. Clock-domain
#  separation is now handled by fpga/basys3/nd120_timing.xdc.
########################################################################
# set_clock_groups -logically_exclusive \
#     -group [get_clocks -of_objects [get_pins mmcm_cpu_clk/CLKOUT0]] \
#     -group [get_clocks -of_objects [get_pins mmcm_cpu_clk/CLKOUT1]]

########################################################################
#  Warning suppressions moved to vivado_build.tcl (not allowed in XDC)
#  - Synth 8-3936: register trimming (R81/L4/L8/R41P)
#  - Synth 8-5837: dual async set/reset (D_FLIPFLOP/F617/F714)
########################################################################

########################################################################
#  ILA debug core is created dynamically in vivado_build.tcl after
#  synthesis (not here) so it can adapt to optimized-away nets.
#  Do NOT add ILA definitions here — they conflict with the TCL script.
########################################################################
