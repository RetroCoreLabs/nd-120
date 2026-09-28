# MEGA65 core - board-glue testbenches (iverilog)
#
#   make test-keys     MEGA65 keyboard scan -> PS/2 events, through the shared TDV decoder
#   make test-console  the console glue: keyboard path, banner, echo, video shape
#   make lint          Verilator lint over the MEGA65 glue + the terminal core
#   make clean
#
# The board-independent terminal core has its own suite in Verilog/Terminals/sim/.
# What is tested HERE is only what is specific to this board - see the header of
# nd120_console_mega65_tb.v for why glue is worth testing separately.
#
# Run from WSL/Linux with iverilog on PATH.

SHELL := /bin/bash
.DELETE_ON_ERROR:

IVERILOG ?= iverilog
VVP      ?= vvp
VERILATOR ?= verilator
GLUE      = ../rtl
TERM      = ../../../Terminals/rtl
SDFAT     = ../../../SD-FAT/circuit

IVFLAGS = -g2012 -Wall

# The TDV2200 pair is what terminal_top picks by default; the VT100 pair is
# compiled alongside (terminal_top instantiates one under `ifdef).
TERM_SRC = $(TERM)/terminal_top.v $(TERM)/terminal_ctrl.v $(TERM)/terminal_ctrl_tdv.v $(TERM)/text_screen.v \
           $(TERM)/char_ram.v $(TERM)/vga_timing.v $(TERM)/font_rom.v \
           $(TERM)/cdc_byte.v $(TERM)/byte_fifo.v $(TERM)/ps2_decoder.v $(TERM)/ps2_ascii_table.v \
           $(TERM)/ps2_decoder_tdv.v $(TERM)/ps2_ascii_table_tdv.v $(TERM)/key_tdv2200.v \
           $(TERM)/term_banner.v $(TERM)/term_banner_rom.v \
           $(TERM)/term_console_feed.v $(TERM)/term_panel.v $(TERM)/term_panel_rom.v $(TERM)/rate_meter.v $(TERM)/ratio_meter.v

.PHONY: all test-keys test-console test-storage-vdrives test-storage-devices test-avalon-port lint clean

all: test-keys test-console test-storage-vdrives test-storage-devices test-avalon-port
	@echo "MEGA65 core: all testbenches passed"

# The storage backend: the ND-120 client bus (Verilog/docs/
# nd-storage-interface-spec.md section 4) served by MiSTer2MEGA65's virtual
# drives. Run against vdrives_model.v, a signal-level model of vdrives.vhd +
# the QNICE firmware that also CHECKS the handshake rules (request held until
# ack, dropped on ack, lba stable, no request on an unmounted slot). Same
# checks as the MiSTer's test-storage-hps, on the byte-wide buffer bus.
test-storage-vdrives: nd_storage_vdrives_tb.vvp
	@$(VVP) $< | tee nd_storage_vdrives_tb.log
	@grep -q "TB_RESULT: PASS" nd_storage_vdrives_tb.log \
		|| { echo "nd_storage_vdrives_tb FAILED"; exit 1; }

nd_storage_vdrives_tb.vvp: nd_storage_vdrives_tb.v vdrives_model.v $(GLUE)/nd_storage_vdrives.v
	$(IVERILOG) $(IVFLAGS) -I$(SDFAT) -o $@ $^

# The whole storage subsystem: two floppy drives, two Winchester units and
# the tape on the controller-facing adapters over nd_storage_vdrives, driven
# at the FDISK_*/WDISK_*/TAPE seams exactly as ND120_CORE drives them (the
# MiSTer's test-storage-devices on the vdrives backend).
test-storage-devices: nd_storage_mega65_devices_tb.vvp
	@$(VVP) $< | tee nd_storage_mega65_devices_tb.log
	@grep -q "TB_RESULT: PASS" nd_storage_mega65_devices_tb.log 		|| { echo "nd_storage_mega65_devices_tb FAILED"; exit 1; }

nd_storage_mega65_devices_tb.vvp: nd_storage_mega65_devices_tb.v vdrives_model.v 		$(GLUE)/nd_storage_mega65_devices.v $(GLUE)/nd_storage_vdrives.v 		$(SDFAT)/nd_storage_floppy_adapter.v $(SDFAT)/nd_storage_disc_adapter.v 		$(SDFAT)/nd_storage_tape_adapter.v
	$(IVERILOG) $(IVFLAGS) -I$(SDFAT) -o $@ $^

# The R3 HyperRAM backend: nd_ddr2_port's contract on an Avalon-MM master,
# against a slave model with random waitrequest / read latency that also
# checks the Avalon rules; both the burst and the single-beat fallback DUTs.
test-avalon-port: nd_avalon_port_tb.vvp
	@$(VVP) $< | tee nd_avalon_port_tb.log
	@grep -q "TB_RESULT: PASS" nd_avalon_port_tb.log 		|| { echo "nd_avalon_port_tb FAILED"; exit 1; }

nd_avalon_port_tb.vvp: nd_avalon_port_tb.v $(GLUE)/nd_avalon_port.v
	$(IVERILOG) $(IVFLAGS) -o $@ $^

test-keys: m65_keys_to_ps2_tb.vvp
	@$(VVP) $< | tee m65_keys_to_ps2_tb.log
	@grep -q "TB_RESULT: PASS" m65_keys_to_ps2_tb.log \
		|| { echo "m65_keys_to_ps2_tb FAILED"; exit 1; }

m65_keys_to_ps2_tb.vvp: m65_keys_to_ps2_tb.v $(GLUE)/m65_keys_to_ps2.v $(TERM)/ps2_decoder_tdv.v $(TERM)/ps2_ascii_table_tdv.v
	$(IVERILOG) $(IVFLAGS) -o $@ $^

test-console: nd120_console_mega65_tb.vvp
	@$(VVP) $< | tee nd120_console_mega65_tb.log
	@grep -q "TB_RESULT: PASS" nd120_console_mega65_tb.log \
		|| { echo "nd120_console_mega65_tb FAILED"; exit 1; }

nd120_console_mega65_tb.vvp: nd120_console_mega65_tb.v $(GLUE)/nd120_console_mega65.v $(GLUE)/m65_keys_to_ps2.v $(TERM_SRC)
	$(IVERILOG) $(IVFLAGS) -o $@ $^

# Same suppression set as the MiSTer glue lint (fpga/mister/sim/Makefile) so
# "lint clean" means the same thing on both boards.
VVFLAGS = --lint-only -Wall \
  -Wno-BLKSEQ -Wno-DECLFILENAME -Wno-EOFNEWLINE -Wno-LATCH -Wno-PINCONNECTEMPTY \
  -Wno-PINMISSING -Wno-SYNCASYNCNET -Wno-TIMESCALEMOD -Wno-UNDRIVEN \
  -Wno-UNOPTFLAT -Wno-UNUSED -Wno-WIDTH

lint:
	$(VERILATOR) $(VVFLAGS) --top-module nd120_console_mega65 \
	  $(GLUE)/nd120_console_mega65.v $(GLUE)/m65_keys_to_ps2.v $(TERM_SRC)
	@echo "MEGA65 console glue: verilator lint clean"

clean:
	rm -f *.vvp *.vcd *.log
