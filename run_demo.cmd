@echo off
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
set "SERVER_URL=http://127.0.0.1:8000/index.html"
set "PYTHON_CMD="

pushd "%SCRIPT_DIR%"

call :find_python
if errorlevel 1 goto :fail

call :check_server
if not errorlevel 1 goto :launch

echo Starting local HTTP server from:
echo   %CD%
echo.

start "VSSM HTTP Server" /MIN cmd /c "%PYTHON_CMD% -m http.server 8000"

echo Waiting for server to become ready...
for /L %%I in (1,1,20) do (
  timeout /t 1 /nobreak >nul
  call :check_server
  if not errorlevel 1 goto :launch
)

echo Failed to start the local HTTP server on port 8000.
goto :fail

:launch
echo Opening demo...
call "%SCRIPT_DIR%launch_webgpu_chrome.cmd" "%SERVER_URL%"
goto :done

:find_python
where py >nul 2>&1
if not errorlevel 1 (
  set "PYTHON_CMD=py -3"
  exit /b 0
)
where python >nul 2>&1
if not errorlevel 1 (
  set "PYTHON_CMD=python"
  exit /b 0
)
echo Python was not found in PATH.
echo Install Python or use open_file_mode.cmd instead.
exit /b 1

:check_server
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "try { $r = Invoke-WebRequest -UseBasicParsing -Uri '%SERVER_URL%' -TimeoutSec 2; if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 500) { exit 0 } else { exit 1 } } catch { exit 1 }" >nul 2>&1
exit /b %errorlevel%

:fail
echo.
echo The demo launcher could not continue.
pause

:done
popd
endlocal
