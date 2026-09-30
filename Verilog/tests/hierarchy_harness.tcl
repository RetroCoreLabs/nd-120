# hierarchy_harness.tcl - run a board's OWN build script with the vendor tool
# swapped out for stubs, and print exactly what that script hands to synthesis:
# the Verilog files (in order), the defines, the include folders and the top.
#
# WHY THIS EXISTS
#     gen_hierarchy.py draws the module tree of every board from a real yosys
#     elaboration. For that it needs each board's file list and defines. Those
#     live in the board's build script (Vivado build.tcl, the Basys3 project
#     script, the MiSTer Quartus .qsf/.qip). Copying the lists into the
#     generator would give a second copy that drifts; guessing them from the
#     folder layout would be wrong. So the script itself is run here, in a
#     plain tclsh, and every vendor command it calls lands in a stub:
#       read_verilog / add_files / set_global_assignment  -> record the files
#       synth_design / launch_runs synth_1                -> record the top and
#                                                             defines, then stop
#       every other vendor command                        -> does nothing
#
# WHAT IS SWITCHED OFF, SO RUNNING A BUILD SCRIPT HERE CHANGES NOTHING
#     exec           raises an error. The scripts already catch it (the banner
#                    stamp falls back to the committed ROM), and no git,
#                    python or vendor tool is ever started from here.
#     exit           prints a note and carries on. A build script stops when a
#                    prerequisite is missing (the microcode images, a generated
#                    MIG core, the MEGA65 framework submodule). None of those
#                    change which Verilog files are read, so the harness goes
#                    on to the file list instead of stopping.
#     file mkdir/copy/delete/rename, cd, and open for writing do nothing (writes
#                    go to /dev/null). Build scripts copy microcode images into
#                    the tree and write build stamps; a documentation run must
#                    not.
#     open for reading of a missing .xpr project file reads an empty file (the
#                    MEGA65 framework project when the submodule is not checked
#                    out). Any other missing file fails as normal.
#
# OUTPUT, one item per line on stdout (everything else the script prints is
# passed through and ignored by the caller):
#     HIER|FILE|<0 or 1 = SystemVerilog>|<path>
#     HIER|DEFINE|<NAME or NAME=VALUE>
#     HIER|INCDIR|<path>
#     HIER|TOP|<module>
#     HIER|PROJECT|<path of a Vivado .xpr the script opened>
#     HIER|SKIP|<what was not followed, e.g. a framework .qip>
#     HIER|NOTE|<text>
#     HIER|STOP|<command where synthesis would start>
#
# USAGE (called by gen_hierarchy.py, not by hand)
#     tclsh hierarchy_harness.tcl vivado  <build.tcl> [script args...]
#     tclsh hierarchy_harness.tcl project <vivado_build.tcl> [script args...]
#     tclsh hierarchy_harness.tcl quartus <project.qsf>
#
# Last reviewed: 30-SEP-2026
# Ronny Hansen

set ::H_mode   [lindex $argv 0]
set ::H_script [file normalize [lindex $argv 1]]
set ::H_args   [lrange $argv 2 end]
set ::H_stopped 0

proc H_out {kind args} {
    puts stdout "HIER|$kind|[join $args |]"
    flush stdout
}

# A Windows path (E:/...) stays as written: gen_hierarchy.py maps it onto the
# checkout it runs in. Everything else is made absolute here, relative to the
# folder the build script works in.
proc H_norm {p} {
    if {[regexp {^[A-Za-z]:[/\\]} $p]} { return [string map {\\ /} $p] }
    return [file normalize $p]
}

# A Windows path as WSL sees it (F:/x -> /mnt/f/x), for a project file the
# Basys3 script opens from a drive outside the repository.
proc H_host_path {p} {
    if {[regexp {^([A-Za-z]):[/\\](.*)$} $p -> drv rest]} {
        return "/mnt/[string tolower $drv]/[string map {\\ /} $rest]"
    }
    return $p
}

# ---- side effects off (see the header) -------------------------------------
rename exec _H_real_exec
proc exec {args} { error "exec is switched off in the hierarchy harness" }

rename exit _H_real_exit
proc exit {{code 0}} { H_out NOTE "the build script asked to stop here (exit $code); carried on" }

rename cd _H_real_cd
proc cd {args} { return "" }

rename file _H_real_file
proc file {sub args} {
    switch -- $sub {
        mkdir - copy - delete - rename - link { return "" }
        exists {
            # the Basys3 script names its sources with Windows paths (E:/...)
            return [_H_real_file exists [H_host_path [lindex $args 0]]]
        }
        size {
            # the Basys3 script prints the size of microcode images that only
            # exist after its PowerShell wrapper ran; a missing one is 0 here
            set p [H_host_path [lindex $args 0]]
            if {![_H_real_file exists $p]} { return 0 }
            return [_H_real_file size $p]
        }
        default { return [uplevel 1 [list _H_real_file $sub {*}$args]] }
    }
}

rename open _H_real_open
proc open {path {mode r} args} {
    if {[string match {*[wa]*} $mode]} {
        return [_H_real_open /dev/null w]
    }
    set hp [H_host_path $path]
    # only a missing PROJECT file reads as empty; any other missing file
    # (Tcl's own tclIndex lookups included) fails the normal way
    if {[string match *.xpr $hp] && ![_H_real_file exists $hp]} {
        H_out NOTE "not found, read as empty: [_H_real_file tail $path]"
        return [_H_real_open /dev/null r]
    }
    return [_H_real_open $hp $mode {*}$args]
}

# Any command tclsh does not know is a vendor command: it does nothing and
# returns an empty string. Tcl's own lazily loaded procedures still load.
rename unknown _H_real_unknown
proc unknown {args} {
    set cmd [lindex $args 0]
    if {[auto_load $cmd]} { return [uplevel 1 $args] }
    return ""
}

# ---- Vivado non-project flow (Nexys 4 DDR, Cmod A7, QMTECH, MEGA65) --------
proc read_verilog {args} {
    set sv 0
    set n [llength $args]
    for {set i 0} {$i < $n} {incr i} {
        set a [lindex $args $i]
        switch -- $a {
            -sv { set sv 1 }
            -library - -define - -include_dirs { incr i }
            default {
                # read_verilog takes a Tcl LIST of files as one argument
                foreach f $a { H_out FILE $sv [H_norm $f] }
            }
        }
    }
    return ""
}

proc synth_design {args} {
    set n [llength $args]
    for {set i 0} {$i < $n} {incr i} {
        switch -- [lindex $args $i] {
            -top            { H_out TOP [lindex $args [incr i]] }
            -verilog_define { H_out DEFINE [lindex $args [incr i]] }
            -include_dirs   { foreach d [lindex $args [incr i]] { H_out INCDIR [H_norm $d] } }
        }
    }
    H_out STOP synth_design
    set ::H_stopped 1
    error HIER_STOP
}

# ---- Vivado project flow (Basys3: the file list lives in an .xpr) ----------
set ::H_proj_defines {}
set ::H_proj_incdirs {}
set ::H_proj_top ""

proc open_project {path} {
    set hp [H_host_path $path]
    H_out PROJECT $hp
    if {![_H_real_file exists $hp]} { return "" }
    set fh [_H_real_open $hp r]
    set xml [read $fh]
    close $fh
    # only the design sources: <FileSet Name="sources_1" ...> ... </FileSet>
    if {![regexp {<FileSet Name="sources_1".*?</FileSet>} $xml block]} { return "" }
    foreach {all name val} [regexp -all -inline \
            {<Verilog_Define Name="([^"]+)"(?: Val="([^"]*)")?/>} $block] {
        if {$val ne ""} { lappend ::H_proj_defines "$name=$val" } else { lappend ::H_proj_defines $name }
    }
    foreach {all d} [regexp -all -inline {<Option Name="VerilogDir" Val="([^"]+)"/>} $block] {
        lappend ::H_proj_incdirs $d
    }
    regexp {<Option Name="TopModule" Val="([^"]+)"/>} $block -> ::H_proj_top
    return ""
}

proc get_property {name args} {
    switch -nocase -- $name {
        verilog_define { return $::H_proj_defines }
        include_dirs   { return $::H_proj_incdirs }
        default        { return "" }
    }
}

proc set_property {args} {
    # set_property <name> <value> <objects>; the -dict form is not used for these
    set name [lindex $args 0]
    set val  [lindex $args 1]
    switch -nocase -- $name {
        verilog_define { set ::H_proj_defines $val }
        include_dirs   { set ::H_proj_incdirs $val }
        top            { set ::H_proj_top $val }
    }
    return ""
}

proc add_files {args} {
    set fileset sources_1
    set files {}
    set n [llength $args]
    for {set i 0} {$i < $n} {incr i} {
        set a [lindex $args $i]
        switch -- $a {
            -fileset { set fileset [lindex $args [incr i]] }
            -norecurse - -quiet { }
            default { foreach f $a { lappend files $f } }
        }
    }
    if {$fileset ne "sources_1"} { return "" }
    foreach f $files {
        if {[regexp {\.s?v$} $f]} { H_out FILE [regexp {\.sv$} $f] [H_norm $f] }
    }
    return ""
}

# The first command that starts synthesis of the project is the stop point:
# everything the script set up before it is what synthesis reads.
proc H_project_stop {cmd args} {
    if {[lsearch -exact $args synth_1] < 0} { return "" }
    foreach d $::H_proj_defines { H_out DEFINE $d }
    foreach d $::H_proj_incdirs { H_out INCDIR [H_norm $d] }
    if {$::H_proj_top ne ""} { H_out TOP $::H_proj_top }
    H_out STOP $cmd
    set ::H_stopped 1
    error HIER_STOP
}
proc reset_run   {args} { H_project_stop reset_run {*}$args }
proc launch_runs {args} { H_project_stop launch_runs {*}$args }
proc open_run    {args} { H_project_stop open_run {*}$args }

# ---- Quartus project (MiSTer: nd120.qsf, which sources files.qip) ----------
proc set_global_assignment {args} {
    set name ""
    set vals {}
    set n [llength $args]
    for {set i 0} {$i < $n} {incr i} {
        set a [lindex $args $i]
        switch -- $a {
            -name { set name [lindex $args [incr i]] }
            -section_id - -entity - -to - -from - -tag - -library - -hdl_version { incr i }
            default { lappend vals $a }
        }
    }
    set v [lindex $vals 0]
    switch -- $name {
        VERILOG_FILE       { H_out FILE 0 [H_norm $v] }
        SYSTEMVERILOG_FILE { H_out FILE 1 [H_norm $v] }
        VERILOG_MACRO      { H_out DEFINE $v }
        SEARCH_PATH        { H_out INCDIR [H_norm $v] }
        TOP_LEVEL_ENTITY   { H_out TOP $v }
        QIP_FILE           { H_out SKIP "QIP_FILE $v" }
    }
    return ""
}

# The MiSTer framework (sys/) is not ours and is not followed; see
# gen_module_docs.py WHAT IT SKIPS.
rename source _H_real_source
proc source {path args} {
    if {$::H_mode eq "quartus" && [string match sys/* $path]} {
        H_out SKIP "source $path"
        return ""
    }
    return [uplevel #0 [list _H_real_source $path {*}$args]]
}

# ---- run the build script ---------------------------------------------------
set argv $::H_args
set argc [llength $::H_args]
set argv0 $::H_script
_H_real_cd [_H_real_file dirname $::H_script]
if {[catch {uplevel #0 [list _H_real_source $::H_script]} err]} {
    if {!$::H_stopped} {
        H_out NOTE "build script failed before synthesis: $err"
    }
}
if {$::H_mode eq "quartus"} { H_out STOP end-of-project-file }
_H_real_exit 0
