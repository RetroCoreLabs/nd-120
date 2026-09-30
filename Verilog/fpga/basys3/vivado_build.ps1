# ND-120 Vivado Build Script (PowerShell)
#
# Usage (from Verilog\fpga\basys3):
#   .\vivado_build.ps1                 # FRESH full synthesis (~1h) + implementation, NO programming (safe, no board needed)
#   .\vivado_build.ps1 -Program        # ...same, then program JTAG + SPI flash (board must be attached)
#   .\vivado_build.ps1 -ReuseSynth     # skip the ~1h resynth, reuse the last synthesized design (impl only)
#   .\vivado_build.ps1 -LintOnly       # run the linter only
#
# Prerequisites: Vivado installed, and local.mk at the repository root
# (python3 configure.py - or py configure.py - writes it). Settings come from
# there (or from the environment, which wins):
#   ND120_BUILD_DIR       where builds go (required) - everything this build
#                         writes goes to <ND120_BUILD_DIR>\basys3
#   ND120_VIVADO          vivado.bat (required); -VivadoPath overrides it
#   ND120_VIVADO_LICENSE  licence file list; used when XILINXD_LICENSE_FILE
#                         is not already set in this process
#
# Since 30-SEP-2026 this is a non-project flow (see vivado_build.tcl): no
# Vivado project, no ND120_BASYS3_PROJECT, and nothing is copied into the
# checkout any more - the microcode images go to the build folder, which
# vivado_build.tcl makes Vivado's working folder.
#
# Defaults changed for the clock-timing bring-up phase:
#   * FULL SYNTHESIS is the default (pass -ReuseSynth to skip it). No more accidental stale-checkpoint runs.
#   * PROGRAMMING IS OFF by default (pass -Program to flash a board). Avoids the misleading
#     "BUILD FAILED" that Vivado emits from open_hw_target when no board is on JTAG.
#   * All output is logged to <build>\logs\  (see paths printed at start/end).

param(
    # Empty = take ND120_VIVADO (see Verilog/fpga/paths.ps1).
    [string]$VivadoPath = "",
    [switch]$LintOnly,
    # Reuse the last synthesized design (<build>\post_synth.dcp) instead of a fresh ~1h synthesis.
    [switch]$ReuseSynth,
    # Program the FPGA (JTAG) and SPI flash after the build. OFF by default (needs a board on JTAG).
    [switch]$Program,
    # Deprecated no-op: skipping programming is now the default. Kept so old invocations don't error.
    [switch]$SkipProgram
)

$ErrorActionPreference = "Continue"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
# Shared path helpers: reads local.mk at the repository root into the environment.
. (Join-Path $ScriptDir "..\paths.ps1")
$TclScript = Join-Path $ScriptDir "vivado_build.tcl"
$LintScript = Join-Path $ScriptDir "vivado_lint.tcl"

# Check the settings before any work: -VivadoPath, else ND120_VIVADO; the
# build folder. A missing one stops here with the one message naming it.
if (-not $VivadoPath) {
    Assert-ND120Settings -Tools @("ND120_VIVADO") -Names @("ND120_BUILD_DIR") -Target "vivado_build.ps1"
}
$VivadoPath = Resolve-ND120Tool -Given $VivadoPath -Var "ND120_VIVADO" -Target "vivado_build.ps1"
$OutDir     = Get-ND120BuildDir -Board "basys3" -Target "vivado_build.ps1"

# ---------------------------------------------------------------------------
# Logging: everything lands in <build>\logs\.
# ---------------------------------------------------------------------------
$LogDir = Join-Path $OutDir "logs"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

$stamp     = Get-Date -Format "yyyyMMdd_HHmmss"
# Fixed names (easy to find + grep) plus a timestamped archive copy at the end.
$VivadoLog = Join-Path $LogDir "vivado_build.log"     # Vivado's own -log (authoritative: has BUFG/timing/warnings)
$VivadoJou = Join-Path $LogDir "vivado_build.jou"
$PsLog     = Join-Path $LogDir "ps_build.log"         # PowerShell transcript (console echo)

# Vivado overwrites -log; clear the PS transcript too so each run starts clean.
Start-Transcript -Path $PsLog -Force | Out-Null

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " ND-120 Vivado build (Basys3, non-project)" -ForegroundColor Cyan
Write-Host " Build folder: $OutDir" -ForegroundColor Cyan
Write-Host "   Vivado log : $VivadoLog" -ForegroundColor Cyan
Write-Host "   PS console : $PsLog" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Licence: make the Windows *user* XILINXD_LICENSE_FILE reach this process.
#
# A Windows process started through WSL interop inherits the parent's
# environment block, NOT the user's registry environment, so XILINXD_LICENSE_FILE
# arrives UNSET and Vivado falls back to whatever licence it can find on its own.
# That is how a build launched from WSL ran on the BASIC licence and died at
# create_debug_core, while the same Vivado started from Windows had ENTERPRISE.
#
# Read the value from the user environment at runtime - do not hard-code a
# licence path here, it is machine-specific. If the variable is already set in
# this process (a normal Windows shell), leave it alone. ND120_VIVADO_LICENSE
# (local.mk at the repository root) is tried first, then the user, then the machine value.
# ---------------------------------------------------------------------------
if (-not $env:XILINXD_LICENSE_FILE) {
    $userLic = $env:ND120_VIVADO_LICENSE
    if (-not $userLic) {
        $userLic = [Environment]::GetEnvironmentVariable('XILINXD_LICENSE_FILE','User')
    }
    if (-not $userLic) {
        $userLic = [Environment]::GetEnvironmentVariable('XILINXD_LICENSE_FILE','Machine')
    }
    if ($userLic) {
        $env:XILINXD_LICENSE_FILE = $userLic
        Write-Host "Licence: took XILINXD_LICENSE_FILE from ND120_VIVADO_LICENSE or the user/machine environment" -ForegroundColor Gray
        Write-Host "         $userLic" -ForegroundColor Gray
    } else {
        Write-Host "Licence: XILINXD_LICENSE_FILE is not set anywhere - Vivado will pick its own." -ForegroundColor DarkYellow
    }
} else {
    Write-Host "Licence: XILINXD_LICENSE_FILE already set in this process" -ForegroundColor Gray
}

Write-Host "Using Vivado: $VivadoPath" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Assemble tclargs.
#   synth : full_synth (fresh synthesis) UNLESS -ReuseSynth.
#   prog  : skip_program UNLESS -Program.
# ---------------------------------------------------------------------------
if ($SkipProgram) {
    Write-Host "Note: -SkipProgram is now the default and is ignored (use -Program to flash)." -ForegroundColor DarkYellow
}

# Vivado works in the build folder, so its .Xil and anything else it writes
# next to itself land there, never in the checkout.
Push-Location $OutDir
try {
    if ($LintOnly) {
        Write-Host "`n=== Running Linter Only ===" -ForegroundColor Yellow
        & $VivadoPath -mode batch -source $LintScript -log $VivadoLog -journal $VivadoJou
        $exitCode = $LASTEXITCODE
    } else {
        $tclargs = @()
        if ($ReuseSynth) {
            Write-Host "`nSYNTH MODE: REUSE the last synthesized design (NO fresh synthesis)." -ForegroundColor Yellow
            Write-Host "            -> use this ONLY when the RTL has not changed since the last synth." -ForegroundColor DarkYellow
        } else {
            Write-Host "`nSYNTH MODE: FULL SYNTHESIS (~1h). Fresh netlist." -ForegroundColor Green
            $tclargs += "full_synth"
        }
        if ($Program) {
            Write-Host "PROGRAM MODE: will program JTAG + SPI flash after build (board required)." -ForegroundColor Yellow
        } else {
            Write-Host "PROGRAM MODE: SKIP programming (no board needed). Pass -Program to flash." -ForegroundColor Green
            $tclargs += "skip_program"
        }

        Write-Host "`n=== Launching Vivado (tclargs: $tclargs) ===" -ForegroundColor Yellow
        & $VivadoPath -mode batch -source $TclScript -log $VivadoLog -journal $VivadoJou -tclargs $tclargs
        $exitCode = $LASTEXITCODE
    }
} finally {
    Pop-Location
}

# The reports are written straight into the build folder by vivado_build.tcl
# (there is no project folder to pull them out of any more):
#   timing_impl.rpt, utilization_impl.rpt, ram_utilization.rpt,
#   rom_init_check.txt, drc.rpt, methodology.rpt, power.rpt

if ($exitCode -eq 0) {
    Write-Host "`nBUILD SUCCESSFUL" -ForegroundColor Green
    if ($Program -and -not $LintOnly) {
        Write-Host "Bitstream programmed to FPGA and SPI flash (persistent)." -ForegroundColor Green
    }

    # Show ROM init check result
    $RomCheck = Join-Path $OutDir "rom_init_check.txt"
    if (Test-Path $RomCheck) {
        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host " MICROCODE ROM CHECK" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        $content = Get-Content $RomCheck
        $hasData = $content | Select-String "OK: INIT_00 has non-zero data"
        $isEmpty = $content | Select-String "WARNING.*empty"
        if ($hasData) {
            Write-Host "  ROM: POPULATED (WCS microcode preload OK)" -ForegroundColor Green
        } elseif ($isEmpty) {
            Write-Host "  ROM: EMPTY - MICROCODE NOT LOADED!" -ForegroundColor Red
            Write-Host "  Check the wcs_*.hex files in $OutDir" -ForegroundColor Red
        } else {
            Write-Host "  ROM: No microcode BRAMs found (check wcs_*.hex on readmemh path)" -ForegroundColor Yellow
        }
        Write-Host "  Full report: $RomCheck" -ForegroundColor Gray
        Write-Host "========================================" -ForegroundColor Cyan
    }

    Write-Host "`nNext steps:" -ForegroundColor Yellow
    Write-Host "  Timing: $(Join-Path $OutDir 'timing_impl.rpt')  (WNS/TNS + clock + critical paths)" -ForegroundColor Gray
    Write-Host "  .\vivado_build.ps1 -Program   # build + flash when a board is attached" -ForegroundColor Gray
    Write-Host "  .\flash.ps1                   # program JTAG + SPI flash (persistent)" -ForegroundColor Gray
    Write-Host "  Serial: COM16 @ 115200 8N1  |  SW0 UP = run, SW0 DOWN = reset" -ForegroundColor Gray
} else {
    Write-Host "`nBUILD FAILED (exit code: $exitCode)" -ForegroundColor Red
    Write-Host "Check the Vivado log: $VivadoLog"
    if (-not $Program) {
        Write-Host "(Programming was skipped, so this is a real synth/impl error, not a missing board.)" -ForegroundColor DarkYellow
    }
}

# Timestamped archive copies so a rerun does not overwrite the previous evidence.
Copy-Item $VivadoLog (Join-Path $LogDir "vivado_build_$stamp.log") -Force -ErrorAction SilentlyContinue

Write-Host "`nLog files:" -ForegroundColor Cyan
Write-Host "  $VivadoLog" -ForegroundColor Cyan
Write-Host "  $PsLog" -ForegroundColor Cyan
Write-Host "  (archive) $(Join-Path $LogDir "vivado_build_$stamp.log")" -ForegroundColor Cyan

Stop-Transcript | Out-Null
exit $exitCode
