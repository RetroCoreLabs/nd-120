#!/bin/bash
###############################################################################
# run_area_test.sh <AREA> - one instruction-verify area gate
#
# Boots INSTRUCTION-B (400$ papertape), types the AREA command, records the
# golden-format trace and compares it against the ND-110 reference:
#   $ND_REPOS/ND110Compile/traces/TRACE-INSTRUCTION-VERIFY-<AREA>.md
# ND_REPOS is the folder that holds the other ND checkouts; it must be set.
# Prints "TB_RESULT: PASS" only when the comparator reports equivalence.
#
# Heavy gate (~15 min sim): invoked from `make test-instr-<area>` /
# `make test-full`, not the fail-fast `make test`.
###############################################################################
set -u

AREA="${1:?usage: run_area_test.sh <AREA>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNSIM="$HERE/../../runSim"
if [ -z "${ND_REPOS:-}" ]; then
    echo "FAIL: ND_REPOS is not set - it names the folder that holds the"
    echo "      ND110Compile checkout, where the ND-110 golden traces live."
    echo "TB_RESULT: FAIL (ND_REPOS not set - area NOT tested)"
    exit 1
fi
GOLDEN="$ND_REPOS/ND110Compile/traces/TRACE-INSTRUCTION-VERIFY-${AREA}.md"
OUT="${TMPDIR:-/tmp}/nd120_iverify_${AREA}"
TRACE="$OUT.md"
LOG="$OUT.log"

# A missing golden is a FAILURE, never a skip: a gate that prints PASS
# without comparing anything would report a green area that was never tested.
# The ND-110 reference traces live in the ND110Compile repository, outside
# this one; check that it is checked out where GOLDEN points.
if [ ! -f "$GOLDEN" ]; then
    echo "FAIL: golden trace not found: $GOLDEN"
    echo "      The ND-110 reference traces come from the ND110Compile repository."
    echo "      Without the golden file this area cannot be checked."
    echo "TB_RESULT: FAIL (no golden trace - area NOT tested)"
    exit 1
fi

cd "$RUNSIM" || exit 1
make compile USE_LATCHES=0 EXTRA_VDEFINES="--public-flat-rw" \
     EXTRA_CFLAGS="-DND120_TRACE_VERIFY" > "$LOG" 2>&1 || {
    echo "FAIL: runSim build failed (see $LOG)"; echo "TB_RESULT: FAIL"; exit 1; }

rm -f "$TRACE"
# Match golden's capture window: arm our emitter at the golden trace's own
# first-section fetch address (the 14 area traces arm on the first test-code
# fetch at PIL 0; RUN arms at the first PIL-1 instruction). Extract it from the
# golden `### #1  \`<addr> : <opcode>\`` header.
ARM="$(grep -m1 -E '^### #1[^0-9]' "$GOLDEN" | grep -oE '`[0-7]+' | head -1 | tr -d '`')"
if [ -z "$ARM" ]; then
    echo "FAIL: could not read arm address from $GOLDEN"; echo "TB_RESULT: FAIL"; exit 1
fi
echo "arming at golden first-section address $ARM (octal)"
# MAX_CNT is a safety ceiling only - the emitter exits as soon as it has
# recorded ND120_TVERIFY_MAX (400) instructions (see Run120.cpp tverify block),
# so a run terminates promptly instead of spinning. Floating-point areas need a
# longer preamble, hence the generous bound.
# TVERIFY_MAX=460 (not 400): our emitter double-logs EXR (executed instruction
# as a second same-address row) and logs panel interludes, so ~416-424 raw rows
# are needed to cover the golden's 400 unique test-level instructions after
# normalization. The comparator aligns the golden's full 400; our extra tail is
# harmless.
printf '400$%s\r' "$AREA" | \
    ND120_MAX_CNT=800000000 ND120_STDIN_GAP=300000 \
    ND120_TVERIFY_ARM_ADDR="$ARM" ND120_TVERIFY_MAX=460 \
    ND120_TVERIFY_OUT="$TRACE" \
    ND120_TVERIFY_SYMS="$HERE/nd120_symbols.tsv" \
    ./obj_dir/VND120_TOP >> "$LOG" 2>&1

if ! grep -q "Run summary" "$TRACE" 2>/dev/null; then
    echo "FAIL: trace did not complete (no Run summary in $TRACE, see $LOG)"
    echo "TB_RESULT: FAIL"
    exit 1
fi

DIVLOG="$OUT.divergence.md"
python3 "$HERE/compare_trace.py" --map "$HERE/nd110_nd120_mic_map.tsv" \
    "$GOLDEN" "$TRACE" --ignore-regs F --divergence-log "$DIVLOG"
rc=$?
if [ $rc -eq 0 ]; then
    echo "TB_RESULT: PASS"
else
    echo "trace kept at $TRACE for analysis"
    echo "DIVERGENCE DETAIL (registers + context + microcode): $DIVLOG"
    echo "TB_RESULT: FAIL"
fi
exit $rc
