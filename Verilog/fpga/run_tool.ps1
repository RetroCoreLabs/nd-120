# ND-120 FPGA - start a Windows build tool (Vivado, gw_sh) from make in WSL,
# with the build folder as its working folder.
#
# paths.mk ($(call nd120_run,TOOL,DIR,ARGS)) runs it as
#   ND120_RUN_DIR=<build folder> ND120_RUN_TOOL=<program> \
#       powershell.exe -NoProfile -ExecutionPolicy Bypass -File run_tool.ps1 ARGS...
#
# Why a script and not an inline command: the tool's arguments pass through
# untouched as $args (this script has NO param block, so "-mode", "-source",
# "-tclargs" are never taken for its own parameters - measured 30-SEP-2026
# with a probe script: every argument, including ones with spaces and '=',
# arrived as one $args entry each), and the working folder and program come
# in through the environment (listed in WSLENV by paths.mk), so no quoting has
# to survive a second shell.
#
# Why the working folder matters: Vivado writes vivado.log, vivado.jou and
# its .Xil scratch folder into whatever folder it was started in. Starting it
# in the build folder keeps all of that out of the repository.

$dir  = $env:ND120_RUN_DIR
$tool = $env:ND120_RUN_TOOL
if (-not $dir -or -not $tool) {
    Write-Host "run_tool.ps1: ND120_RUN_DIR and ND120_RUN_TOOL must be set (paths.mk sets them)." -ForegroundColor Red
    exit 2
}
if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
    Write-Host "nd-120: the program $tool does not exist - run configure.py again." -ForegroundColor Red
    exit 2
}
if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
Set-Location -LiteralPath $dir

# Licence: a Windows process started through WSL interop inherits the WSL
# environment, NOT the user's registry environment, so XILINXD_LICENSE_FILE
# arrives unset and Vivado falls back to whatever licence it finds on its own
# (that is how a WSL-started build once ran on the BASIC licence and died at
# create_debug_core). ND120_VIVADO_LICENSE (local.mk) is tried first, then the
# Windows user, then the machine value. Never a path written here.
if (-not $env:XILINXD_LICENSE_FILE) {
    $lic = $env:ND120_VIVADO_LICENSE
    if (-not $lic) { $lic = [Environment]::GetEnvironmentVariable('XILINXD_LICENSE_FILE', 'User') }
    if (-not $lic) { $lic = [Environment]::GetEnvironmentVariable('XILINXD_LICENSE_FILE', 'Machine') }
    if ($lic) { $env:XILINXD_LICENSE_FILE = $lic }
}

Write-Host "run_tool: $tool $args"
Write-Host "          in $dir"
& $tool @args
exit $LASTEXITCODE
