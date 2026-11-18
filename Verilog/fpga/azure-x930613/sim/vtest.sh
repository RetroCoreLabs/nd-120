#!/usr/bin/env bash
# Boot the whole Azure-card machine (nd120_azure_top) in Verilator --timing:
# nd120_azure_top_tb.v plays the PC on the simulated PCIe window and waits for
# MOPC's '#' through the PCIe console, then types RETURN and waits for a new
# '#'. (docs/00-plan.md, step V4.)
#
#   ./vtest.sh          build and run (several minutes)
#   ./vtest.sh disk     floppy boot from a PC-served image (nd120_azure_disk_tb.v)
#   ./vtest.sh lint     Verilator lint of the top only
#
# The CPU source list is the MiSTer core's files.qip (the same shared tree
# every board builds) minus the MiSTer-only files, plus this board's rtl/.
# The binary runs in vtest-run/ (created here, ignored by git), where the WCS
# images and the two microcode PROM images are copied so $readmemh finds them
# as it does in a build - the MEGA65 vtest does the same.
set -e
mode=${1:-vtest}
here=$(cd "$(dirname "$0")" && pwd)
mister=$here/../../mister
vroot=$here/../../..
rtl=$here/../rtl
srcs=()
while read -r f; do
  case "$f" in
    sys/*|rtl/nd120_console_mister.v|rtl/pll_cpu.v|rtl/nd120_diag_print.v|rtl/nd120_csa_trace.v|rtl/nd120_sterr_catch.v|rtl/nd120_storage_probe.v|build/term_banner_rom.v|nd120.sdc|nd120.sv|*.qip) continue;;
    ../../Terminals/*) continue;;
  esac
  srcs+=("$mister/$f")
done < <(grep -E "VERILOG_FILE|SYSTEMVERILOG_FILE" "$mister/files.qip" | sed 's/.*_FILE //')
term=$vroot/Terminals/rtl
flags=(-Wall
  -Wno-BLKSEQ -Wno-DECLFILENAME -Wno-EOFNEWLINE -Wno-LATCH -Wno-PINCONNECTEMPTY
  -Wno-PINMISSING -Wno-SYNCASYNCNET -Wno-TIMESCALEMOD -Wno-UNDRIVEN
  -Wno-UNOPTFLAT -Wno-UNUSED -Wno-WIDTH -Wno-CASEINCOMPLETE -Wno-MULTIDRIVEN -Wno-IMPLICIT
  -Wno-CASEOVERLAP -Wno-INITIALDLY -Wno-COMBDLY -Wno-MODDUP -Wno-fatal
  -DFPGA_FF_MODE -DBOARD_CLK_FREQ=20000000 -DUART_BAUD_RATE=115200 -DSKIP_WCS_LOAD
  -DND120_PANEL_CLOCK
  -DMAIN_RAM_BLOCKRAM -DND120_BLOCKRAM_ADDR_BITS=20 -DND120_BLOCKRAM_BANK_SLOTS=1 -DND120_ONBOARD_2MB
  -DND120_AZURE_SIM_PCIE
  -I$vroot/SD-FAT/circuit -I$vroot/Shared/support -I$vroot/CPU-BOARD-3202/circuit)
top_srcs=(
  $rtl/nd120_azure_top.v $rtl/pcie_hip_wrap.v $rtl/pcie_bar_bus.v
  $rtl/nd_pcie_console.v $rtl/nd_pcie_storage.v
  $term/console_uart_rx.v $term/console_uart_tx.v
  "${srcs[@]}")
case "$mode" in
  lint)
    verilator --lint-only "${flags[@]}" --top-module nd120_azure_top "${top_srcs[@]}" 2>&1 \
      | grep -E "%Error|azure|nd_pcie|pcie_" | head -30
    echo "lint done"
    ;;
  vtest|disk)
    if [ "$mode" = disk ]; then
      tb=nd120_azure_disk_tb; extra=("$here/pc_storage_model.v")
    else
      tb=nd120_azure_top_tb; extra=()
    fi
    run=$here/vtest-run/$mode
    mkdir -p "$run"
    cp "$vroot"/Shared/support/wcs_*.hex "$run"/
    cp "$vroot"/../Code/Microcode/AM27256_45132L.hex "$vroot"/../Code/Microcode/AM27256_45133L.hex "$run"/
    cd "$run"
    if [ "$mode" = disk ]; then
      # the runSim floppy gate's image; its first 64 KB, one hex byte per line
      python3 "$vroot/tests/gen_fboot_img.py" fboot.img fboot_exp.txt
      python3 -c 'd=open("fboot.img","rb").read(65536); open("fboot.hex","w").write("".join("%02x\n" % b for b in d))'
    fi
    verilator --binary --timing -j 4 "${flags[@]}" --top-module $tb \
      -CFLAGS "-std=gnu++20 -fcoroutines" \
      "$here/$tb.v" "${extra[@]}" "${top_srcs[@]}" 2>&1 \
      | grep -E "%Error|%Warning" | grep -vE "WIDTH|UNUSED" | head -40 || true
    [ -x obj_dir/V$tb ] || { echo "vtest: build failed"; exit 1; }
    ./obj_dir/V$tb 2>&1 | tee "$here/$tb.log"
    grep -q "TB_RESULT: PASS" "$here/$tb.log"
    ;;
  *) echo "usage: $0 [vtest|disk|lint]"; exit 2;;
esac
