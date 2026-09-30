# Flash the existing bitstream to FPGA and/or SPI flash
# Usage: .\flash.ps1              (JTAG + SPI flash, persistent)
#        .\flash.ps1 -Quick       (JTAG only, volatile, fast)

#
# Paths: ND120_BUILD_DIR (the bitstream is <build>\basys3\ND120_TOP.bit) and
# ND120_VIVADO, both required, from local.mk at the repository root (python3
# configure.py writes it) or the environment - see local.mk.example.
# Vivado is started in the build folder, so its log and journal land there.

param(
    # Empty = take ND120_VIVADO (see Verilog/fpga/paths.ps1).
    [string]$VivadoPath = "",
    [switch]$Quick
)

. (Join-Path $PSScriptRoot "..\paths.ps1")

$VivadoPath = Resolve-ND120Tool -Given $VivadoPath -Var "ND120_VIVADO" -Target "flash.ps1"
$OutDir  = Get-ND120BuildDir -Board "basys3" -Target "flash.ps1"
$BitFile = Join-Path $OutDir "ND120_TOP.bit"
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

Push-Location $OutDir
try {
    & $VivadoPath -mode batch -source $TclScript -log vivado_flash.log -journal vivado_flash.jou -tclargs $mode
} finally {
    Pop-Location
}

$exitCode = $LASTEXITCODE
if ($exitCode -eq 0) {
    Write-Host "`nPROGRAMMING SUCCESSFUL" -ForegroundColor Green
} else {
    Write-Host "`nPROGRAMMING FAILED (exit code: $exitCode)" -ForegroundColor Red
    Write-Host "Check $(Join-Path $OutDir 'vivado_flash.log') for details."
}
exit $exitCode
