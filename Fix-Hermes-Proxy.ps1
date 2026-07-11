<#
.SYNOPSIS
    Fix-Hermes-Proxy.ps1 — Windows PowerShell CLI 版本

.DESCRIPTION
    与 Fix-Hermes-Proxy.bat 完全等价的 4 步（清 WinInet 代理 + 杀 Hermes 后端 +
    广播 settings-changed），但更适合从终端/脚本里调用。

.EXAMPLE
    # 下载、检查后执行：
    Invoke-WebRequest https://raw.githubusercontent.com/reymondmeking-dot/nvwa-hermes-fix/main/Fix-Hermes-Proxy.ps1 -OutFile Fix-Hermes-Proxy.ps1

.EXAMPLE
    # 下载后本地跑：
    .\Fix-Hermes-Proxy.ps1
    .\Fix-Hermes-Proxy.ps1 -DryRun
    .\Fix-Hermes-Proxy.ps1 -NoKill
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$DryRun,
    [switch]$NoKill,
    [switch]$Version
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$IS = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
$script:CommandContext = $PSCmdlet

if ($Version) {
    Write-Output '1.1.1'
    return
}

function Step($n, $msg) { Write-Host "`n[$n] $msg" -ForegroundColor Cyan }
function Invoke-Change($label, [scriptblock]$block) {
    if ($DryRun) {
        Write-Host "  (dry) $label" -ForegroundColor DarkGray
        return
    }
    if ($script:CommandContext.ShouldProcess($label)) {
        & $block
    }
}
function Show-ProxyState {
    foreach ($v in 'ProxyServer','ProxyEnable','AutoConfigURL') {
        $item = Get-ItemProperty -Path $IS -Name $v -ErrorAction SilentlyContinue
        if ($null -eq $item) {
            $val = '<unset>'
        } elseif ($v -eq 'ProxyEnable') {
            $val = if ([int]$item.$v -eq 0) { 'disabled (0)' } else { 'enabled (1)' }
        } elseif ([string]::IsNullOrEmpty([string]$item.$v)) {
            $val = '<empty>'
        } else {
            $val = '<configured; value redacted>'
        }
        Write-Host ('  {0,-14}= {1}' -f $v, $val)
    }
}

Write-Host '============================================================'
Write-Host ' Hermes API Connection Error - Fix Tool (PowerShell)'
Write-Host ' ---------------------------------------------------------'
Write-Host ' Symptom : API call failed after 3 retries: Connection error'
Write-Host ' Root    : Ghost WinInet proxy left by VPN/proxy software.'
Write-Host ' Scope   : HKCU only. No admin needed.'
if ($DryRun) { Write-Host ' Mode    : DRY-RUN (no changes will be made)' -ForegroundColor Yellow }
Write-Host '============================================================'

# --- 1) Show state ---
Step '1/4' 'Current WinInet proxy state:'
Show-ProxyState

# --- 2) Clear WinInet proxy ---
Step '2/4' 'Clearing WinInet ProxyServer / ProxyEnable / AutoConfigURL ...'
if (-not (Test-Path -LiteralPath $IS)) {
    throw "WinInet settings key not found: $IS"
}
Invoke-Change 'Set ProxyServer=""'   { Set-ItemProperty -Path $IS -Name ProxyServer   -Value '' -Type String }
Invoke-Change 'Set ProxyEnable=0'    { Set-ItemProperty -Path $IS -Name ProxyEnable   -Value 0  -Type DWord }
Invoke-Change 'Set AutoConfigURL=""' { Set-ItemProperty -Path $IS -Name AutoConfigURL -Value '' -Type String }
Write-Host '  done.'

# --- 3) Stop Hermes backend ---
Step '3/4' 'Stopping Hermes backend processes ...'
if ($NoKill) {
    Write-Host '  -NoKill: skipping.'
} else {
    $killed = 0
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | ForEach-Object {
        $exe  = if ($_.ExecutablePath) { $_.ExecutablePath.ToLower() } else { '' }
        $cmd  = if ($_.CommandLine)    { $_.CommandLine.ToLower()    } else { '' }
        $name = if ($_.Name)           { $_.Name.ToLower()           } else { '' }
        $hit  = $false
        if     ($exe  -match '\\hermes\\')                                    { $hit = $true }
        elseif ($name -eq 'hermes.exe')                                       { $hit = $true }
        elseif (($name -eq 'python.exe' -or $name -eq 'pythonw.exe') -and
                ($cmd -match 'hermes_cli|tui_gateway|slash_worker|hermes\.gateway')) { $hit = $true }
        if ($hit -and $_.ProcessId -ne $PID) {
            $processId = [int]$_.ProcessId
            $processName = [string]$_.Name
            Write-Host ('  killing pid {0} ({1})' -f $processId, $processName)
            Invoke-Change "Stop-Process $processId" {
                Stop-Process -Id $processId -Force
                $script:killed++
            }
        }
    }
    if (-not $DryRun) { Write-Host "  done. killed $killed process(es)." }
}

# --- 4) Broadcast WinInet settings-changed ---
Step '4/4' 'Broadcasting WinInet settings-changed ...'
Invoke-Change 'InternetSetOption(SETTINGS_CHANGED + REFRESH)' {
    if (-not ('WI.Api' -as [type])) {
        Add-Type -Namespace WI -Name Api -MemberDefinition '[DllImport("wininet.dll", SetLastError=true)] public static extern bool InternetSetOption(IntPtr h, int o, IntPtr b, int l);'
    }
    [void][WI.Api]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0)
    [void][WI.Api]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0)
}
Write-Host '  done.'

Write-Host "`n============================================================"
Write-Host ' Post-fix state:'
Show-ProxyState
Write-Host ''
Write-Host ' Restart Hermes from your desktop / Start Menu shortcut.'
Write-Host '============================================================'
