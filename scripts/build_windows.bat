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

set "BUILD_OUT_DIR=%WORKSPACE_ROOT%\.build"
if not exist "%BUILD_OUT_DIR%" mkdir "%BUILD_OUT_DIR%"
echo === Copying Windows build artifacts to %BUILD_OUT_DIR% ===
if exist "%TAURI_DIR%\src-tauri\target\release\bundle\msi" (
    copy "%TAURI_DIR%\src-tauri\target\release\bundle\msi\*.msi" "%BUILD_OUT_DIR%\" >nul 2>nul
)
if exist "%TAURI_DIR%\src-tauri\target\release\bundle\nsis" (
    copy "%TAURI_DIR%\src-tauri\target\release\bundle\nsis\*.exe" "%BUILD_OUT_DIR%\" >nul 2>nul
)

echo.
echo === Build finished ===
echo Artifacts copied to: %BUILD_OUT_DIR%
