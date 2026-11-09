@echo off
cd /d "%~dp0"
"D:\Program Files (x86)\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --headless --path "%~dp0." -s "res://sound/render_clips.gd"
echo.
echo Clips are in the sound folder. Opening it.
start "" explorer "%~dp0sound"
pause
