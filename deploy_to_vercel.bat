@echo off
title Deploy Rameez Kitchen to Vercel
color 0A
echo ========================================================
echo   RAMEEZ KITCHEN - ONE-CLICK VERCEL DEPLOYMENT
echo ========================================================
echo.

cd /d "%~dp0flutter_apps\customer_app"
echo [1/3] Building Customer App for Web (Production)...
call flutter build web --release
if %errorlevel% neq 0 (
    echo [ERROR] Flutter build failed.
    pause
    exit /b %errorlevel%
)

echo.
echo [2/3] Copying Vercel configuration...
copy /Y "%~dp0flutter_apps\customer_app\vercel.json" "%~dp0flutter_apps\customer_app\build\web\vercel.json" >nul

echo.
echo [3/3] Deploying to Vercel Production...
cd /d "%~dp0flutter_apps\customer_app\build\web"
call npx --yes vercel --prod --yes

echo.
echo ========================================================
echo   DEPLOYMENT FINISHED SUCCESSFULLY!
echo ========================================================
pause
