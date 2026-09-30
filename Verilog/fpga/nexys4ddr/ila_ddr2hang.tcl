# DDR2-main-RAM SINTRAN-hang capture (25-AUG-2026).
# Probes (build.tcl -tclargs ilaslim): CSA_12_0, cpu_txd, s_ila_ddr2[7:0]
#   s_ila_ddr2: [7:5] astate  [4] MEM_HOLD  [3] last_hit  [2] refill_pend
#               [1] op_busy   [0] have_data
# Modes:
#   snap  immediate capture (trigger_now) - use WHILE the hang is live;
#         writes ila_hang.csv next to this script
#   hold  arm on MEM_HOLD==1 level, wait up to 3 min, then upload
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
set_property PARAM.FREQUENCY 5000000 [current_hw_target]
set dev [lindex [get_hw_devices xc7a100t*] 0]
current_hw_device $dev
set_property PROBES.FILE [file join $outdir nd120_nexys4ddr.ltx] $dev
refresh_hw_device $dev
set ila [lindex [get_hw_ilas] 0]
if {$ila eq ""} { puts "ERROR: no hw_ila found"; exit 1 }

set_property CONTROL.TRIGGER_POSITION 512 $ila
set_property CONTROL.CAPTURE_MODE ALWAYS $ila

if {$mode eq "at"} {
    # boot-alignment capture: trigger on a READ of the given octal word
    # address; store ONE sample per access (capture-qualify on the bridge
    # A_COL lookup state) so the window holds ~1024 consecutive accesses.
    # usage: -tclargs at <octal-addr> [pretrig]
    set at_oct  [lindex $argv 1]
    set pretrig [lindex $argv 2]
    if {$pretrig eq ""} { set pretrig 64 }
    set at_val [expr 0o$at_oct]
    set pm [lindex [get_hw_probes *s_ila_maddr* -of_objects $ila] 0]
    # 22-bit compare: bit21=1 (read) + the 21-bit address
    set cmpbits [format %022b [expr (1<<21) | $at_val]]
    set_property TRIGGER_COMPARE_VALUE eq22'b$cmpbits $pm
    set pd [lindex [get_hw_probes *s_ila_ddr2* -of_objects $ila] 0]
    set_property CAPTURE_COMPARE_VALUE eq8'b001xxxxx $pd
    set_property CONTROL.CAPTURE_MODE BASIC $ila
    set_property CONTROL.TRIGGER_POSITION $pretrig $ila
    run_hw_ila $ila
    puts "ARMED at RD $at_oct (capture-qualified per access)"
    if {[catch {wait_on_hw_ila -timeout 5 $ila} err]} {
        puts "NO TRIGGER: address never fetched in 5 min ($err)"
        close_hw_manager
        exit 2
    }
} elseif {$mode eq "wrat"} {
    # 25-AUG PIL-11 spin hunt: trigger on a WRITE of the given octal word
    # address (bit21=0), capture-qualified one sample per access - shows who
    # writes the 056063 interlock word (CPU store vs DMA burst pattern).
    set at_oct  [lindex $argv 1]
    set pretrig [lindex $argv 2]
    if {$pretrig eq ""} { set pretrig 64 }
    set at_val [expr 0o$at_oct]
    set pm [lindex [get_hw_probes *s_ila_maddr* -of_objects $ila] 0]
    set cmpbits [format %022b $at_val]
    set_property TRIGGER_COMPARE_VALUE eq22'b$cmpbits $pm
    set pd [lindex [get_hw_probes *s_ila_ddr2* -of_objects $ila] 0]
    set_property CAPTURE_COMPARE_VALUE eq8'b001xxxxx $pd
    set_property CONTROL.CAPTURE_MODE BASIC $ila
    set_property CONTROL.TRIGGER_POSITION $pretrig $ila
    run_hw_ila $ila
    puts "ARMED at WR $at_oct (capture-qualified per access)"
    if {[catch {wait_on_hw_ila -timeout 10 $ila} err]} {
        puts "NO TRIGGER: address never written in 10 min ($err)"
        close_hw_manager
        exit 2
    }
} elseif {$mode eq "wratraw"} {
    # raw-sample variant of wrat: no capture qualifier, every sysclk stored.
    # Shows the write to the given word with exact data and neighbours.
    set at_oct  [lindex $argv 1]
    set pretrig [lindex $argv 2]
    if {$pretrig eq ""} { set pretrig 512 }
    set at_val [expr 0o$at_oct]
    set pm [lindex [get_hw_probes *s_ila_maddr* -of_objects $ila] 0]
    set cmpbits [format %022b $at_val]
    set_property TRIGGER_COMPARE_VALUE eq22'b$cmpbits $pm
    set_property CONTROL.CAPTURE_MODE ALWAYS $ila
    set_property CONTROL.TRIGGER_POSITION $pretrig $ila
    run_hw_ila $ila
    puts "ARMED raw at WR $at_oct"
    if {[catch {wait_on_hw_ila -timeout 10 $ila} err]} {
        puts "NO TRIGGER: address never written in 10 min ($err)"
        close_hw_manager
        exit 2
    }
} elseif {$mode eq "wrval"} {
    # trigger on WRITE of a specific value to a specific word:
    # -tclargs wrval <octal-addr> <octal-value> [pretrig]
    # raw capture (write data is same-sample on this probe pair).
    set at_oct  [lindex $argv 1]
    set val_oct [lindex $argv 2]
    set pretrig [lindex $argv 3]
    if {$pretrig eq ""} { set pretrig 512 }
    set at_val [expr 0o$at_oct]
    set dv     [expr 0o$val_oct]
    set pm [lindex [get_hw_probes *s_ila_maddr* -of_objects $ila] 0]
    set cmpbits [format %022b $at_val]
    set_property TRIGGER_COMPARE_VALUE eq22'b$cmpbits $pm
    set pdat [lindex [get_hw_probes *s_ila_mdata* -of_objects $ila] 0]
    set_property TRIGGER_COMPARE_VALUE eq16'b[format %016b $dv] $pdat
    set_property CONTROL.TRIGGER_CONDITION AND $ila
    set_property CONTROL.CAPTURE_MODE ALWAYS $ila
    set_property CONTROL.TRIGGER_POSITION $pretrig $ila
    run_hw_ila $ila
    puts "ARMED wrval $at_oct = $val_oct"
    if {[catch {wait_on_hw_ila -timeout 10 $ila} err]} {
        puts "NO TRIGGER: value never written to that word in 10 min ($err)"
        close_hw_manager
        exit 2
    }
} elseif {$mode eq "rdval"} {
    # trigger on a READ of a word being served a specific value:
    # -tclargs rdval <octal-addr> <octal-value> [pretrig]
    # raw capture; deep pretrig shows the accesses that planted the value.
    set at_oct  [lindex $argv 1]
    set val_oct [lindex $argv 2]
    set pretrig [lindex $argv 3]
    if {$pretrig eq ""} { set pretrig 900 }
    set at_val [expr (1<<21) | 0o$at_oct]
    set dv     [expr 0o$val_oct]
    set pm [lindex [get_hw_probes *s_ila_maddr* -of_objects $ila] 0]
    set_property TRIGGER_COMPARE_VALUE eq22'b[format %022b $at_val] $pm
    set pdat [lindex [get_hw_probes *s_ila_mdata* -of_objects $ila] 0]
    set_property TRIGGER_COMPARE_VALUE eq16'b[format %016b $dv] $pdat
    set_property CONTROL.TRIGGER_CONDITION AND $ila
    set_property CONTROL.CAPTURE_MODE ALWAYS $ila
    set_property CONTROL.TRIGGER_POSITION $pretrig $ila
    run_hw_ila $ila
    puts "ARMED rdval $at_oct = $val_oct"
    if {[catch {wait_on_hw_ila -timeout 10 $ila} err]} {
        puts "NO TRIGGER: value never served from that word in 10 min ($err)"
        close_hw_manager
        exit 2
    }
} elseif {$mode eq "wrpage"} {
    # 25-AUG PIL-11 spin hunt: trigger on a WRITE anywhere in the given
    # 1KW physical page (octal page number). Catches the disc DMA landing.
    set pg_oct  [lindex $argv 1]
    set pretrig [lindex $argv 2]
    if {$pretrig eq ""} { set pretrig 512 }
    set pg_val [expr 0o$pg_oct]
    set pm [lindex [get_hw_probes *s_ila_maddr* -of_objects $ila] 0]
    # bit21=0 (write) + 11-bit page + 10 don't-care offset bits
    set cmpbits [format 0%011bXXXXXXXXXX $pg_val]
    set_property TRIGGER_COMPARE_VALUE eq22'b$cmpbits $pm
    set pd [lindex [get_hw_probes *s_ila_ddr2* -of_objects $ila] 0]
    set_property CAPTURE_COMPARE_VALUE eq8'b001xxxxx $pd
    set_property CONTROL.CAPTURE_MODE BASIC $ila
    set_property CONTROL.TRIGGER_POSITION $pretrig $ila
    run_hw_ila $ila
    puts "ARMED at WR page $pg_oct (capture-qualified per access)"
    if {[catch {wait_on_hw_ila -timeout 10 $ila} err]} {
        puts "NO TRIGGER: page never written in 10 min ($err)"
        close_hw_manager
        exit 2
    }
} elseif {$mode eq "trap"} {
    # trigger: trap fires (TRAPN falling) with the page-fault vector 3
    set pt [lindex [get_hw_probes *s_ila_trapn* -of_objects $ila] 0]
    set pv [lindex [get_hw_probes *s_ila_tvec* -of_objects $ila] 0]
    set pp [lindex [get_hw_probes *s_ila_pil* -of_objects $ila] 0]
    set_property TRIGGER_COMPARE_VALUE eq1'bF $pt
    set_property TRIGGER_COMPARE_VALUE eq4'h3 $pv
    # legitimate demand-paging faults happen at PIL 0/1 constantly; the
    # fatal signature is a page fault at ANY ISR level (PIL >= 8,
    # PIL bit3): 25-AUG boots have shown both Level 11 and Level 13
    # ERRFATALs, so the old ==11 term missed the Level-13 one.
    set_property TRIGGER_COMPARE_VALUE eq4'b1XXX $pp
    set_property CONTROL.TRIGGER_CONDITION AND $ila
    run_hw_ila $ila
    puts "ARMED on TRAPN fall + TVEC==3 + PIL >= 8"
    if {[catch {wait_on_hw_ila -timeout 4 $ila} err]} {
        puts "NO TRAP TRIGGER in 4 min ($err)"
        close_hw_manager
        exit 2
    }
} elseif {$mode eq "hold"} {
    set p [lindex [get_hw_probes *s_ila_ddr2* -of_objects $ila] 0]
    set_property TRIGGER_COMPARE_VALUE eq8'bXXX1XXXX $p
    run_hw_ila $ila
    puts "ARMED on MEM_HOLD==1"
    if {[catch {wait_on_hw_ila -timeout 3 $ila} err]} {
        puts "NO TRIGGER in 3 min: MEM_HOLD never high ($err)"
        close_hw_manager
        exit 2
    }
} else {
    run_hw_ila -trigger_now $ila
    wait_on_hw_ila $ila
}
# MEASURED 27-AUG-2026 (Vivado 2026.1): wait_on_hw_ila -timeout does NOT
# throw on timeout - it silently STOPS the core ("stopped by user", "No
# data to upload") and returns normally, so the catch branches above never
# fire and a timed-out run used to print CAPTURE WRITTEN over an EMPTY csv
# (header + radix rows only). Detect the empty upload and say so.
upload_hw_ila_data $ila
write_hw_ila_data -csv_file -force [file join $outdir ila_hang.csv] [current_hw_ila_data]
set _fh [open [file join $outdir ila_hang.csv] r]
set _nl 0
while {[gets $_fh _line] >= 0} { incr _nl }
close $_fh
if {$_nl <= 2} {
    puts "NO TRIGGER: the wait timed out (empty capture) - ila_hang.csv has no samples"
    close_hw_manager
    exit 2
}
puts "CAPTURE WRITTEN: ila_hang.csv ($_nl lines)"
close_hw_manager
