# ND-120 Vivado Build Script (PowerShell)
#
# Usage (from Verilog\fpga\basys3):
#   .\vivado_build.ps1                 # FRESH full synthesis (~1h) + implementation, NO programming (safe, no board needed)
#   .\vivado_build.ps1 -Program        # ...same, then program JTAG + SPI flash (board must be attached)
#   .\vivado_build.ps1 -ReuseSynth     # skip the ~1h resynth, reuse existing synth_1 checkpoint (impl only)
#   .\vivado_build.ps1 -LintOnly       # run the linter only
#
# Prerequisites: Vivado installed, and Verilog/fpga/local.mk made from
# local.mk.example. Paths come from there (or from the environment):
#   ND120_BASYS3_PROJECT  folder holding the Vivado project ND3202D.xpr (required)
#   ND120_VIVADO          vivado.bat; -VivadoPath overrides it, and when
#                         neither is given vivado.bat on PATH is used
#   ND120_VIVADO_LICENSE  licence file list; used when XILINXD_LICENSE_FILE
#                         is not already set in this process
#
# Defaults changed for the clock-timing bring-up phase:
#   * FULL SYNTHESIS is the default (pass -ReuseSynth to skip it). No more accidental stale-checkpoint runs.
#   * PROGRAMMING IS OFF by default (pass -Program to flash a board). Avoids the misleading
#     "BUILD FAILED" that Vivado emits from open_hw_target when no board is on JTAG.
#   * All output is logged to .\logs\  (see paths printed at start/end).

param(
    # Empty = take ND120_VIVADO, else vivado.bat on PATH (see Verilog/fpga/paths.ps1).
    [string]$VivadoPath = "",
    [switch]$LintOnly,
    # Reuse the existing synth_1 checkpoint instead of a fresh ~1h synthesis.
    [switch]$ReuseSynth,
    # Program the FPGA (JTAG) and SPI flash after the build. OFF by default (needs a board on JTAG).
    [switch]$Program,
    # Deprecated no-op: skipping programming is now the default. Kept so old invocations don't error.
    [switch]$SkipProgram
)

$ErrorActionPreference = "Continue"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
# Shared path helpers: reads Verilog/fpga/local.mk into the environment.
. (Join-Path $ScriptDir "..\paths.ps1")
$RepoRoot  = (Resolve-Path (Join-Path $ScriptDir "..\..\..")).Path   # the checkout this script sits in
$TclScript = Join-Path $ScriptDir "vivado_build.tcl"
$LintScript = Join-Path $ScriptDir "vivado_lint.tcl"

# ---------------------------------------------------------------------------
# Logging: everything lands in .\logs\ (inside the checkout = readable from WSL).
# ---------------------------------------------------------------------------
$LogDir = Join-Path $ScriptDir "logs"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

$stamp     = Get-Date -Format "yyyyMMdd_HHmmss"
# Fixed names (easy to find + grep) plus a timestamped archive copy at the end.
$VivadoLog = Join-Path $LogDir "vivado_build.log"     # Vivado's own -log (authoritative: has BUFG/timing/warnings)
$VivadoJou = Join-Path $LogDir "vivado_build.jou"
$PsLog     = Join-Path $LogDir "ps_build.log"         # PowerShell transcript (console echo)

# Vivado overwrites -log; clear the PS transcript too so each run starts clean.
Start-Transcript -Path $PsLog -Force | Out-Null

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " ND-120 Vivado build" -ForegroundColor Cyan
Write-Host " Logs (readable from WSL under Verilog/fpga/basys3/logs/):" -ForegroundColor Cyan
Write-Host "   Vivado log : $VivadoLog" -ForegroundColor Cyan
Write-Host "   PS console : $PsLog" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# Check Vivado exists: -VivadoPath, else ND120_VIVADO, else vivado.bat on PATH.
$VivadoPath = Resolve-ND120Tool -Given $VivadoPath -Var "ND120_VIVADO" -Names @("vivado.bat", "vivado")
if (-not $VivadoPath) {
    Write-Error "Vivado not found. Set ND120_VIVADO in Verilog/fpga/local.mk, pass -VivadoPath, or put vivado.bat on PATH."
    Stop-Transcript | Out-Null
    exit 1
}

# Copy microcode hex files to Vivado project directory
# (Verilog uses $readmemh with relative paths; Vivado runs from the project dir)
$VivadoProjectDir = Get-ND120Required -Var "ND120_BASYS3_PROJECT" -What "the folder holding the Basys3 Vivado project ND3202D.xpr"
if (-not $VivadoProjectDir) {
    Stop-Transcript | Out-Null
    exit 1
}
$OutDir           = Join-Path $VivadoProjectDir "output"
$MicrocodeDir     = Join-Path $RepoRoot "Code\Microcode"
$HexFiles = @("AM27256_45132L.hex", "AM27256_45133L.hex")

foreach ($hex in $HexFiles) {
    $src = Join-Path $MicrocodeDir $hex
    $dst = Join-Path $VivadoProjectDir $hex
    if (-not (Test-Path $src)) {
        Write-Error "Microcode file not found: $src"
        Stop-Transcript | Out-Null
        exit 1
    }
    Copy-Item $src $dst -Force
    Write-Host "Copied microcode: $hex" -ForegroundColor Gray
}

# Copy the 32 WCS nibble preload images (SKIP_WCS_LOAD). The build now defines
# SKIP_WCS_LOAD, so the WCS IDT6168A chips are bitstream-preloaded from these
# wcs_<16..31><C|D>.hex files via $readmemh, and the microcode PROM is compiled out.
# Generated by Code/Microcode/gen_wcs_image.py.
#
# CRITICAL: Vivado resolves a $readmemh RELATIVE path against the directory of the
# RTL source file that contains the call -- NOT the project dir. The call is in
# Shared/support/IDT6168A_20.v, so the images MUST sit next to it there. (This is
# the same mechanism by which AM27256_*.hex is found next to CPU_CS_PROM_19.v.)
$WcsDir     = Join-Path $MicrocodeDir "wcs"
$WcsDestDir = Join-Path $RepoRoot "Verilog\Shared\support"   # dir of IDT6168A_20.v
$WcsFiles   = Get-ChildItem -Path $WcsDir -Filter "wcs_*.hex" -ErrorAction SilentlyContinue
if ($null -eq $WcsFiles -or $WcsFiles.Count -lt 32) {
    Write-Error "WCS preload images missing/incomplete in ${WcsDir} (found $($WcsFiles.Count), need 32). Re-run gen_wcs_image.py."
    Stop-Transcript | Out-Null
    exit 1
}
foreach ($f in $WcsFiles) {
    Copy-Item $f.FullName (Join-Path $WcsDestDir $f.Name) -Force
}
Write-Host "Copied $($WcsFiles.Count) WCS preload images -> $WcsDestDir (SKIP_WCS_LOAD)" -ForegroundColor Gray

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
# (Verilog/fpga/local.mk) is tried first, then the user, then the machine value.
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
#   synth : full_synth (fresh reset_run + launch) UNLESS -ReuseSynth.
#   prog  : skip_program UNLESS -Program.
# ---------------------------------------------------------------------------
if ($SkipProgram) {
    Write-Host "Note: -SkipProgram is now the default and is ignored (use -Program to flash)." -ForegroundColor DarkYellow
}

if ($LintOnly) {
    Write-Host "`n=== Running Linter Only ===" -ForegroundColor Yellow
    & $VivadoPath -mode batch -source $LintScript -log $VivadoLog -journal $VivadoJou
    $exitCode = $LASTEXITCODE
} else {
    $tclargs = @()
    if ($ReuseSynth) {
        Write-Host "`nSYNTH MODE: REUSE existing synth_1 checkpoint (NO fresh synthesis)." -ForegroundColor Yellow
        Write-Host "            -> use this ONLY when the RTL has not changed since the last synth." -ForegroundColor DarkYellow
    } else {
        Write-Host "`nSYNTH MODE: FULL SYNTHESIS (reset_run synth_1 + launch, ~1h). Fresh netlist." -ForegroundColor Green
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

# ---------------------------------------------------------------------------
# Pull the key reports out of the Vivado project folder (ND120_BASYS3_PROJECT)
# into .\logs\ so they can be read from WSL (that drive may not be mounted there).
# ---------------------------------------------------------------------------
$reportsToGrab = @(
    "timing_impl.rpt",        # report_timing_summary (WNS/TNS + clock summary + critical paths)
    "utilization_impl.rpt",
    "ram_utilization.rpt",
    "rom_init_check.txt",
    "drc.rpt"
)
foreach ($r in $reportsToGrab) {
    $rp = Join-Path $OutDir $r
    if (Test-Path $rp) { Copy-Item $rp (Join-Path $LogDir $r) -Force }
}

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
            Write-Host "  Check wcs_*.hex files in $VivadoProjectDir" -ForegroundColor Red
        } else {
            Write-Host "  ROM: No microcode BRAMs found (check wcs_*.hex on readmemh path)" -ForegroundColor Yellow
        }
        Write-Host "  Full report: $RomCheck" -ForegroundColor Gray
        Write-Host "========================================" -ForegroundColor Cyan
    }

    Write-Host "`nNext steps:" -ForegroundColor Yellow
    Write-Host "  Timing: logs\timing_impl.rpt  (WNS/TNS + clock + critical paths)" -ForegroundColor Gray
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

# Timestamped archive copies so a rerun does not clobber the previous evidence.
Copy-Item $VivadoLog (Join-Path $LogDir "vivado_build_$stamp.log") -Force -ErrorAction SilentlyContinue

Write-Host "`nLog files:" -ForegroundColor Cyan
Write-Host "  $VivadoLog" -ForegroundColor Cyan
Write-Host "  $PsLog" -ForegroundColor Cyan
Write-Host "  (archive) $(Join-Path $LogDir "vivado_build_$stamp.log")" -ForegroundColor Cyan

Stop-Transcript | Out-Null
exit $exitCode
