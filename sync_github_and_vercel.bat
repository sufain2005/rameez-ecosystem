@echo off
title Sync Rameez Kitchen to GitHub and Vercel
color 0B
echo ========================================================
echo   RAMEEZ KITCHEN - GITHUB & VERCEL AUTO-SYNC
echo ========================================================
echo.

cd /d "%~dp0"

echo [1/4] Staging changes for Git...
git add -A

echo.
echo Commit message:
echo [Press ENTER to use default: "update: latest features and fixes"]
set /p COMMIT_MSG="Enter message (optional): "
if "%COMMIT_MSG%"=="" set COMMIT_MSG=update: latest features and fixes

echo.
echo [2/4] Pushing changes to GitHub repository...
git commit -m "%COMMIT_MSG%"
git push origin main

echo.
echo [3/4] Compiling Flutter Customer Web App (Release mode)...
cd /d "%~dp0flutter_apps\customer_app"
call flutter build web --release
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Flutter build encountered an error.
    pause
    exit /b %errorlevel%
)

echo.
echo [4/4] Deploying to Vercel Production...
copy /Y "%~dp0flutter_apps\customer_app\vercel.json" "%~dp0flutter_apps\customer_app\build\web\vercel.json" >nul
cd /d "%~dp0flutter_apps\customer_app\build\web"
call npx --yes vercel --prod --yes

echo.
echo ========================================================
echo   SUCCESS! BOTH GITHUB AND VERCEL ARE FULLY UPDATED!
echo.
echo   GitHub:   https://github.com/sufain2005/rameez-ecosystem
echo   Live App: https://rameezkitchen.vercel.app
echo ========================================================
pause

