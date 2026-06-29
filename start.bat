@echo off
chcp 65001 >nul 2>&1
title WDTT Panel

echo.
echo  ═══════════════════════════════════════════
echo     WDTT Panel — Запуск (Windows)
echo  ═══════════════════════════════════════════
echo.

where node >nul 2>&1
if %errorlevel% neq 0 (
  echo  [ОШИБКА] Node.js не найден!
  echo.
  echo  Скачайте и установите Node.js 20 с сайта:
  echo  https://nodejs.org/
  echo.
  pause
  exit /b 1
)

for /f "tokens=1 delims=." %%v in ('node -e "process.stdout.write(process.versions.node)"') do set NODE_MAJOR=%%v
if %NODE_MAJOR% LSS 18 (
  echo  [ОШИБКА] Требуется Node.js 18+.
  echo  Скачайте: https://nodejs.org/
  pause
  exit /b 1
)

echo  [OK] Node.js найден
echo.

cd /d "%~dp0server"

if not exist "node_modules" (
  echo  [INFO] Установка зависимостей...
  call npm install --loglevel=error
  if %errorlevel% neq 0 (
    echo  [ОШИБКА] Не удалось установить зависимости
    pause
    exit /b 1
  )
  echo  [OK] Зависимости установлены
)

echo  [INFO] Запуск WDTT Panel...
echo.
echo  Нажмите Ctrl+C для остановки
echo.

node index.js %*
pause
