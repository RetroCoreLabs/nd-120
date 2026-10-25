#!/usr/bin/env bash
# Verilator over the whole MEGA65 machine (nd120_mega65_machine) in one of
# its two memory configurations. The CPU source list is the MiSTer core's
# files.qip - the configuration this machine is copied from - minus the
# MiSTer-only files, plus the MEGA65 glue.
#   ./lint_machine.sh sdram            # lint, R4/R5/R6 configuration
#   ./lint_machine.sh hyperram         # lint, R3 configuration
#   ./lint_machine.sh sdram vtest      # BOOT the machine in Verilator --timing
#                                      # (nd120_mega65_machine_tb.v) on a 16-bit
#                                      # SDRAM model and type RETURN at the
#                                      # OPCOM prompt - the full keyboard path
# vtest runs the binary from vtest-run/ (created here, ignored by git), where
# the 33 WCS images and the two CS PROM images are copied so $readmemh finds
# them as it does in the build.
set -e
cfg=${1:-sdram}
mode=${2:-lint}
here=$(cd "$(dirname "$0")" && pwd)
mister=$here/../../mister
vroot=$here/../../..
srcs=()
while read -r f; do
  case "$f" in
    sys/*|rtl/nd120_console_mister.v|rtl/pll_cpu.v|rtl/nd120_diag_print.v|rtl/nd120_csa_trace.v|rtl/nd120_sterr_catch.v|rtl/nd120_storage_probe.v|rtl/nd_storage_hps.v|rtl/nd_storage_mister_devices.v|build/term_banner_rom.v|nd120.sdc|nd120.sv|*.qip) continue;;
    ../../Terminals/*) continue;;
  esac
  srcs+=("$mister/$f")
done < <(grep -E "VERILOG_FILE|SYSTEMVERILOG_FILE" "$mister/files.qip" | sed 's/.*_FILE //')
case "$cfg" in
  sdram)    defs="-DMAIN_RAM_SDRAM -DND_SDRAM_PACK16 -DND_SDRAM_DQ16 -DND_SDRAM_REFRESH_US=7";;
  hyperram) defs="-DMAIN_RAM_DDR2"; srcs+=("$vroot/fpga/nexys4ddr/ddr2/MEM_RAM_49_DDR2.v");;
  *) echo "usage: $0 sdram|hyperram [lint|vtest]"; exit 2;;
esac
term=$vroot/Terminals/rtl
common_flags=(-Wall
  -Wno-BLKSEQ -Wno-DECLFILENAME -Wno-EOFNEWLINE -Wno-LATCH -Wno-PINCONNECTEMPTY
  -Wno-PINMISSING -Wno-SYNCASYNCNET -Wno-TIMESCALEMOD -Wno-UNDRIVEN
  -Wno-UNOPTFLAT -Wno-UNUSED -Wno-WIDTH -Wno-CASEINCOMPLETE -Wno-MULTIDRIVEN -Wno-IMPLICIT
  -Wno-CASEOVERLAP -Wno-INITIALDLY -Wno-COMBDLY -Wno-MODDUP -Wno-fatal
  -DFPGA_FF_MODE -DBOARD_CLK_FREQ=20000000 -DUART_BAUD_RATE=115200 -DSKIP_WCS_LOAD
  -DND120_PANEL_CLOCK -DND120_MIPS_TAP $defs
  -I$vroot/SD-FAT/circuit -I$vroot/Shared/support -I$vroot/CPU-BOARD-3202/circuit)
machine_srcs=(
  $here/../rtl/nd120_mega65_machine.v $here/../rtl/nd120_console_mega65.v $here/../rtl/m65_keys_to_ps2.v
  $here/../rtl/nd_storage_mega65_devices.v $here/../rtl/nd_storage_vdrives.v $here/../rtl/nd_avalon_port.v
  $term/terminal_top.v $term/terminal_ctrl.v $term/terminal_ctrl_tdv.v $term/text_screen.v
  $term/char_ram.v $term/vga_timing.v $term/font_rom.v $term/cdc_byte.v $term/byte_fifo.v
  $term/ps2_decoder.v $term/ps2_ascii_table.v $term/ps2_decoder_tdv.v $term/ps2_ascii_table_tdv.v
  $term/key_tdv2200.v $term/key_vt100.v $term/term_banner.v $term/term_banner_rom.v $term/term_console_feed.v
  $term/term_panel.v $term/term_panel_rom.v $term/rate_meter.v $term/ratio_meter.v $term/mips_counter.v
  $term/console_uart_rx.v $term/console_uart_tx.v
  "${srcs[@]}")
case "$mode" in
  lint)
    verilator --lint-only "${common_flags[@]}" --top-module nd120_mega65_machine \
      "${machine_srcs[@]}" 2>&1 | grep -E "%Error|mega65|nd_avalon" | head -30
    echo "lint($cfg) done"
    ;;
  vtest)
    [ "$cfg" = sdram ] || { echo "vtest: only the sdram configuration has a memory model here"; exit 2; }
    run=$here/vtest-run
    mkdir -p "$run"
    cp "$vroot"/Shared/support/wcs_*.hex "$run"/
    cp "$vroot"/../Code/Microcode/AM27256_45132L.hex "$vroot"/../Code/Microcode/AM27256_45133L.hex "$run"/
    cd "$run"
    verilator --binary --timing -j 4 "${common_flags[@]}" --top-module nd120_mega65_machine_tb \
      -CFLAGS "-std=gnu++20 -fcoroutines" \
      "$here/nd120_mega65_machine_tb.v" "$here/sdram16_model.v" "${machine_srcs[@]}" 2>&1 \
      | grep -E "%Error|%Warning" | grep -vE "WIDTH|UNUSED" | head -40 || true
    [ -x obj_dir/Vnd120_mega65_machine_tb ] || { echo "vtest: build failed"; exit 1; }
    ./obj_dir/Vnd120_mega65_machine_tb 2>&1 | tee "$here/nd120_mega65_machine_tb.log"
    grep -q "TB_RESULT: PASS" "$here/nd120_mega65_machine_tb.log"
    ;;
  *) echo "usage: $0 sdram|hyperram [lint|vtest]"; exit 2;;
esac
