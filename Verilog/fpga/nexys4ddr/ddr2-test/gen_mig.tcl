# Generate the DDR2 memory controller (MIG 7-series) for the Nexys 4 DDR.
#
#   vivado -mode batch -source gen_mig.tcl
#
# The whole configuration - including the fixed DDR2 pinout, which must be
# entered and validated in the MIG wizard and is far too easy to get wrong by
# hand - comes from Digilent's own project file, ip/mig.prj, taken from
# github.com/Digilent/Nexys-4-DDR-OOB (src/ip/ddr/mig.prj). What it asks for:
#
#   MemoryDevice   MT47H64M16HR-25E     the part fitted on this board
#   TimePeriod     3333 ps              600 Mbps
#   PHYRatio       4:1                  -> ui_clk = 300 MHz / 4 = 75 MHz
#   DataWidth      16, DataMask on      -> app_wdf_data is 128 bits
#   RowAddress     13, ColAddress 10
#   InputClkFreq   200.02 MHz           sys_clk_i must be ~200 MHz
#   SystemClock    No Buffer            MIG expects an already-buffered clock
#   ReferenceClock Use System Clock     no separate clk_ref_i
#   PortInterface  NATIVE               app_* interface, not AXI
#   SysReset       ACTIVE LOW
#
# The generated core is written to ip/ and is NOT rebuilt by the normal build
# (generation takes minutes); build.tcl reads what this script produced.

set srcdir [file dirname [file normalize [info script]]]
set ipdir  [file join $srcdir ip]
set prj    [file join $ipdir mig.prj]
set part   xc7a100tcsg324-1

if {![file exists $prj]} {
    puts "ERROR: $prj missing (Digilent MIG project file)"
    exit 1
}

create_project -in_memory -part $part
set_property target_language Verilog [current_project]
set_property ip_repo_paths {} [current_project]

# The .prj names the module 'ddr' - keep that so the file and the module agree
create_ip -name mig_7series -vendor xilinx.com -library ip \
          -module_name ddr -dir $ipdir

set_property -dict [list \
    CONFIG.XML_INPUT_FILE       $prj \
    CONFIG.RESET_BOARD_INTERFACE {Custom} \
    CONFIG.MIG_DONT_TOUCH_PARAM  {Custom} \
    CONFIG.BOARD_MIG_PARAM       {Custom} \
] [get_ips ddr]

generate_target all [get_ips ddr]
synth_ip [get_ips ddr]

# The generated files below are committed, and Vivado writes into them the
# absolute folders they were made in (this checkout and the Vivado install).
# A machine path must not be committed, so rewrite those to repo-relative
# text. Only header comments and the MIG batch record (xil_txt.in) carry them;
# nothing in this repo's flow reads xil_txt.in back.
set _repo_rel "Verilog/fpga/nexys4ddr/ddr2-test"
set _map [list "$srcdir/" "$_repo_rel/"]
if {[info exists ::env(XILINX_VIVADO)] && $::env(XILINX_VIVADO) ne ""} {
    lappend _map "[file normalize $::env(XILINX_VIVADO)]/" "<Vivado install>/"
}
foreach _f {ddr_stub.v ddr_stub.vhdl ddr_sim_netlist.v ddr_sim_netlist.vhdl xil_txt.in} {
    set _p [file join $ipdir ddr $_f]
    if {![file exists $_p]} continue
    set _h [open $_p r]; fconfigure $_h -translation binary; set _t [read $_h]; close $_h
    set _h [open $_p w]; fconfigure $_h -translation binary
    puts -nonewline $_h [string map -nocase $_map $_t]
    close $_h
}

# Report the real port list - the tester must be written against THIS, not
# against what the documentation is assumed to say.
set stub [file join $ipdir ddr ddr_stub.v]
if {[file exists $stub]} {
    puts "=== ddr_stub.v ==="
    set fp [open $stub r]
    puts [read $fp]
    close $fp
} else {
    puts "NOTE: no stub at $stub - look for ddr.veo / ddr_sim_netlist.v"
}

puts "=== MIG GENERATION COMPLETE ==="
