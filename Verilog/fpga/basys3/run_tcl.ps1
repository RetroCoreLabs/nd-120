# Generic Vivado batch runner - Vivado comes from ND120_VIVADO (local.mk at
# the repository root, written by configure.py); Vivado runs in the build
# folder <ND120_BUILD_DIR>\basys3 and its logs go to <build>\logs\.
# Usage:  .\run_tcl.ps1 exp_slowclk.tcl
#         .\run_tcl.ps1 timing_explore.tcl
param(
    [Parameter(Mandatory=$true)][string]$Tcl,
    # Empty = take ND120_VIVADO (see Verilog/fpga/paths.ps1).
    [string]$VivadoPath = ""
)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "..\paths.ps1")   # reads local.mk at the repository root (ND120_BUILD_DIR reaches the Tcl through the environment)
$VivadoPath = Resolve-ND120Tool -Given $VivadoPath -Var "ND120_VIVADO" -Target "run_tcl.ps1"
$TclPath = if (Test-Path $Tcl) { (Resolve-Path $Tcl).Path } else { Join-Path $ScriptDir $Tcl }
$OutDir = Get-ND120BuildDir -Board "basys3" -Target "run_tcl.ps1"
$LogDir = Join-Path $OutDir "logs"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$base = [System.IO.Path]::GetFileNameWithoutExtension($TclPath)

if (-not (Test-Path $TclPath))    { Write-Error "Tcl not found: $TclPath"; exit 1 }

Write-Host "Running $TclPath ..." -ForegroundColor Cyan
Push-Location $OutDir
try {
    & $VivadoPath -mode batch -source $TclPath -log (Join-Path $LogDir "$base.log") -journal (Join-Path $LogDir "$base.jou")
} finally {
    Pop-Location
}
Write-Host "Done. Log: $(Join-Path $LogDir "$base.log")" -ForegroundColor Green
