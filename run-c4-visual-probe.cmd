@echo off
setlocal
set "VB_REPORTS=%~dp0reports"
if not exist "%VB_REPORTS%" mkdir "%VB_REPORTS%"
for %%F in (
  step16-c4-visual-probe.log
  step16-c4-evidence.json
  step16-c4-dropped.png
  step16-c4-planted.png
  step16-c4-urgent.png
) do if exist "%VB_REPORTS%\%%F" del "%VB_REPORTS%\%%F"

echo [Vector Breach] Running Step 16 C4 Gatehouse visual/performance probe on configured dGPU...
call "%~dp0play-dgpu.cmd" --scene res://scenes/tests/C4DeviceVisualProbe.tscn --log-file "%VB_REPORTS%\step16-c4-visual-probe.log"
set "VB_EXIT=%ERRORLEVEL%"

if not "%VB_EXIT%"=="0" goto :done
for %%F in (
  step16-c4-evidence.json
  step16-c4-dropped.png
  step16-c4-planted.png
  step16-c4-urgent.png
) do (
  if not exist "%VB_REPORTS%\%%F" (
    echo [Vector Breach] ERROR: expected fresh evidence missing: %%F
    set "VB_EXIT=1"
  )
)

:done
echo [Vector Breach] Probe exit code: %VB_EXIT%
echo [Vector Breach] Evidence JSON: %VB_REPORTS%\step16-c4-evidence.json
echo [Vector Breach] Screenshots: %VB_REPORTS%\step16-c4-dropped.png, step16-c4-planted.png, step16-c4-urgent.png
echo [Vector Breach] Probe log: %VB_REPORTS%\step16-c4-visual-probe.log
exit /b %VB_EXIT%
