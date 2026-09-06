# ============================================================================
# QMTECH XC7A35T SDRAM core board - pins for the ND-120 build
# Full path: Verilog/fpga/qmtech-a35t/nd120_qmtech.xdc
# Top module: rtl/nd120_qmtech_top.v      Part: xc7a35tcsg325-1
#
# On-board pins (clock, keys, LEDs, SDRAM) are copied from board-pins.xdc in
# this directory, which was cross-checked against the vendor sample XDCs and
# the schematic. Header pins (console + SD card) are chosen here and derived
# from the schematic's JP3 table - see the note above that section.
#
# All board I/O is 3.3 V (every bank is powered at 3V3) -> LVCMOS33.
# ============================================================================

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

# N25Q064A SPI flash, x4, board straps M0:M1:M2 = 1:0:0 (SPI master boot).
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]

# ---- System clock ----------------------------------------------------------
# 50 MHz SG-310SCN oscillator on R2 = IO_L13P_T2_MRCC_34, a clock-capable
# (MRCC) pin, so it drives the MMCM directly (manual 2.2.3, schematic sheet 2).
set_property PACKAGE_PIN R2 [get_ports sys_clk_50]
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk_50]
create_clock -period 20.000 -name sys_clk_50 [get_ports sys_clk_50]

# ---- Keys (active low, 4.7k pull-ups; schematic sheet 2) -------------------
# SW1 = USER_KEY0 = H18 -> RESET.  SW2 = USER_KEY1 = H17 -> spare.
# (SW3 is PROG_B, hard-wired to the config pin, not visible to user logic.)
set_property PACKAGE_PIN H18 [get_ports key0_n]
set_property PACKAGE_PIN H17 [get_ports key1_n]
set_property IOSTANDARD LVCMOS33 [get_ports {key0_n key1_n}]

# ---- User LEDs (manual 2.2.5) ----------------------------------------------
# ACTIVE LOW: 3V3 -> 1k -> LED -> FPGA pin, so driving 0 lights the LED.
# The schematic (sheet 2) reads: D8 = USER_LED0 (LED D1), C8 = USER_LED1
# (LED D4). NOTE: board-pins.xdc in this directory carries that same comment
# but then assigns led_n[0] to C8, i.e. the other way round. The schematic is
# followed here. It only decides which of two LEDs blinks, but the two files
# disagreeing is worth knowing about before anyone reads a bring-up result.
#   led_n[0] = D8 = CPU RED   (error / halt)
#   led_n[1] = C8 = CPU GREEN (self-test passed, running)
set_property PACKAGE_PIN D8 [get_ports {led_n[0]}]
set_property PACKAGE_PIN C8 [get_ports {led_n[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_n[*]}]

# ---- Console UART + SD card, on header JP3 ---------------------------------
# This board has NO on-board USB-UART and (as far as the manual and schematic
# say) no SD slot: the Mini USB socket is power only. Both go on header pins.
#
# JP3 pin -> FPGA pin, read off schematic sheet 2. The header's net names are
# IO_<pin>, so the net name IS the FPGA pin. Pins 5-20 of JP3 are:
#     5=F18   6=G17   7=E18   8=F17   9=D18  10=E17  11=C17  12=C18
#    13=G15  14=H16  15=F15  16=G16  17=E16  18=E15  19=D16  20=D15
# All are bank-15 I/O. Pins 1-4 are NOT signals: pin 1 = USB_5V and
# pin 2 = 3V3 on both headers - do not wire a signal to either.
#
# NOT VERIFIED: which JP3 pin is ground. The manual and schematic name the
# 5 V and 3V3 rails on pins 1 and 2 but the extraction of the header's power
# pins was not legible for GND. Confirm a ground pin against the physical
# board or the schematic before wiring the adapter or the card - a card
# powered from 3V3 with no shared ground will simply not respond.
#
# Console: a 3.3 V USB-serial adapter. 115200 8N1. Cross the pair over -
# the adapter's TX goes to the FPGA's RX.
set_property PACKAGE_PIN F18 [get_ports uart_tx]   ;# JP3 pin 5  -> adapter RX
set_property PACKAGE_PIN G17 [get_ports uart_rx]   ;# JP3 pin 6  <- adapter TX
set_property IOSTANDARD LVCMOS33 [get_ports {uart_tx uart_rx}]

# SD card. All six signals are constrained so switching the build to the
# 4-bit bus later is a parameter change (USE_4BIT in the top level) and not
# a pin job; the first build uses CLK, CMD and DAT0 only.
# DAT1 and DAT2 must still be pulled high on the card side even in 1-bit
# mode, and DAT3 doubles as the card's chip select during initialisation -
# so wire all four data lines even though only DAT0 carries traffic at first.
set_property PACKAGE_PIN E18 [get_ports sd_clk]    ;# JP3 pin 7
set_property PACKAGE_PIN F17 [get_ports sd_cmd]    ;# JP3 pin 8
set_property PACKAGE_PIN D18 [get_ports sd_dat0]   ;# JP3 pin 9
set_property PACKAGE_PIN E17 [get_ports sd_dat1]   ;# JP3 pin 10
set_property PACKAGE_PIN C17 [get_ports sd_dat2]   ;# JP3 pin 11
set_property PACKAGE_PIN C18 [get_ports sd_dat3]   ;# JP3 pin 12
set_property IOSTANDARD LVCMOS33 \
    [get_ports {sd_clk sd_cmd sd_dat0 sd_dat1 sd_dat2 sd_dat3}]

# The card's own pull-ups sit on the module. These internal ones keep CMD and
# the data lines from floating while the FPGA has them released, which matters
# on jumper wires far more than on a board trace.
set_property PULLUP true [get_ports {sd_cmd sd_dat0 sd_dat1 sd_dat2 sd_dat3}]

# ---- SDRAM: Winbond W9825G6KH-6, 32 MB, 16-bit bus (manual 2.2.8) ----------
# Copied verbatim from board-pins.xdc, which matched the vendor sample XDC
# pin-for-pin against schematic sheet 4. The control lines carry 4.7k pull-ups
# to 3V3 on the board, so the chip idles safely while the FPGA is unconfigured.
set_property PACKAGE_PIN P16 [get_ports sdram_clk]
set_property PACKAGE_PIN R16 [get_ports sdram_cke]
set_property PACKAGE_PIN V13 [get_ports sdram_cs_n]
set_property PACKAGE_PIN V14 [get_ports sdram_ras_n]
set_property PACKAGE_PIN U14 [get_ports sdram_cas_n]
set_property PACKAGE_PIN U15 [get_ports sdram_we_n]

set_property PACKAGE_PIN V12 [get_ports {sdram_ba[0]}]
set_property PACKAGE_PIN U12 [get_ports {sdram_ba[1]}]

set_property PACKAGE_PIN V16 [get_ports {sdram_dqm[0]}]
set_property PACKAGE_PIN N16 [get_ports {sdram_dqm[1]}]

set_property PACKAGE_PIN U11 [get_ports {sdram_addr[0]}]
set_property PACKAGE_PIN U10 [get_ports {sdram_addr[1]}]
set_property PACKAGE_PIN V9  [get_ports {sdram_addr[2]}]
set_property PACKAGE_PIN U9  [get_ports {sdram_addr[3]}]
set_property PACKAGE_PIN T12 [get_ports {sdram_addr[4]}]
set_property PACKAGE_PIN R13 [get_ports {sdram_addr[5]}]
set_property PACKAGE_PIN T13 [get_ports {sdram_addr[6]}]
set_property PACKAGE_PIN T14 [get_ports {sdram_addr[7]}]
set_property PACKAGE_PIN P14 [get_ports {sdram_addr[8]}]
set_property PACKAGE_PIN T15 [get_ports {sdram_addr[9]}]
set_property PACKAGE_PIN V11 [get_ports {sdram_addr[10]}]
set_property PACKAGE_PIN R15 [get_ports {sdram_addr[11]}]
set_property PACKAGE_PIN P15 [get_ports {sdram_addr[12]}]

set_property PACKAGE_PIN P18 [get_ports {sdram_dq[0]}]
set_property PACKAGE_PIN R18 [get_ports {sdram_dq[1]}]
set_property PACKAGE_PIN R17 [get_ports {sdram_dq[2]}]
set_property PACKAGE_PIN T18 [get_ports {sdram_dq[3]}]
set_property PACKAGE_PIN T17 [get_ports {sdram_dq[4]}]
set_property PACKAGE_PIN U17 [get_ports {sdram_dq[5]}]
set_property PACKAGE_PIN V17 [get_ports {sdram_dq[6]}]
set_property PACKAGE_PIN U16 [get_ports {sdram_dq[7]}]
set_property PACKAGE_PIN N17 [get_ports {sdram_dq[8]}]
set_property PACKAGE_PIN N18 [get_ports {sdram_dq[9]}]
set_property PACKAGE_PIN M16 [get_ports {sdram_dq[10]}]
set_property PACKAGE_PIN M17 [get_ports {sdram_dq[11]}]
set_property PACKAGE_PIN K17 [get_ports {sdram_dq[12]}]
set_property PACKAGE_PIN L18 [get_ports {sdram_dq[13]}]
set_property PACKAGE_PIN K18 [get_ports {sdram_dq[14]}]
set_property PACKAGE_PIN J18 [get_ports {sdram_dq[15]}]

set_property IOSTANDARD LVCMOS33 [get_ports {sdram_clk sdram_cke sdram_cs_n \
    sdram_ras_n sdram_cas_n sdram_we_n sdram_ba[*] sdram_dqm[*] \
    sdram_addr[*] sdram_dq[*]}]
