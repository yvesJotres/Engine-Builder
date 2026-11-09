@echo off
rem Builds the engine_sim extension for Windows with CMake and Ninja. Usage: build_win.bat [template_debug|template_release]
rem Needs the Visual Studio 2022 Build Tools (C++ workload), CMake, and Ninja (pip install ninja).
set TARGET=%1
if "%TARGET%"=="" set TARGET=template_debug
set BT=Debug
if "%TARGET%"=="template_release" set BT=Release
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat" -arch=x64 -host_arch=x64
set PATH=%PATH%;C:\Program Files\CMake\bin;%LOCALAPPDATA%\Programs\Python\Python312\Scripts
cd /d "%~dp0"
cmake -S . -B build\win-%BT% -G Ninja -DCMAKE_BUILD_TYPE=%BT% -DCMAKE_C_COMPILER=cl -DCMAKE_CXX_COMPILER=cl
if errorlevel 1 exit /b 1
cmake --build build\win-%BT%
