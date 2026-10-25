@echo off
echo ========================================================
echo   Starting Rameez Kitchen Ecosystem (4 Services)
echo ========================================================
echo.

echo [1/4] Launching Backend Server on port 5000...
start "Backend Server (Port 5000)" cmd /k "cd /d d:\rameez-ecosystem\backend && node server.js"

timeout /t 2 /nobreak >nul

echo [2/4] Launching Customer App on port 8080...
start "Customer App (Port 8080)" cmd /k "cd /d d:\rameez-ecosystem\flutter_apps\customer_app && flutter run -d chrome --web-port 8080 --web-hostname 0.0.0.0"

timeout /t 2 /nobreak >nul

echo [3/4] Launching Merchant App on port 8081...
start "Merchant App (Port 8081)" cmd /k "cd /d d:\rameez-ecosystem\flutter_apps\merchant_app && flutter run -d chrome --web-port 8081 --web-hostname 0.0.0.0"

timeout /t 2 /nobreak >nul

echo [4/4] Launching Driver App on port 8082...
start "Driver App (Port 8082)" cmd /k "cd /d d:\rameez-ecosystem\flutter_apps\driver_app && flutter run -d chrome --web-port 8082 --web-hostname 0.0.0.0"

echo.
echo ========================================================
echo   All 4 services launched successfully!
echo.
echo   [PC Browser Links]
echo   - Backend API:    http://localhost:5000
echo   - Customer App:   http://localhost:8080
echo   - Merchant App:   http://localhost:8081
echo   - Driver App:     http://localhost:8082
echo.
echo   [Direct Mobile Phone Links - Same Wi-Fi]
echo   - Customer App:   http://192.168.100.86:8080
echo   - Merchant App:   http://192.168.100.86:8081
echo   - Driver App:     http://192.168.100.86:8082
echo ========================================================
