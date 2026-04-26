# build.ps1 — KrakenSDR Triangulator Build Script
# ==================================================
# Produces BOTH a standalone executable AND a portable ZIP, then optionally
# builds the Inno Setup installer.
#
# Usage:
#   .\build.ps1              # Full build (exe + zip + installer)
#   .\build.ps1 -SkipInstaller  # Build exe + zip only (no Inno Setup needed)
#
# Prerequisites:
#   - Python 3.8+ with pip
#   - Inno Setup 6 (for installer build): https://jrsoftware.org/isdl.php

param(
    [switch]$SkipInstaller
)

$ErrorActionPreference = "Stop"
$Version = "1.7.0"
$DistName = "KrakenSDR-Triangulator"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  KrakenSDR Triangulator v$Version — Build Script" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# ── Step 1: Install Python dependencies ──────────────────────────────────
Write-Host "[1/5] Installing Python dependencies..." -ForegroundColor Yellow
pip install pyinstaller flask flask-cors requests pymavlink --quiet
if ($LASTEXITCODE -ne 0) { throw "Failed to install dependencies" }
Write-Host "  Done." -ForegroundColor Green

# ── Step 2: Clean previous builds ────────────────────────────────────────
Write-Host "[2/5] Cleaning previous build artifacts..." -ForegroundColor Yellow
if (Test-Path "dist") { Remove-Item -Recurse -Force "dist" }
if (Test-Path "build") { Remove-Item -Recurse -Force "build" }
Write-Host "  Done." -ForegroundColor Green

# ── Step 3: Run PyInstaller ──────────────────────────────────────────────
Write-Host "[3/5] Building executable with PyInstaller..." -ForegroundColor Yellow
pyinstaller kraken_triangulator.spec --clean --noconfirm
if ($LASTEXITCODE -ne 0) { throw "PyInstaller build failed" }
Write-Host "  Done." -ForegroundColor Green

# ── Step 4: Create portable ZIP ──────────────────────────────────────────
Write-Host "[4/5] Creating portable ZIP archive..." -ForegroundColor Yellow
$ZipName = "$DistName-v$Version-portable.zip"
$ZipPath = Join-Path "dist" $ZipName
Compress-Archive -Path "dist\$DistName\*" -DestinationPath $ZipPath -Force
$ZipSize = [math]::Round((Get-Item $ZipPath).Length / 1MB, 1)
Write-Host "  Created: $ZipPath ($ZipSize MB)" -ForegroundColor Green

# ── Step 5: Build Inno Setup installer (optional) ────────────────────────
if (-not $SkipInstaller) {
    Write-Host "[5/5] Building Inno Setup installer..." -ForegroundColor Yellow
    
    $InnoPath = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
    if (Test-Path $InnoPath) {
        & $InnoPath "installer.iss"
        if ($LASTEXITCODE -ne 0) { throw "Inno Setup build failed" }
        $InstallerPath = "Output\$DistName-Setup-v$Version.exe"
        if (Test-Path $InstallerPath) {
            $InstallerSize = [math]::Round((Get-Item $InstallerPath).Length / 1MB, 1)
            Write-Host "  Created: $InstallerPath ($InstallerSize MB)" -ForegroundColor Green
        }
    } else {
        Write-Host "  [SKIP] Inno Setup not found at $InnoPath" -ForegroundColor DarkYellow
        Write-Host "         Install from: https://jrsoftware.org/isdl.php" -ForegroundColor DarkYellow
    }
} else {
    Write-Host "[5/5] Skipping installer (use -SkipInstaller to skip)." -ForegroundColor DarkYellow
}

# ── Summary ──────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  BUILD COMPLETE" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Executable folder: dist\$DistName\" -ForegroundColor White
Write-Host "  Portable ZIP:      dist\$ZipName" -ForegroundColor White
if (-not $SkipInstaller -and (Test-Path "Output\$DistName-Setup-v$Version.exe")) {
    Write-Host "  Installer:         Output\$DistName-Setup-v$Version.exe" -ForegroundColor White
}
Write-Host ""
Write-Host "  To test: .\dist\$DistName\$DistName.exe" -ForegroundColor Cyan
Write-Host ""
