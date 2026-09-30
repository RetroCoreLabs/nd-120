# Flash the existing bitstream to FPGA and/or SPI flash
# Usage: .\flash.ps1              (JTAG + SPI flash, persistent)
#        .\flash.ps1 -Quick       (JTAG only, volatile, fast)

#
# Paths: ND120_BASYS3_PROJECT (the Vivado project folder) and ND120_VIVADO,
# both required, from local.mk at the repository root (python3 configure.py
# writes it) or the environment - see local.mk.example.

param(
    # Empty = take ND120_VIVADO (see Verilog/fpga/paths.ps1).
    [string]$VivadoPath = "",
    [switch]$Quick
)

. (Join-Path $PSScriptRoot "..\paths.ps1")

$VivadoPath = Resolve-ND120Tool -Given $VivadoPath -Var "ND120_VIVADO" -Target "flash.ps1"
$ProjectDir = Get-ND120Required -Var "ND120_BASYS3_PROJECT" -Target "flash.ps1"
$BitFile = Join-Path $ProjectDir "output\ND120_TOP.bit"
if (-not (Test-Path $BitFile)) {
    Write-Error "No bitstream found at $BitFile - run a build first"
    exit 1
}

Write-Host "Bitstream: $BitFile" -ForegroundColor Cyan
Write-Host "Timestamp: $((Get-Item $BitFile).LastWriteTime)" -ForegroundColor Cyan

if ($Quick) {
    $mode = "jtag_only"
    Write-Host "`n=== Programming FPGA via JTAG (volatile) ===" -ForegroundColor Yellow
} else {
    $mode = "jtag_and_flash"
    Write-Host "`n=== Programming FPGA via JTAG + SPI Flash ===" -ForegroundColor Yellow
}

$TclScript = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "flash.tcl"

& $VivadoPath -mode batch -source $TclScript -log vivado_flash.log -journal vivado_flash.jou -tclargs $mode

$exitCode = $LASTEXITCODE
if ($exitCode -eq 0) {
    Write-Host "`nPROGRAMMING SUCCESSFUL" -ForegroundColor Green
} else {
    Write-Host "`nPROGRAMMING FAILED (exit code: $exitCode)" -ForegroundColor Red
    Write-Host "Check vivado_flash.log for details."
}
exit $exitCode
