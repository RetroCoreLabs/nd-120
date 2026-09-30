REM Yosys synthesis of ND120_TOP from nd-120.ys.
REM nd-120.ys names its sources relative to this folder, so run from here.
REM ND120_OSS_CAD_SUITE = the oss-cad-suite folder (see local.mk.example at the
REM repository root; this .bat reads it from the environment only - set it
REM there, or run it from make/PowerShell, which pass local.mk on).
REM Unset = yosys on PATH.
cd /d "%~dp0"
if defined ND120_OSS_CAD_SUITE call "%ND120_OSS_CAD_SUITE%\environment.bat"

yosys -s nd-120.ys --trace -d

REM  -v 3
