# Generic Vivado batch runner - no vivado-on-PATH needed when ND120_VIVADO is
# set (Verilog/fpga/local.mk); logs go to .\logs\.
# Usage:  .\run_tcl.ps1 exp_slowclk.tcl
#         .\run_tcl.ps1 timing_explore.tcl
param(
    [Parameter(Mandatory=$true)][string]$Tcl,
    # Empty = take ND120_VIVADO, else vivado.bat on PATH (see Verilog/fpga/paths.ps1).
    [string]$VivadoPath = ""
)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir "..\paths.ps1")   # reads Verilog/fpga/local.mk (ND120_BASYS3_PROJECT reaches the Tcl through the environment)
$VivadoPath = Resolve-ND120Tool -Given $VivadoPath -Var "ND120_VIVADO" -Names @("vivado.bat", "vivado")
if (-not $VivadoPath) { Write-Error "Vivado not found - set ND120_VIVADO in Verilog/fpga/local.mk or pass -VivadoPath"; exit 1 }
$TclPath = if (Test-Path $Tcl) { (Resolve-Path $Tcl).Path } else { Join-Path $ScriptDir $Tcl }
$LogDir = Join-Path $ScriptDir "logs"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$base = [System.IO.Path]::GetFileNameWithoutExtension($TclPath)

if (-not (Test-Path $TclPath))    { Write-Error "Tcl not found: $TclPath"; exit 1 }

Write-Host "Running $TclPath ..." -ForegroundColor Cyan
& $VivadoPath -mode batch -source $TclPath -log (Join-Path $LogDir "$base.log") -journal (Join-Path $LogDir "$base.jou")
Write-Host "Done. Log: $(Join-Path $LogDir "$base.log")" -ForegroundColor Green
