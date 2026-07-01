@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul 2>&1
title Fix Hermes "API call failed: Connection error"

echo ============================================================
echo  Hermes API Connection Error - Fix Tool
echo  ---------------------------------------------------------
echo  Symptom : "API call failed after 3 retries: Connection error"
echo  Root    : Ghost proxy (e.g. 127.0.0.1:19828) left in WinInet
echo            registry by a VPN/proxy app. Python/httpx picks
echo            it up on startup and all API traffic dies on a
echo            dead port.
echo  Action  : Clear WinInet proxy + kill Hermes backend so it
echo            reboots with a clean HTTP client.
echo  Scope   : Current user (HKCU) only. No admin needed.
echo ============================================================
echo.

REM --- 1) Show current state -------------------------------------------------
echo [1/4] Current WinInet proxy state:
for /f "tokens=2,*" %%A in ('reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyServer 2^>nul ^| findstr /i ProxyServer') do echo         ProxyServer  = %%B
for /f "tokens=2,*" %%A in ('reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable 2^>nul ^| findstr /i ProxyEnable') do echo         ProxyEnable  = %%B
for /f "tokens=2,*" %%A in ('reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v AutoConfigURL 2^>nul ^| findstr /i AutoConfigURL') do echo         AutoConfigURL= %%B
echo.

REM --- 2) Clear WinInet proxy (User scope) ----------------------------------
echo [2/4] Clearing WinInet ProxyServer / disabling ProxyEnable ...
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyServer   /t REG_SZ    /d ""  /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable   /t REG_DWORD /d 0   /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v AutoConfigURL /t REG_SZ    /d ""  /f >nul 2>&1
echo         done.
echo.

REM --- 3) Kill Hermes backend (desktop shell + gateway + slash_workers) -----
REM     Uses PowerShell + CIM (works on Win10/11 with or without wmic;
REM     wmic was removed in Windows 11 24H2 so we cannot rely on it).
echo [3/4] Stopping Hermes backend processes ...
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
echo.

REM --- 4) Notify WinInet listeners so any survivor re-reads the setting -----
echo [4/4] Broadcasting WinInet settings-changed ...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Add-Type -Namespace WI -Name Api -MemberDefinition '[DllImport(\"wininet.dll\", SetLastError=true)] public static extern bool InternetSetOption(IntPtr h, int o, IntPtr b, int l);';" ^
  "[void][WI.Api]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0);" ^
  "[void][WI.Api]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0);" ^
  "Write-Host '         done.'"
echo.

REM --- Report -----------------------------------------------------------
echo ============================================================
echo  Post-fix WinInet proxy state:
for /f "tokens=2,*" %%A in ('reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyServer 2^>nul ^| findstr /i ProxyServer') do echo         ProxyServer  = %%B
for /f "tokens=2,*" %%A in ('reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable 2^>nul ^| findstr /i ProxyEnable') do echo         ProxyEnable  = %%B
for /f "tokens=2,*" %%A in ('reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v AutoConfigURL 2^>nul ^| findstr /i AutoConfigURL') do echo         AutoConfigURL= %%B
echo.
echo  Hermes backend has been stopped. To restart:
echo    * Double-click your Hermes desktop / Start Menu shortcut, OR
echo    * Look for Hermes.exe under one of:
echo         %LOCALAPPDATA%\Programs\hermes\Hermes.exe
echo         %LOCALAPPDATA%\hermes\hermes-agent\apps\desktop\release\win-unpacked\Hermes.exe
echo.
echo  New Hermes processes will read the clean proxy setting and
echo  reach the API directly.
echo ============================================================
echo.
pause
endlocal
