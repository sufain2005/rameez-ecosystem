Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  Starting Rameez Kitchen Ecosystem (4 Services)" -ForegroundColor Yellow
Write-Host "========================================================" -ForegroundColor Cyan
echo.

# 1. Backend + Customer Web
Write-Host "[1/4] Starting Backend Server (Port 5000)..." -ForegroundColor Green
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd 'd:\rameez-ecosystem\backend'; node server.js"
Start-Sleep -Seconds 2

# 2. Customer App (Dev)
Write-Host "[2/4] Starting Customer App Dev Server (Port 8080)..." -ForegroundColor Green
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd 'd:\rameez-ecosystem\flutter_apps\customer_app'; flutter run -d chrome --web-port 8080 --web-hostname 0.0.0.0"
Start-Sleep -Seconds 2

# 3. Merchant App
Write-Host "[3/4] Starting Merchant App (Port 8081)..." -ForegroundColor Green
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd 'd:\rameez-ecosystem\flutter_apps\merchant_app'; flutter run -d chrome --web-port 8081 --web-hostname 0.0.0.0"
Start-Sleep -Seconds 2

# 4. Driver App
Write-Host "[4/4] Starting Driver App (Port 8082)..." -ForegroundColor Green
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd 'd:\rameez-ecosystem\flutter_apps\driver_app'; flutter run -d chrome --web-port 8082 --web-hostname 0.0.0.0"

Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host "  All services launched successfully!" -ForegroundColor Green
Write-Host "  [PC Links]" -ForegroundColor Yellow
Write-Host "  - Backend API & App: http://localhost:5000" -ForegroundColor White
Write-Host "  - Customer App Dev:  http://localhost:8080" -ForegroundColor White
Write-Host "  - Merchant App:      http://localhost:8081" -ForegroundColor White
Write-Host "  - Driver App:        http://localhost:8082" -ForegroundColor White
Write-Host "`n  [Direct Mobile Phone Links - Same Wi-Fi]" -ForegroundColor Yellow
Write-Host "  - Customer App:      http://192.168.100.86:5000" -ForegroundColor Cyan
Write-Host "  - Merchant App:      http://192.168.100.86:8081" -ForegroundColor Cyan
Write-Host "  - Driver App:        http://192.168.100.86:8082" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
