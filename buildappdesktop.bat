@echo off
setlocal EnableExtensions

rem Build Hermes desktop app from the repo root.
rem Usage:
rem   buildappdesktop.bat                 build Windows installers (NSIS + MSI)
rem   buildappdesktop.bat pack            build unpacked app under apps\desktop\release\
rem   buildappdesktop.bat build           build renderer/electron assets only
rem   buildappdesktop.bat dist            build current-platform installers
rem   buildappdesktop.bat dist:win:nsis   build Windows NSIS installer only
rem   buildappdesktop.bat dist:win:msi    build Windows MSI installer only

set "QUIET_LOG=%TEMP%\hermes-buildappdesktop-check.log"
chcp 65001 >"%QUIET_LOG%" 2>&1
cd /d "%~dp0"

set "REPO_DIR=%CD%"
set "DESKTOP_DIR=%REPO_DIR%\apps\desktop"
set "BUILD_SCRIPT=%~1"

if not defined BUILD_SCRIPT set "BUILD_SCRIPT=dist:win"

if /I "%BUILD_SCRIPT%"=="win" set "BUILD_SCRIPT=dist:win"
if /I "%BUILD_SCRIPT%"=="msi" set "BUILD_SCRIPT=dist:win:msi"
if /I "%BUILD_SCRIPT%"=="nsis" set "BUILD_SCRIPT=dist:win:nsis"

if not exist "%DESKTOP_DIR%\package.json" goto NO_DESKTOP_PACKAGE

where npm.cmd >"%QUIET_LOG%" 2>&1
if errorlevel 1 goto NO_NPM

if not exist "%REPO_DIR%\node_modules" (
    echo Installing root workspace dependencies...
    call npm.cmd install
    if errorlevel 1 goto INSTALL_FAILED
)

call npm.cmd ls --workspace apps/desktop --depth=0 >"%QUIET_LOG%" 2>&1
if errorlevel 1 (
    echo Installing desktop workspace dependencies...
    call npm.cmd install --workspace apps/desktop
    if errorlevel 1 goto INSTALL_FAILED
)

echo.
echo Building Hermes desktop app
echo Repo: %REPO_DIR%
echo Script: %BUILD_SCRIPT%
echo.

call npm.cmd run %BUILD_SCRIPT% --workspace apps/desktop
if errorlevel 1 goto BUILD_FAILED

echo.
echo Build complete.
echo Output: %DESKTOP_DIR%\release
exit /b 0

:NO_DESKTOP_PACKAGE
echo ERROR: apps\desktop\package.json not found.
echo Run this script from a Hermes Agent checkout.
exit /b 1

:NO_NPM
echo ERROR: npm.cmd not found in PATH.
echo Install Node.js 20+ and npm, then run this script again.
exit /b 1

:INSTALL_FAILED
echo ERROR: npm install failed.
exit /b 1

:BUILD_FAILED
echo ERROR: desktop build failed.
exit /b 1
