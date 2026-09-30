# ND120 Tang Nano 20K - attach the board's FTDI to WSL (Windows PowerShell)
#
#   cd Verilog\fpga\tang-nano-20k        (inside your checkout)
#   .\tang_usb.ps1
#
# WHY THIS EXISTS
#   The Tang's FTDI (0403:6010) is a Windows USB device. WSL cannot see it -
#   and therefore openFPGALoader and /dev/ttyUSB* do not exist there - until
#   usbipd hands it over. usb-attach.sh does this from the WSL side by calling
#   powershell.exe, but that interop path is not always available; this script
#   is the same dance driven from Windows, where usbipd actually lives.
#
#   Run after EVERY board power cycle or replug: usbipd drops the attachment
#   when the device loses power.
#
# WHAT IT DOES
#   1. finds the Tang FTDI busid in `usbipd list`
#   2. `usbipd bind` it if it is not already Shared   (needs Administrator -
#      the script re-launches itself elevated for this, once per machine)
#   3. `usbipd attach --wsl`
#   4. loads ftdi_sio inside WSL and opens /dev/ttyUSB* permissions
#
# RESULT
#   /dev/ttyUSB0 = JTAG (FTDI interface A, used by openFPGALoader)
#   /dev/ttyUSB1 = OPCOM console (FTDI interface B) at 9600 8N1

param(
    [switch]$Detach
)

$ErrorActionPreference = "Stop"
$VIDPID = "0403:6010"

function Get-TangBusId {
    $lines = (usbipd list) -split "`r?`n"
    foreach ($line in $lines) {
        # "BUSID  VID:PID  DEVICE  STATE"
        if ($line -match '^\s*(\S+)\s+' + [regex]::Escape($VIDPID) + '\s') {
            return @{ BusId = $matches[1]; Line = $line }
        }
    }
    return $null
}

if (-not (Get-Command usbipd -ErrorAction SilentlyContinue)) {
    Write-Error @"
usbipd is not installed (or not on PATH).

Install it once, from an elevated prompt:
    winget install usbipd
then re-run this script.
"@
}

$tang = Get-TangBusId
if ($null -eq $tang) {
    Write-Host "usbipd list:" -ForegroundColor Yellow
    usbipd list
    Write-Error "No $VIDPID device found. Is the Tang Nano 20K plugged in?"
}

$busid = $tang.BusId
Write-Host "Tang FTDI $VIDPID at busid $busid"
Write-Host "  $($tang.Line)"

if ($Detach) {
    usbipd detach --busid $busid
    Write-Host "Detached - the board is back on the Windows side." -ForegroundColor Green
    return
}

# --- bind (one-time per machine, needs Administrator) ------------------------
if ($tang.Line -notmatch 'Shared|Attached') {
    $isAdmin = ([Security.Principal.WindowsPrincipal] `
                [Security.Principal.WindowsIdentity]::GetCurrent()
               ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        Write-Host "Device is not Shared yet - 'usbipd bind' needs Administrator." -ForegroundColor Yellow
        Write-Host "Re-launching this script elevated..."
        $self = $MyInvocation.MyCommand.Path
        Start-Process powershell.exe -Verb RunAs -Wait -ArgumentList @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$self`""
        )
        Write-Host "Elevated pass finished - re-checking." -ForegroundColor Cyan
        $tang = Get-TangBusId
        if ($tang.Line -notmatch 'Shared|Attached') {
            Write-Error "Still not Shared. Run manually, elevated: usbipd bind --busid $busid"
        }
    } else {
        usbipd bind --busid $busid
        Write-Host "Bound (Shared)."
    }
}

# --- attach to WSL (idempotent) ---------------------------------------------
$tang = Get-TangBusId
if ($tang.Line -match 'Attached') {
    Write-Host "Already attached to WSL."
} else {
    usbipd attach --wsl --busid $busid
    Write-Host "Attached to WSL."
}

# --- serial driver + permissions inside WSL ---------------------------------
# sudo may prompt for your WSL password.
Write-Host "Setting up ftdi_sio + /dev/ttyUSB* permissions inside WSL..."
$sh = @'
for i in $(seq 1 20); do lsusb -d 0403:6010 >/dev/null 2>&1 && break; sleep 0.5; done
if ! lsusb -d 0403:6010 >/dev/null 2>&1; then
    echo "ERROR: device did not appear in WSL (lsusb)"; exit 1
fi
DEVPATH=$(lsusb -d 0403:6010 | sed -n 's|^Bus \([0-9]*\) Device \([0-9]*\).*|/dev/bus/usb/\1/\2|p' | head -1)
sudo chmod 666 "$DEVPATH" && echo "raw USB node: $DEVPATH (rw)"
sudo modprobe ftdi_sio
for i in $(seq 1 20); do ls /dev/ttyUSB* >/dev/null 2>&1 && break; sleep 0.5; done
if ls /dev/ttyUSB* >/dev/null 2>&1; then
    sudo chmod 666 /dev/ttyUSB*
    echo "serial ready: $(ls /dev/ttyUSB* | tr '\n' ' ')"
else
    echo "ERROR: no /dev/ttyUSB* appeared (ftdi_sio)"; exit 1
fi
'@
wsl.exe -e bash -lc $sh
if ($LASTEXITCODE -ne 0) { Write-Error "WSL-side setup failed (exit $LASTEXITCODE)" }

Write-Host ""
Write-Host "Board is attached to WSL." -ForegroundColor Green
Write-Host "  /dev/ttyUSB0 = JTAG      (openFPGALoader)"
Write-Host "  /dev/ttyUSB1 = console   9600 8N1"
