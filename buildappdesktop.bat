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
set "NPM_CONFIG_CACHE=%TEMP%\hermes-npm-cache"
set "NPM_CONFIG_UPDATE_NOTIFIER=false"
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

set "HERMES_NODE_DIR=%LOCALAPPDATA%\hermes\node"
if exist "%HERMES_NODE_DIR%\node.exe" if exist "%HERMES_NODE_DIR%\npm.cmd" (
    set "PATH=%HERMES_NODE_DIR%;%PATH%"
)

where node.exe >"%QUIET_LOG%" 2>&1
if errorlevel 1 goto NO_NODE

where npm.cmd >"%QUIET_LOG%" 2>&1
if errorlevel 1 goto NO_NPM

set "NODE_EXE="
set "NPM_EXE="
for /f "delims=" %%I in ('where node.exe 2^>nul') do if not defined NODE_EXE set "NODE_EXE=%%I"
for /f "delims=" %%I in ('where npm.cmd 2^>nul') do if not defined NPM_EXE set "NPM_EXE=%%I"

call node -e "const [major, minor] = process.versions.node.split('.').map(Number); process.exit((major === 20 && minor >= 19) || (major === 22 && minor >= 12) || major >= 23 ? 0 : 1)"
if errorlevel 1 goto NODE_TOO_OLD

call node -e "const cp = require('node:child_process'); const npm = cp.execSync('npm -v', { encoding: 'utf8' }).trim(); const [major, minor] = npm.split('.').map(Number); process.exit(major === 11 && minor >= 10 && minor < 17 ? 1 : 0)"
if errorlevel 1 goto NPM_UNSUPPORTED

set "NODE_MAJOR="
for /f "delims=." %%A in ('node -p "process.versions.node"') do set "NODE_MAJOR=%%A"

set "NEED_INSTALL="
if not exist "%REPO_DIR%\node_modules\vite\package.json" set "NEED_INSTALL=1"
if not exist "%REPO_DIR%\node_modules\esbuild\package.json" set "NEED_INSTALL=1"
if not exist "%REPO_DIR%\node_modules\electron-builder\package.json" set "NEED_INSTALL=1"
if not exist "%REPO_DIR%\node_modules\builder-util\package.json" set "NEED_INSTALL=1"
if not exist "%REPO_DIR%\node_modules\app-builder-lib\package.json" set "NEED_INSTALL=1"
if not exist "%REPO_DIR%\node_modules\js-yaml\package.json" set "NEED_INSTALL=1"
if not exist "%REPO_DIR%\node_modules\cross-env\package.json" set "NEED_INSTALL=1"
if not exist "%REPO_DIR%\node_modules\electron\package.json" set "NEED_INSTALL=1"
if not exist "%REPO_DIR%\node_modules\node-pty\package.json" set "NEED_INSTALL=1"

if defined NEED_INSTALL call :INSTALL_DEPS
if errorlevel 1 exit /b 1

call node -e "for (const m of ['vite','esbuild','electron-builder','builder-util','app-builder-lib','js-yaml','electron','node-pty']) require.resolve(m + '/package.json')" >"%QUIET_LOG%" 2>&1
if errorlevel 1 call :INSTALL_DEPS
if errorlevel 1 exit /b 1

call :CHECK_DESKTOP_DEPS
if errorlevel 1 call :INSTALL_DEPS
if errorlevel 1 exit /b 1

call :CHECK_DESKTOP_DEPS
if errorlevel 1 goto DESKTOP_DEPS_FAILED

call node -e "const esbuild = require('esbuild'); const path = require('node:path'); esbuild.buildSync({ entryPoints: [path.resolve('apps/desktop/electron/preload.ts')], write: false, bundle: false, platform: 'node', format: 'cjs', target: 'node20', logLevel: 'silent' });" >"%QUIET_LOG%" 2>&1
if errorlevel 1 goto ESBUILD_PREFLIGHT_FAILED

echo.
echo Building Hermes desktop app
echo Repo: %REPO_DIR%
echo Script: %BUILD_SCRIPT%
echo Node: %NODE_EXE%
echo npm: %NPM_EXE%
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
echo Install Node.js 22 LTS and npm, then run this script again.
exit /b 1

:NO_NODE
echo ERROR: node.exe not found in PATH.
echo Install Node.js 22 LTS and npm, then run this script again.
exit /b 1

:NODE_TOO_OLD
echo ERROR: Node.js is too old for the desktop build.
echo Required: Node.js 20.19+ or 22.12+.
echo Current:
node -v
exit /b 1

:NPM_UNSUPPORTED
echo ERROR: npm is not supported by this checkout.
echo Required: npm ^<11.10.0 or ^>=11.17.0.
echo Current:
npm -v
echo.
echo Fix:
echo   npm install -g npm@11.17.0
exit /b 1

:INSTALL_DEPS
echo Installing or repairing root workspace dependencies...
call npm.cmd install --no-audit --fund=false
if errorlevel 1 goto INSTALL_FAILED
exit /b 0

:CHECK_DESKTOP_DEPS
call npm.cmd ls --workspace apps/desktop --depth=0 --omit=optional --silent >"%QUIET_LOG%" 2>&1
exit /b %ERRORLEVEL%

:INSTALL_FAILED
echo ERROR: npm install failed.
echo Run this from the repo root, then retry:
echo   npm install --no-audit --fund=false
exit /b 1

:DESKTOP_DEPS_FAILED
echo ERROR: desktop workspace dependencies are missing or out of sync.
echo.
type "%QUIET_LOG%"
echo.
echo Run this from the repo root, then retry:
echo   npm install --no-audit --fund=false
exit /b 1

:ESBUILD_PREFLIGHT_FAILED
echo ERROR: esbuild cannot read the Electron desktop source files from this shell.
echo.
>>"%QUIET_LOG%" echo.
>>"%QUIET_LOG%" echo Try these fixes:
>>"%QUIET_LOG%" echo   1. Open a normal PowerShell/CMD window, cd to this repo, then run buildappdesktop.bat again.
>>"%QUIET_LOG%" echo   2. Run npm install from the repo root to repair node_modules.
>>"%QUIET_LOG%" echo   3. Make sure the build process can read parent folders such as %USERPROFILE%.
>>"%QUIET_LOG%" echo.
>>"%QUIET_LOG%" echo esbuild details:
type "%QUIET_LOG%"
exit /b 1

:BUILD_FAILED
echo ERROR: desktop build failed.
exit /b 1
