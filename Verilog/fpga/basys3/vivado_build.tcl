# ND-120 Vivado Build Script - Basys3 (xc7a35tcpg236-1)
# Usage: vivado -mode batch -source vivado_build.tcl -tclargs [flags...]
#
# NON-PROJECT FLOW since 30-SEP-2026, like the Nexys 4 DDR, Cmod A7, QMTECH
# and MEGA65 builds: no Vivado project, everything this build needs is in the
# repository, and everything it writes goes to the build folder,
# <ND120_BUILD_DIR>/basys3 (local.mk at the repository root, written by
# configure.py). Until then this script opened a Vivado GUI project outside
# the repository (ND3202D.xpr, named by ND120_BASYS3_PROJECT) that held the
# file list and the only copy of the pin constraints - so no other machine
# could build the board. What that project held, and where each piece went:
#   * the source list, 267 files in the project's order -> nd120_basys3_sources.txt
#     (8 of them were disabled in the project and are still not read);
#   * the constraint set synth_1/impl_1 used (constrs_2, 113 lines, used in
#     implementation only) -> nd120_basys3.xdc, read after synthesis, then
#     nd120_timing.xdc (the project had it LATE in the same set);
#   * top ND120_TOP, part xc7a35tcpg236-1, include dir Shared/support, the
#     five defines, the two message suppressions -> below, unchanged;
#   * run strategies: "Vivado Synthesis Defaults" (plain synth_design) and
#     "Vivado Implementation Defaults" (opt, place, phys_opt, route - the four
#     steps the last impl_1 run's step markers show; the power-opt and
#     post-route phys_opt steps were off) -> below;
#   * NOT carried over: the board part (digilentinc.com:basys3:part0:1.2 -
#     only IP and board automation use it, this design has neither), the
#     unused constrs_1 stub, and utils_1/imports/synth_1/TOP_3202D.dcp - an
#     automatic incremental-synthesis reference named after an OLD top
#     (TOP_3202D) that synth_1 did not use (AutoIncrementalCheckpoint=false;
#     its synthesis script has no read_checkpoint -incremental).
#
# Flags (any order):
#   full_synth       - run synthesis (~1h). Without it the script REUSES the
#                      synthesized design from the last full_synth run
#                      (<build>/post_synth.dcp) and does implementation only.
#   skip_program     - do not open Hardware Manager / JTAG / SPI flash
#   skip_synth       - (legacy) same as the default - reuse post_synth.dcp
#   no_reset_synth   - (legacy, ignored) the project flow's "keep the old run";
#                      a non-project synthesis always starts clean
#   backup_bit       - only with full_synth: copy <build>/ND120_TOP.bit to
#                      ND120_TOP.before_synth.bit if it exists
#   enable_ila       - build the ILA debug core (needs a licence above BASIC)
#   lint             - synthesis with -lint only, then stop (vivado_lint.tcl)
#
# From PowerShell:
#   .\vivado_build.ps1          (see its header; make in this folder from WSL)

# Configuration
source [file join [file dirname [file normalize [info script]]] paths.tcl]   ;# repo + build folder paths
set top_module "ND120_TOP"
set part "xc7a35tcpg236-1"
set verilog_dir $b3_verilog_dir
set output_dir $b3_build_dir
set synth_dcp $b3_synth_dcp

# Vivado works IN the build folder: anything it writes next to itself (.Xil,
# the ILA's generated files) lands there, never in the checkout.
cd $output_dir

proc b3_flag {name} {
    global argv
    return [expr {[lsearch $argv $name] >= 0}]
}
set lint_only  [b3_flag lint]
set full_synth [expr {[b3_flag full_synth] || $lint_only}]

puts "============================================"
puts " ND-120 Vivado Build (Basys3, non-project)"
puts " Part:   $part"
puts " Top:    $top_module"
puts " Output: $output_dir"
puts "============================================"

########################################################################
# MICROCODE
#  SKIP_WCS_LOAD (defined below) preloads the 32 WCS IDT6168A chips from the
#  wcs_<16..31><C|D>.hex nibble images via $readmemh, and compiles the
#  microcode PROM out. The images are made from the tracked PROM dumps by
#  Code/Microcode/gen_wcs_image.py (configure.py runs it) and copied into the
#  build folder, which is Vivado's working folder: in this in-memory flow a
#  relative $readmemh resolves against the working folder (measured on the
#  Nexys build, 02-SEP-2026). The other place Vivado searches - next to the
#  .v that holds the $readmemh, Shared/support/IDT6168A_20.v - already holds
#  TRACKED copies of the same raw board images (test-microcode-sync keeps
#  them equal), so nothing is copied into the checkout any more. (The project
#  flow's vivado_build.ps1 used to copy them there, and the PROM images into
#  the project folder.) The two PROM images are copied too: the old script
#  refused to build without them next to the project, and with SKIP_WCS_LOAD
#  they are not read, so this only keeps that check.
########################################################################
set uc_dir  [file normalize [file join $verilog_dir .. Code Microcode]]
set wcs_dir [file join $uc_dir wcs]
set wcs_n 0
foreach bank {C D} {
    for {set chip 16} {$chip <= 31} {incr chip} {
        set f [file join $wcs_dir "wcs_${chip}${bank}.hex"]
        if {![file exists $f]} {
            puts "ERROR: WCS preload image missing: $f"
            puts "       Run python3 configure.py from the repository root - it runs"
            puts "       Code/Microcode/gen_wcs_image.py. Without these the WCS is empty."
            exit 1
        }
        file copy -force $f [file join $output_dir [file tail $f]]
        incr wcs_n
    }
}
puts "Microcode OK: $wcs_n WCS preload images copied to the build folder (SKIP_WCS_LOAD)"
foreach hex {AM27256_45132L.hex AM27256_45133L.hex} {
    if {![file exists [file join $uc_dir $hex]]} {
        puts "ERROR: Microcode file missing: [file join $uc_dir $hex]"
        puts "The ROM will be empty without this file. Aborting."
        exit 1
    }
    file copy -force [file join $uc_dir $hex] [file join $output_dir $hex]
    puts "Microcode OK: $hex ([file size [file join $uc_dir $hex]] bytes)"
}

########################################################################
# Suppress known harmless synthesis warnings
#  - Synth 8-3936: register trimming (R81/L4/L8/R41P fewer bits than width)
#  - Synth 8-5837: dual async set/reset (D_FLIPFLOP/F617/F714)
# (The project carried the same two as message rules.)
########################################################################
set_msg_config -id {Synth 8-3936} -suppress
set_msg_config -id {Synth 8-5837} -suppress

########################################################################
# SYNTHESIS
########################################################################
puts "\n=== SYNTHESIS ==="
if {$full_synth} {
    if {[b3_flag no_reset_synth]} {
        puts "no_reset_synth: ignored - a non-project synthesis always starts clean."
    }
    if {[b3_flag backup_bit]} {
        set prev_bit "${output_dir}/${top_module}.bit"
        if {[file exists $prev_bit]} {
            set bak "${output_dir}/${top_module}.before_synth.bit"
            file copy -force $prev_bit $bak
            puts "backup_bit: saved previous bitstream as $bak"
        }
    }

    create_project -in_memory -part $part
    set_property default_lib xil_defaultlib [current_project]
    set_property target_language Verilog [current_project]

    ####################################################################
    # SOURCES - nd120_basys3_sources.txt, in the project's order. The
    # project's synthesis script read the .vh header first, then the .v
    # files; lines starting with '-' were disabled in the project and are
    # not read. The ND-BUS device models (ND_BUS_SLAVE/ND_TAPE_400/
    # ND_FLOPPY_DMA/ND_SMD/ND_WINCHESTER/ND_DMA_MASTER) are deliberately NOT
    # listed: ND120_VERILOG_DEVICES is not defined for this board, so
    # ND120_CORE's INCLUDE_* parameters are all 0 and every device instance
    # sits in a false generate branch. Add them to the list (and
    # ND-BUS-DEVICES/*/circuit to the include path, for nd_storage_status.vh)
    # only if this board ever builds with -DND120_VERILOG_DEVICES.
    ####################################################################
    set src_list [file join $b3_here nd120_basys3_sources.txt]
    set fh [open $src_list r]
    set headers {}
    set vfiles {}
    set skipped 0
    foreach line [split [read $fh] "\n"] {
        set line [string trim $line]
        if {$line eq "" || [string index $line 0] eq "#"} { continue }
        if {[string index $line 0] eq "-"} { incr skipped; continue }
        set f [file normalize [file join $verilog_dir $line]]
        if {![file exists $f]} {
            puts "ERROR: source in nd120_basys3_sources.txt not found on disk: $f"
            exit 1
        }
        if {[file extension $f] eq ".vh"} { lappend headers $f } else { lappend vfiles $f }
    }
    close $fh
    puts "Sources: [llength $vfiles] .v + [llength $headers] .vh from nd120_basys3_sources.txt ($skipped disabled, not read)"
    foreach h $headers { read_verilog $h }
    read_verilog -library xil_defaultlib $vfiles

    ####################################################################
    # VERILOG INCLUDE PATH
    #  ND120_CORE.v and Shared/support/BACKWIRING_PROM.v both do
    #  `include "nd120_backwiring_defaults.vh". Set the header's directory
    #  on the include path explicitly rather than relying on the .vh
    #  file-type being inferred as a Verilog header. This is the same include
    #  dir the Nexys 4 DDR flow passes with -include_dirs
    #  (fpga/nexys4ddr/build.tcl), and the one the project had.
    ####################################################################
    set_property include_dirs [list [file join $verilog_dir Shared support]] [current_fileset]

    ####################################################################
    # VERILOG DEFINES FOR FPGA SYNTHESIS (the project's five, unchanged)
    #  FPGA_FF_MODE  -- activates the phase-accurate FF clock generation in
    #                   CPU-BOARD-3202/circuit/CYC_36.v. WITHOUT this define Vivado
    #                   compiles the ELSE branch (original gated combinational
    #                   clocks: ALUCLK/MCLK/MACLK/CLK/UCLK minted from TERM_n), which
    #                   creates un-constrainable clock nets (BUFG-on-LUT, LUT-driving-
    #                   clock) and cannot meet timing. It does NOT re-enable
    #                   transparent latches: USE_TRANSPARENT_LATCHES is gated behind
    #                   VERILATOR_SIM (ND120_TOP.v), which is absent for synthesis.
    #  SKIP_WCS_LOAD -- bitstream-preload the WCS from the 32 wcs_*.hex nibble images
    #                  and neutralise the LCS latch so the ~573K-cycle runtime PROM->WCS
    #                  load never runs (PAL_44403C.v). With this define the microcode
    #                  PROM (CPU_CS_PROM_19) is never read, so its ROM arrays are
    #                  compiled out (see CPU_CS_PROM_19.v) -- reclaims ~7850 LUTs.
    #                  See docs/skip-wcs-load.md.
    #  MAIN_RAM_BLOCKRAM -- select the block-RAM sheet-49 backend (MEM_RAM_49_BLOCKRAM,
    #                  3 banks x 4K 18-bit words = 24 KB, the xc7a35t BRAM budget).
    #                  ADDED 3-AUG-2026. Until then this board defined NO MAIN_RAM_*
    #                  at all and therefore fell through MEM_43.v's `else branch into
    #                  the six-chip SIP1M9 DRAM sheet -- the exact "silent fallthrough"
    #                  that branch's own comment said must never happen, while the
    #                  comment simultaneously claimed no build used it. MEM_43.v now
    #                  makes a missing selection a compile error, so this define is
    #                  REQUIRED, not optional: without it synthesis fails on the
    #                  module ND120_ERROR_no_main_ram_backend_selected.
    #                  Same backend Cmod A7 already used (fpga/cmod-a7-35t/build.tcl).
    #  BOARD_CLK_FREQ=16666667 -- the UART (SC2661_UART.v) derives its baud divisor
    #                   DELAY_FRAMES = BOARD_CLK_FREQ / UART_BAUD_RATE. The UART is
    #                   clocked by the CPU-board sysclk = clk_cpu = 16.667 MHz (100/6),
    #                   NOT 100 MHz. The default 100_000_000 made the console baud ~6x
    #                   wrong (garbled serial). Without this the CPU sits in
    #                   STOP/OPCOM but can never receive a console command.
    #  UART_BAUD_RATE=9600 -- to match the baud-rate thumbwheel (s_baud_rate_switch=
    #                   4'b1000=8=9600, ND120_TOP.v). The microcode reads that
    #                   thumbwheel (o2013 IDBS.IOR -> Q) and the o2016 BAUDV T.JMP
    #                   selects the 9600 console-clock config (jumps to o5670). The
    #                   SC2661_UART model uses a FIXED DELAY_FRAMES =
    #                   BOARD_CLK_FREQ/UART_BAUD_RATE, so it must be told 9600 or it
    #                   transmits at the stale 115200 default, mismatching what the
    #                   CPU configured. 16666667/9600 = 1736 -> ~9601 baud.
    #                   Console: COM3 9600 7E1. (Go 115200 later once serial works:
    #                   bump this AND the thumbwheel's BAUDV code.)
    ####################################################################
    set_property verilog_define {FPGA_FF_MODE SKIP_WCS_LOAD MAIN_RAM_BLOCKRAM BOARD_CLK_FREQ=16666667 UART_BAUD_RATE=9600} [current_fileset]
    puts "Verilog defines for synthesis: [get_property verilog_define [current_fileset]]"

    if {$lint_only} {
        puts "\n=== LINT (synth_design -lint) ==="
        synth_design -top $top_module -part $part -lint
        puts "\n=== LINT COMPLETE ==="
        exit 0
    }

    # "Vivado Synthesis Defaults": a plain synth_design.
    synth_design -top $top_module -part $part
    write_checkpoint -force $synth_dcp
    puts "Synthesized design saved: $synth_dcp"
} else {
    puts "DEFAULT: NOT re-running synthesis (no full_synth flag) - opening the last synthesized design."
    puts "  To run synthesis (~1h), add:  -tclargs full_synth  (and other flags as needed)"
    if {![file exists $synth_dcp]} {
        puts "ERROR: no synthesized design yet: $synth_dcp"
        puts "  Run once with full synthesis, e.g.:"
        puts "    vivado -mode batch -source vivado_build.tcl -tclargs full_synth skip_program"
        exit 1
    }
    open_checkpoint $synth_dcp
    puts "Synthesized design opened successfully (from $synth_dcp)"
}

# Report utilization after synthesis
report_utilization -file "${output_dir}/utilization_synth.rpt"
report_ram_utilization -detail -file "${output_dir}/ram_utilization.rpt"
puts "Utilization report: ${output_dir}/utilization_synth.rpt"
puts "RAM report: ${output_dir}/ram_utilization.rpt"

# Verify BRAM count - microcode ROM should use at least 8 BRAMs
set bram_count [llength [get_cells -hierarchical -filter {PRIMITIVE_TYPE =~ BMEM.*}]]
puts "BRAM cells used: $bram_count"
if {$bram_count < 8} {
    puts "WARNING: Only $bram_count BRAMs - microcode ROM may be empty!"
}

# Dump BRAM INIT values to verify the microcode is populated.
# With SKIP_WCS_LOAD the microcode PROM (rom_lo/rom_hi) is compiled out; the
# microcode now lives in the 32 WCS IDT6168A chips, bitstream-preloaded from the
# wcs_*.hex nibble images. So we check the WCS BRAMs (idt_memory_array), not the
# old PROM. NOTE the parenthesised filter: without it, `&& || ` binds as
# (BMEM && name) || name, matching non-BRAM cells too (old precedence bug).
set rom_cells [get_cells -hierarchical -filter {PRIMITIVE_TYPE =~ BMEM.* && (NAME =~ *idt_memory_array* || NAME =~ *rom_lo* || NAME =~ *rom_hi*)}]
set rom_report_file "${output_dir}/rom_init_check.txt"
set fp [open $rom_report_file w]
puts $fp "=== Microcode BRAM INIT Check (WCS preload + any PROM) ==="
puts $fp "Date: [clock format [clock seconds]]"
puts $fp ""
set _nonzero 0
foreach cell $rom_cells {
    puts $fp "Cell: $cell"
    set init0 [get_property INIT_00 $cell]
    set init1 [get_property INIT_01 $cell]
    puts $fp "  INIT_00: $init0"
    puts $fp "  INIT_01: $init1"
    if {$init0 eq "256'h0000000000000000000000000000000000000000000000000000000000000000"
        || $init0 eq ""} {
        puts $fp "  ** WARNING: INIT_00 is all zeros - this slice may be empty!"
    } else {
        puts $fp "  OK: INIT_00 has non-zero data"
        incr _nonzero
    }
    puts $fp ""
}
close $fp
puts "ROM init check: ${rom_report_file}"
if {[llength $rom_cells] == 0} {
    puts "  ROM: No microcode BRAMs found (idt_memory_array / rom_lo / rom_hi)."
    puts "       Under SKIP_WCS_LOAD the WCS should map to BRAM and be preloaded"
    puts "       from wcs_*.hex - check those files are on the \$readmemh path."
} else {
    puts "  ROM: [llength $rom_cells] microcode BRAM slice(s), $_nonzero with non-zero INIT."
}

########################################################################
# SET UP ILA DEBUG CORE
# Recreated after every synthesis because net names may change.
# Probes all mark_debug signals from ND120_TOP.
########################################################################
# ILA temporarily disabled (2026-07-08): after recent RTL changes the debug-core
# opt_design fails ("Synthesis of Debug Cores has failed"). The ILA is not needed
# for console/memory/execution testing. When 0, the ILA is built in-memory but NOT
# written into the checkpoint impl reads, so implementation runs ILA-free. Set to 1
# (and fix the failing probe) to restore on-chip debug. Override: -tclargs enable_ila
set _enable_ila 0
if {[lsearch $argv "enable_ila"] >= 0} { set _enable_ila 1 }

puts "\n=== SETTING UP ILA DEBUG CORE (enabled=$_enable_ila) ==="


# GUARD: everything from here to "ILA debug core configured" only runs when the
# ILA is actually wanted.
#
# Two reasons this must be guarded rather than run-then-discard:
#  1. It was pointless work when disabled. With _enable_ila 0 the cores were built
#     in memory and then simply NOT written to the synth checkpoint (the project
#     flow's write_checkpoint, before 30-SEP-2026), so implementation ran ILA-free
#     anyway.
#  2. Under Vivado 2026.1 with a BASIC licence it is FATAL, not pointless:
#     "ERROR: [Vivado 12-29205] 'create_debug_core' tcl command is not supported.
#      Your current selected license is BASIC." That error aborted the whole
#     script at line 366 BEFORE implementation, so a full_synth run produced a
#     valid synthesis and then no implementation, no timing report and no
#     bitstream. Guarding it lets the default (ILA-off) build complete.
#
# Passing -tclargs enable_ila on a BASIC licence will still fail here, and should
# -- that is an honest licence error, not something to paper over.
if {$_enable_ila} {
    # Remove any existing debug cores from previous runs
    catch {delete_debug_core -quiet [get_debug_cores -quiet]}

    # Create ILA core
    create_debug_core u_ila_0 ila
    set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_0]
    set_property ALL_PROBE_SAME_MU_CNT 1 [get_debug_cores u_ila_0]
    set_property C_ADV_TRIGGER false [get_debug_cores u_ila_0]
    set_property C_DATA_DEPTH 1024 [get_debug_cores u_ila_0]
    set_property C_EN_STRG_QUAL false [get_debug_cores u_ila_0]
    set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_0]
    set_property C_TRIGIN_EN false [get_debug_cores u_ila_0]
    set_property C_TRIGOUT_EN false [get_debug_cores u_ila_0]

    # Connect ILA clock.
    # Sample on clk1 (= clk_cpu, ~16.67 MHz, the CPU/bus domain) NOT sysclk (100 MHz).
    # The CPU is now a single synchronous clk_cpu domain, so clk1 captures every CPU
    # state; sampling on sysclk instead made ~175 ILA probe-input paths cross from
    # clk_cpu into the 100 MHz ILA and fail timing. All probe DATA nets are CPU
    # (clk_cpu) signals, so with a clk1 sample clock they are intra-domain.
    set ila_clk_net "clk1"
    set_property port_width 1 [get_debug_ports u_ila_0/clk]
    connect_debug_port u_ila_0/clk [get_nets [list $ila_clk_net]]

    # Helper: connect a probe to nets that actually exist after synthesis.
    #
    # Vivado renames `reg` declarations during synthesis (e.g. `regREP[12:0]`
    # becomes `regREP_reg[12:0]`), and may slightly mangle hierarchical instance
    # names. To avoid silent failures we try several patterns:
    #   1. The exact pattern as given.
    #   2. The pattern with `_reg[*]` substituted for `[*]` (Vivado reg rename).
    #   3. The pattern with `_reg` appended (scalar reg rename).
    #   4. A hierarchical fallback search using the leaf basename (-hierarchical).
    # If none match, the probe is dummy-connected to sysclk_IBUF_BUFG and a
    # WARNING is printed so we can see which probe failed.
    #
    # All patterns are tried QUIETLY before reporting failure, so a successful
    # fallback doesn't pollute the build log.
    proc connect_probe {probe_port net_pattern probe_name} {
        # Build the variant pattern list
        set patterns [list $net_pattern]

        # Variant 2: replace [*] with _reg[*] for vector reg rename
        if {[string match "*\\\[\*\\\]*" $net_pattern]} {
            # nothing — handled below by literal substitution
        }
        set v2 [string map {"[*]" "_reg[*]"} $net_pattern]
        if {$v2 ne $net_pattern} { lappend patterns $v2 }

        # Variant 3: append _reg for scalar reg
        lappend patterns "${net_pattern}_reg"

        # Variant 4: hierarchical search by leaf basename
        set leaf [file tail $net_pattern]
        if {$leaf ne $net_pattern} {
            lappend patterns "*${leaf}"
            lappend patterns "*[string map {"[*]" "_reg[*]"} $leaf]"
        }

        set nets {}
        set used_pattern ""
        foreach p $patterns {
            set try [get_nets -quiet $p]
            if {[llength $try] > 0} {
                set nets $try
                set used_pattern $p
                break
            }
        }

        set count [llength $nets]
        if {$count == 0} {
            puts "WARNING: No nets found for $probe_name (tried: $patterns) - skipping probe"
            # Connect to a dummy 1-bit signal to avoid unconnected probe errors.
            # Use clk1 (the ILA sample clock / clk_cpu domain) so a missing probe does
            # not introduce a 100 MHz sysclk CDC into the clk1-sampled ILA.
            set_property port_width 1 [get_debug_ports $probe_port]
            connect_debug_port $probe_port [get_nets [list clk1]]
            return
        }
        if {$used_pattern eq $net_pattern} {
            puts "  $probe_name: $count nets found"
        } else {
            puts "  $probe_name: $count nets found (via fallback pattern: $used_pattern)"
        }
        set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports $probe_port]
        set_property port_width $count [get_debug_ports $probe_port]
        connect_debug_port $probe_port $nets
    }

    # probe0: MIC address (CSA_12_0)
    connect_probe u_ila_0/probe0 {s_debug_csa[*]} "CSA"

    # probe1: CPU run state
    create_debug_port u_ila_0 probe
    connect_probe u_ila_0/probe1 {s_run} "RUN"

    # probe2: Cycle state {TERM_n, CC3_n, CC2_n, CC1_n, CC0_n}
    create_debug_port u_ila_0 probe
    connect_probe u_ila_0/probe2 {s_debug_cc_term[*]} "CC_TERM"

    # probe3: LCS_n (microcode loaded)
    create_debug_port u_ila_0 probe
    connect_probe u_ila_0/probe3 {s_debug_lcs_n} "LCS_n"

    # probe4: UART TX
    create_debug_port u_ila_0 probe
    connect_probe u_ila_0/probe4 {s_debug_uartTx} "UART_TX"

    # probe5: Memory clock
    create_debug_port u_ila_0 probe
    connect_probe u_ila_0/probe5 {s_debug_mclk} "MCLK"

    # probe6: UART RX
    create_debug_port u_ila_0 probe
    connect_probe u_ila_0/probe6 {s_debug_uartRx} "UART_RX"

    # probe7: MAP_n / EWCA_n / TRAP_n — IPOS mux selectors that drive CSA combinationally
    # (replaces CPU_LED to free BRAM for the new IDB source probes)
    create_debug_port u_ila_0 probe
    connect_probe u_ila_0/probe7 {CPU_BOARD/CPU/PROC/CGA/DELILAH/MIC/s_map_n} "MAP_n"

    # probe8: FETCH
    create_debug_port u_ila_0 probe
    connect_probe u_ila_0/probe8 {s_debug_fetch} "FETCH"

    # probe9: MR_n (Master Reset)
    create_debug_port u_ila_0 probe
    connect_probe u_ila_0/probe9 {s_debug_mr_n} "MR_n"

    # probe10: CLEAR_n
    create_debug_port u_ila_0 probe
    connect_probe u_ila_0/probe10 {s_debug_clear_n} "CLEAR_n"

    # probe11: REFRQ_n (Refresh Request)
    create_debug_port u_ila_0 probe
    connect_probe u_ila_0/probe11 {s_debug_refrq_n} "REFRQ_n"

    # probe12: INTRQ_n (Interrupt Request)
    create_debug_port u_ila_0 probe
    connect_probe u_ila_0/probe12 {s_debug_intrq_n} "INTRQ_n"

    # probe13: clk_cpu (was sysclk; the CPU is now a single clk_cpu domain so a raw
    # 100 MHz sysclk probe would be a CDC into the clk1-sampled ILA. Point at the
    # sample clock itself.)
    create_debug_port u_ila_0 probe
    set_property port_width 1 [get_debug_ports u_ila_0/probe13]
    set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe13]
    connect_debug_port u_ila_0/probe13 [get_nets [list $ila_clk_net]]

    # probe14: WCA_12_0 (Write Control Store Address)
    create_debug_port u_ila_0 probe
    connect_probe u_ila_0/probe14 {CPU_BOARD/CPU/PROC/CGA/DELILAH/MIC/s_wca_12_0[*]} "WCA"

    # probe15: CD_15_0 (CPU data bus output)
    create_debug_port u_ila_0 probe
    connect_probe u_ila_0/probe15 {CPU_BOARD/s_cpu_cd_15_0_out[*]} "CD"

    # probe16: CLOSC (power-on clear oscillator)
    create_debug_port u_ila_0 probe
    connect_probe u_ila_0/probe16 {CPU_BOARD/IO/DCD/s_closc} "CLOSC"

    # probe17: sys_rst_n
    create_debug_port u_ila_0 probe
    connect_probe u_ila_0/probe17 {CPU_BOARD/sys_rst_n} "SYS_RST_n"

    # probe18: regPowerOnClear
    create_debug_port u_ila_0 probe
    connect_probe u_ila_0/probe18 {CPU_BOARD/IO/DCD/regPowerOnClear_reg} "PWR_ON_CLR"

    # probe19: CLIRQ group
    create_debug_port u_ila_0 probe
    connect_probe u_ila_0/probe19 {CPU_BOARD/CPU/PROC/CGA/DELILAH/DCD/s_iclirq_group} "CLIRQ"

    # probe20: FIDBO_15_0 (internal data bus, threaded through hierarchy)
    create_debug_port u_ila_0 probe
    connect_probe u_ila_0/probe20 {s_debug_fidbo[*]} "FIDBO"

    # probe21: free slot (was PROM_DATA — removed). Dummy-connected to the ILA sample
    # clock (clk1) to keep probe numbering aligned for probes 22-47.
    create_debug_port u_ila_0 probe
    set_property port_width 1 [get_debug_ports u_ila_0/probe21]
    set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe21]
    connect_debug_port u_ila_0/probe21 [get_nets [list $ila_clk_net]]

    # probe22: ALU Q register (mark_debug in CGA_ALU.v)
    create_debug_port u_ila_0 probe
    connect_probe u_ila_0/probe22 {CPU_BOARD/CPU/PROC/CGA/DELILAH/ALU/s_q_15_0[*]} "ALU_Q"

    # probe23: ALU F result (mark_debug in CGA_ALU.v)
    create_debug_port u_ila_0 probe
    connect_probe u_ila_0/probe23 {CPU_BOARD/CPU/PROC/CGA/DELILAH/ALU/s_f_15_0[*]} "ALU_F"

    # probe24: ALU Zero flag (mark_debug in CGA.v)
    create_debug_port u_ila_0 probe
    connect_probe u_ila_0/probe24 {CPU_BOARD/CPU/PROC/CGA/DELILAH/s_zf} "ALU_ZF"

    # probe25: ALU Carry (mark_debug in CGA.v)
    create_debug_port u_ila_0 probe
    connect_probe u_ila_0/probe25 {CPU_BOARD/CPU/PROC/CGA/DELILAH/s_cry} "ALU_CRY"

    # probe26: MIC condition output (mark_debug in CGA.v)
    create_debug_port u_ila_0 probe
    connect_probe u_ila_0/probe26 {CPU_BOARD/CPU/PROC/CGA/DELILAH/s_cond} "COND"

    # probe27: SC5/SC6 mux selector bits [3:2]=SC6/SC5, [1:0]=SC4/SC3 (mark_debug in CGA_MIC.v)
    create_debug_port u_ila_0 probe
    connect_probe u_ila_0/probe27 {CPU_BOARD/CPU/PROC/CGA/DELILAH/MIC/s_sc_6_3_out[*]} "SC_6_3"

    # probe28: CSEL latch output s_cond_n (mark_debug in CGA_MIC.v)
    create_debug_port u_ila_0 probe
    connect_probe u_ila_0/probe28 {CPU_BOARD/CPU/PROC/CGA/DELILAH/MIC/s_cond_n} "MIC_COND_N"

    # probe29: etrue / efalse (condition routing to SC5/SC6) (mark_debug in CGA_MIC.v)
    create_debug_port u_ila_0 probe
    connect_probe u_ila_0/probe29 {CPU_BOARD/CPU/PROC/CGA/DELILAH/MIC/s_etrue} "ETRUE"
    create_debug_port u_ila_0 probe
    connect_probe u_ila_0/probe30 {CPU_BOARD/CPU/PROC/CGA/DELILAH/MIC/s_efalse} "EFALSE"

    # probe31: CSEL latch D-input s_pcond_n (mark_debug in CGA_MIC_CSEL.v)
    create_debug_port u_ila_0 probe
    connect_probe u_ila_0/probe31 {CPU_BOARD/CPU/PROC/CGA/DELILAH/MIC/CSEL/s_pcond_n} "CSEL_D"

    # probe32: CSEL latch Q-output s_cond_n_out (mark_debug in CGA_MIC_CSEL.v)
    create_debug_port u_ila_0 probe
    connect_probe u_ila_0/probe32 {CPU_BOARD/CPU/PROC/CGA/DELILAH/MIC/CSEL/s_cond_n_out} "CSEL_Q"

    # probe33: LUA_12_0 — PROM address upper bits from ACAL (mark_debug in CPU_CS_16.v)
    # Should equal CSA_12_0. If it doesn't, ACAL is latching the wrong CSA value via MACLK.
    create_debug_port u_ila_0 probe
    connect_probe u_ila_0/probe33 {CPU_BOARD/CPU/CS/s_LUA_12_0[*]} "LUA"

    # probe34: MACLK — controls when ACAL latches CSA into LUA (from CYC_36 via CPU_CS_16)
    create_debug_port u_ila_0 probe
    connect_probe u_ila_0/probe34 {CPU_BOARD/CPU/CS/ACAL/s_maclk} "MACLK"

    # probe35: ALUCLK — controls CSEL latch enable (mark_debug or hierarchical net)
    create_debug_port u_ila_0 probe
    connect_probe u_ila_0/probe35 {CPU_BOARD/CPU/PROC/CGA/DELILAH/MIC/CSEL/s_aluclk} "ALUCLK"

    # probe36: clk_cpu — the ILA sample clock (was sysclk; CPU is single clk_cpu domain)
    create_debug_port u_ila_0 probe
    set_property port_width 1 [get_debug_ports u_ila_0/probe36]
    set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe36]
    connect_debug_port u_ila_0/probe36 [get_nets [list $ila_clk_net]]

    # probe37: LC — link counter (lower 4 bits), used for PANVC dispatch
    create_debug_port u_ila_0 probe
    connect_probe u_ila_0/probe37 {CPU_BOARD/CPU/PROC/CGA/DELILAH/MIC/s_lc_3_0[*]} "LC"

    # probe38: CSIDBS_4_0 — microcode IDB source select (which IDB source we expect)
    create_debug_port u_ila_0 probe
    connect_probe u_ila_0/probe38 {CPU_BOARD/IO/s_csidbs_4_0[*]} "CSIDBS"

    # probe39: IDB_UART — output of IO_UART_42 (gated by EIOR_n / RUART_n)
    create_debug_port u_ila_0 probe
    connect_probe u_ila_0/probe39 {CPU_BOARD/IO/s_idb_15_0_uart_out[*]} "IDB_UART"

    # probe40: IDB_PANCAL — output of IO_PANCAL_40 (gated by EPANS_n)
    create_debug_port u_ila_0 probe
    connect_probe u_ila_0/probe40 {CPU_BOARD/IO/s_idb_15_0_pancal_out[*]} "IDB_PANCAL"

    # probe41: IDB_REG — output of IO_REG_41 (gated by RINR_n / TRAALD_n)
    create_debug_port u_ila_0 probe
    connect_probe u_ila_0/probe41 {CPU_BOARD/IO/s_idb_15_0_reg_out[*]} "IDB_REG"

    # probe42: IDB_DCD — output of IO_DCD_38 panel vector (8 bits, gated by EPAN_n)
    create_debug_port u_ila_0 probe
    connect_probe u_ila_0/probe42 {CPU_BOARD/IO/s_idb_7_0_dcd_out[*]} "IDB_DCD"

    # probe43: EWCA_n — IPOS mux selector input
    create_debug_port u_ila_0 probe
    connect_probe u_ila_0/probe43 {CPU_BOARD/CPU/PROC/CGA/DELILAH/MIC/s_ewca_n} "EWCA_n"

    # probe44: TRAP_n — IPOS mux selector input
    create_debug_port u_ila_0 probe
    connect_probe u_ila_0/probe44 {CPU_BOARD/CPU/PROC/CGA/DELILAH/MIC/s_trap_n} "TRAP_n"

    # probe45: MA_12_0 — MIC_IPOS output, the combinational microcode address
    # (= CSA at the CGA_MIC level. Probe at MIC wire, not MASEL internal reg.)
    create_debug_port u_ila_0 probe
    connect_probe u_ila_0/probe45 {CPU_BOARD/CPU/PROC/CGA/DELILAH/MIC/s_ma_12_0_out[*]} "MA_12_0"

    # probe46: W_12_0 — MASEL output wire at the CGA_MIC level
    # (s_w_12_0 drives MIC_IPOS. During idle = regREP, during active = regIW.)
    create_debug_port u_ila_0 probe
    connect_probe u_ila_0/probe46 {CPU_BOARD/CPU/PROC/CGA/DELILAH/MIC/s_w_12_0[*]} "W_12_0"

    # probe47: IW_12_0 — MASEL output wire at the CGA_MIC level
    # (s_iw_12_0 feeds MIC_IINC for NEXT calculation.)
    create_debug_port u_ila_0 probe
    connect_probe u_ila_0/probe47 {CPU_BOARD/CPU/PROC/CGA/DELILAH/MIC/s_iw_12_0[*]} "IW_12_0"

    # Connect debug hub clock. The dbg_hub (JTAG comms) needs >= 25 MHz, so it stays
    # on the 100 MHz sysclk even though the ILA SAMPLES on clk1 (~16.67 MHz). The ILA
    # IP handles the hub<->capture-clock crossing internally; this is a supported
    # config (capture clock independent of the debug-hub clock).
    set_property C_CLK_INPUT_FREQ_HZ 100000000 [get_debug_cores dbg_hub]
    set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
    set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
    connect_debug_port dbg_hub/clk [get_nets sysclk_IBUF_BUFG]

    # Save the debug constraints
    # NOTE: Do NOT use save_constraints here — it writes ILA definitions into the
    # XDC file, which then conflict with this script on the next build.

    puts "ILA debug core configured with 48 probes (depth 1024)"
} else {
    puts "ILA disabled: skipping debug-core creation entirely (no create_debug_core)."
    puts "  Implementation runs ILA-free, exactly as when the cores were built and discarded."
    puts "  Pass -tclargs enable_ila to build them (needs a licence above BASIC)."
}

# In this non-project flow the ILA above (when enabled) is already part of the
# in-memory design that implementation continues from - nothing has to be
# written back to a synthesis checkpoint first, as the project flow did.

########################################################################
# CONSTRAINTS - implementation only, as in the project
#  nd120_basys3.xdc is the project's constrs_2 pin map (USED_IN =
#  implementation; it is where "create_clock -name sys_clk" lives), and
#  nd120_timing.xdc declares the CPU clk_cpu_pre domain asynchronous to the
#  100 MHz sys_clk (ILA/7-seg/POR) domain. Both are read here, AFTER
#  synthesis, so synthesis never sees them - the project's USED_IN =
#  implementation - and nd120_timing.xdc is read LAST, so sys_clk exists
#  when it does "get_clocks sys_clk" (the project's PROCESSING_ORDER LATE).
#  History: nd120_timing.xdc once defaulted to "synthesis implementation" in
#  the project, so synthesis read it while NO clock existed yet and reported
#    WARNING  [Vivado 12-627]   No clocks matched 'sys_clk'.
#    WARNING  [Vivado 12-627]   No clocks matched 'clk_cpu_pre'.
#    CRITICAL [Constraints 18-4644] set_clock_groups: All clock groups ... empty.
#  and before that it sat in constrs_1, a set no run read, so the grouping
#  was never applied at all.
#  constraints_tie_unused.xdc in this folder was in neither of the project's
#  constraint sets and is not read.
########################################################################
foreach _xdc [list [file join $b3_here nd120_basys3.xdc] [file join $b3_here nd120_timing.xdc]] {
    if {![file exists $_xdc]} {
        puts "ERROR: constraints not found on disk: $_xdc"
        exit 1
    }
    read_xdc $_xdc
    puts "Constraints read: $_xdc"
}

########################################################################
# IMPLEMENTATION - "Vivado Implementation Defaults": opt, place, phys_opt,
# route (the four steps the project's last impl_1 run executed).
########################################################################
puts "\n=== IMPLEMENTATION ==="
opt_design
place_design
phys_opt_design
route_design
puts "Implemented design ready"

# Apply combinational loop constraints
catch {set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets -hierarchical -quiet -filter {NAME =~ *CPU_BOARD*}]}

# The routed checkpoint, for the no-resynth timing experiments in this folder
# (timing_explore.tcl, exp_*.tcl, find_clk.tcl open it).
write_checkpoint -force $b3_routed_dcp
puts "Routed checkpoint: $b3_routed_dcp"

# Reports (the project's impl run also wrote methodology and power reports)
report_timing_summary -file "${output_dir}/timing_impl.rpt"
report_utilization -file "${output_dir}/utilization_impl.rpt"
report_drc -file "${output_dir}/drc.rpt"
report_methodology -file "${output_dir}/methodology.rpt"
report_power -file "${output_dir}/power.rpt"
puts "Reports written to ${output_dir}/"

########################################################################
# BITSTREAM
#  No timing gate here, as before: the Basys3 is known not to meet timing
#  (see README.md), and this flow writes the bitstream regardless, exactly
#  like the project flow did. The other boards' builds refuse on WNS < 0.
########################################################################
puts "\n=== BITSTREAM ==="
set bit_file "${output_dir}/${top_module}.bit"
write_bitstream -force $bit_file

# Hardware Manager expects .ltx next to the bitstream for ILA auto-connect.
# write_bitstream does not emit this file; write_debug_probes does.
if {$_enable_ila} {
    if {[catch {write_debug_probes -force "${output_dir}/${top_module}.ltx"} dbg_err]} {
        puts "ERROR: write_debug_probes failed (no ILA in implemented design?): $dbg_err"
        exit 1
    }
    puts "Debug probes file: ${output_dir}/${top_module}.ltx"
} else {
    puts "ILA disabled: skipping write_debug_probes / .ltx (no on-chip ILA this build)"
}

# Check for bitstream
if {[file exists $bit_file]} {
    puts "\nSUCCESS: Bitstream generated!"
    puts "Output: $bit_file"
} else {
    puts "\nERROR: Bitstream not generated. Check DRC report."
    puts "DRC report: ${output_dir}/drc.rpt"
    exit 1
}

########################################################################
# PROGRAM FPGA AND FLASH
########################################################################
# Skip programming if -tclargs skip_program was passed
if {[lsearch $argv "skip_program"] >= 0} {
    puts "\n=== SKIPPING PROGRAMMING (skip_program flag) ==="
    puts "\n=== BUILD COMPLETE ==="
    exit 0
}

puts "\n=== PROGRAMMING FPGA ==="

# Open hardware manager
open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target

# Get the FPGA device
set hw_device [get_hw_devices xc7a35t_0]
current_hw_device $hw_device
set_property PROGRAM.FILE "${output_dir}/${top_module}.bit" $hw_device

# Program FPGA via JTAG (volatile - immediate test)
program_hw_devices $hw_device
puts "FPGA programmed via JTAG"

# Generate flash image and program SPI flash (non-volatile - survives power cycle)
puts "\n=== PROGRAMMING SPI FLASH ==="
set mcs_file "${output_dir}/${top_module}.mcs"
write_cfgmem -force -format mcs -interface SPIx4 -size 4 \
    -loadbit "up 0x0 ${output_dir}/${top_module}.bit" $mcs_file

# Create cfgmem object for the Basys3 flash (S25FL032P)
create_hw_cfgmem -hw_device $hw_device [lindex [get_cfgmem_parts {s25fl032p-spi-x1_x2_x4}] 0]
set hw_cfgmem [get_property PROGRAM.HW_CFGMEM $hw_device]
set_property PROGRAM.ADDRESS_RANGE  {use_file} $hw_cfgmem
set_property PROGRAM.FILES          [list $mcs_file] $hw_cfgmem
set_property PROGRAM.PRM_FILE       {} $hw_cfgmem
set_property PROGRAM.UNUSED_PIN_TERMINATION {pull-none} $hw_cfgmem
set_property PROGRAM.BLANK_CHECK    0 $hw_cfgmem
set_property PROGRAM.ERASE          1 $hw_cfgmem
set_property PROGRAM.CFG_PROGRAM    1 $hw_cfgmem
set_property PROGRAM.VERIFY         1 $hw_cfgmem
set_property PROGRAM.CHECKSUM       0 $hw_cfgmem

# CRITICAL: Generate the indirect-programming bitstream and load it into the FPGA.
# The FPGA must be programmed with a special SPI-proxy bitstream so that Vivado
# can communicate with the flash chip via JTAG-to-SPI bridging.  Without this,
# program_hw_cfgmem fails with "Failure to set flash parameters" (Labtools 27-3347).
create_hw_bitstream -hw_device $hw_device [get_property PROGRAM.HW_CFGMEM_BITFILE $hw_device]
program_hw_devices $hw_device

program_hw_cfgmem -hw_cfgmem $hw_cfgmem
puts "SPI flash programmed"

# Reboot FPGA from flash to verify
boot_hw_device [current_hw_device]
puts "FPGA rebooted from flash - bitstream will persist after power cycle"

close_hw_target
disconnect_hw_server
close_hw_manager

puts "\n=== BUILD COMPLETE ==="
exit 0
