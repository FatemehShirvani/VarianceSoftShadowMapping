@echo off
setlocal EnableExtensions

set "CHROME_EXE=C:\Program Files\Google\Chrome\Application\chrome.exe"
if not exist "%CHROME_EXE%" (
  echo Chrome not found at:
  echo   %CHROME_EXE%
  exit /b 1
)

set "TARGET_URL=%~1"
if "%TARGET_URL%"=="" (
  set "CACHE_BUST=%RANDOM%%RANDOM%%RANDOM%"
  for %%I in ("%~dp0index.html") do set "INDEX_FULL=%%~fI"
  set "TARGET_URL=file:///%INDEX_FULL:\=/%?build=%CACHE_BUST%"
)

set "PROFILE_DIR=%TEMP%\vssm_webgpu_submission_profile"

echo Launching Chrome:
echo   %TARGET_URL%
echo.

start "" "%CHROME_EXE%" ^
  --user-data-dir="%PROFILE_DIR%" ^
  --no-first-run ^
  --no-default-browser-check ^
  --new-window ^
  --disable-extensions ^
  --enable-unsafe-webgpu ^
  --ignore-gpu-blocklist ^
  --force-high-performance-gpu ^
  --allow-file-access-from-files ^
  "%TARGET_URL%"

endlocal
