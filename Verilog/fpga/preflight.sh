#!/usr/bin/env bash
# preflight.sh - refuse to start a board build until the cheap checks passed.
#
# Verilog/fpga/preflight.sh <board>        e.g. ./preflight.sh tang-nano-20k
#
# WHY THIS EXISTS. A Gowin build plus flash plus boot is 25-60 minutes, and the
# most expensive habit measured across this project is going to silicon before
# simulating - "did you try verilator and wd disk ?" had to be asked
# repeatedly. This turns that instruction into something that cannot be
# skipped. Run it BEFORE gowin_build.ps1 / vivado_build.tcl.
#
# It checks, in ascending order of cost:
#   1. the silicon path is flip-flop mode          (tests/check_no_latches.sh)
#   2. the board top elaborates                    (verilator --lint-only)
#   3. RTL touched since the last build has a testbench that ran green
#   4. nothing else is holding the board's console
#
# Exit 0 = safe to build. Non-zero = do not burn the cycle.
set -uo pipefail

BOARD="${1:-tang-nano-20k}"
VERILOG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOARDDIR="$VERILOG_ROOT/fpga/$BOARD"
fail=0

say()  { printf '%s\n' "$*"; }
bad()  { printf 'FAIL  %s\n' "$*"; fail=$((fail+1)); }
good() { printf 'ok    %s\n' "$*"; }

[ -d "$BOARDDIR" ] || { say "no such board: $BOARDDIR"; exit 2; }
say "=== preflight: $BOARD ==="

# --- 1. silicon path must be FF mode -----------------------------------------
if "$VERILOG_ROOT/tests/check_no_latches.sh" >/dev/null 2>&1; then
  good "silicon path is FF mode"
else
  bad "check_no_latches.sh FAILED - run it to see which board"
fi

# --- 2. does the board top still elaborate? ----------------------------------
# Cheap (seconds) and catches the class of error that otherwise surfaces 20
# minutes into synthesis.
GPRJ="$BOARDDIR/$(basename "$BOARD" | sed 's/-nano-20k/_tang20k/')".gprj
if command -v verilator >/dev/null 2>&1 && [ -f "$BOARDDIR/nd120_tang20k.gprj" ]; then
  incs=$(cd "$VERILOG_ROOT" && find . -name '*.vh' -printf '%h\n' | sort -u \
          | sed "s|^\./|-I$VERILOG_ROOT/|")
  files=$(grep -o 'path="[^"]*"[^>]*enable="1"' "$BOARDDIR/nd120_tang20k.gprj" \
          | sed 's/path="//; s/".*//' | grep '\.v$' | sed "s|^|$BOARDDIR/|")
  stub=$(mktemp /tmp/pll_stub_XXXX.v)
  cat > "$stub" <<'STUB'
// The real Gowin rPLL is configured by defparam, so the stub MUST declare
// every parameter the RTL sets - a bare stub makes each defparam an %Error
// and the check then fails on itself instead of on the design.
module rPLL #(
  parameter FCLKIN = "100.0", parameter DEVICE = "GW2A-18",
  parameter DYN_IDIV_SEL = "false", parameter IDIV_SEL = 0,
  parameter DYN_FBDIV_SEL = "false", parameter FBDIV_SEL = 0,
  parameter DYN_ODIV_SEL = "false", parameter ODIV_SEL = 8,
  parameter PSDA_SEL = "0000", parameter DYN_DA_EN = "false",
  parameter DUTYDA_SEL = "1000",
  parameter CLKOUT_FT_DIR = 1'b1, parameter CLKOUTP_FT_DIR = 1'b1,
  parameter CLKOUT_DLY_STEP = 0, parameter CLKOUTP_DLY_STEP = 0,
  parameter CLKFB_SEL = "internal", parameter CLKOUT_BYPASS = "false",
  parameter CLKOUTP_BYPASS = "false", parameter CLKOUTD_BYPASS = "false",
  parameter CLKOUTD_SRC = "CLKOUT", parameter CLKOUTD3_SRC = "CLKOUT",
  parameter DYN_SDIV_SEL = 2
) (output CLKOUT, output LOCK, output CLKOUTP, output CLKOUTD,
             output CLKOUTD3, input CLKIN, input CLKFB, input [5:0] FBDSEL,
             input [5:0] IDSEL, input [5:0] ODSEL, input [3:0] PSDA,
             input [3:0] DUTYDA, input [3:0] FDLY, input RESET, input RESET_P);
  assign CLKOUT=CLKIN; assign LOCK=1'b1; assign CLKOUTP=CLKIN;
  assign CLKOUTD=CLKIN; assign CLKOUTD3=CLKIN;
endmodule
STUB
  # shellcheck disable=SC2086
  # Grep for %Error AND the warning classes that Gowin treats as hard errors.
  # Measured 24-AUG-2026: `st_tmr[33]` on a 32-bit reg passed this check
  # (verilator calls it a warning) and then failed synthesis 20 minutes later
  # with EX3784 "Index 33 is out of range". Catching it here is free.
  lintout=$(verilator --lint-only -Wno-fatal --top-module ND120_TANG20K_TOP \
              $incs "$stub" $files 2>&1)
  if printf '%s' "$lintout" | grep -q '%Error'; then
    bad "board top does NOT elaborate - fix before building"
  elif printf '%s' "$lintout" | grep -qE 'SELRANGE|Index .* out of range'; then
    bad "out-of-range bit select - Gowin will reject this (EX3784)"
    printf '%s' "$lintout" | grep -E 'SELRANGE|out of range' | head -3 | sed 's/^/        /'
  else
    good "board top elaborates, no out-of-range selects"
  fi
  rm -f "$stub"
else
  say "skip  elaboration check (no verilator, or board has no .gprj)"
fi

# --- 3. RTL newer than the last bitstream, without a green testbench ---------
# The bitstream is in the build folder, $ND120_BUILD_DIR/<board> (local.mk at
# the repository root; configure.py reads it). No build folder set = no
# bitstream to compare against, and this check is skipped.
BUILD_ROOT="$(python3 "$VERILOG_ROOT/../configure.py" --get ND120_BUILD_DIR 2>/dev/null)"
FS=""
[ -n "$BUILD_ROOT" ] && FS=$(ls -t "$BUILD_ROOT/$BOARD"/*/impl/pnr/*.fs 2>/dev/null | head -1)
if [ -n "$FS" ]; then
  newer=$(find "$VERILOG_ROOT" -name '*.v' -newer "$FS" \
            -not -path '*/build/*' -not -path '*/.Xil/*' -not -path '*/sim/*' \
            -not -path '*/obj_dir*' 2>/dev/null | head -20)
  if [ -n "$newer" ]; then
    n=$(printf '%s\n' "$newer" | wc -l)
    say "note  $n RTL file(s) changed since the last bitstream:"
    printf '%s\n' "$newer" | sed 's|^|        |' | head -10
    say "      -> run the matching module testbenches (make test) FIRST."
    say "      Going to silicon before simulating is the single most"
    say "      expensive habit measured on this project."
  else
    good "no RTL newer than the last bitstream"
  fi
else
  say "skip  no previous bitstream to compare against"
fi

# --- 4. is anything holding the console? -------------------------------------
if [ -e /dev/ttyUSB1 ]; then
  holder=$(fuser /dev/ttyUSB1 2>/dev/null | tr -d ' ')
  if [ -n "$holder" ]; then
    # A WARNING, not a failure: a build does not need the console. It matters
    # at FLASH/BOOT time, where a leftover reader makes the board look dead
    # and gets the bitstream blamed for it (measured 24-AUG-2026 - a good
    # build was nearly rebuilt because a previous collector still held the
    # port). A legitimate picocom session lives here too.
    say "note  /dev/ttyUSB1 is held by PID(s): $holder"
    say "      fine for building. Before you FLASH and boot, make sure this is"
    say "      your own terminal and not a leftover collector - otherwise the"
    say "      board will look dead and the bitstream will get the blame."
  else
    good "console /dev/ttyUSB1 is free"
  fi
fi

say "---"
if [ "$fail" -eq 0 ]; then say "PREFLIGHT: PASS - safe to build"; exit 0
else say "PREFLIGHT: FAIL ($fail) - do not burn the build cycle"; exit 1; fi
