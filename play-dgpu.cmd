@echo off
setlocal
set "VB_GODOT=D:\Godot\4.7.1\Godot_v4.7.1-stable_win64.exe"
if not exist "%VB_GODOT%" (
  echo [Vector Breach] Godot executable not found: %VB_GODOT%
  pause
  exit /b 1
)
echo [Vector Breach] Starting Forward+ on GPU index 0 ^(RTX 5060 on this workstation^)...
"%VB_GODOT%" --path "%~dp0." --gpu-index 0 %*
endlocal
