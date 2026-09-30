# ND-120 FPGA - shared local-settings helpers for the Vivado and Gowin Tcl
# scripts.
#
# Source it from a board script:
#   source [file join [file dirname [file normalize [info script]]] .. paths.tcl]
#
# The rule it serves: no machine-specific folder is written into a script.
# Paths OUTSIDE the repository (the build folder, other repositories) come
# from named variables, read from the environment and, when a variable is not
# set there, from local.mk at the REPOSITORY ROOT - the untracked file
# configure.py writes. Same rule as paths.mk and paths.ps1: the environment
# wins over local.mk. So a script started straight from the Vivado console or
# gw_sh (not through make) needs nothing extra.
#
# Procs (all prefixed nd120_ so they cannot collide with a script's names):
#   nd120_setting NAME            the value, or "" when not set
#   nd120_require NAMES ?TARGET?  stop with the one message when a setting is
#                                 missing (same words as paths.mk/paths.ps1)
#   nd120_board_dir BOARD         $ND120_BUILD_DIR/BOARD, created, normalized -
#                                 where EVERY output of that board's build goes
#   nd120_host_path VALUE         X:\... <-> /mnt/x/... for the host Tcl runs on
#
# Variables it sets:
#   nd120_root      the repository root
#   nd120_local_mk  <repository root>/local.mk

set nd120_root     [file normalize [file join [file dirname [file normalize [info script]]] .. ..]]
set nd120_local_mk [file join $nd120_root local.mk]

# Short descriptions, for the messages. Same words as configure.py.
array set nd120_what {
    ND120_BUILD_DIR      {where builds go}
    ND120_VIVADO         {the Vivado program}
    ND120_GOWIN          {the Gowin gw_sh program}
    ND_REPOS             {the folder holding the other ND repositories}
    ND120_ILA_CSV        {an ILA capture exported as CSV}
    ND120_ORACLE_DIR     {where long trace captures are kept}
}

# Copy the ND120_* / ND_REPOS settings from local.mk into ::env - only the
# ones the environment does not already hold. Only plain "NAME := value"
# lines are read; '$$' is '$' and '\#' is '#' in make syntax.
proc nd120_import_local_mk {} {
    global nd120_local_mk
    if {![file exists $nd120_local_mk]} { return }
    set fh [open $nd120_local_mk r]
    set text [read $fh]
    close $fh
    foreach line [split $text "\n"] {
        set line [string trimright $line "\r"]
        if {[regexp {^\s*(ND120_[A-Za-z0-9_]+|ND_REPOS)\s*[:?]?=(.*)$} $line -> name val]} {
            set val [string map [list {$$} {$} {\#} {#}] [string trim $val]]
            if {![info exists ::env($name)] || [string trim $::env($name)] eq ""} {
                set ::env($name) $val
            }
        }
    }
}

# local.mk holds folders in the form the shell that ran configure.py used.
# Windows Tcl (Vivado/gw_sh on Windows) needs X:/..., Linux Tcl needs /mnt/x/...
proc nd120_host_path {value} {
    if {$::tcl_platform(platform) eq "windows"} {
        if {[regexp {^/mnt/([a-zA-Z])(/.*)?$} $value -> d rest]} {
            if {$rest eq ""} { set rest / }
            return "[string toupper $d]:$rest"
        }
        return $value
    }
    if {[regexp {^([A-Za-z]):[\\/](.*)$} $value -> d rest]} {
        set p "/mnt/[string tolower $d]/[string map {\\ /} $rest]"
        if {[file isdirectory "/mnt/[string tolower $d]"]} { return $p }
    }
    return $value
}

proc nd120_setting {name} {
    if {[info exists ::env($name)]} { return [string trim $::env($name)] }
    return ""
}

# Stop the script. In batch mode (vivado -mode batch, gw_sh, tclsh) that is
# exit 1 - an uncaught error would add a Tcl stack trace under the message.
# In the Vivado GUI console exit would close the GUI, so it is an error there.
proc nd120_stop {msg} {
    set batch 1
    if {[info exists ::rdi::mode] && $::rdi::mode ne "batch"} { set batch 0 }
    if {$batch} { exit 1 }
    error $msg
}

# The one "missing setting" block - word for word what configure.py,
# paths.mk and paths.ps1 print.
proc nd120_require {names {target ""}} {
    global nd120_local_mk nd120_what
    set parts {}
    foreach n $names {
        set w "a local setting"
        if {[info exists nd120_what($n)]} { set w $nd120_what($n) }
        lappend parts "$n ($w)"
    }
    set missing {}
    set bad {}
    foreach n $names {
        set v [nd120_setting $n]
        if {$v eq ""} { lappend missing $n; continue }
        if {$n in {ND120_VIVADO ND120_GOWIN} && ![file isfile [nd120_host_path $v]]} {
            lappend bad [list $n $v]
        }
    }
    if {[llength $missing] == 0 && [llength $bad] == 0} { return }
    if {[llength $parts] == 1} {
        set needs [lindex $parts 0]
    } else {
        set needs "[join [lrange $parts 0 end-1] {, }] and [lindex $parts end]"
    }
    set who "this target"
    if {$target ne ""} { set who "'$target'" }
    puts "nd-120: $who needs $needs."
    if {[llength $missing]} {
        if {![file exists $nd120_local_mk]} {
            puts "  local.mk not found at $nd120_local_mk."
        } else {
            puts "  $nd120_local_mk does not set [join $missing {, }]."
        }
    }
    foreach b $bad {
        puts "  [lindex $b 0] points at [lindex $b 1], which does not exist - run configure.py again."
    }
    set first [lindex $names 0]
    if {[llength $missing]} { set first [lindex $missing 0] } elseif {[llength $bad]} { set first [lindex [lindex $bad 0] 0] }
    set ph "<value>"
    if {$first eq "ND120_BUILD_DIR"} { set ph "<folder>" } elseif {$first in {ND120_VIVADO ND120_GOWIN}} { set ph "<program>" }
    puts "  Fix: from the repository root run   python3 configure.py    (Windows: py configure.py)"
    puts "       or set one value:              python3 configure.py --set $first=$ph"
    puts "  See CONTRIBUTING.md \"Local settings\"."
    nd120_stop "nd-120: stopped before doing any work - see above"
}

# This board's build folder, created when missing. Everything a board build
# writes goes here: bitstream, reports, timing-analysis runs, checkpoints,
# copied microcode images, generated sources.
proc nd120_board_dir {board {target ""}} {
    nd120_require ND120_BUILD_DIR $target
    set dir [file normalize [file join [nd120_host_path [nd120_setting ND120_BUILD_DIR]] $board]]
    file mkdir $dir
    return $dir
}

nd120_import_local_mk
