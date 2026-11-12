@echo off
title Engine Builder - pad resolution census (works over Bluetooth)
setlocal
cd /d "%~dp0..\.."
set "GODOT=D:\Program Files (x86)\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
set "OUT=%~dp0..\..\tools\diagnostics\pad_census.txt"

rem a goto, not an if-block: the ")" in "Program Files (x86)" would close a parenthesised block early
if not exist "%GODOT%" goto nogodot
if exist "%OUT%" del /q "%OUT%"

echo ============================================================
echo  Pad resolution census
echo ============================================================
echo  A window opens for 15 seconds. During that time:
echo.
echo    - squeeze RIGHT TRIGGER slowly all the way in and back
echo    - squeeze LEFT TRIGGER  slowly all the way in and back
echo    - tap A, RB, LB, Y once each
echo.
echo  Unlike the Python tool this does NOT need XInput, so it also
echo  sees pads connected over Bluetooth.
echo ============================================================
echo.

start "" "%GODOT%" --path "%CD%" -s res://tools/diagnostics/probe_pad_census.gd

echo waiting for the census...
:wait
ping -n 3 127.0.0.1 > nul
if not exist "%OUT%" goto wait

echo.
echo ================= census =================
type "%OUT%"
echo ==========================================
echo.
echo  How to read it: an axis with 2 distinct values is a switch,
echo  an axis with dozens is analog. Compare the trigger axes.
echo.
echo  Closing in 20 seconds.
ping -n 21 127.0.0.1 > nul
exit /b 0

:nogodot
echo Godot not found at:
echo   "%GODOT%"
echo Edit the GODOT line at the top of this file.
pause
exit /b 2
