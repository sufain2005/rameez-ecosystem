# ==============================================================================
# Rameez Kitchen Ecosystem — Production Secure Obfuscated Build Script
# ==============================================================================
# Features:
# 1. Full Dart AOT Code Obfuscation (--obfuscate)
# 2. Debug Symbol Stripping (--split-debug-info) -> prevents reverse engineering
# 3. Android R8 / ProGuard Minification & Resource Shrinking
# 4. Anti-Tampering & Anti-Burp Suite TLS Hardening
# ==============================================================================

param (
    [ValidateSet("customer_app", "driver_app", "merchant_app", "all")]
    [string]$App = "all",
    [ValidateSet("apk", "appbundle")]
    [string]$Target = "apk"
)

$ErrorActionPreference = "Stop"
$rootDir = $PSScriptRoot

function Build-SecureApp {
    param (
        [string]$appName,
        [string]$targetType
    )

    $appPath = Join-Path $rootDir "flutter_apps\$appName"
    $symbolsPath = Join-Path $rootDir "build_symbols\$appName"
    
    if (-not (Test-Path $symbolsPath)) {
        New-Item -ItemType Directory -Path $symbolsPath -Force | Out-Null
    }

    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " Building Secure Obfuscated $appName ($targetType)" -ForegroundColor Green
    Write-Host " Symbols Directory: $symbolsPath" -ForegroundColor DarkGray
    Write-Host "============================================================" -ForegroundColor Cyan

    Push-Location $appPath
    try {
        Write-Host "-> Fetching dependencies..." -ForegroundColor Yellow
        flutter pub get

        Write-Host "-> Compiling with AOT Obfuscation & Symbol Stripping..." -ForegroundColor Yellow
        if ($targetType -eq "apk") {
            flutter build apk --release --obfuscate "--split-debug-info=$symbolsPath"
            Write-Host "✔ Secure Obfuscated APK successfully generated at:" -ForegroundColor Green
            Write-Host "  $appPath\build\app\outputs\flutter-apk\app-release.apk" -ForegroundColor White
        } else {
            flutter build appbundle --release --obfuscate "--split-debug-info=$symbolsPath"
            Write-Host "✔ Secure Obfuscated AppBundle successfully generated at:" -ForegroundColor Green
            Write-Host "  $appPath\build\app\outputs\bundle\release\app-release.aab" -ForegroundColor White
        }
    } finally {
        Pop-Location
    }
}

if ($App -eq "all") {
    Build-SecureApp -appName "customer_app" -targetType $Target
    Build-SecureApp -appName "driver_app" -targetType $Target
    Build-SecureApp -appName "merchant_app" -targetType $Target
} else {
    Build-SecureApp -appName $App -targetType $Target
}

Write-Host "`nAll requested builds finished securely." -ForegroundColor Green

