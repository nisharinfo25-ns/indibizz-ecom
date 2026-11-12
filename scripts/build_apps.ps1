# IndiaBizz - Local Application Build Script
# This script uses the extracted Flutter SDK in tools\flutter to build Android APKs and Windows EXE.

param (
    [ValidateSet("all", "apk", "exe", "customer", "delivery", "seller")]
    [string]$Target = "all"
)

$ErrorActionPreference = "Stop"
$WorkspaceRoot = $PSScriptRoot | Split-Path -Parent
$FlutterBin = Join-Path $WorkspaceRoot "tools\flutter\bin"

if (-not (Test-Path "$FlutterBin\flutter.bat")) {
    Write-Host "Error: Flutter SDK not found in $FlutterBin." -ForegroundColor Red
    exit 1
}

# Add Flutter to current session PATH
$env:PATH = "$FlutterBin;$env:PATH"
$env:LOCALAPPDATA = "$WorkspaceRoot\.localappdata"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  IndiaBizz - Build Pipeline" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# 1. Build APKs
if ($Target -in @("all", "apk", "customer")) {
    Write-Host "`n>>> Building Customer App APK..." -ForegroundColor Green
    Push-Location (Join-Path $WorkspaceRoot "apps\customer_app")
    try {
        & flutter.bat pub get
        & flutter.bat build apk --release
        Write-Host ">>> Customer APK generated: apps\customer_app\build\app\outputs\flutter-apk\app-release.apk" -ForegroundColor Green
    } catch {
        Write-Host "Failed to build Customer APK: $_" -ForegroundColor Yellow
        Write-Host "Note: Building an APK locally requires Android Studio / Android SDK to be installed." -ForegroundColor Yellow
    } finally {
        Pop-Location
    }
}

if ($Target -in @("all", "apk", "delivery")) {
    Write-Host "`n>>> Building Delivery Fleet App APK..." -ForegroundColor Green
    Push-Location (Join-Path $WorkspaceRoot "apps\delivery_app")
    try {
        & flutter.bat pub get
        & flutter.bat build apk --release
        Write-Host ">>> Delivery APK generated: apps\delivery_app\build\app\outputs\flutter-apk\app-release.apk" -ForegroundColor Green
    } catch {
        Write-Host "Failed to build Delivery APK: $_" -ForegroundColor Yellow
        Write-Host "Note: Building an APK locally requires Android Studio / Android SDK to be installed." -ForegroundColor Yellow
    } finally {
        Pop-Location
    }
}

if ($Target -in @("all", "apk", "seller")) {
    Write-Host "`n>>> Building Seller App APK..." -ForegroundColor Green
    Push-Location (Join-Path $WorkspaceRoot "apps\seller_app")
    try {
        & flutter.bat pub get
        & flutter.bat build apk --release
        Write-Host ">>> Seller APK generated: apps\seller_app\build\app\outputs\flutter-apk\app-release.apk" -ForegroundColor Green
    } catch {
        Write-Host "Failed to build Seller APK: $_" -ForegroundColor Yellow
        Write-Host "Note: Building an APK locally requires Android Studio / Android SDK to be installed." -ForegroundColor Yellow
    } finally {
        Pop-Location
    }
}

# 2. Build Windows Executable
if ($Target -in @("all", "exe", "seller")) {
    Write-Host "`n>>> Building Seller App Windows Executable (.exe)..." -ForegroundColor Green
    Push-Location (Join-Path $WorkspaceRoot "apps\seller_app")
    try {
        & flutter.bat pub get
        & flutter.bat build windows --release
        Write-Host ">>> Windows EXE generated: apps\seller_app\build\windows\x64\runner\Release\indibizz_seller.exe" -ForegroundColor Green
    } catch {
        Write-Host "Failed to build Windows EXE: $_" -ForegroundColor Yellow
        Write-Host "Note: Building a Windows EXE locally requires Visual Studio with 'Desktop development with C++'." -ForegroundColor Yellow
    } finally {
        Pop-Location
    }
}

Write-Host "`nBuild execution completed." -ForegroundColor Cyan
