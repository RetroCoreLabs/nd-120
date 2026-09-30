# ---------------------------------------------------------------------------
# ILA session for the CACHE-WRITE question (build.tcl -tclargs ilacache).
#
# THE QUESTION. CACHE-1X0-A00 test 2, run on the board 28-AUG-2026, reports the
# cache inert in both directions and both halves, paged and unpaged: nothing is
# ever copied INTO it, nothing is ever taken FROM it, so CUP never sets. A
# cache write is PAL_44402D asserting WCA, and its PALASM says
#
#   WCA = /RT * DT * EWC * CYD * /FMISS * /LSHADOW      ; write outside shadow
#       + RT * /IHIT * EWC * CYD * /FMISS * /LSHADOW    ; fetch/read without hit
#
# Both terms need EWC and CYD high and FMISS and LSHADOW low. The PAL is
# transcribed correctly (checked against DesignDocuments/PAL-Code/SRC/44402D.txt)
# and CON is tied high in ND120_CORE.v, so the blocker is one of WCINH_n,
# BRK_n, CYD, FMISS, LSHADOW - and the source cannot say which. This measures it.
#
# s_ila_cache, from CPU_MMU_24's DBG_CACHE port:
#   [0] LSHADOW  [1] FMISS  [2] CYD  [3] BRK_n  [4] WCINH_n  [5] WCA_n
#
# MODES (pass ONE as -tclargs):
#   program   program the .bit + .ltx and leave the board running
#   armnow    free-running capture, triggers immediately. Use this FIRST: one
#             window of the five gating bits while the test runs usually names
#             the blocker outright.
#   armwca    trigger on WCA_n going LOW - i.e. on the cache actually being
#             written. If this never triggers while test 2 runs, that is the
#             finding, and it is a stronger statement than any single window.
#   read      upload the capture to ila_cache.csv next to this script
#   status    print capture status and exit
#
# Order of work: program, then boot TPE and load CACHE-1X0-A00 over the serial
# console, THEN arm, then RUN 2, then read. Programming resets the machine, so
# arming before the program step measures nothing.
#
# Written 28-AUG-2026.
# ---------------------------------------------------------------------------

set srcdir [file dirname [file normalize [info script]]]
# The bitstream, probes file and captures live in the build folder,
# $ND120_BUILD_DIR/nexys4ddr (local.mk at the repository root, written by
# configure.py) - never in this source folder.
source [file join $srcdir .. paths.tcl]
set outdir [nd120_board_dir nexys4ddr]
set mode   [lindex $argv 0]

open_hw_manager
connect_hw_server
open_hw_target
# ILA readback corrupts when JTAG TCK outpaces the ILA clock domain - keep TCK
# well below clk_cpu. Same reason and same value as ila_capture.tcl.
set_property PARAM.FREQUENCY 5000000 [current_hw_target]
set dev [lindex [get_hw_devices xc7a100t*] 0]
current_hw_device $dev

if {$mode eq "program"} {
    set_property PROGRAM.FILE [file join $outdir nd120_nexys4ddr.bit] $dev
    set_property PROBES.FILE  [file join $outdir nd120_nexys4ddr.ltx] $dev
    program_hw_devices $dev
    refresh_hw_device $dev
    puts "PROGRAMMED (JTAG, with probes)"
    exit 0
}

set_property PROBES.FILE [file join $outdir nd120_nexys4ddr.ltx] $dev
refresh_hw_device $dev

set ila [lindex [get_hw_ilas] 0]
if {$ila eq ""} { puts "ERROR: no hw_ila found"; exit 1 }

# The same net shows up under several hierarchy aliases; take ONE probe object.
set p_cache [lindex [get_hw_probes *s_ila_cache* -of_objects $ila] 0]
if {$p_cache eq ""} { puts "ERROR: s_ila_cache probe not found"; exit 1 }

if {$mode eq "armnow"} {
    # Trigger position 0 and an always-true condition: the window starts the
    # moment it is armed, which is what we want for a steady-state look.
    set_property CONTROL.TRIGGER_POSITION 0 $ila
    set_property CONTROL.CAPTURE_MODE ALWAYS $ila
    set_property CONTROL.TRIGGER_MODE BASIC_ONLY $ila
    # match anything: all six bits "don't care"
    set_property TRIGGER_COMPARE_VALUE eq8'bxxxxxxxx $p_cache
    run_hw_ila $ila
    puts "ILA ARMED (free-running)"
    exit 0
}

if {$mode eq "armwca"} {
    set_property CONTROL.TRIGGER_POSITION 256 $ila
    set_property CONTROL.CAPTURE_MODE ALWAYS $ila
    set_property CONTROL.TRIGGER_MODE BASIC_ONLY $ila
    # bit 5 is WCA_n, active LOW. Trigger the moment a cache write happens.
    set_property TRIGGER_COMPARE_VALUE eq8'bxx0xxxxx $p_cache
    run_hw_ila $ila
    puts "ILA ARMED (trigger: WCA_n low = a cache write)"
    exit 0
}

if {$mode eq "status"} {
    puts "TRIGGER_STATUS: [get_property CORE.STATUS $ila]"
    exit 0
}

if {$mode eq "read"} {
    # Fails loudly rather than writing a half-empty file if it never triggered:
    # "no trigger" is itself a result and must not look like a bad upload.
    set st [get_property CORE.STATUS $ila]
    puts "TRIGGER_STATUS: $st"
    display_hw_ila_data [upload_hw_ila_data $ila]
    set out [file join $outdir ila_cache.csv]
    write_hw_ila_data -csv_file -force $out [current_hw_ila_data]
    puts "WROTE: $out"
    exit 0
}

puts "ERROR: unknown mode '$mode' - use program | armnow | armwca | read | status"
exit 1
