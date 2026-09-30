# ND-120 FPGA - shared path helpers for the PowerShell build scripts.
#
# Dot-source it from a board script:
#   . (Join-Path $PSScriptRoot "..\paths.ps1")
#
# The rule it serves: no machine-specific folder is written into a script.
#   * Paths INSIDE the repository come from the script's own location
#     ($PSScriptRoot) - never from a drive letter.
#   * Paths OUTSIDE the repository are named variables (ND120_VIVADO,
#     ND120_VIVADO_LICENSE, ND120_GOWIN, ND120_BASYS3_PROJECT, ...). They are
#     read from the environment, and when a variable is not set there, from
#     Verilog/fpga/local.mk - the untracked file each person makes by copying
#     Verilog/fpga/local.mk.example. So a script started by hand from a
#     Windows shell sees the same settings make would pass it.
#
# Tool executables fall back to the tool found on PATH. Anything else that is
# missing stops the script with an error naming the variable.

$script:ND120FpgaDir   = $PSScriptRoot
$script:ND120LocalMk   = Join-Path $PSScriptRoot "local.mk"
$script:ND120MkExample = "Verilog/fpga/local.mk.example"

# Copy the ND120_* / ND_REPOS settings from local.mk into this process's
# environment - but only the ones the environment does not already hold, so
# a value set in the shell (or passed on by make) always wins. Only plain
# "NAME := value" (or = / ?=) lines are read; make functions are not expanded.
function Import-ND120LocalMk {
    if (-not (Test-Path $script:ND120LocalMk)) { return }
    foreach ($line in Get-Content $script:ND120LocalMk) {
        if ($line -match '^\s*(ND120_[A-Za-z0-9_]+|ND_REPOS)\s*[:?]?=(.*)$') {
            $name = $Matches[1]
            $val  = $Matches[2].Trim()
            if (-not [Environment]::GetEnvironmentVariable($name, 'Process')) {
                [Environment]::SetEnvironmentVariable($name, $val, 'Process')
            }
        }
    }
}

# Find a tool executable. Order: the value the caller was given (a script
# -Parameter), then the named variable, then the first of $Names on PATH.
# Returns $null when none of those gives an existing file.
function Resolve-ND120Tool {
    param(
        [string]$Given,
        [Parameter(Mandatory=$true)][string]$Var,
        [Parameter(Mandatory=$true)][string[]]$Names
    )
    if ($Given) {
        if (Test-Path $Given) { return $Given }
        Write-Host "Not found (given on the command line): $Given" -ForegroundColor Red
        return $null
    }
    $fromEnv = [Environment]::GetEnvironmentVariable($Var, 'Process')
    if ($fromEnv) {
        if (Test-Path $fromEnv) { return $fromEnv }
        Write-Host "Not found ($Var): $fromEnv" -ForegroundColor Red
        return $null
    }
    foreach ($n in $Names) {
        $cmd = Get-Command $n -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd) { return $cmd.Source }
    }
    Write-Host "Not found: none of '$($Names -join "', '")' is on PATH and $Var is not set." -ForegroundColor Red
    Write-Host "Copy $script:ND120MkExample to Verilog/fpga/local.mk and set $Var there, or put the tool on PATH." -ForegroundColor Red
    return $null
}

# A required out-of-repo folder or file. Returns the value, or $null after
# printing which variable is missing and where to set it.
function Get-ND120Required {
    param(
        [Parameter(Mandatory=$true)][string]$Var,
        [Parameter(Mandatory=$true)][string]$What
    )
    $v = [Environment]::GetEnvironmentVariable($Var, 'Process')
    if ($v) { return $v }
    Write-Host "ERROR: $Var is not set - it must name $What." -ForegroundColor Red
    Write-Host "       Copy $script:ND120MkExample to Verilog/fpga/local.mk and set it there," -ForegroundColor Red
    Write-Host "       or set it in the environment." -ForegroundColor Red
    return $null
}

Import-ND120LocalMk
