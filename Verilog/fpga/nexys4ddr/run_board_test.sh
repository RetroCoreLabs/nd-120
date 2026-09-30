#!/bin/bash
###############################################################################
# ND-120 Nexys 4 DDR - unattended board test runner
#
# Runs one boardtests/<name>.bt script against the live board with full
# hang handling, no human needed:
#
#   1. JTAG-reset the board (program the CURRENT nd120_nexys4ddr.bit) so
#      every run starts from the OPCOM '#' prompt.
#   2. Drive the console through board_expect.ps1 (send/expect/quiet).
#   3. On a HANG or FAIL verdict: BEFORE resetting, take an ILA capnow
#      capture of the live machine (only if the programmed bitstream has
#      an ILA - pass -ila to say so), then save the transcript + capture
#      into $ND120_BUILD_DIR/nexys4ddr/boardtest-results/<name>-<timestamp>/.
#   4. Exit 0 with "BOARD_TEST: PASS" or nonzero with "BOARD_TEST: FAIL".
#
# Usage (from fpga/nexys4ddr/, WSL side):
#   ./run_board_test.sh lfn            # boardtests/lfn.bt, plain bitstream
#   ./run_board_test.sh lfn -ila       # same, bitstream has ILA -> capture on hang
#   ./run_board_test.sh sintran_boot
#
# Requirements: the Windows host runs Vivado, COM11 free.
# Vivado path and licence: ND120_VIVADO (required) and ND120_VIVADO_LICENSE,
# from the environment or local.mk at the repository root (python3
# configure.py writes it). ND120_VIVADO_LICENSE unset = the Windows user
# (then machine) XILINXD_LICENSE_FILE.
# The runner NEVER fights for the port: if COM11 is held (a human at the
# console), it reports port-busy and exits without touching anything.
###############################################################################
set -u
cd "$(dirname "$0")"

NAME="${1:?usage: run_board_test.sh <name> [-ila]}"
HAS_ILA="${2:-}"
BT="boardtests/${NAME}.bt"
[ -f "$BT" ] || { echo "BOARD_TEST: FAIL no such script $BT"; exit 2; }

# Local settings: the environment first, then local.mk at the repository
# root - configure.py does the reading (and checks before any work), so the
# rule and the message are the same as make's.
ROOT="$(cd ../../.. && pwd)"
python3 "$ROOT/configure.py" --require ND120_VIVADO ND120_BUILD_DIR --for "run_board_test.sh" || exit 2
ND120_VIVADO="${ND120_VIVADO:-$(python3 "$ROOT/configure.py" --get ND120_VIVADO)}"
ND120_VIVADO_LICENSE="${ND120_VIVADO_LICENSE:-$(python3 "$ROOT/configure.py" --get ND120_VIVADO_LICENSE)}"
VIVADO_EXE="$ND120_VIVADO"

# Results, the ILA capture and Vivado's own files go to the build folder,
# never into this source folder. Vivado is started there (Set-Location), and
# the Tcl scripts are named by their full Windows path.
BOARD_DIR="$(python3 "$ROOT/configure.py" --get ND120_BUILD_DIR)/nexys4ddr"
mkdir -p "$BOARD_DIR"
STAMP=$(date +%Y%m%d-%H%M%S)
OUT="$BOARD_DIR/boardtest-results/${NAME}-${STAMP}"
mkdir -p "$OUT"
HERE_WIN=$(wslpath -w "$(pwd)")
BOARD_WIN=$(wslpath -w "$BOARD_DIR")
OUT_WIN=$(wslpath -w "$OUT")
if [ -n "${ND120_VIVADO_LICENSE:-}" ]; then
    LIC_PS="\$env:XILINXD_LICENSE_FILE='${ND120_VIVADO_LICENSE}'"
else
    # A Windows process started from WSL does not get the user's registry
    # environment, so read the licence list from there explicitly.
    LIC_PS="if (-not \$env:XILINXD_LICENSE_FILE) { \$env:XILINXD_LICENSE_FILE = [Environment]::GetEnvironmentVariable('XILINXD_LICENSE_FILE','User'); if (-not \$env:XILINXD_LICENSE_FILE) { \$env:XILINXD_LICENSE_FILE = [Environment]::GetEnvironmentVariable('XILINXD_LICENSE_FILE','Machine') } }"
fi

VIVADO_PS="
$LIC_PS
Set-Location '$BOARD_WIN'
& '$VIVADO_EXE' -mode batch -nolog -nojournal"

echo "[boardtest] reset: programming nd120_nexys4ddr.bit"
if [ "$HAS_ILA" = "-ila" ]; then
    powershell.exe -NoProfile -Command "$VIVADO_PS -source '$HERE_WIN\\ila_capture.tcl' -tclargs program" \
        > "$OUT/program.log" 2>&1
else
    powershell.exe -NoProfile -Command "$VIVADO_PS -source '$HERE_WIN\\program_only.tcl'" \
        > "$OUT/program.log" 2>&1
fi
grep -aq "PROGRAMMED" "$OUT/program.log" || {
    echo "BOARD_TEST: FAIL programming failed (see $OUT/program.log)"; exit 3; }

echo "[boardtest] running $BT"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File board_expect.ps1 \
    -Script "boardtests\\${NAME}.bt" -Log "${OUT_WIN}\\console.log" \
    | tee "$OUT/verdict.txt"
RC=${PIPESTATUS[0]}

if [ "$RC" -ne 0 ]; then
    echo "[boardtest] FAIL (rc=$RC) - preserving live state"
    if [ "$HAS_ILA" = "-ila" ]; then
        echo "[boardtest] taking ILA capnow of the live machine"
        rm -f "$BOARD_DIR/ila_data.csv"
        powershell.exe -NoProfile -Command "$VIVADO_PS -source '$HERE_WIN\\ila_capture.tcl' -tclargs capnow" \
            > "$OUT/capnow.log" 2>&1
        [ -f "$BOARD_DIR/ila_data.csv" ] && cp "$BOARD_DIR/ila_data.csv" "$OUT/ila_hang.csv"
    fi
    echo "BOARD_TEST: FAIL $NAME (artifacts: $OUT)"
    exit "$RC"
fi

echo "BOARD_TEST: PASS $NAME (artifacts: $OUT)"
exit 0
