@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "WORKSPACE_ROOT=%SCRIPT_DIR%.."
set "TAURI_DIR=%WORKSPACE_ROOT%\Sources"

echo === Building VNKey Tauri for Windows ===
where npm >nul 2>nul || (echo Error: npm is required. & exit /b 1)
where cargo >nul 2>nul || (echo Error: Rust/Cargo is required. & exit /b 1)

cd /d "%TAURI_DIR%"
call npm ci || exit /b 1
call npm run check || exit /b 1
call npm run tauri build || exit /b 1

echo.
echo === Build finished ===
echo Bundles: %TAURI_DIR%\src-tauri\target\release\bundle
