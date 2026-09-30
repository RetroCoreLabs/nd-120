# Runs timing_explore.tcl (opens the routed checkpoint, no resynth, ~1-2 min).
# Wrapper so you don't need vivado on PATH (ND120_VIVADO in local.mk at the
# repository root, written by configure.py).
param(
    # Empty = take ND120_VIVADO (see Verilog/fpga/paths.ps1).
    [string]$VivadoPath = ""
)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "..\paths.ps1")   # reads local.mk at the repository root (ND120_BASYS3_PROJECT reaches the Tcl through the environment)
$VivadoPath = Resolve-ND120Tool -Given $VivadoPath -Var "ND120_VIVADO" -Target "timing_explore.ps1"
$Tcl = Join-Path $ScriptDir "timing_explore.tcl"
$LogDir = Join-Path $ScriptDir "logs"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

Write-Host "Running timing explore (no resynth)..." -ForegroundColor Cyan
& $VivadoPath -mode batch -source $Tcl -log (Join-Path $LogDir "explore.log") -journal (Join-Path $LogDir "explore.jou")
Write-Host "`nReports in: $LogDir" -ForegroundColor Green
Get-ChildItem (Join-Path $LogDir "explore_*.rpt") | ForEach-Object { Write-Host "  $($_.FullName)" -ForegroundColor Gray }
