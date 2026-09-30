# ND-120 FPGA - shared path helpers for the PowerShell build scripts.
#
# Dot-source it from a board script:
#   . (Join-Path $PSScriptRoot "..\paths.ps1")
#
# The rule it serves: no machine-specific folder is written into a script.
#   * Paths INSIDE the repository come from the script's own location
#     ($PSScriptRoot) - never from a drive letter.
#   * Paths OUTSIDE the repository are named variables (ND120_BUILD_DIR,
#     ND120_VIVADO, ND120_VIVADO_LICENSE, ND120_GOWIN, ...). They are read
#     from the environment, and when a variable is not set there, from
#     local.mk at the REPOSITORY ROOT - the untracked file configure.py
#     writes (python3 configure.py, or py configure.py from a Windows shell).
#     So a script started by hand from a Windows shell sees the same settings
#     make would pass it. Same rule as paths.mk and paths.tcl: the
#     environment wins over local.mk.
#
# A setting that is missing, or a tool path that does not exist, stops the
# script with the same message paths.mk and paths.tcl print (the wording is
# kept identical to configure.py's require_message - change them together).
#
# Written for Windows PowerShell 5.1 as well as PowerShell 7: no ?? or ?:.

$script:ND120FpgaDir = $PSScriptRoot
$script:ND120Root    = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$script:ND120LocalMk = Join-Path $script:ND120Root "local.mk"

# Short descriptions, for the messages. Same words as configure.py.
$script:ND120What = @{
    "ND120_BUILD_DIR"      = "where builds go"
    "ND120_VIVADO"         = "the Vivado program"
    "ND120_VIVADO_LICENSE" = "the Vivado licence file list"
    "ND120_GOWIN"          = "the Gowin gw_sh program"
    "ND120_QUARTUS"        = "the Quartus bin folder"
    "ND120_OSS_CAD_SUITE"  = "the oss-cad-suite folder"
    "ND120_W64DEVKIT"      = "the w64devkit folder"
    "ND_REPOS"             = "the folder holding the other ND repositories"
    "ND120_ILA_CSV"        = "an ILA capture exported as CSV"
    "ND120_ORACLE_DIR"     = "where long trace captures are kept"
    "ND120_FRESH_DIR"      = "an empty folder for make fresh-build"
}
$script:ND120Placeholder = @{
    "ND120_BUILD_DIR" = "<folder>"; "ND120_VIVADO" = "<program>"; "ND120_GOWIN" = "<program>"
}

# local.mk may hold /mnt/x/... (written by configure.py in WSL); a Windows
# program needs X:/... - the same conversion paths.mk and paths.tcl make.
function ConvertTo-ND120HostPath {
    param([string]$Value)
    if ($Value -match '^/mnt/([a-zA-Z])(/.*)?$') {
        $rest = $Matches[2]
        if (-not $rest) { $rest = "/" }
        return ($Matches[1].ToUpper() + ":" + $rest)
    }
    return $Value
}

# Copy the ND120_* / ND_REPOS settings from local.mk into this process's
# environment - but only the ones the environment does not already hold, so
# a value set in the shell (or passed on by make) always wins. Only plain
# "NAME := value" (or = / ?=) lines are read; make functions are not expanded.
# In make syntax '$$' is '$' and '\#' is '#'.
function Import-ND120LocalMk {
    if (-not (Test-Path $script:ND120LocalMk)) { return }
    foreach ($line in Get-Content $script:ND120LocalMk) {
        if ($line -match '^\s*(ND120_[A-Za-z0-9_]+|ND_REPOS)\s*[:?]?=(.*)$') {
            $name = $Matches[1]
            $val  = $Matches[2].Trim().Replace('$$', '$').Replace('\#', '#')
            if (-not [Environment]::GetEnvironmentVariable($name, 'Process')) {
                [Environment]::SetEnvironmentVariable($name, $val, 'Process')
            }
        }
    }
}

# The one "missing setting" block. $Problems: list of @(kind, name, value),
# kind 'missing' or 'bad'. Prints it and exits the script.
function Write-ND120SettingsProblem {
    param([string[]]$Names, [object[]]$Problems, [string]$Target)
    $parts = @()
    foreach ($n in $Names) {
        $w = $script:ND120What[$n]; if (-not $w) { $w = "a local setting" }
        $parts += "$n ($w)"
    }
    if ($parts.Count -eq 1) { $needs = $parts[0] }
    else { $needs = ($parts[0..($parts.Count - 2)] -join ", ") + " and " + $parts[-1] }
    $who = "this target"; if ($Target) { $who = "'$Target'" }
    $lines = @("nd-120: $who needs $needs.")
    $missing = @()
    foreach ($p in $Problems) { if ($p[0] -eq 'missing') { $missing += $p[1] } }
    if ($missing.Count -gt 0) {
        if (-not (Test-Path $script:ND120LocalMk)) {
            $lines += "  local.mk not found at $($script:ND120LocalMk)."
        } else {
            $lines += "  $($script:ND120LocalMk) does not set $($missing -join ', ')."
        }
    }
    foreach ($p in $Problems) {
        if ($p[0] -eq 'bad') {
            $lines += "  $($p[1]) points at $($p[2]), which does not exist - run configure.py again."
        }
    }
    $first = $Names[0]
    if ($missing.Count -gt 0) { $first = $missing[0] } elseif ($Problems.Count -gt 0) { $first = $Problems[0][1] }
    $ph = $script:ND120Placeholder[$first]; if (-not $ph) { $ph = "<value>" }
    $lines += "  Fix: from the repository root run   python3 configure.py    (Windows: py configure.py)"
    $lines += "       or set one value:              python3 configure.py --set $first=$ph"
    $lines += "  See CONTRIBUTING.md `"Local settings`"."
    foreach ($l in $lines) { Write-Host $l -ForegroundColor Red }
    exit 1
}

# Check the settings a script needs BEFORE it does any work. $Tools are
# program files and must exist; $Names only have to be set. Exits the script
# with the one message when something is wrong.
function Assert-ND120Settings {
    param([string[]]$Names = @(), [string[]]$Tools = @(), [string]$Target = "")
    $all = @($Tools) + @($Names)
    $problems = @()
    foreach ($n in $all) {
        $v = [Environment]::GetEnvironmentVariable($n, 'Process')
        if (-not $v) { $problems += ,@('missing', $n, ''); continue }
        if ($Tools -contains $n) {
            $p = ConvertTo-ND120HostPath $v
            if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { $problems += ,@('bad', $n, $v) }
        }
    }
    if ($problems.Count -gt 0) { Write-ND120SettingsProblem -Names $all -Problems $problems -Target $Target }
}

# Find a tool executable. Order: the value the caller was given (a script
# -Parameter), then the named variable. There is no PATH fallback any more:
# configure.py finds the tool (on PATH too) and writes the variable, so every
# script uses the same program. Exits with the one message when missing.
function Resolve-ND120Tool {
    param(
        [string]$Given,
        [Parameter(Mandatory=$true)][string]$Var,
        [string]$Target = ""
    )
    if ($Given) {
        if (Test-Path -LiteralPath $Given) { return $Given }
        Write-Host "nd-120: the program given on the command line does not exist: $Given" -ForegroundColor Red
        exit 1
    }
    Assert-ND120Settings -Tools @($Var) -Target $Target
    return (ConvertTo-ND120HostPath ([Environment]::GetEnvironmentVariable($Var, 'Process')))
}

# A required out-of-repo value. Returns it, or exits with the one message.
function Get-ND120Required {
    param(
        [Parameter(Mandatory=$true)][string]$Var,
        [string]$What = "",
        [string]$Target = ""
    )
    Assert-ND120Settings -Names @($Var) -Target $Target
    return (ConvertTo-ND120HostPath ([Environment]::GetEnvironmentVariable($Var, 'Process')))
}

# This board's build folder: $ND120_BUILD_DIR/<board>, created when missing.
# Every build output goes there - bitstream, reports, logs, the tool's own
# journal and .Xil.
function Get-ND120BuildDir {
    param([Parameter(Mandatory=$true)][string]$Board, [string]$Target = "")
    $root = Get-ND120Required -Var "ND120_BUILD_DIR" -Target $Target
    $dir = Join-Path $root $Board
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    return (Resolve-Path $dir).Path
}

Import-ND120LocalMk
