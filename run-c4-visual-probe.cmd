@echo off
setlocal
if not exist "%~dp0reports" mkdir "%~dp0reports"
if exist "%~dp0reports\step16-c4-visual-probe.log" del "%~dp0reports\step16-c4-visual-probe.log"
echo [Vector Breach] Running Step 16 C4 Gatehouse visual probe on configured dGPU...
call "%~dp0play-dgpu.cmd" --scene res://scenes/tests/C4DeviceVisualProbe.tscn --log-file "%~dp0reports\step16-c4-visual-probe.log"
set "VB_EXIT=%ERRORLEVEL%"
echo [Vector Breach] Probe exit code: %VB_EXIT%
echo [Vector Breach] Evidence directory: %~dp0reports
exit /b %VB_EXIT%
