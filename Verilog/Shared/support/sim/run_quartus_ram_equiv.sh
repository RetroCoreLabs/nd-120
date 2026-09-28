#!/bin/bash
#############################################################################
#  run_quartus_ram_equiv.sh - the Quartus RAM arm vs the reference arm       #
#                                                                            #
#  WHY THIS EXISTS (01-SEP-2026)                                             #
#  ------------------------------                                            #
#  Only the MiSTer build compiles the `ifdef QUARTUS_RAM_INFER` sections of  #
#  IDT6168A_20.v (the WCS) and MEM_RAM_49_BLOCKRAM.v (main memory). Vivado,   #
#  Gowin and Verilator all compile the plain-Verilog model instead. So a      #
#  difference between the two is invisible to every normal simulation, and    #
#  shows up only as a board that does not boot.                              #
#                                                                            #
#  That is exactly what happened to the arm's PREDECESSOR, an explicit        #
#  altsyncram megafunction (31-AUG-2026, deleted 01-SEP-2026). The WCS was    #
#  built with outdata_reg_a="CLOCK0", which gives a TWO-clock read because    #
#  altsyncram always registers the address as well (M10K cannot read          #
#  asynchronously). The plain model takes ONE clock. Every microinstruction   #
#  therefore reached the microsequencer a clock late on that board, the       #
#  sequencer ran one step out of step with the cycle controller, and a nested #
#  microsubroutine T,RETURN popped the wrong address - so MACL never resumed  #
#  and the CPU looped in the interrupt-register microcode instead of         #
#  reaching OPCOM.                                                            #
#                                                                            #
#  It went unnoticed because the equivalence check of the day compared the    #
#  megafunction against a hand-written stub (altsyncram_stub.v), which was    #
#  itself wrong by one clock in BOTH settings, so the comparison passed.      #
#  Nothing can simulate a megafunction. That is why the megafunction arm and  #
#  its stub are gone, and why the surviving Quartus arm is ordinary Verilog:  #
#  iverilog runs the code Quartus will actually build, not a model of it.     #
#                                                                            #
#  METHOD: build each testbench TWICE and diff the logged waveforms - they    #
#  must be byte-identical.                                                    #
#    ref - the plain arm Vivado, Gowin, Verilator and iverilog all build      #
#    inf - -DQUARTUS_RAM_INFER, plain Verilog restructured for Quartus        #
#                                                                            #
#  TEETH, checked 01-SEP-2026: giving the `inf` arm one extra clock of read   #
#  latency - the exact bug above - makes this script FAIL. Note that breaking #
#  its write-first BYPASS does NOT, and that is correct: during a write       #
#  regWE_n is low, so D_3_0_OUT is masked to 0 that cycle and the bypassed    #
#  value is overwritten before the mask lifts. It is unobservable at the pin. #
#############################################################################
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SUP="$HERE/.."
CIRC="$HERE/../../../CPU-BOARD-3202/circuit"
IVERILOG=${IVERILOG:-iverilog}
VVP=${VVP:-vvp}
fail=0

# run one arm and leave its logged waveform in /tmp/eq_<label>_<arm>.txt
# $1=label $2=arm $3=tb $4=dut $5=logfile  (extra args: iverilog flags/files)
run_arm () {
    local label="$1" arm="$2" tb="$3" dut="$4" log="$5"; shift 5
    rm -f "$log"
    $IVERILOG -g2012 -o "/tmp/eq_${label}_${arm}" "$tb" "$dut" "$@" || return 1
    # Each arm must ALSO pass its own self-check (28-SEP-2026): two arms that
    # agree can agree on a wrong answer, so the diff alone is not enough.
    local out; out=$($VVP "/tmp/eq_${label}_${arm}" 2>&1)
    cp "$log" "/tmp/eq_${label}_${arm}.txt" 2>/dev/null \
        || { echo "  $label/$arm: produced no log"; return 1; }
    rm -f "$log"        # the copy in /tmp is the one compared; keep the tree clean
    if ! printf '%s\n' "$out" | grep -q "^TB_RESULT: PASS"; then
        echo "  $label/$arm: self-check did not pass:"
        printf '%s\n' "$out" | grep -E "FAIL|checked" | head -12
        return 1
    fi
    echo "  $label/$arm: $(printf '%s\n' "$out" | grep '^checked')"
}

# compare one Quartus arm against the reference arm
cmp_arm () {            # $1 = label, $2 = arm, $3 = human name
    local label="$1" arm="$2" what="$3"
    local n; n=$(wc -l < "/tmp/eq_${label}_ref.txt")
    if diff -q "/tmp/eq_${label}_ref.txt" "/tmp/eq_${label}_${arm}.txt" > /dev/null; then
        echo "  $label / $what: MATCH ($n samples)"
        return 0
    fi
    echo "  $label / $what: MISMATCH - does not behave like the reference arm"
    diff "/tmp/eq_${label}_ref.txt" "/tmp/eq_${label}_${arm}.txt" | head -8
    return 1
}

check () {          # $1 = label, $2 = tb, $3 = dut, $4 = logfile, $5 = workdir
    local label="$1" tb="$2" dut="$3" log="$4" wd="$5" rc=0
    cd "$wd" || return 1

    # the reference arm - what Vivado, Gowin, Verilator and iverilog all build
    run_arm "$label" ref "$tb" "$dut" "$log" || return 1

    # QUARTUS_RAM_INFER: the restructured plain-Verilog arm. NOTHING is stubbed
    # here - it is ordinary Verilog, so iverilog runs the real thing. This
    # comparison tests the code Quartus will actually build, not a model of it.
    run_arm "$label" inf "$tb" "$dut" "$log" -DQUARTUS_RAM_INFER=1 \
        && cmp_arm "$label" inf "inference arm" || rc=1

    return $rc
}

# Which pair to check: "wcs" (IDT6168A_20, run by this directory's
# test-quartus-ram-equiv), "mem" (MEM_RAM_49_BLOCKRAM, run by
# CPU-BOARD-3202/circuit/sim test-mem-ram-equiv), or none given = both.
which="${1:-all}"
case "$which" in
    wcs|mem|all) ;;
    *) echo "usage: $0 [wcs|mem]"; echo "TB_RESULT: FAIL"; exit 1 ;;
esac

echo "Quartus RAM arm vs the plain-Verilog reference arm:"
if [ "$which" != mem ]; then
    check wcs  "$HERE/IDT6168A_20_equiv_tb.v" "$SUP/IDT6168A_20.v" equiv_log.txt "$HERE" || fail=1
fi
if [ "$which" != wcs ]; then
    check mem  "$CIRC/sim/MEM_RAM_49_BLOCKRAM_equiv_tb.v" "$CIRC/MEM_RAM_49_BLOCKRAM.v" \
               mem_equiv_log.txt "$CIRC/sim" || fail=1
fi

if [ "$fail" -eq 0 ]; then echo "TB_RESULT: PASS"; else echo "TB_RESULT: FAIL"; fi
exit $fail
