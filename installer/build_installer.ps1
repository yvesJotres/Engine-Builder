<# 
.SYNOPSIS
    Build script for Engine Builder Windows Installer
.DESCRIPTION
    This script builds the NSIS installer for Engine Builder.
    Requires NSIS (makensis) to be installed and in PATH.
.NOTES
    Run from the project root directory: .\installer\build_installer.ps1
#>

param(
    [string]$NsisPath = "makensis",
    [switch]$SkipIconConversion
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Engine Builder - Installer Build Script" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# Get project root
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ProjectRoot = Split-Path -Parent $ScriptDir
$InstallerDir = Join-Path $ProjectRoot "installer"
$BuildDir = Join-Path $ProjectRoot "build"
$WindowsBuildDir = Join-Path $BuildDir "windows"
$OutputDir = Join-Path $BuildDir "installer"

# Create output directory
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    Write-Host "Created output directory: $OutputDir" -ForegroundColor Green
}

# Check for required files
$ExePath = Join-Path $WindowsBuildDir "EngineBuilder.exe"
$PckPath = Join-Path $WindowsBuildDir "EngineBuilder.pck"

if (-not (Test-Path $ExePath)) {
    Write-Error "EngineBuilder.exe not found at $ExePath. Please build the Windows export first."
    exit 1
}

if (-not (Test-Path $PckPath)) {
    Write-Error "EngineBuilder.pck not found at $PckPath. Please build the Windows export first."
    exit 1
}

Write-Host "Found EngineBuilder.exe and EngineBuilder.pck" -ForegroundColor Green

# Check for NSIS
$NsisExe = Get-Command $NsisPath -ErrorAction SilentlyContinue
if (-not $NsisExe) {
    Write-Error "NSIS (makensis) not found in PATH. Please install NSIS from https://nsis.sourceforge.io/"
    Write-Host "Alternatively, specify the path with -NsisPath parameter."
    exit 1
}

Write-Host "Found NSIS: $($NsisExe.Source)" -ForegroundColor Green

# Convert app_icon.png to .ico if needed
$IconPng = Join-Path $ProjectRoot "assets\app_icon.png"
$IconIco = Join-Path $InstallerDir "app_icon.ico"
$BannerBmp = Join-Path $InstallerDir "installer_banner.bmp"

if (-not $SkipIconConversion) {
    if (Test-Path $IconPng) {
        Write-Host "Converting app_icon.png to .ico..." -ForegroundColor Yellow
        try {
            # Use ImageMagick if available
            $Magick = Get-Command "magick" -ErrorAction SilentlyContinue
            if (-not $Magick) {
                $Magick = Get-Command "convert" -ErrorAction SilentlyContinue
            }
            
            if ($Magick) {
                & $Magick.Source $IconPng -define icon:auto-resize=256,128,64,48,32,16 $IconIco
                Write-Host "Icon converted successfully" -ForegroundColor Green
            } else {
                Write-Warning "ImageMagick not found. Skipping icon conversion. Please manually convert assets/app_icon.png to installer/app_icon.ico"
            }
        } catch {
            Write-Warning "Failed to convert icon: $($_.Exception.Message)"
        }
    } else {
        Write-Warning "app_icon.png not found at $IconPng"
    }
}

# Create a simple banner if it doesn't exist (150x570 for MUI2)
if (-not (Test-Path $BannerBmp)) {
    Write-Host "Creating placeholder banner..." -ForegroundColor Yellow
    try {
        $Magick = Get-Command "magick" -ErrorAction SilentlyContinue
        if (-not $Magick) {
            $Magick = Get-Command "convert" -ErrorAction SilentlyContinue
        }
        
        if ($Magick) {
            & $Magick.Source -size 150x570 gradient:#2c3e50-#34495e -gravity center -pointsize 24 -fill white -annotate +0+0 "Engine Builder" $BannerBmp
            Write-Host "Banner created successfully" -ForegroundColor Green
        } else {
            Write-Warning "ImageMagick not found. Please create installer/installer_banner.bmp (150x570px) manually"
        }
    } catch {
        Write-Warning "Failed to create banner: $($_.Exception.Message)"
    }
}

# Copy license file to installer directory if not exists
$LicenseSrc = Join-Path $InstallerDir "LICENSE.txt"
$LicenseDst = Join-Path $InstallerDir "LICENSE.txt"
# Already created above

# Change to installer directory and run makensis
Set-Location $InstallerDir

Write-Host "Building installer with NSIS..." -ForegroundColor Cyan
$Result = & $NsisExe.Source "installer.nsi"

if ($LASTEXITCODE -eq 0) {
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "Installer built successfully!" -ForegroundColor Green
    Write-Host "Output: $OutputDir\EngineBuilder_Setup_0.1.5.exe" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green
} else {
    Write-Error "NSIS build failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}