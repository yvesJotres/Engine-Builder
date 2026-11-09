@echo off
REM Engine Builder - Publish Update Script
REM Builds new version, creates patch, and prepares for distribution

setlocal enabledelayedexpansion

REM ==========================================
REM Configuration
REM ==========================================
set "GODOT_PATH=D:\Program Files (x86)\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
set "NSIS_PATH=C:\Program Files (x86)\NSIS\makensis.exe"
set "PROJECT_ROOT=D:\Projects\Engine Builder"
set "PATCH_SERVER_URL=https://your-server.com/engine-builder/patches"
set "VERSION_FILE=%PROJECT_ROOT%\project.godot"
set "SUPPORTED_VERSIONS=0.1.0 0.1.1"  REM Versions that can receive delta patches
set "SIGNING_KEY=%PROJECT_ROOT%\server\signing\private.pem"

echo ==========================================
echo Engine Builder - Publish Update
echo ==========================================
echo.

REM Read current version from project.godot
for /f "tokens=2 delims==" %%a in ('findstr /r "config/version=" "%VERSION_FILE%"') do (
    set "CURRENT_VERSION=%%a"
)
set "CURRENT_VERSION=%CURRENT_VERSION:"=%"
set "CURRENT_VERSION=%CURRENT_VERSION: =%"

echo Current version: %CURRENT_VERSION%
echo.

echo [1] Patch release (bug fixes) - %CURRENT_VERSION% ^> x.x.(N+1)
echo [2] Minor release (features)  - %CURRENT_VERSION% ^> x.(N+1).0
echo [3] Major release (breaking)  - %CURRENT_VERSION% ^> (N+1).0.0
echo [4] Custom version
echo [5] Build only (no version bump)
echo [6] Exit
echo.

:CHOICE
set /p CHOICE="Enter choice [1-6]: "

if "%CHOICE%"=="1" call :BUMP_PATCH
if "%CHOICE%"=="2" call :BUMP_MINOR
if "%CHOICE%"=="3" call :BUMP_MAJOR
if "%CHOICE%"=="4" call :CUSTOM_VERSION
if "%CHOICE%"=="5" (
    set "NEW_VERSION=%CURRENT_VERSION%"
    goto BUILD_ONLY
)
if "%CHOICE%"=="6" goto EXIT

echo Invalid choice. Please enter 1-6.
goto CHOICE

:BUMP_PATCH
for /f "tokens=1-3 delims=." %%a in ("%CURRENT_VERSION%") do (
    set /a NEW_PATCH=%%c+1
    set "NEW_VERSION=%%a.%%b.!NEW_PATCH!"
)
goto CONFIRM_VERSION

:BUMP_MINOR
for /f "tokens=1-3 delims=." %%a in ("%CURRENT_VERSION%") do (
    set /a NEW_MINOR=%%b+1
    set "NEW_VERSION=%%a.!NEW_MINOR!.0"
)
goto CONFIRM_VERSION

:BUMP_MAJOR
for /f "tokens=1-3 delims=." %%a in ("%CURRENT_VERSION%") do (
    set /a NEW_MAJOR=%%a+1
    set "NEW_VERSION=!NEW_MAJOR!.0.0"
)
goto CONFIRM_VERSION

:CUSTOM_VERSION
set /p NEW_VERSION="Enter new version (x.y.z): "
if not defined NEW_VERSION (
    echo No version entered.
    goto CHOICE
)
goto CONFIRM_VERSION

:CONFIRM_VERSION
echo.
echo New version will be: %NEW_VERSION%
set /p CONFIRM="Confirm? [Y/N]: "
if /i "%CONFIRM%"=="Y" goto UPDATE_VERSION
echo Cancelled.
goto CHOICE

:UPDATE_VERSION
echo Updating version to %NEW_VERSION%...
powershell -Command "(Get-Content '%VERSION_FILE%') -replace 'config/version=\"%CURRENT_VERSION%\"', 'config/version=\"%NEW_VERSION%\"' | Set-Content '%VERSION_FILE%'"
if %errorlevel% neq 0 (
    echo ERROR: Failed to update version
    exit /b 1
)
echo Version updated in project.godot

REM Update export presets too
set "EXPORT_PRESETS=%PROJECT_ROOT%\export_presets.cfg"
powershell -Command "(Get-Content '%EXPORT_PRESETS%') -replace 'version/name=\"%CURRENT_VERSION%\"', 'version/name=\"%NEW_VERSION%\"' | Set-Content '%EXPORT_PRESETS%'"
powershell -Command "(Get-Content '%EXPORT_PRESETS%') -replace 'version/code=%%a', 'version/code=%%b' >nul 2>&1" 2>nul

REM Increment version code for Android
for /f "tokens=2 delims==" %%a in ('findstr /r "version/code=" "%EXPORT_PRESETS%"') do (
    set "OLD_CODE=%%a"
)
set /a NEW_CODE=%OLD_CODE%+1
powershell -Command "(Get-Content '%EXPORT_PRESETS%') -replace 'version/code=%OLD_CODE%', 'version/code=%NEW_CODE%' | Set-Content '%EXPORT_PRESETS%'"
echo Android version code updated to %NEW_CODE%

REM Update NSIS installer script version
set "NSIS_SCRIPT=%PROJECT_ROOT%\installer\installer.nsi"
powershell -Command "(Get-Content '%NSIS_SCRIPT%') -replace '!define PRODUCT_VERSION \"%CURRENT_VERSION%\"', '!define PRODUCT_VERSION \"%NEW_VERSION%\"' | Set-Content '%NSIS_SCRIPT%'"
powershell -Command "(Get-Content '%NSIS_SCRIPT%') -replace '!define OUTPUT_FILE \"D:\\\\Projects\\\\Engine Builder\\\\build\\\\installer\\\\EngineBuilder_Setup_%CURRENT_VERSION%.exe\"', '!define OUTPUT_FILE \"D:\\\\Projects\\\\Engine Builder\\\\build\\\\installer\\\\EngineBuilder_Setup_%NEW_VERSION%.exe\"' | Set-Content '%NSIS_SCRIPT%'"
echo NSIS installer script version updated to %NEW_VERSION%

:BUILD_ONLY
echo.
echo ==========================================
echo Building Windows Export...
echo ==========================================
"%GODOT_PATH%" --headless --export-release "Windows Desktop" "%PROJECT_ROOT%\build\windows\EngineBuilder.exe"
if %errorlevel% neq 0 (
    echo ERROR: Windows export failed
    exit /b 1
)
echo Windows export successful

echo.
echo ==========================================
echo Building NSIS Installer...
echo ==========================================
cd /d "%PROJECT_ROOT%\installer"
"%NSIS_PATH%" installer.nsi
if %errorlevel% neq 0 (
    echo ERROR: NSIS build failed
    exit /b 1
)
cd /d "%PROJECT_ROOT%"
echo NSIS installer build successful

echo.
echo ==========================================
echo Creating Patches for All Supported Versions...
echo ==========================================
echo.

mkdir "%PROJECT_ROOT%\build\patch" 2>nul

REM We need previous .pck files for each supported version
REM For now, create a delta from the current build (simulating prior versions)
REM In production, you'd keep .pck files from each release

echo Generating delta patches for supported versions: %SUPPORTED_VERSIONS%

REM Backup current .pck as the "new" version
copy "%PROJECT_ROOT%\build\windows\EngineBuilder.pck" "%PROJECT_ROOT%\build\patch\EngineBuilder_%NEW_VERSION%.pck" >nul

for %%V in (%SUPPORTED_VERSIONS%) do (
    echo.
    echo Creating patch from %%V to %NEW_VERSION%...
    
    REM In real usage, you'd have: build\patch\EngineBuilder_%%V.pck from previous releases
    REM For now, simulate by creating a patch from current to current (demo)
    if exist "%PROJECT_ROOT%\build\patch\EngineBuilder_%%V.pck" (
        "%GODOT_PATH%" --headless --export-pack "Windows Desktop" "%PROJECT_ROOT%\build\patch\EngineBuilder_%%V_to_%NEW_VERSION%.pck" --patch "%PROJECT_ROOT%\build\patch\EngineBuilder_%%V.pck"
        if %errorlevel% neq 0 (
            echo WARNING: Failed to create patch for %%V
        ) else (
            echo Patch created: build\patch\EngineBuilder_%%V_to_%NEW_VERSION%.pck
        )
    ) else (
        echo NOTE: No .pck for version %%V found (expected at build\patch\EngineBuilder_%%V.pck)
        echo        Save each release's .pck to build\patch\ for future delta patches
    )
)

echo.
echo ==========================================
echo Generating Manifest & Checksums...
echo ==========================================

REM Use PowerShell to generate manifest directly
powershell -ExecutionPolicy Bypass -Command ^
    "$ver='%NEW_VERSION%'; ^
    $base='%PATCH_SERVER_URL%'; ^
    $patchDir='%PROJECT_ROOT%\build\patch'; ^
    $manifest = @{ latest_version=$ver; base_url=$base; full_installer='EngineBuilder_Setup_$ver.exe'; patches=@{}; patch_sizes=@{}; patch_sha256=@{} }; ^
    $supported='%SUPPORTED_VERSIONS%'.Split(' '); ^
    foreach ($v in $supported) { ^
        $patchFile='EngineBuilder_'+$v+'_to_'+$ver+'.pck'; ^
        $fullPath=Join-Path $patchDir $patchFile; ^
        if (Test-Path $fullPath) { ^
            $bytes=(Get-Item $fullPath).Length; ^
            $sha=(Get-FileHash -Algorithm SHA256 $fullPath).Hash; ^
            $manifest.patches[$v]=$patchFile; ^
            $manifest.patch_sizes[$v]=$bytes; ^
            $manifest.patch_sha256[$v]=$sha; ^
            Write-Host \"Manifest: $v -> $patchFile ($bytes bytes, SHA256: $sha)\"; ^
        } ^
    }; ^
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $patchDir 'manifest.json') -Encoding UTF8; ^
    Write-Host 'Manifest written to build\patch\manifest.json'"
echo.
echo ==========================================
echo Publishing to Server...
echo ==========================================
echo.
echo Manual steps required:
echo 1. Upload installer: build\installer\EngineBuilder_Setup_%NEW_VERSION%.exe
echo 2. Upload patch (if created): build\patch\EngineBuilder_patch_%NEW_VERSION%.pck
echo 3. Update version manifest at: %PATCH_SERVER_URL%
echo 4. Notify users via in-app update checker
echo.
echo Example manifest.json:
echo {
echo   "latest_version": "%NEW_VERSION%",
echo   "installer_url": "%PATCH_SERVER_URL%/EngineBuilder_Setup_%NEW_VERSION%.exe",
echo   "patch_url": "%PATCH_SERVER_URL%/EngineBuilder_patch_%NEW_VERSION%.pck",
echo   "changelog_url": "%PATCH_SERVER_URL%/changelog_%NEW_VERSION%.md",
echo   "mandatory": false
echo }
echo.
set /p OPEN_FOLDER="Open build folder? [Y/N]: "
if /i "%OPEN_FOLDER%"=="Y" explorer "%PROJECT_ROOT%\build"

echo.
echo ==========================================
echo Update %NEW_VERSION% ready for distribution!
echo ==========================================
goto END

:EXIT
echo.
echo Publish cancelled.
goto END

:END
echo.
echo ==========================================
pause