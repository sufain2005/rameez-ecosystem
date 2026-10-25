@echo off
title Rameez Ecosystem - Share to Mobile
cls
echo ========================================================
echo   Rameez Kitchen - Direct Mobile Phone Share
echo ========================================================
echo.
echo [1/2] Starting Master Server (Port 5000)...
start "1. Backend Server + Customer Web (Port 5000)" cmd /k "cd /d d:\rameez-ecosystem\backend && node server.js"

timeout /t 3 /nobreak >nul

echo [2/2] Generating Direct Instant Mobile Link (No password needed)...
start "2. Mobile Link (Direct HTTPS)" cmd /k "echo Connecting Direct Tunnel... && ssh -o StrictHostKeyChecking=no -o ServerAliveInterval=30 -R 80:localhost:5000 nokey@localhost.run"

echo.
echo ========================================================
echo   HOW TO VIEW ON MOBILE PHONE:
echo ========================================================
echo.
echo   OPTION A (Same Wi-Fi):
echo   👉 http://192.168.100.86:5000
echo.
echo   OPTION B (Direct HTTPS - Anywhere on Mobile Data):
echo   👉 Check the '2. Mobile Link' window for your https://xxxx.lhr.life URL!
echo      (No password or security check needed!)
echo.
echo ========================================================
echo   Keep the windows open while using on your phone!
echo ========================================================
pause
