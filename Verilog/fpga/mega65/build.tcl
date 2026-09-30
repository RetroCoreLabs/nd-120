# ND-120 on the MEGA65 - self-contained in-memory Vivado flow, one board
# revision per run. THE WHOLE MACHINE: ND-120 CPU board, 4 MB main memory,
# TDV2200 terminal on the MEGA65's own keyboard and screen, floppy 0/1,
# Winchester 0/1 and paper tape on the framework's virtual drives.
#
#   vivado -mode batch -source build.tcl -tclargs board r6     # R6 (default): SDRAM main memory
#   vivado -mode batch -source build.tcl -tclargs board r3     # R3 / R3A:    HyperRAM main memory
#   vivado -mode batch -source build.tcl -tclargs board r4     # R4, R5: SDRAM like the R6
#   vivado -mode batch -source build.tcl -tclargs board r5
#   ... nocache        compile the CPU cache RAMs out (ND120_NO_CACHE)
#   ... nopanelclock   leave the MC68705 panel clock out (ND120_PANEL_CLOCK off)
#
# Template: fpga/nexys4ddr/build.tcl (same in-memory flow, same report
# battery, same "fail loudly on negative slack" gate). Differences:
#   - the framework's source list comes from ITS OWN project file for the
#     chosen revision, m2m/CORE/CORE-R<n>.xpr, so a framework update that
#     adds or drops a file is picked up without editing this script. Files
#     under the framework's CORE/ are redirected to OUR CORE/ next to the
#     submodule; the four board tops are redirected to
#     CORE/vhdl/framework-overrides/ (the SDRAM pins handed into the core).
#   - the CPU source list comes from the MiSTer core's files.qip, the
#     configuration this machine is copied from (SDRAM bridge + storage over
#     the block protocol + the shared console), minus the MiSTer-only files.
#   - all framework VHDL is read as VHDL-2008 (every .vhd in the .xpr is
#     SFType="VHDL2008"); the framework's three .v are MiSTer SystemVerilog.
#   - no JTAG programming step: there is no MEGA65 here. The product is the
#     .bit, packed into a per-revision .cor by the Makefile (coretool).
#
# MEMORY PER REVISION (docs/00-plan.md, Ronny 02-SEP-2026: both):
#   R4/R5/R6  MAIN_RAM_SDRAM + ND_SDRAM_PACK16 + ND_SDRAM_DQ16: the board's
#             64 MB SDRAM (IS42S16320F, 32M x 16) on the Tang/MiSTer sheet-49
#             bridge in 16-bit-module mode, exactly the DE10-Nano build that
#             boots SINTRAN. ND_SDRAM_REFRESH_US=7: that part has 8192 rows
#             to refresh in 64 ms = 7.8 us per row, the same figure the
#             MiSTer's 8192-row module uses.
#   R3        MAIN_RAM_DDR2: the Nexys variable-latency seam (MEM_RAM_49_DDR2
#             cache + MEM_HOLD) over the framework's HyperRAM Avalon port
#             through rtl/nd_avalon_port.v. The define's name is the Nexys's;
#             what it selects is the seam, not the chip.
#
# History: B0 (02-SEP-2026) built the framework's untouched demo core through
# this script to prove the toolchain (Vivado 2026.1 against projects written
# by 2022.2) - R6 WNS +0.284, R3 +0.339, ~14.8k LUTs, 55.5 BRAM tiles. B1 put
# the console on it (R6 +0.203, R3 +0.158). Both are in git history.
#
# "board r6" and "board=r6" are both accepted: cmd.exe splits on '=' (measured
# on the Nexys flow, 20-AUG-2026), so a script that only understood one form
# silently built the default.

set part   xc7a200tfbg484-2
set srcdir [file dirname [file normalize [info script]]]
set m2m    [file join $srcdir m2m]        ;# the MiSTer2MEGA65 submodule
set core   [file join $srcdir CORE]       ;# our side of the M2M contract
set vroot  [file normalize [file join $srcdir .. ..]]   ;# Verilog/
set mister [file join $vroot fpga mister]

proc has_flag {name} {
    global argv
    set want [string tolower [string trimleft $name "-"]]
    foreach a $argv {
        if {[string tolower [string trimleft $a "-"]] eq $want} { return 1 }
    }
    return 0
}

set board r6
set _n [llength $argv]
for {set i 0} {$i < $_n} {incr i} {
    set a [lindex $argv $i]
    if {[regexp {^board=(\w+)$} $a -> v]} {
        set board [string tolower $v]
    } elseif {$a eq "board" && $i + 1 < $_n} {
        set board [string tolower [lindex $argv [expr {$i + 1}]]]
    }
}
if {[lsearch -exact {r3 r4 r5 r6} $board] < 0} {
    puts "ERROR: board=$board not supported. Choose one of: r3 r4 r5 r6"
    exit 1
}
set BOARD [string toupper $board]
set memory [expr {$board eq "r3" ? "hyperram" : "sdram"}]
puts "argv: $argv  -> board = $board, main memory = $memory"

# ---- prerequisites the framework needs baked into the bitstream ------------
# The QNICE soft CPU's firmware and the OSD font are read at synthesis by
# VHDL textio (m2m/M2M/QNICE/vhdl/block_rom.vhd and m2m/M2M/vhdl/*), with
# paths that resolve relative to the reading source file. They are set in
# CORE/vhdl/globals.vhd. Check them here so a missing ROM fails in one line
# instead of a page of "file not found" deep inside elaboration.
foreach {what path how} [list \
    "M2M firmware ROM" [file join $core m2m-rom m2m-rom.rom] \
        "make rom   (in WSL; needs make toolchain once)" \
    "QNICE monitor ROM" [file join $m2m M2M QNICE monitor monitor.rom] \
        "make toolchain   (in WSL)" \
    "OSD font" [file join $m2m M2M font Anikki-16x16-m2m.rom] \
        "git submodule update --init --recursive"] {
    if {![file exists $path]} {
        puts "ERROR: $what missing: $path"
        puts "       $how"
        exit 1
    }
}

# ---- outputs go to $ND120_BUILD_DIR/mega65/<board>/ ------------------------
# Never into the submodule, and never into this checkout: the build folder
# comes from ND120_BUILD_DIR (local.mk at the repository root, written by
# configure.py; the environment wins). Vivado works in it (cd), so .Xil and
# anything else it writes next to itself lands there too.
source [file join $srcdir .. paths.tcl]
set outdir [nd120_board_dir mega65/$board "MEGA65 build.tcl"]
cd $outdir

# ---- microcode: the WCS preloaded from the 33 nibble images ---------------
# SKIP_WCS_LOAD, as on the Tang, Nexys and MiSTer: the microcode goes into
# the WCS block RAMs as bitstream INIT and the original machine's runtime
# PROM->WCS load phase is bypassed (no PROM emulation compiled at all).
# $readmemh("wcs_NN.hex") in Shared/support/IDT6168A_20.v resolves against
# Vivado's WORKING directory (measured on the Nexys flow, 02-SEP-2026) - the
# build directory here - and the older note said next to the .v source.
# The images are copied into the build directory only: the second place,
# Shared/support, already holds TRACKED copies of the same raw board variant
# (test-microcode-sync keeps them equal), so copying there only risked
# dirtying the checkout. The master copies are made in Code/Microcode/wcs/ by
# gen_wcs_image.py, which configure.py runs.
set wcs_src [file normalize [file join $vroot .. Code Microcode wcs]]
set wcs_files [glob -nocomplain [file join $wcs_src wcs_*.hex]]
if {[llength $wcs_files] != 33} {
    puts "ERROR: expected 33 WCS images in $wcs_src, found [llength $wcs_files]"
    puts "       Run python3 configure.py from the repository root - it makes them."
    exit 1
}
foreach f $wcs_files {
    file copy -force $f [file join $outdir [file tail $f]]
}
puts "WCS preload: [llength $wcs_files] images copied (SKIP_WCS_LOAD)."

create_project -in_memory -part $part

# ---- framework sources from its project file -------------------------------
set xpr [file join $m2m CORE CORE-$BOARD.xpr]
if {![file exists $xpr]} {
    puts "ERROR: framework project missing: $xpr (is the submodule checked out?)"
    exit 1
}
set fp [open $xpr r]
set xml [read $fp]
close $fp

set vhdl {}
set verilog {}
set sverilog {}
set xdcs {}
set overrides [file join $core vhdl framework-overrides]
foreach {full path} [regexp -all -inline {<File Path="([^"]+)">} $xml] {
    # $PPRDIR is the framework's CORE/ folder. Its own files (vhdl/, CORE.xdc,
    # m2m-rom/) are the template we copied to OUR CORE/; everything under
    # ../M2M/ stays in the submodule - except a file with the same name under
    # CORE/vhdl/framework-overrides/, which replaces it (the board tops).
    if {[string match {$PPRDIR/../M2M/*} $path]} {
        set rel [string range $path [string length {$PPRDIR/../M2M/}] end]
        set f [file join $m2m M2M $rel]
        set ov [file join $overrides [file tail $rel]]
        if {[file exists $ov]} {
            puts "OVERRIDE: $rel <- CORE/vhdl/framework-overrides/[file tail $rel]"
            set f $ov
        }
    } elseif {[string match {$PPRDIR/*} $path]} {
        set f [file join $core [string range $path [string length {$PPRDIR/}] end]]
    } else {
        puts "ERROR: unexpected path shape in $xpr: $path"
        exit 1
    }
    # No comments inside this switch body: Tcl reads them as pattern/body
    # tokens ("extra switch pattern with no body", 02-SEP-2026). The *.tcl
    # arm is synth_pre.tcl, the framework's ROM hook - we build the ROM
    # before Vivado instead (Makefile: rom).
    switch -glob -- [string tolower $f] {
        *.vhd - *.vhdl { lappend vhdl $f }
        *.sv           { lappend sverilog $f }
        *.v            { lappend verilog $f }
        *.xdc          { lappend xdcs $f }
        *.tcl          { }
        default        { puts "WARNING: skipping $f (unknown type)" }
    }
}
foreach f [concat $vhdl $verilog $sverilog $xdcs] {
    if {![file exists $f]} {
        puts "ERROR: source listed in $xpr does not exist: $f"
        exit 1
    }
}
puts "Framework sources from CORE-$BOARD.xpr: [llength $vhdl] VHDL, [llength $verilog] Verilog, [llength $sverilog] SystemVerilog, [llength $xdcs] XDC"

read_vhdl -vhdl2008 $vhdl
# The framework's .v files are MiSTer files (av_pipeline/audio_out.v,
# controllers/MiSTer/*.v) and use SystemVerilog inside a .v - declarations
# inside an unnamed always-block. Vivado 2022.2 let that through as plain
# Verilog; 2026.1 refuses it ("[Synth 8-10632] declarations are not allowed
# in an unnamed block", measured 02-SEP-2026). Reading them as SV is what
# Quartus does on the MiSTer, where these files come from.
if {[llength $verilog]}  { read_verilog -sv $verilog }
if {[llength $sverilog]} { read_verilog -sv $sverilog }

# ---- the ND-120 machine: Verilog, ours ------------------------------------
# CPU board, bus devices, SDRAM bridge and the three storage adapters: the
# MiSTer core's list, minus what is MiSTer-only (its top, PLL, HPS storage,
# probes, framework) and minus the terminal (listed below by name).
set qip [file join $mister files.qip]
set fp [open $qip r]
set qtxt [read $fp]
close $fp
set mister_only {
    rtl/nd120_console_mister.v rtl/pll_cpu.v rtl/nd120_diag_print.v
    rtl/nd120_csa_trace.v rtl/nd120_sterr_catch.v rtl/nd120_storage_probe.v
    rtl/nd_storage_hps.v rtl/nd_storage_mister_devices.v
    build/term_banner_rom.v nd120.sdc nd120.sv
}
set cpu {}
foreach line [split $qtxt "\n"] {
    if {![regexp {(VERILOG_FILE|SYSTEMVERILOG_FILE)\s+(\S+)} $line -> _ rel]} { continue }
    if {[string match sys/* $rel]} { continue }
    if {[string match ../../Terminals/* $rel]} { continue }
    if {[string match *.qip $rel]} { continue }
    if {[lsearch -exact $mister_only $rel] >= 0} { continue }
    lappend cpu [file normalize [file join $mister $rel]]
}
if {$memory eq "hyperram"} {
    # the Nexys seam: the BRAM cache + MEM_HOLD freeze in front of the port
    lappend cpu [file join $vroot fpga nexys4ddr ddr2 MEM_RAM_49_DDR2.v]
}
puts "CPU sources from fpga/mister/files.qip: [llength $cpu] files"

# the shared terminal core + the UART bridge + the MIPS counter
set tdir [file join $vroot Terminals rtl]
set ours {}
foreach f {vga_timing.v font_rom.v char_ram.v text_screen.v terminal_ctrl.v
           terminal_ctrl_tdv.v
           cdc_byte.v byte_fifo.v terminal_top.v ps2_decoder.v
           ps2_ascii_table.v key_vt100.v
           ps2_decoder_tdv.v ps2_ascii_table_tdv.v key_tdv2200.v
           mips_counter.v term_banner.v
           term_console_feed.v term_panel.v term_panel_rom.v rate_meter.v
           ratio_meter.v console_uart_rx.v console_uart_tx.v} {
    lappend ours [file join $tdir $f]
}
# the MEGA65 glue
foreach f {nd120_mega65_machine.v nd120_console_mega65.v m65_keys_to_ps2.v
           nd_storage_mega65_devices.v nd_storage_vdrives.v nd_avalon_port.v} {
    lappend ours [file join $srcdir rtl $f]
}

# ---- build stamp in the power-on banner (standing rule on every terminal
# board): git short hash (+ if the tree was dirty), date/time, and the
# board/config line. Regenerated per build into the build folder so the
# committed ROM is never dirtied; falls back to the committed ROM if the
# generator cannot run. Nobody can tell two MEGA65 bitstreams apart from a
# photograph otherwise - and a photograph is all we get back.
set banner_rom [file join $tdir term_banner_rom.v]
set stamp ""
if {![catch {exec git -C $vroot rev-parse --short HEAD} _h]} {
    set stamp [string trim $_h]
    if {![catch {exec git -C $vroot status --porcelain} _d] && [string trim $_d] ne ""} {
        append stamp "+"
    }
}
append stamp [clock format [clock seconds] -format { %d-%b-%Y %H:%M}]
set _memtxt [expr {$memory eq "sdram" ? "SDRAM 4 MB" : "HyperRAM 4 MB"}]
set _cachetxt [expr {[has_flag nocache] ? "no cache" : "cache on"}]
set _mhz [expr {$board eq "r3" ? "13.33" : "20.00"}]
set config "MEGA65 $BOARD - $_mhz MHz - $_memtxt - $_cachetxt"
set _gen [file join $outdir term_banner_rom.v]
if {[catch {exec python [file join $vroot Terminals font make_banner.py] $stamp $_gen $config} _e]} {
    if {[catch {exec python3 [file join $vroot Terminals font make_banner.py] $stamp $_gen $config} _e2]} {
        puts "BANNER: generator failed ($_e2) - using the committed ROM"
        set _gen ""
    }
}
if {$_gen ne "" && [file exists $_gen]} {
    set banner_rom $_gen
    puts "BANNER: build stamp \"$stamp\", config \"$config\""
}
# The same stamp goes into the .cor header (Makefile: cor), read from this
# file so the flash menu and the banner never disagree about which build
# this is - the repo HEAD moves while Vivado runs (another session commits).
set _sf [open [file join $outdir banner_stamp.txt] w]
puts $_sf $stamp
close $_sf
lappend ours $banner_rom

foreach f [concat $cpu $ours] {
    if {![file exists $f]} { puts "ERROR: missing source: $f"; exit 1 }
}
read_verilog [concat $cpu $ours]
puts "ND-120 side: [llength $cpu] CPU + [llength $ours] terminal/glue Verilog files"

# XDC order as in the project: the board pin file, then common.xdc (clocks,
# bitstream settings), then CORE.xdc (the core's own generated clocks and our
# repair of the framework's ascal reset false path).
foreach x $xdcs { read_xdc $x }

# ---- Verilog defines -------------------------------------------------------
# The MiSTer configuration (fpga/mister/nd120.qsf) minus the Quartus-only ones
# (QUARTUS_RAM_INFER, QUARTUS_LATCH_RENAME - Vivado infers the WCS block RAMs
# from the plain IDT6168A_20 model as the Nexys does) and its ND120_NO_CACHE:
# the cache is BUILT IN here as on the Nexys (Xilinx fabric, the 31-AUG cache
# fixes proven on its board), with the OSD switch (CPU cache) selecting it at
# run time; pass nocache to compile it out.
#   FPGA_FF_MODE       edge-triggered flip-flops, not the original latches
#   BOARD_CLK_FREQ     20 MHz = clk.vhd CLKOUT1: the SC2661 baud divisor, the
#                      device timings, the RTC tick all derive from it
#   UART_BAUD_RATE     the console: 115200, fixed
#   SKIP_WCS_LOAD      microcode preloaded (above)
#   ND120_PANEL_CLOCK  the MC68705 panel clock, so SINTRAN can set/read time
#   ND120_MIPS_TAP     the CGA-side tap for the panel's MIPS field
# CPU clock per revision (CORE/vhdl/clk.vhd G_CPU_DIV, chosen in mega65.vhd
# from G_BOARD): 20 MHz on R4/R5/R6; 13.333 MHz on R3. The R3 netlist (the
# HyperRAM seam instead of the SDRAM bridge) times the CGA's IDB ring
# through a longer loop-break point: 93 logic levels, 57 ns, where the R6
# netlist's break gives 58 levels / 34 ns (both measured 02-SEP-2026 on
# the post-route checkpoints, the same WCS -> MAC endpoints). The ring is
# functionally impossible (fpga/nexys4ddr/build.tcl has the analysis) but
# the honest fix is a period that fits it, not a false path through the
# internal data bus.
set cpu_hz [expr {$board eq "r3" ? 13333333 : 20000000}]
set defines [list FPGA_FF_MODE BOARD_CLK_FREQ=$cpu_hz UART_BAUD_RATE=115200 \
                  SKIP_WCS_LOAD ND120_MIPS_TAP]
if {![has_flag nopanelclock]} { lappend defines ND120_PANEL_CLOCK }
if {[has_flag nocache]}       { lappend defines ND120_NO_CACHE }
if {$memory eq "sdram"} {
    lappend defines MAIN_RAM_SDRAM ND_SDRAM_PACK16 ND_SDRAM_DQ16 ND_SDRAM_REFRESH_US=7
} else {
    lappend defines MAIN_RAM_DDR2
}
set synth_args {}
foreach d $defines { lappend synth_args -verilog_define $d }
puts "Verilog defines: $defines"
# nd_storage `include "nd_storage_status.vh" (SD-FAT/circuit) and ND120_CORE
# `include "nd120_backwiring_defaults.vh" (Shared/support)
lappend synth_args -include_dirs [list \
    [file join $vroot SD-FAT circuit] \
    [file join $vroot Shared support]]

# The framework's clock-domain crossings are Xilinx XPM cells (xpm_cdc_*
# in clk_m2m.vhd, framework.vhd, vdrives.vhd) whose false-path constraints
# live in Vivado's own data/ip/xpm/xpm_cdc/tcl/*.tcl, applied only when the
# in-memory project knows XPM is in use. Project mode sets that up by
# itself; this flow must ask. Measured 02-SEP-2026 without it: every
# intra-clock group met timing and ALL 229 failing endpoints were
# qnice_clk<->main_clk XPM synchronisers plus the async-reset recovery
# paths, WNS -6.287 ns.
auto_detect_xpm
puts "XPM libraries in use: [get_property XPM_LIBRARIES [current_project]]"

# ---- synthesis -------------------------------------------------------------
set top mega65_$board
synth_design -top $top -part $part {*}$synth_args

# ---- clock-domain crossings of the machine ---------------------------------
# main_clk (40), cpu_clk (20) and sdram_clk (40 @ 180) share one MMCM and ARE
# related - the SDRAM bridge depends on that (it samples the CPU's RAS/CAS as
# synchronous signals), so they stay timed as synchronous. Everything else
# the machine talks to is a different MMCM: the storage backend's QNICE side
# (qnice_clk, 50 MHz) and, on R3, the HyperRAM port (hr_clk, 100 MHz). Both
# crossings are toggle handshakes with the payload held stable behind the
# toggle - the same shape the Nexys bounds with set_max_delay -datapath_only
# (fpga/nexys4ddr/build.tcl: NOT set_clock_groups, which left the payload
# buses untimed and let a payload race its toggle on the floppy client).
# One destination period per crossing.
set _ccpu [get_clocks -quiet cpu_clk]
set _cqn  [get_clocks -quiet qnice_clk]
set _chr  [get_clocks -quiet hr_clk]
if {[llength $_ccpu] == 0 || [llength $_cqn] == 0 || [llength $_chr] == 0} {
    puts "ERROR: expected clocks not found (cpu_clk/qnice_clk/hr_clk). Present: [get_clocks]"
    exit 1
}
set _cpu_ns [expr {1.0e9 / $cpu_hz}]
foreach {src dst lim} [list \
    $_ccpu $_cqn 20.000 \
    $_cqn  $_ccpu $_cpu_ns \
    $_ccpu $_chr 10.000 \
    $_chr  $_ccpu $_cpu_ns] {
    set_max_delay -datapath_only -from $src -to $dst $lim
}
# The OSD cache switch: a quasi-static bit from the framework's main_clk
# synchroniser into the machine's own 2-FF synchroniser on cpu_clk
# (nd120_mega65_machine.v s_cache_sync). Not a data path.
set _csync [get_cells -hierarchical -filter {NAME =~ *s_cache_sync_reg[0]}]
if {[llength $_csync] == 0} { puts "ERROR: s_cache_sync_reg[0] not found"; exit 1 }
set_false_path -to $_csync

# ---- implementation --------------------------------------------------------
opt_design
place_design
# The framework's impl_1 run has phys_opt_design enabled (CORE-R6.xpr,
# EnableStepBool=1); keep the flow the same as the one its cores ship from.
phys_opt_design
route_design
# Post-route hold repair. Measured 02-SEP-2026 on the first full R6 build:
# route_design's own summary said WHS +0.053, the sign-off report said
# -0.491 ns on the framework's MMCM DRP pins (i_video_out_clock cfg_den_reg
# -> MMCM/DEN: 1.68 ns of clock skew into the MMCM against 1.18 ns of data
# delay) plus a clk_m2m counter - 26 endpoints the router believed it had
# fixed. A hold violation on a DRP write would corrupt the framework's
# dynamic HDMI clock reprogramming, so it is not something to wave through.
# -hold_fix inserts data-path delay against the sign-off numbers.
phys_opt_design -hold_fix

report_utilization    -file [file join $outdir util.rpt]
report_timing_summary -file [file join $outdir timing.rpt]

# Post-route evidence set, same battery as the Nexys flow, in a run folder
# that is never overwritten.
set _rundir [file join $outdir timing-analysis run]
set _sfx 1
while {[file exists $_rundir]} {
    set _rundir [file join $outdir timing-analysis run_$_sfx]
    incr _sfx
}
file mkdir $_rundir
puts "REPORTS: $_rundir"
foreach {rname rcmd} [list \
    timing_summary_post_route.rpt {report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose -max_paths 100 -file $_rf} \
    setup_paths_post_route.rpt    {report_timing -delay_type max -max_paths 100 -nworst 20 -path_type full_clock_expanded -input_pins -file $_rf} \
    hold_paths_post_route.rpt     {report_timing -delay_type min -max_paths 100 -nworst 20 -path_type full_clock_expanded -input_pins -file $_rf} \
    clocks.rpt                    {report_clocks -file $_rf} \
    clock_interaction.rpt         {report_clock_interaction -delay_type min_max -file $_rf} \
    cdc.rpt                       {report_cdc -details -file $_rf} \
    methodology.rpt               {report_methodology -file $_rf} \
    utilization_hierarchical.rpt  {report_utilization -hierarchical -file $_rf} \
    high_fanout_nets.rpt          {report_high_fanout_nets -timing -max_nets 100 -file $_rf} \
    drc.rpt                       {report_drc -file $_rf}] {
    set _rf [file join $_rundir $rname]
    if {[catch {eval $rcmd} _err]} {
        puts "WARNING: $rname failed: $_err"
    }
}
write_checkpoint -force [file join $_rundir post_route.dcp]

# Fail loudly on negative slack. A friend cannot tell a timing miss from a
# bug, and the round trip to find out is days.
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
puts "WNS: $wns ns"
puts "WHS: $whs ns"
if {$wns < 0 || $whs < 0} {
    puts "ERROR: timing NOT met (WNS $wns ns, WHS $whs ns). No bitstream written."
    exit 1
}

# The CPU's known combinatorial loops (the CGA IDB ring: ALU_OUTMUX
# D_15_0 -> G_15_0 -> FIDBO -> MAC/INTR -> back; functionally impossible
# by the one-hot CSIDBS select, unprovable by the tool) trip DRC LUTLP-1,
# which write_bitstream treats as an ERROR. The deployed Nexys build
# downgrades it exactly like this (fpga/nexys4ddr/build.tcl, with the full
# evidence: same loops run SINTRAN on the Tang and Nexys, and the
# instruction-verify traces match the ND-110 golden emulator). This build
# has the same 16 loops on the same nets (compared 02-SEP-2026). Parked
# debt, not a fix: timing through those paths is a lower bound.
set_property SEVERITY {Warning} [get_drc_checks LUTLP-1]
puts "NOTE: LUTLP-1 downgraded to Warning - the known CGA IDB loops, see build.tcl"

set bit [file join $outdir nd120_mega65_$board.bit]
write_bitstream -force $bit
puts "BITSTREAM: $bit"
puts "=== ND120 MEGA65 $BOARD BUILD COMPLETE ($memory) ==="
