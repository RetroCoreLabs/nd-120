<#
.SYNOPSIS
    Run the Nexys 4 DDR build with a LIVE, WATCHABLE console - and shout when
    it stalls instead of sitting there silently.

.DESCRIPTION
    The plain batch launch has two problems, both hit on 20-AUG-2026:

      1. Output went to a redirected file, so nothing appeared for over an
         hour and there was no way to tell work from a hang.
      2. When synth_design got stuck walking the CGA's combinational loops,
         it burned a whole CPU core for two hours and never said a word.
         A second run from five hours earlier was ALSO still sitting there,
         unnoticed, stealing a core from everything since.

    So this script does three things the raw launch does not:

      - prints every Vivado line as it arrives, stamped with wall-clock time
        and elapsed time, so progress is visible;
      - watches for silence, and after -StallMinutes says so LOUDLY, with the
        process CPU time, so "still computing" and "stopped computing"
        cannot be confused;
      - refuses to start if another vivado.exe is already running, unless you
        pass -AllowConcurrent. That is what would have caught the orphan.

    It never kills anything on its own. -KillAfterMinutes is opt-in and off by
    default; a stall is reported, not acted on.

.PARAMETER Clk
    CPU clock selection passed to build.tcl. Valid: 8 10 12 16 20 25 27 33 50 100.
    12 means 12.5 MHz. Default 12.

.PARAMETER Program
    Program the board over JTAG when the build succeeds. Without it, build.tcl
    is called with -noburn and stops after write_bitstream.

.PARAMETER StallMinutes
    Silence after which the run is called out as stalled. Default 10.
    Synthesis stages on this design normally print every few seconds; the
    known-good builds finished synth_design in about five minutes total.

.PARAMETER KillAfterMinutes
    OPT-IN. Kill the run after this many minutes of TOTAL silence. 0 = never,
    which is the default. Nothing is killed unless you ask for it.

.PARAMETER WatchOnly
    Do not start anything. Attach to the log of a build already running and
    follow it, with the same stall detection.

.PARAMETER VivadoPath
    Full path to vivado.bat. If omitted, the script looks at $env:ND120_VIVADO
    (also read from local.mk at the repository root), then $env:VIVADO_BAT,
    then $env:XILINX_VIVADO\bin\vivado.bat, then vivado.bat on PATH. No install
    path is hard-coded here - this file lives in the repo and a machine-
    specific path must not.

.EXAMPLE
    .\build-watch.ps1
    Build at 12.5 MHz, do not program, watch it live.

.EXAMPLE
    .\build-watch.ps1 -Clk 16 -Program
    Build at 16.667 MHz and program the board when it passes.

.EXAMPLE
    .\build-watch.ps1 -WatchOnly
    Follow a build someone else already started.

.NOTES
    Run from this directory:
        cd Verilog\fpga\nexys4ddr
        .\build-watch.ps1

    From WSL:
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File build-watch.ps1
#>

[CmdletBinding()]
param(
    [ValidateSet(8, 10, 12, 16, 20, 25, 27, 33, 50, 100)]
    [int]$Clk = 12,

    [switch]$Program,
    [int]$StallMinutes = 10,
    [int]$KillAfterMinutes = 0,
    [switch]$WatchOnly,
    [switch]$AllowConcurrent,
    [string]$VivadoPath = ""
)

$ErrorActionPreference = "Stop"
$ScriptDir = $PSScriptRoot
# Shared path helpers: copies ND120_* settings from local.mk (repository root) into
# this process's environment when the environment does not hold them already.
. (Join-Path $ScriptDir "..\paths.ps1")
$TclScript = Join-Path $ScriptDir "build.tcl"
$LogFile   = Join-Path $ScriptDir "build-watch.log"

# ---------------------------------------------------------------------------
# Console helpers - colour is a reinforcement, the tag is the real signal, so
# this stays readable when piped to a file or read by someone who cannot
# distinguish the colours (see Verilog/docs/COLOR-STANDARDS.md).
# ---------------------------------------------------------------------------
function Write-Tag {
    param([string]$Tag, [string]$Text, [string]$Colour = "Gray")
    Write-Host ("[{0}] " -f $Tag) -ForegroundColor $Colour -NoNewline
    Write-Host $Text
}
function Say  { param([string]$m) Write-Tag "INFO" $m "Cyan" }
function Warn { param([string]$m) Write-Tag "WARN" $m "Yellow" }
function Fail { param([string]$m) Write-Tag "FAIL" $m "Red" }
function Good { param([string]$m) Write-Tag " OK " $m "Green" }

# ---------------------------------------------------------------------------
# vivado.bat is a BATCH SHIM: it spawns the real vivado.exe as a child and then
# does nothing. Reporting the shim's CPU is worse than reporting nothing, because
# it says "CPU 1s, WS 10 MB" while the real process is saturating a core - which
# is exactly backwards from the question being asked. Walk the tree and track the
# real one. 20-AUG-2026: this was reported wrong for a full 40-minute stall.
# ---------------------------------------------------------------------------
function Get-RealVivado {
    param([int]$RootPid)
    $all = @(Get-CimInstance Win32_Process -Filter "name='vivado.exe'")
    if ($all.Count -eq 0) { return $null }

    # prefer a descendant of the shim we started
    $tree = @{}
    Get-CimInstance Win32_Process | ForEach-Object { $tree[[int]$_.ProcessId] = [int]$_.ParentProcessId }
    foreach ($v in $all) {
        $cur = [int]$v.ProcessId
        for ($hop = 0; $hop -lt 8 -and $tree.ContainsKey($cur); $hop++) {
            $cur = $tree[$cur]
            if ($cur -eq $RootPid) {
                return (Get-Process -Id $v.ProcessId -ErrorAction SilentlyContinue)
            }
        }
    }
    # fall back to the newest vivado.exe - better than reporting the shim
    $newest = $all | Sort-Object CreationDate -Descending | Select-Object -First 1
    return (Get-Process -Id $newest.ProcessId -ErrorAction SilentlyContinue)
}

function Format-Elapsed {
    param([TimeSpan]$ts)
    "{0:00}:{1:00}:{2:00}" -f [int]$ts.TotalHours, $ts.Minutes, $ts.Seconds
}

# ---------------------------------------------------------------------------
# Locate Vivado without hard-coding an install path into a committed file.
# ---------------------------------------------------------------------------
function Resolve-Vivado {
    param([string]$Explicit)

    if ($Explicit) {
        if (Test-Path $Explicit) { return $Explicit }
        throw "-VivadoPath '$Explicit' does not exist."
    }
    if ($env:ND120_VIVADO) {
        $v = ConvertTo-ND120HostPath $env:ND120_VIVADO
        if (Test-Path $v) { return $v }
        throw "ND120_VIVADO points at $($env:ND120_VIVADO), which does not exist - run configure.py again."
    }
    if ($env:VIVADO_BAT -and (Test-Path $env:VIVADO_BAT)) { return $env:VIVADO_BAT }
    if ($env:XILINX_VIVADO) {
        $c = Join-Path $env:XILINX_VIVADO "bin\vivado.bat"
        if (Test-Path $c) { return $c }
    }
    $onPath = Get-Command vivado.bat -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }

    throw @"
Cannot find vivado.bat.

Run python3 configure.py (Windows: py configure.py) from the repository
root - it finds Vivado and writes ND120_VIVADO to local.mk - or
set it once for this shell:
    `$env:VIVADO_BAT = '<your Vivado install>\bin\vivado.bat'
or permanently:
    [Environment]::SetEnvironmentVariable('VIVADO_BAT','<path>','User')
or pass -VivadoPath '<path>'.

The path is deliberately NOT stored in this script: it is committed to the
repo and a machine-specific path only works on one machine.
"@
}

# ---------------------------------------------------------------------------
# Refuse to pile a second build on top of a forgotten one.
# ---------------------------------------------------------------------------
function Assert-NoStrayVivado {
    $running = @(Get-Process vivado -ErrorAction SilentlyContinue)
    if ($running.Count -eq 0) { return }

    Warn "$($running.Count) vivado.exe already running:"
    foreach ($p in $running) {
        $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId=$($p.Id)").CommandLine
        $age = Format-Elapsed (New-TimeSpan -Start $p.StartTime -End (Get-Date))
        Write-Host ("       PID {0}  started {1}  age {2}  CPU {3:N0}s" -f `
                    $p.Id, $p.StartTime.ToString("HH:mm:ss"), $age, $p.CPU)
        if ($cmd) { Write-Host ("             {0}" -f $cmd.Trim()) -ForegroundColor DarkGray }
    }
    if ($AllowConcurrent) {
        Warn "-AllowConcurrent given: starting anyway. They will compete for cores."
        return
    }
    throw @"
Refusing to start while another Vivado is running - that is how a stuck run
goes unnoticed for hours and quietly halves the CPU available to the new one.

Either wait for it, or stop the one you recognise:
    Stop-Process -Id <PID> -Force
Then run this again. Pass -AllowConcurrent to override.
"@
}

# ---------------------------------------------------------------------------
# Follow a log file live, with stall detection.
# Returns $true if the watched process ended, $false if we killed it.
# ---------------------------------------------------------------------------
function Watch-Log {
    param(
        [string]$Path,
        [System.Diagnostics.Process]$Proc,   # $null in -WatchOnly mode
        [DateTime]$Started
    )

    $pos          = 0
    $lastOutput   = Get-Date
    $lastStallSay = [DateTime]::MinValue
    $lastLine     = ""
    $script:lastCpu = 0
    $killed       = $false

    while ($true) {
        Start-Sleep -Milliseconds 500

        if (Test-Path $Path) {
            $fs = $null
            try {
                # FileShare ReadWrite+Delete: Vivado is writing this right now.
                $fs = [System.IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite,Delete')
                if ($fs.Length -lt $pos) { $pos = 0 }   # log was rotated
                if ($fs.Length -gt $pos) {
                    [void]$fs.Seek($pos, 'Begin')
                    $sr = New-Object System.IO.StreamReader($fs)
                    while (($line = $sr.ReadLine()) -ne $null) {
                        $stamp = (Get-Date).ToString("HH:mm:ss")
                        $el    = Format-Elapsed (New-TimeSpan -Start $Started -End (Get-Date))
                        $colour = "Gray"
                        if ($line -match '^ERROR|^CRITICAL WARNING|ERROR: timing')  { $colour = "Red" }
                        elseif ($line -match '^WARNING')                            { $colour = "Yellow" }
                        elseif ($line -match '^(WNS:|BITSTREAM:|PROGRAMMED)')       { $colour = "Green" }
                        elseif ($line -match 'Start |Finished |Phase \d|completed') { $colour = "Cyan" }
                        Write-Host ("{0} +{1} | " -f $stamp, $el) -ForegroundColor DarkGray -NoNewline
                        Write-Host $line -ForegroundColor $colour
                        if ($line.Trim()) { $lastLine = $line.Trim() }
                        $lastOutput = Get-Date
                    }
                    $pos = $fs.Position
                    $sr.Dispose()
                }
            } catch {
                # transient sharing violation - try again next tick
            } finally {
                if ($fs) { $fs.Dispose() }
            }
        }

        $silent = (New-TimeSpan -Start $lastOutput -End (Get-Date)).TotalMinutes

        if ($silent -ge $StallMinutes -and
            (New-TimeSpan -Start $lastStallSay -End (Get-Date)).TotalMinutes -ge $StallMinutes) {
            $lastStallSay = Get-Date
            $cpuNote = ""
            $real = $null
            if ($Proc) { $real = Get-RealVivado -RootPid $Proc.Id }
            elseif ($true) { $real = Get-RealVivado -RootPid 0 }
            if ($real) {
                $real.Refresh()
                $nowCpu = $real.CPU
                $delta  = $nowCpu - $script:lastCpu
                $script:lastCpu = $nowCpu
                $verdict = if ($delta -gt 1) { "USING CPU - computing, or going round a loop" }
                           else              { "IDLE - not computing at all" }
                $cpuNote = " - vivado.exe PID {0}: CPU {1:N0}s (+{2:N0}s since last check), WS {3:N0} MB -> {4}" -f `
                           $real.Id, $nowCpu, $delta, ($real.WorkingSet64 / 1MB), $verdict
            } else {
                $cpuNote = " - NO vivado.exe found (it has exited)"
            }
            Warn ("NO OUTPUT for {0:N1} min{1}" -f $silent, $cpuNote)
            Write-Host ("       last line: {0}" -f $lastLine) -ForegroundColor DarkGray
            Write-Host ("       If CPU keeps climbing it is computing, not deadlocked - but on this") -ForegroundColor DarkGray
            Write-Host ("       design synth_design normally finishes in about 5 minutes total.")     -ForegroundColor DarkGray
        }

        if ($KillAfterMinutes -gt 0 -and $silent -ge $KillAfterMinutes -and $Proc -and -not $Proc.HasExited) {
            $realKill = Get-RealVivado -RootPid $Proc.Id
            if ($realKill) {
                Fail ("-KillAfterMinutes {0} reached with no output. Stopping vivado.exe PID {1}." -f $KillAfterMinutes, $realKill.Id)
                Stop-Process -Id $realKill.Id -Force
            }
            Fail ("Stopping launcher PID {0}." -f $Proc.Id)
            Stop-Process -Id $Proc.Id -Force
            $killed = $true
            break
        }

        if ($Proc) {
            if ($Proc.HasExited) { Start-Sleep -Seconds 1; break }   # one last drain
        } else {
            if (-not (Get-Process vivado -ErrorAction SilentlyContinue)) { break }
        }
    }
    return (-not $killed)
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
$started = Get-Date

if ($WatchOnly) {
    $existing = Join-Path $ScriptDir "vivado.log"
    if (-not (Test-Path $existing)) { throw "No vivado.log in $ScriptDir to watch." }
    Say "Watch-only: following $existing (Ctrl-C to stop watching; the build is not affected)."
    [void](Watch-Log -Path $existing -Proc $null -Started $started)
    Say "Watched process is gone."
    return
}

if (-not (Test-Path $TclScript)) { throw "build.tcl not found next to this script ($ScriptDir)." }

$vivado = Resolve-Vivado -Explicit $VivadoPath
Assert-NoStrayVivado

$tclArgs = @()
if (-not $Program) { $tclArgs += "-noburn" }
$tclArgs += @("clk", "$Clk")

Say ("Vivado    : {0}" -f $vivado)
Say ("Script    : {0}" -f $TclScript)
Say ("Arguments : {0}" -f ($tclArgs -join " "))
Say ("Program   : {0}" -f $(if ($Program) { "YES - JTAG after a passing build" } else { "no (-noburn)" }))
Say ("Stall call: after {0} min of silence{1}" -f $StallMinutes,
     $(if ($KillAfterMinutes -gt 0) { "; auto-kill after $KillAfterMinutes min" } else { "; NO auto-kill" }))
Say ("Log       : {0}" -f $LogFile)
Write-Host ("-" * 78) -ForegroundColor DarkGray

# Vivado's own -log is the one that flushes as it goes; follow that, and keep
# stdout separately so nothing is lost if Vivado dies before writing its log.
$vivadoLog = Join-Path $ScriptDir "vivado.log"
$stdoutLog = Join-Path $ScriptDir "build-watch.stdout.log"
Remove-Item $vivadoLog, $stdoutLog -ErrorAction SilentlyContinue

$allArgs = @("-mode", "batch", "-source", $TclScript, "-log", $vivadoLog,
             "-nojournal", "-tclargs") + $tclArgs

$proc = Start-Process -FilePath $vivado -ArgumentList $allArgs `
                      -WorkingDirectory $ScriptDir -NoNewWindow -PassThru `
                      -RedirectStandardOutput $stdoutLog `
                      -RedirectStandardError  ($stdoutLog + ".err")

Say ("Started PID {0} at {1}" -f $proc.Id, $started.ToString("HH:mm:ss"))

$finishedOnItsOwn = Watch-Log -Path $vivadoLog -Proc $proc -Started $started

$proc.WaitForExit()
$elapsed = Format-Elapsed (New-TimeSpan -Start $started -End (Get-Date))

Write-Host ("-" * 78) -ForegroundColor DarkGray

# ---- verdict, stated plainly ----------------------------------------------
$logText = ""
if (Test-Path $vivadoLog) { $logText = Get-Content $vivadoLog -Raw }

$wns  = ([regex]::Matches($logText, '(?m)^WNS:\s*(\S+)')      | Select-Object -Last 1)
$bit  = ([regex]::Matches($logText, '(?m)^BITSTREAM:\s*(.+)$')| Select-Object -Last 1)
$prog = $logText -match 'PROGRAMMED'
$loops = ([regex]::Matches($logText, '8-295')).Count

Say ("Elapsed   : {0}" -f $elapsed)
Say ("Exit code : {0}" -f $proc.ExitCode)
if ($loops -gt 0) { Warn ("Combinational loop warnings [Synth 8-295]: {0}" -f $loops) }
if ($wns)  { Say  ("WNS       : {0} ns" -f $wns.Groups[1].Value) }

if (-not $finishedOnItsOwn) {
    Fail "Killed by -KillAfterMinutes. No bitstream."
} elseif ($bit) {
    Good ("BITSTREAM : {0}" -f $bit.Groups[1].Value.Trim())
    if ($Program) {
        if ($prog) { Good "Board PROGRAMMED over JTAG." }
        else       { Fail "Bitstream written but programming did not report success - check the log." }
    }
} else {
    Fail "NO BITSTREAM produced."
    $errs = [regex]::Matches($logText, '(?m)^(ERROR.*|.*ERROR: timing.*)$')
    if ($errs.Count -gt 0) {
        Write-Host "       First errors:" -ForegroundColor DarkGray
        $errs | Select-Object -First 5 | ForEach-Object {
            Write-Host ("       {0}" -f $_.Value.Trim()) -ForegroundColor Red
        }
    }
}
Say ("Full log  : {0}" -f $vivadoLog)
