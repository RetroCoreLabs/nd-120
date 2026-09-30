# ILA session for the floppy CB-fetch / FDISK seam (build.tcl -tclargs ila).
# Modes (pass ONE as -tclargs):
#   program   program nd120_nexys4ddr.bit + .ltx, leave the board at OPCOM
#   arm       arm the ILA: trigger = rising edge of the floppy DMA client
#             request (first command-block fetch word); capture qualifier =
#             any of req/ack/FDISK_REQ/FDISK_DONE high, so idle cycles are
#             not stored. Returns immediately after arming.
#   read      upload a completed capture and write ila_data.csv next to
#             this script. Fails if the ILA has not triggered yet.
#   status    print the ILA capture status and exit.

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
# ILA readback corrupts when JTAG TCK outpaces the ILA clock domain
# (12.5 MHz clk_cpu): drop TCK well below it.
set_property PARAM.FREQUENCY 5000000 [current_hw_target]
set dev [lindex [get_hw_devices xc7a100t*] 0]
current_hw_device $dev

if {$mode eq "program"} {
    set_property PROGRAM.FILE [file join $outdir nd120_nexys4ddr.bit] $dev
    set_property PROBES.FILE  [file join $outdir nd120_nexys4ddr.ltx] $dev
    program_hw_devices $dev
    refresh_hw_device $dev
    puts "PROGRAMMED (JTAG, with probes)"
} else {
    set_property PROBES.FILE [file join $outdir nd120_nexys4ddr.ltx] $dev
    refresh_hw_device $dev
}

set ila [lindex [get_hw_ilas] 0]
if {$ila eq ""} { puts "ERROR: no hw_ila found"; exit 1 }

if {$mode eq "arm"} {
    set_property CONTROL.TRIGGER_POSITION 256 $ila
    set_property CONTROL.CAPTURE_MODE ALWAYS $ila
    # the same net can appear under several hierarchy aliases - use ONE probe
    set_property TRIGGER_COMPARE_VALUE eq1'bR \
        [lindex [get_hw_probes *s_fdma_req* -of_objects $ila] 0]
    run_hw_ila $ila
    puts "ILA ARMED"
} elseif {$mode eq "capture"} {
    # arm, poll for the trigger (kick the program from another shell while
    # this runs), then upload IN THE SAME SESSION - separate sessions have
    # shown corrupted uploads (Labtools 27-3312).
    set_property CONTROL.TRIGGER_POSITION 256 $ila
    set_property CONTROL.CAPTURE_MODE ALWAYS $ila
    set_property TRIGGER_COMPARE_VALUE eq1'bR \
        [lindex [get_hw_probes *s_fdma_req* -of_objects $ila] 0]
    run_hw_ila $ila
    puts "ILA ARMED (in-session)"
    if {[catch {wait_on_hw_ila -timeout 3 $ila} err]} {
        puts "ILA TIMEOUT: no trigger in 3 min ($err)"
        close_hw_manager
        exit 1
    }
    upload_hw_ila_data $ila
    set d [current_hw_ila_data]
    write_hw_ila_data -force -csv_file [file join $outdir ila_data.csv] $d
    puts "ILA DATA WRITTEN"
} elseif {$mode eq "capnow"} {
    # capture whatever is happening RIGHT NOW (steady-state runaway): no
    # trigger compare at all = the first sample triggers; upload in-session
    set_property CONTROL.TRIGGER_POSITION 0 $ila
    set_property CONTROL.CAPTURE_MODE ALWAYS $ila
    run_hw_ila $ila
    if {[catch {wait_on_hw_ila -timeout 1 $ila} err]} {
        puts "ILA TIMEOUT ($err)"; close_hw_manager; exit 1
    }
    upload_hw_ila_data $ila
    set d [current_hw_ila_data]
    write_hw_ila_data -force -csv_file [file join $outdir ila_data.csv] $d
    puts "ILA DATA WRITTEN"
} elseif {$mode eq "captrans"} {
    # trigger on the FIRST arrival at the runaway code (CSA == 0o16035,
    # 13 bits) with ~3800 samples of PRE-trigger history: the instructions
    # that led there. Arm, then drive the console from another shell.
    set_property CONTROL.TRIGGER_POSITION 3800 $ila
    set_property CONTROL.CAPTURE_MODE ALWAYS $ila
    set_property TRIGGER_COMPARE_VALUE eq13'h1C1D \
        [lindex [get_hw_probes *CSA_12_0* -of_objects $ila] 0]
    run_hw_ila $ila
    puts "ILA ARMED (transition)"
    # 180 s: long enough to drive the console (LIST-FILE-NAMES) from
    # another shell after arming - 6 s was only enough for a loop already
    # printing.
    if {[catch {wait_on_hw_ila -timeout 180 $ila} err]} {
        puts "ILA TIMEOUT ($err)"; close_hw_manager; exit 1
    }
    upload_hw_ila_data $ila
    set d [current_hw_ila_data]
    write_hw_ila_data -force -csv_file [file join $outdir ila_data.csv] $d
    puts "ILA DATA WRITTEN"
} elseif {$mode eq "capjpl"} {
    # LIST-FILE-NAMES wrong-indirect-jump hunt (v3 probes): trigger on the
    # pointer word 0o060004 (hex 6004) arriving at the CGA_MAC on
    # s_cd_15_0. Arm at the FILSYS "User no." prompt, then type 0 from
    # another shell.
    #   - fires  -> the pointer reached the MAC intact; the samples after
    #               the trigger show s_ica_15_0 / s_la_23_10_out corrupting
    #               (or not).
    #   - 180 s timeout during the runaway -> the word never reached the
    #               MAC; the corruption is on the memory-read side.
    set_property CONTROL.TRIGGER_POSITION 1024 $ila
    set_property CONTROL.CAPTURE_MODE ALWAYS $ila
    # (a fresh hw session starts with don't-care compares on every probe)
    set_property TRIGGER_COMPARE_VALUE eq16'h6004 \
        [lindex [get_hw_probes *s_cd_15_0* -of_objects $ila] 0]
    run_hw_ila $ila
    puts "ILA ARMED (capjpl: s_cd_15_0 == 6004)"
    if {[catch {wait_on_hw_ila -timeout 180 $ila} err]} {
        puts "ILA TIMEOUT ($err)"; close_hw_manager; exit 1
    }
    upload_hw_ila_data $ila
    set d [current_hw_ila_data]
    write_hw_ila_data -force -csv_file [file join $outdir ila_data.csv] $d
    puts "ILA DATA WRITTEN"
} elseif {$mode eq "capbad"} {
    # Catch the FAILING pass of the LIST-FILE-NAMES indirect jump: trigger
    # the first time the effective address equals the WRONG target 0o016004
    # (hex 1c04) on s_ica_15_0. Deep pre-history (3800 samples ~ 80+
    # instructions) shows the JPL I fetch and the pointer value on
    # s_cd_15_0 at the moment it went wrong. Arm at the FILSYS "User no."
    # prompt, then type 0 from another shell. 24-AUG: the healthy pass was
    # captured with capjpl - CD=6004 -> ICA=6004 -> LA=0018, all correct -
    # so the fault is intermittent and only the bad pass matters.
    set_property CONTROL.TRIGGER_POSITION 3800 $ila
    set_property CONTROL.CAPTURE_MODE ALWAYS $ila
    set_property TRIGGER_COMPARE_VALUE eq16'h1c04 \
        [lindex [get_hw_probes *s_ica_15_0* -of_objects $ila] 0]
    run_hw_ila $ila
    puts "ILA ARMED (capbad: s_ica_15_0 == 1c04)"
    if {[catch {wait_on_hw_ila -timeout 180 $ila} err]} {
        puts "ILA TIMEOUT ($err)"; close_hw_manager; exit 1
    }
    upload_hw_ila_data $ila
    set d [current_hw_ila_data]
    write_hw_ila_data -force -csv_file [file join $outdir ila_data.csv] $d
    puts "ILA DATA WRITTEN"
} elseif {$mode eq "caperr"} {
    # First entry into FILSYS's DEVICE NEVER READY error printer (0o060224
    # = 0x6094 on s_ica_15_0), deep pre-history: the 3800 samples before it
    # contain the status read (device IOX / console IOR / memory flag) whose
    # test failed. Arm at the "User no." prompt, then type 0.
    set_property CONTROL.TRIGGER_POSITION 3800 $ila
    set_property CONTROL.CAPTURE_MODE ALWAYS $ila
    set_property TRIGGER_COMPARE_VALUE eq16'h6094 \
        [lindex [get_hw_probes *s_ica_15_0* -of_objects $ila] 0]
    run_hw_ila $ila
    puts "ILA ARMED (caperr: s_ica_15_0 == 6094)"
    if {[catch {wait_on_hw_ila -timeout 5 $ila} err]} {
        puts "ILA TIMEOUT ($err)"; close_hw_manager; exit 1
    }
    upload_hw_ila_data $ila
    set d [current_hw_ila_data]
    write_hw_ila_data -force -csv_file [file join $outdir ila_data.csv] $d
    puts "ILA DATA WRITTEN"
} elseif {$mode eq "capda"} {
    # Phantom-input hunt (24-AUG): trigger when a microcode IOR read
    # (EIOR_n low) captures DA_n low = "console input char available" while
    # nobody is typing. Two probe compares AND together in basic mode.
    # Fires -> phantom input confirmed; 3-min timeout -> no phantom chars.
    set_property CONTROL.TRIGGER_POSITION 2048 $ila
    set_property CONTROL.CAPTURE_MODE ALWAYS $ila
    set_property TRIGGER_COMPARE_VALUE eq1'b0 \
        [lindex [get_hw_probes *s_eiorn_n -of_objects $ila] 0]
    set_property TRIGGER_COMPARE_VALUE eq16'bX0XX_XXXX_XXXX_XXXX \
        [lindex [get_hw_probes *s_io_idb_15_0_out* -of_objects $ila] 0]
    run_hw_ila $ila
    puts "ILA ARMED (capda: EIOR read with DA available)"
    if {[catch {wait_on_hw_ila -timeout 3 $ila} err]} {
        puts "ILA TIMEOUT ($err)"; close_hw_manager; exit 1
    }
    upload_hw_ila_data $ila
    set d [current_hw_ila_data]
    write_hw_ila_data -force -csv_file [file join $outdir ila_data.csv] $d
    puts "ILA DATA WRITTEN"
} elseif {$mode eq "capmenu"} {
    # LFN-runaway decision hunt (24-AUG morning): the reprint reads the
    # menu-line text at word 0o010446 (0x1126) once per printed line.
    # Trigger on the effective address hitting that word; the 3800
    # pre-trigger samples contain the code path that DECIDED to print
    # (branch operand reads included). Run while the runaway is printing.
    set_property CONTROL.TRIGGER_POSITION 3800 $ila
    set_property CONTROL.CAPTURE_MODE ALWAYS $ila
    set_property TRIGGER_COMPARE_VALUE eq16'h1126 \
        [lindex [get_hw_probes *s_ica_15_0* -of_objects $ila] 0]
    run_hw_ila $ila
    puts "ILA ARMED (capmenu: s_ica_15_0 == 1126)"
    if {[catch {wait_on_hw_ila -timeout 2 $ila} err]} {
        puts "ILA TIMEOUT ($err)"; close_hw_manager; exit 1
    }
    upload_hw_ila_data $ila
    set d [current_hw_ila_data]
    write_hw_ila_data -force -csv_file [file join $outdir ila_data.csv] $d
    puts "ILA DATA WRITTEN"
} elseif {$mode eq "capioq"} {
    # Global console-IO trace (24-AUG): store ONLY samples where EIOR_n is
    # low - every microcode IOR (console status) read over many seconds,
    # with the IOR value and CSA. The whole runaway IO story in one
    # capture. Trigger = immediate.
    set_property CONTROL.TRIGGER_POSITION 0 $ila
    set_property CONTROL.CAPTURE_MODE BASIC $ila
    set_property CAPTURE_COMPARE_VALUE eq1'b0 \
        [lindex [get_hw_probes *s_eiorn_n -of_objects $ila] 0]
    run_hw_ila $ila
    puts "ILA ARMED (capioq: EIOR-qualified)"
    if {[catch {wait_on_hw_ila -timeout 2 $ila} err]} {
        puts "ILA TIMEOUT ($err)"; close_hw_manager; exit 1
    }
    upload_hw_ila_data $ila
    set d [current_hw_ila_data]
    write_hw_ila_data -force -csv_file [file join $outdir ila_data.csv] $d
    puts "ILA DATA WRITTEN"
} elseif {$mode eq "capgap"} {
    # Inter-line-gap code capture (24-AUG): trigger on the per-line
    # bookkeeping write 0x57D7 (one of the 8 writes that end each printed
    # line) and capture FORWARD - the window lands inside the ~0.8 s
    # no-write spin and shows exactly which code loops there.
    set_property CONTROL.TRIGGER_POSITION 256 $ila
    set_property CONTROL.CAPTURE_MODE ALWAYS $ila
    set_property TRIGGER_COMPARE_VALUE eq1'b1 \
        [lindex [get_hw_probes *s_ila_ram_wr -of_objects $ila] 0]
    set_property TRIGGER_COMPARE_VALUE eq15'h57D7 \
        [lindex [get_hw_probes *s_ila_ram_addr* -of_objects $ila] 0]
    run_hw_ila $ila
    puts "ILA ARMED (capgap: write to 0x57D7)"
    if {[catch {wait_on_hw_ila -timeout 2 $ila} err]} {
        puts "ILA TIMEOUT ($err)"; close_hw_manager; exit 1
    }
    upload_hw_ila_data $ila
    set d [current_hw_ila_data]
    write_hw_ila_data -force -csv_file [file join $outdir ila_data.csv] $d
    puts "ILA DATA WRITTEN"
} elseif {$mode eq "capinp"} {
    # Input-path discriminator (24-AUG): trigger when the INPUT poll's own
    # IOX 302 service (executing at ICA==0x6106) strobes an IOR read
    # (EIOR_n low) that shows DA=char available (bit14==0 while driven).
    # Type a char into the runaway first. Post-trigger flow shows the BSKP
    # outcome: 0x6107->0x6109 = char seen and taken; ->0x6108 = the status
    # assembly DROPPED the DA bit between IOR and the BSKP.
    set_property CONTROL.TRIGGER_POSITION 512 $ila
    set_property CONTROL.CAPTURE_MODE ALWAYS $ila
    set_property TRIGGER_COMPARE_VALUE eq1'b0 \
        [lindex [get_hw_probes *s_eiorn_n -of_objects $ila] 0]
    set_property TRIGGER_COMPARE_VALUE eq16'h6106 \
        [lindex [get_hw_probes *s_ica_15_0* -of_objects $ila] 0]
    set_property TRIGGER_COMPARE_VALUE eq16'bX0XX_XXXX_XXXX_XXXX \
        [lindex [get_hw_probes *s_io_idb_15_0_out* -of_objects $ila] 0]
    run_hw_ila $ila
    puts "ILA ARMED (capinp: input-poll IOR read with DA)"
    if {[catch {wait_on_hw_ila -timeout 2 $ila} err]} {
        puts "ILA TIMEOUT ($err)"; close_hw_manager; exit 1
    }
    upload_hw_ila_data $ila
    set d [current_hw_ila_data]
    write_hw_ila_data -force -csv_file [file join $outdir ila_data.csv] $d
    puts "ILA DATA WRITTEN"
} elseif {$mode eq "capqual"} {
    # Qualified write-trace (24-AUG): store ONLY samples where the main-RAM
    # write strobe is high - 4096 samples then span SECONDS of real time,
    # one row per memory write (addr+data), bridging the ~0.8 s inter-line
    # gap of the runaway. Trigger = immediate.
    set_property CONTROL.TRIGGER_POSITION 0 $ila
    set_property CONTROL.CAPTURE_MODE BASIC $ila
    set_property CAPTURE_COMPARE_VALUE eq1'b1 \
        [lindex [get_hw_probes *s_ila_ram_wr -of_objects $ila] 0]
    run_hw_ila $ila
    puts "ILA ARMED (capqual: RAM-write qualified)"
    if {[catch {wait_on_hw_ila -timeout 2 $ila} err]} {
        puts "ILA TIMEOUT ($err)"; close_hw_manager; exit 1
    }
    upload_hw_ila_data $ila
    set d [current_hw_ila_data]
    write_hw_ila_data -force -csv_file [file join $outdir ila_data.csv] $d
    puts "ILA DATA WRITTEN"
} elseif {$mode eq "capready"} {
    # Inter-character-gap hunt (24-AUG): trigger on the LIVE TBMT_n
    # FALLING edge = a console character just completed, TX ready. The
    # forward window shows whether the next character starts within
    # microseconds (gap spent elsewhere) or the machine leaves the print
    # path (the 20 ms per-char mystery). Run while the runaway prints.
    set_property CONTROL.TRIGGER_POSITION 256 $ila
    set_property CONTROL.CAPTURE_MODE ALWAYS $ila
    set_property TRIGGER_COMPARE_VALUE eq1'bF \
        [lindex [get_hw_probes *s_tbmt_n -of_objects $ila] 0]
    run_hw_ila $ila
    puts "ILA ARMED (capready: TBMT_n falling)"
    if {[catch {wait_on_hw_ila -timeout 2 $ila} err]} {
        puts "ILA TIMEOUT ($err)"; close_hw_manager; exit 1
    }
    upload_hw_ila_data $ila
    set d [current_hw_ila_data]
    write_hw_ila_data -force -csv_file [file join $outdir ila_data.csv] $d
    puts "ILA DATA WRITTEN"
} elseif {$mode eq "capr6"} {
    # Scratch-R6 hunt (ILA v8, 24-AUG): trigger on a WRITE to WRF register
    # 14 (= microcode scratch R6, the console soft status). Watch the
    # written data (s_rb_15_0) and the register's live value
    # (s_reg14_r6_15_0) around it - does the "device activated" bit 2 get
    # stored and does it read back? Arm at the User-no prompt, then CR.
    set_property CONTROL.TRIGGER_POSITION 1024 $ila
    set_property CONTROL.CAPTURE_MODE ALWAYS $ila
    set_property TRIGGER_COMPARE_VALUE eq16'bX1XX_XXXX_XXXX_XXXX \
        [lindex [get_hw_probes *RBLOCK/s_wr_15_0* -of_objects $ila] 0]
    run_hw_ila $ila
    puts "ILA ARMED (capr6: WRF write select bit 14)"
    if {[catch {wait_on_hw_ila -timeout 3 $ila} err]} {
        puts "ILA TIMEOUT ($err)"; close_hw_manager; exit 1
    }
    upload_hw_ila_data $ila
    set d [current_hw_ila_data]
    write_hw_ila_data -force -csv_file [file join $outdir ila_data.csv] $d
    puts "ILA DATA WRITTEN"
} elseif {$mode eq "capcr"} {
    # Flow capture FORWARD from the LFN answer (24-AUG): trigger on the
    # RAM write of the CR character itself (wdata==0x000D) - the echoed/
    # buffered CR of the "User no." answer - with a small pre-window and
    # ~3800 samples of what follows. The RAM address column then gives the
    # clean memory-access sequence of the answer processing, to diff
    # against the oracle's instruction trace over the same span.
    set_property CONTROL.TRIGGER_POSITION 256 $ila
    set_property CONTROL.CAPTURE_MODE ALWAYS $ila
    set_property TRIGGER_COMPARE_VALUE eq1'b1 \
        [lindex [get_hw_probes *s_ila_ram_wr -of_objects $ila] 0]
    set_property TRIGGER_COMPARE_VALUE eq16'h000D \
        [lindex [get_hw_probes *s_ila_ram_wdata* -of_objects $ila] 0]
    run_hw_ila $ila
    puts "ILA ARMED (capcr: RAM write of 0x000D)"
    if {[catch {wait_on_hw_ila -timeout 3 $ila} err]} {
        puts "ILA TIMEOUT ($err)"; close_hw_manager; exit 1
    }
    upload_hw_ila_data $ila
    set d [current_hw_ila_data]
    write_hw_ila_data -force -csv_file [file join $outdir ila_data.csv] $d
    puts "ILA DATA WRITTEN"
} elseif {$mode eq "capwr"} {
    # THE decisive trigger (ILA v7): a main-RAM WRITE into the constant
    # pointer table - s_ila_ram_wr==1 AND s_ila_ram_addr==0x607C. The
    # oracle provably never writes there; on silicon the first such write
    # is the corruption, and the 3800 pre-trigger samples show the code
    # that did it. Arm right after the FILSYS banner, then type the
    # dialog. Change the address compare here to hunt other cells.
    set_property CONTROL.TRIGGER_POSITION 3800 $ila
    set_property CONTROL.CAPTURE_MODE ALWAYS $ila
    set_property TRIGGER_COMPARE_VALUE eq1'b1 \
        [lindex [get_hw_probes *s_ila_ram_wr -of_objects $ila] 0]
    set_property TRIGGER_COMPARE_VALUE eq15'h607C \
        [lindex [get_hw_probes *s_ila_ram_addr* -of_objects $ila] 0]
    run_hw_ila $ila
    puts "ILA ARMED (capwr: RAM write to 0x607C)"
    if {[catch {wait_on_hw_ila -timeout 3 $ila} err]} {
        puts "ILA TIMEOUT ($err)"; close_hw_manager; exit 1
    }
    upload_hw_ila_data $ila
    set d [current_hw_ila_data]
    write_hw_ila_data -force -csv_file [file join $outdir ila_data.csv] $d
    puts "ILA DATA WRITTEN"
} elseif {$mode eq "capfix2"} {
    # Catch the FIRST write of character junk into the constant pointer
    # table (24-AUG morning): oracle holds mem[0x6088]=0x57CF forever (its
    # whole LFN never writes the table - DAP write-watch proven); silicon
    # delivers 0x000D there during the runaway. Arm right after the FILSYS
    # banner, then type the dialog; the trigger catches the corrupting
    # store with 3800 samples of the writer's code.
    set_property CONTROL.TRIGGER_POSITION 3800 $ila
    set_property CONTROL.CAPTURE_MODE ALWAYS $ila
    set_property TRIGGER_COMPARE_VALUE eq16'h6088 \
        [lindex [get_hw_probes *s_ica_15_0* -of_objects $ila] 0]
    set_property TRIGGER_COMPARE_VALUE eq16'h000D \
        [lindex [get_hw_probes *s_cd_15_0* -of_objects $ila] 0]
    run_hw_ila $ila
    puts "ILA ARMED (capfix2: ICA==6088 && CD==000D)"
    if {[catch {wait_on_hw_ila -timeout 3 $ila} err]} {
        puts "ILA TIMEOUT ($err)"; close_hw_manager; exit 1
    }
    upload_hw_ila_data $ila
    set d [current_hw_ila_data]
    write_hw_ila_data -force -csv_file [file join $outdir ila_data.csv] $d
    puts "ILA DATA WRITTEN"
} elseif {$mode eq "capfix"} {
    # Corruption-writer hunt (24-AUG morning): the runaway's decision path
    # reads 0x1124 (menu-string pointer) from the exit-handler pointer-
    # table area at ~0x607C, where the oracle holds 0xAA87. Trigger on the
    # FIRST time 0x1124 appears on CD while the address is 0x607C - armed
    # BEFORE the LFN answer is typed, the pre-history shows the corrupting
    # write (or the first read of the already-corrupt cell).
    set_property CONTROL.TRIGGER_POSITION 3800 $ila
    set_property CONTROL.CAPTURE_MODE ALWAYS $ila
    set_property TRIGGER_COMPARE_VALUE eq16'h607C \
        [lindex [get_hw_probes *s_ica_15_0* -of_objects $ila] 0]
    set_property TRIGGER_COMPARE_VALUE eq16'h1124 \
        [lindex [get_hw_probes *s_cd_15_0* -of_objects $ila] 0]
    run_hw_ila $ila
    puts "ILA ARMED (capfix: ICA==607C && CD==1124)"
    if {[catch {wait_on_hw_ila -timeout 3 $ila} err]} {
        puts "ILA TIMEOUT ($err)"; close_hw_manager; exit 1
    }
    upload_hw_ila_data $ila
    set d [current_hw_ila_data]
    write_hw_ila_data -force -csv_file [file join $outdir ila_data.csv] $d
    puts "ILA DATA WRITTEN"
} elseif {$mode eq "read"} {
    upload_hw_ila_data $ila
    set d [current_hw_ila_data]
    write_hw_ila_data -force -csv_file [file join $outdir ila_data.csv] $d
    puts "ILA DATA WRITTEN"
} elseif {$mode eq "status"} {
    puts "CAPTURE STATUS: [get_property CONTROL.CAPTURE_STATUS $ila]"
}
close_hw_manager
