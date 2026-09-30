# ND120 Tang Nano 20K - program the board (Windows PowerShell)
#
#   cd Verilog\fpga\tang-nano-20k        (inside your checkout)
#   .\tang_flash.ps1              # permanent write into the board's flash
#   .\tang_flash.ps1 -Sram        # volatile SRAM load (gone on power-off)
#   .\tang_flash.ps1 -Build       # run gowin_build.ps1 first, then flash
#   .\tang_flash.ps1 -Force       # flash even if the staleness check complains
#
# WHY THIS EXISTS
#   Programming needs openFPGALoader, which needs raw USB access to the Tang's
#   FTDI. That lives on the WSL side, and WSL only sees the FTDI after usbipd
#   hands it over. This script does the whole chain from Windows: check the
#   bitstream is real and current, attach the board (tang_usb.ps1), then run
#   openFPGALoader through WSL.
#
# THE STALENESS CHECK
#   The failure that motivated this: a .fs left over from an older build sits
#   in build\ and flashes perfectly happily, so the board runs code that has
#   nothing to do with the sources you just edited. This script compares the
#   bitstream's timestamp against the newest .v in the Verilog tree and the
#   project file list, and refuses (unless -Force) when the bitstream is older.
#   It also prints which optional controllers tang20k_defines.v currently
#   selects, so what you are about to flash is stated out loud.

param(
    [switch]$Sram,
    [switch]$Build,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$here = $PSScriptRoot

# The Gowin build output lives in the build folder, $ND120_BUILD_DIR\tang-nano-20k
# (local.mk at the repository root, written by configure.py).
. (Join-Path $here "..\paths.ps1")
$bdir   = Get-ND120BuildDir -Board "tang-nano-20k" -Target "tang_flash.ps1"
$fsRel  = "nd120_tang20k_build\impl\pnr\nd120_tang20k_build.fs"
$fs     = Join-Path $bdir $fsRel
$rpt    = Join-Path $bdir "nd120_tang20k_build\impl\pnr\nd120_tang20k_build.rpt.txt"
$synLog = Join-Path $bdir "nd120_tang20k_build\impl\gwsynthesis\nd120_tang20k_build.log"
$gprj   = Join-Path $here "nd120_tang20k.gprj"
$defs   = Join-Path $here "src\tang20k_defines.v"
$vroot  = Resolve-Path (Join-Path $here "..\..")   # the Verilog tree

# --- optional build ----------------------------------------------------------
if ($Build) {
    Write-Host "=== Building (gowin_build.ps1 -Variant slow) ===" -ForegroundColor Cyan
    & (Join-Path $here "gowin_build.ps1") -Variant slow
    if ($LASTEXITCODE -ne 0) { Write-Error "Build failed - not flashing." }
}

# --- bitstream present? ------------------------------------------------------
if (-not (Test-Path $fs)) {
    Write-Error "No bitstream at $fsRel - run '.\gowin_build.ps1 -Variant slow' (or pass -Build)."
}
$fsTime = (Get-Item $fs).LastWriteTime
Write-Host "Bitstream: $fsRel"
Write-Host "  built:   $fsTime"

# --- what does this build contain? ------------------------------------------
# An uncommented `define line only; commented-out ones do not count.
if (Test-Path $defs) {
    $on = @()
    foreach ($sym in @("TANG_SMD", "TANG_WD")) {
        $hit = Select-String -Path $defs -Pattern "^\s*``define\s+$sym\b" -ErrorAction SilentlyContinue
        if ($hit) { $on += $sym }
    }
    if ($on.Count -gt 0) {
        Write-Host "  sources currently select: $($on -join ', ')"
    } else {
        Write-Host "  sources currently select: (no optional disc controller)"
    }
}
# Cross-check against the build that actually produced this bitstream.
#
# Read the SYNTHESIS log, not the PnR report. The PnR report (rpt.txt) lists
# flattened instance paths and resource counts - it contains no module names
# at all, so grepping it for ND_WINCHESTER / ND_SMD returns 0 for every build
# including ones that definitely contain them. The synthesis log has the line
# "Compiling module 'ND_WINCHESTER(...)'", which is the real evidence.
if (Test-Path $synLog) {
    $inBuild = @()
    foreach ($m in @("ND_WINCHESTER", "ND_SMD")) {
        if (Select-String -Path $synLog -Pattern "Compiling module '$m\b" -Quiet) { $inBuild += $m }
    }
    if ($inBuild.Count -gt 0) {
        Write-Host "  bitstream contains:       $($inBuild -join ', ')"
    } else {
        Write-Host "  bitstream contains:       (no optional disc controller)"
    }

    # An empty control store is a dead CPU. gowin_build.ps1 checks this too,
    # but a bitstream can be flashed without having just been built here.
    $ex = @(Select-String -Path $synLog -Pattern "EX3988").Count
    if ($ex -gt 0) {
        Write-Error "WCS preload FAILED: $ex 'Cannot open file' (EX3988) warnings in the synthesis log - the control store is EMPTY. Do not flash this bitstream."
    } else {
        Write-Host "  WCS preload:              OK (no EX3988)"
    }
}

# --- staleness ---------------------------------------------------------------
$newest = $null
$srcs = Get-ChildItem -Path $vroot -Filter *.v -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notlike "*\build\*" -and $_.FullName -notlike "*\obj_dir*" }
foreach ($f in @($srcs) + @(Get-Item $gprj -ErrorAction SilentlyContinue)) {
    if ($f -and ($null -eq $newest -or $f.LastWriteTime -gt $newest.LastWriteTime)) { $newest = $f }
}
if ($newest -and $newest.LastWriteTime -gt $fsTime) {
    $msg = @"
STALE BITSTREAM.

  bitstream : $fsTime
  newer src : $($newest.LastWriteTime)  $($newest.FullName)

The bitstream predates your sources, so flashing it would run OLD logic on the
board and any conclusion you draw from it would be about the old build.

Rebuild:   .\gowin_build.ps1 -Variant slow      (or re-run this with -Build)
Override:  re-run this with -Force
"@
    if ($Force) {
        Write-Host $msg -ForegroundColor Yellow
        Write-Host "-Force given: flashing anyway." -ForegroundColor Yellow
    } else {
        Write-Error $msg
    }
} else {
    Write-Host "  staleness check: OK (bitstream is newer than the sources)" -ForegroundColor Green
}

# --- attach the board to WSL -------------------------------------------------
Write-Host ""
Write-Host "=== Attaching board to WSL ===" -ForegroundColor Cyan
& (Join-Path $here "tang_usb.ps1")
if ($LASTEXITCODE -ne 0) { Write-Error "Could not attach the board - see above." }

# --- program -----------------------------------------------------------------
$mode  = if ($Sram) { "volatile SRAM" } else { "permanent flash" }
$fsWsl = (wsl.exe -e wslpath -a "$fs").Trim()
$flag  = if ($Sram) { "" } else { "-f " }

Write-Host ""
Write-Host "=== Programming ($mode) ===" -ForegroundColor Cyan

# openFPGALoader lives in the OSS CAD Suite, which is put on PATH by an
# interactive shell's rc file. `bash -lc` is a LOGIN shell and reads .profile
# instead, so the tool is often absent there ("command not found", exit 127).
# Resolve it explicitly: PATH first, then the usual OSS CAD Suite location
# under the user's home. $HOME is expanded inside WSL, so no machine-specific
# path is baked into this file.
$prog = @"
OFL=`$(command -v openFPGALoader 2>/dev/null)
[ -z "`$OFL" ] && [ -x "`$HOME/oss-cad-suite/bin/openFPGALoader" ] && OFL="`$HOME/oss-cad-suite/bin/openFPGALoader"
[ -z "`$OFL" ] && [ -x "/opt/oss-cad-suite/bin/openFPGALoader" ] && OFL="/opt/oss-cad-suite/bin/openFPGALoader"
if [ -z "`$OFL" ]; then
    echo "ERROR: openFPGALoader not found (PATH, ~/oss-cad-suite/bin, /opt/oss-cad-suite/bin)" >&2
    exit 127
fi
echo "using: `$OFL"
"`$OFL" -b tangnano20k $flag'$fsWsl'
"@
wsl.exe -e bash -lc $prog
if ($LASTEXITCODE -ne 0) { Write-Error "openFPGALoader failed (exit $LASTEXITCODE)" }

Write-Host ""
Write-Host "Programmed ($mode)." -ForegroundColor Green
Write-Host "POWER-CYCLE THE BOARD before judging anything on it." -ForegroundColor Yellow
Write-Host "Then open the console: /dev/ttyUSB1 at 9600 8N1"
Write-Host "  WSL:      picocom -b 9600 /dev/ttyUSB1"
Write-Host "  Windows:  PuTTY on the COM port, 9600 8N1"
Write-Host "(usbipd holds the FTDI on the WSL side - re-run .\tang_usb.ps1"
Write-Host " after the power cycle, or .\tang_usb.ps1 -Detach to hand it back"
Write-Host " to Windows for PuTTY.)"
