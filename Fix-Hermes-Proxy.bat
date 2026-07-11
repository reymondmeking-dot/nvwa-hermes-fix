@echo off
setlocal EnableDelayedExpansion
set "VERSION=1.1.1"
set "DRY_RUN=0"
set "NO_KILL=0"
set "NO_PAUSE=0"

:parse_args
if "%~1"=="" goto args_done
if /i "%~1"=="--dry-run" (
  set "DRY_RUN=1"
  shift
  goto parse_args
)
if /i "%~1"=="--no-kill" (
  set "NO_KILL=1"
  shift
  goto parse_args
)
if /i "%~1"=="--no-pause" (
  set "NO_PAUSE=1"
  shift
  goto parse_args
)
if /i "%~1"=="--version" (
  echo %VERSION%
  exit /b 0
)
if /i "%~1"=="--help" goto show_help
if /i "%~1"=="-h" goto show_help
echo Unknown option: %~1 1>&2
exit /b 2

:show_help
echo Usage: %~nx0 [--dry-run] [--no-kill] [--no-pause] [--version]
exit /b 0

:args_done
chcp 65001 >nul 2>&1
title Fix Hermes "API call failed: Connection error"

echo ============================================================
echo  Hermes API Connection Error - Fix Tool
echo  Version : %VERSION%
echo  ---------------------------------------------------------
echo  Symptom : "API call failed after 3 retries: Connection error"
echo  Root    : Ghost proxy (e.g. 127.0.0.1:19828) left in WinInet
echo            registry by a VPN/proxy app. Python/httpx picks
echo            it up on startup and all API traffic dies on a
echo            dead port.
echo  Action  : Clear WinInet proxy + kill Hermes backend so it
echo            reboots with a clean HTTP client.
echo  Scope   : Current user (HKCU) only. No admin needed.
if "%DRY_RUN%"=="1" echo  Mode    : DRY-RUN (no changes will be made)
echo ============================================================
echo.

REM --- 1) Show current state -------------------------------------------------
echo [1/4] Current WinInet proxy state:
call :ShowProxyState
echo.

REM --- 2) Clear WinInet proxy (User scope) ----------------------------------
echo [2/4] Clearing WinInet ProxyServer / disabling ProxyEnable ...
if "%DRY_RUN%"=="1" (
  echo         ^(dry^) registry values would be cleared.
) else (
  call reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyServer   /t REG_SZ    /d ""  /f >nul 2>&1
  call reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable   /t REG_DWORD /d 0   /f >nul 2>&1
  call reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v AutoConfigURL /t REG_SZ    /d ""  /f >nul 2>&1
  echo         done.
)
echo.

REM --- 3) Kill Hermes backend (desktop shell + gateway + slash_workers) -----
REM     Uses PowerShell + CIM (works on Win10/11 with or without wmic;
REM     wmic was removed in Windows 11 24H2 so we cannot rely on it).
echo [3/4] Stopping Hermes backend processes ...
if "%NO_KILL%"=="1" goto skip_kill
if "%DRY_RUN%"=="1" goto dry_skip_kill
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$killed = 0;" ^
  "Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | ForEach-Object {" ^
  "  $exe = if ($_.ExecutablePath) { $_.ExecutablePath.ToLower() } else { '' };" ^
  "  $cmd = if ($_.CommandLine)   { $_.CommandLine.ToLower()   } else { '' };" ^
  "  $name= if ($_.Name)          { $_.Name.ToLower()          } else { '' };" ^
  "  $hit = $false;" ^
  "  if ($exe -match '\\\\hermes\\\\')                                    { $hit = $true }" ^
  "  elseif ($name -eq 'hermes.exe')                                      { $hit = $true }" ^
  "  elseif (($name -eq 'python.exe' -or $name -eq 'pythonw.exe') -and" ^
  "          ($cmd -match 'hermes_cli' -or $cmd -match 'tui_gateway' -or" ^
  "           $cmd -match 'slash_worker' -or $cmd -match 'hermes\\.gateway')) { $hit = $true }" ^
  "  if ($hit) {" ^
  "    Write-Host ('         killing pid {0}  ({1})' -f $_.ProcessId, $_.Name);" ^
  "    try { Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop; $script:killed++ } catch {}" ^
  "  }" ^
  "};" ^
  "Write-Host ('         done. killed ' + $killed + ' process(es).')"
goto after_kill
:skip_kill
echo         --no-kill: skipping.
goto after_kill
:dry_skip_kill
echo         ^(dry^) matching Hermes processes would be stopped.
:after_kill
echo.

REM --- 4) Notify WinInet listeners so any survivor re-reads the setting -----
echo [4/4] Broadcasting WinInet settings-changed ...
if "%DRY_RUN%"=="1" goto dry_skip_broadcast
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Add-Type -Namespace WI -Name Api -MemberDefinition '[DllImport(\"wininet.dll\", SetLastError=true)] public static extern bool InternetSetOption(IntPtr h, int o, IntPtr b, int l);';" ^
  "[void][WI.Api]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0);" ^
  "[void][WI.Api]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0);" ^
  "Write-Host '         done.'"
goto after_broadcast
:dry_skip_broadcast
echo         ^(dry^) WinInet listeners would be notified.
:after_broadcast
echo.

REM --- Report -----------------------------------------------------------
echo ============================================================
echo  Post-fix WinInet proxy state:
call :ShowProxyState
echo.
if "%NO_KILL%"=="1" (
  echo  Hermes backend was not stopped ^(--no-kill^). To restart manually:
) else if "%DRY_RUN%"=="1" (
  echo  Dry run complete; no Hermes process was stopped.
) else (
  echo  Hermes backend has been stopped. To restart:
)
echo    * Double-click your Hermes desktop / Start Menu shortcut, OR
echo    * Look for Hermes.exe under one of:
echo         %LOCALAPPDATA%\Programs\hermes\Hermes.exe
echo         %LOCALAPPDATA%\hermes\hermes-agent\apps\desktop\release\win-unpacked\Hermes.exe
echo.
echo  New Hermes processes will read the clean proxy setting and
echo  reach the API directly.
echo ============================================================
echo.
if "%NO_PAUSE%"=="0" pause
endlocal
exit /b 0

:ShowProxyState
call reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyServer >nul 2>&1
if errorlevel 1 (
  echo         ProxyServer  = [unset]
) else (
  echo         ProxyServer  = [configured; value redacted]
)

set "PROXY_ENABLE="
for /f "tokens=3" %%A in ('call reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable 2^>nul ^| findstr /i /c:"ProxyEnable"') do set "PROXY_ENABLE=%%A"
if not defined PROXY_ENABLE (
  echo         ProxyEnable  = [unset]
) else if /i "!PROXY_ENABLE!"=="0x0" (
  echo         ProxyEnable  = disabled ^(0x0^)
) else if /i "!PROXY_ENABLE!"=="0x1" (
  echo         ProxyEnable  = enabled ^(0x1^)
) else (
  echo         ProxyEnable  = [configured]
)

call reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v AutoConfigURL >nul 2>&1
if errorlevel 1 (
  echo         AutoConfigURL= [unset]
) else (
  echo         AutoConfigURL= [configured; value redacted]
)
exit /b 0
