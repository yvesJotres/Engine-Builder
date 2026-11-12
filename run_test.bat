@echo off
setlocal EnableExtensions
cd /d "%~dp0"

rem The gate. Every test under tests/unit and tests/integration runs in its own Godot process; a test fails when it
rem exits non-zero, prints a SCRIPT ERROR, or prints a FAIL line. The runner is tests/test_runner.gd and it selects
rem tests with the TEST_FILTER environment variable, so the groups below are just filters over the same sweep.
rem
rem   run_test.bat                 everything (slow: one process per test)
rem   run_test.bat --physics       engine, exhaust, intake, sim and dyno
rem   run_test.bat --ui            controls, structure, visual
rem   run_test.bat --drivetrain    drivetrain, gearbox, bike model
rem   run_test.bat --ecu           ECU, idle, launch, limiter
rem   run_test.bat --audio         audio layers, IR, SPL
rem   run_test.bat engine/woschni  any raw filter; TEST_FILTER matches anywhere in the test path
rem
rem Exit code 1 if any selected test fails. Pauses only when run with no arguments, so CI and agents do not hang.

set "GODOT=D:\Program Files (x86)\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
set "FAILED=0"
set "GROUPS="

rem A stale extension looks exactly like a logic bug: the C++ changed, the DLL did not, and the test compares against the
rem old binary. Warn always, and fail the run when --check-dll is passed (CI and an agent's pre-flight).
call :check_dll
if /I "%~1"=="--check-dll" goto :check_only

if "%~1"=="" goto :run
if /I "%~1"=="--all" goto :run
if /I "%~1"=="--physics" (
	set "GROUPS=engine/ exhaust/ intake/ sim/ dyno/"
	goto :run
)
if /I "%~1"=="--ui" (
	set "GROUPS=controls/ structure/ visual/"
	goto :run
)
if /I "%~1"=="--drivetrain" (
	set "GROUPS=drivetrain/ model/"
	goto :run
)
if /I "%~1"=="--ecu" (
	set "GROUPS=ecu/"
	goto :run
)
if /I "%~1"=="--audio" (
	set "GROUPS=audio/"
	goto :run
)
rem anything else is a raw filter for the runner
set "GROUPS=%~1"

:run
if "%GROUPS%"=="" (
	echo == full sweep
	call :one ""
	goto :done
)
for %%g in (%GROUPS%) do (
	echo == %%g
	call :one "%%g"
)
goto :done

:one
set "TEST_FILTER=%~1"
"%GODOT%" --headless --path "%~dp0." -s "res://tests/test_runner.gd"
if errorlevel 1 set "FAILED=1"
exit /b 0

rem Sets DLL_STALE=1 when any .cpp/.h under gdextension/src or gdextension/include is newer than the debug DLL,
rem 0 when the DLL is current, and leaves it unset if either side is missing.
:check_dll
set "DLL_STALE="
for /f "usebackq delims=" %%s in (`powershell -NoProfile -Command "$dll='%~dp0gdextension\bin\libengine_sim.windows.template_debug.x86_64.dll'; if (-not (Test-Path $dll)) { 'missing'; exit }; $f=Get-ChildItem '%~dp0gdextension\src','%~dp0gdextension\include' -Recurse -Include *.cpp,*.h -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1; if ($f -and $f.LastWriteTime -gt (Get-Item $dll).LastWriteTime) { 'stale' } else { 'current' }"`) do set "DLL_STATE=%%s"
if /I "%DLL_STATE%"=="stale" (
	set "DLL_STALE=1"
	echo WARNING: the native extension is older than gdextension/src - rebuild before trusting a C++ test.
)
if /I "%DLL_STATE%"=="current" set "DLL_STALE=0"
if /I "%DLL_STATE%"=="missing" echo WARNING: no native extension in gdextension\bin - the native tests will skip.
exit /b 0

:done
echo.
if "%FAILED%"=="1" (
	echo GATE: FAILED
	set "RC=1"
) else (
	echo GATE: PASSED
	set "RC=0"
)
rem pause only for a human double-click, so a CI or an agent call does not hang on it
if "%~1"=="" pause
endlocal & exit /b %RC%

rem --check-dll: exit code says whether the native extension matches the C++ sources.
:check_only
if "%DLL_STALE%"=="1" (
	echo GATE: FAILED - the native extension is older than gdextension/src or gdextension/include.
	echo        Run gdextension\build_win.bat template_debug, and close Godot first: it holds the DLL open.
	set "RC=1"
) else (
	echo native extension is up to date with gdextension/src and gdextension/include
	set "RC=0"
)
endlocal & exit /b %RC%