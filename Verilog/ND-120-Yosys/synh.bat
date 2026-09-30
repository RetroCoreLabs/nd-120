REM Yosys synthesis of ND120_TOP from nd-120.ys.
REM nd-120.ys names its sources relative to this folder, so run from here.
REM ND120_OSS_CAD = the oss-cad-suite folder (see Verilog/fpga/local.mk.example;
REM this .bat reads it from the environment only). Unset = yosys on PATH.
cd /d "%~dp0"
if defined ND120_OSS_CAD call "%ND120_OSS_CAD%\environment.bat"

yosys -s nd-120.ys --trace -d

REM  -v 3
