<#
.SYNOPSIS
    Fix-Hermes-Proxy.ps1 — Windows PowerShell CLI 版本

.DESCRIPTION
    与 Fix-Hermes-Proxy.bat 完全等价的 4 步（清 WinInet 代理 + 杀 Hermes 后端 +
    广播 settings-changed），但更适合从终端/脚本里调用。

.EXAMPLE
    # 一行直取执行（不落盘）：
    iwr -useb https://raw.githubusercontent.com/reymondmeking-dot/nvwa-hermes-fix/main/Fix-Hermes-Proxy.ps1 | iex

.EXAMPLE
    # 下载后本地跑：
    .\Fix-Hermes-Proxy.ps1
    .\Fix-Hermes-Proxy.ps1 -DryRun
    .\Fix-Hermes-Proxy.ps1 -NoKill
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$NoKill
)

$ErrorActionPreference = 'Continue'
$IS = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'

function Step($n, $msg) { Write-Host "`n[$n] $msg" -ForegroundColor Cyan }
function Do-It($label, [scriptblock]$block) {
    if ($DryRun) { Write-Host "  (dry) $label" -ForegroundColor DarkGray }
    else        { & $block }
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
foreach ($v in 'ProxyServer','ProxyEnable','AutoConfigURL') {
    $val = (Get-ItemProperty -Path $IS -Name $v -ErrorAction SilentlyContinue).$v
    if ($null -eq $val) { $val = '<unset>' }
    Write-Host ('  {0,-14}= {1}' -f $v, $val)
}

# --- 2) Clear WinInet proxy ---
Step '2/4' 'Clearing WinInet ProxyServer / ProxyEnable / AutoConfigURL ...'
Do-It 'Set ProxyServer=""'   { Set-ItemProperty -Path $IS -Name ProxyServer   -Value ''  -Type String }
Do-It 'Set ProxyEnable=0'    { Set-ItemProperty -Path $IS -Name ProxyEnable   -Value 0   -Type DWord }
Do-It 'Set AutoConfigURL=""' { Set-ItemProperty -Path $IS -Name AutoConfigURL -Value ''  -Type String }
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
            Write-Host ('  killing pid {0} ({1})' -f $_.ProcessId, $_.Name)
            Do-It "Stop-Process $($_.ProcessId)" {
                try { Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop; $script:killed++ } catch {}
            }
        }
    }
    if (-not $DryRun) { Write-Host "  done. killed $killed process(es)." }
}

# --- 4) Broadcast WinInet settings-changed ---
Step '4/4' 'Broadcasting WinInet settings-changed ...'
Do-It 'InternetSetOption(SETTINGS_CHANGED + REFRESH)' {
    Add-Type -Namespace WI -Name Api -MemberDefinition '[DllImport("wininet.dll", SetLastError=true)] public static extern bool InternetSetOption(IntPtr h, int o, IntPtr b, int l);' -ErrorAction SilentlyContinue
    [void][WI.Api]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0)
    [void][WI.Api]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0)
}
Write-Host '  done.'

Write-Host "`n============================================================"
Write-Host ' Post-fix state:'
foreach ($v in 'ProxyServer','ProxyEnable','AutoConfigURL') {
    $val = (Get-ItemProperty -Path $IS -Name $v -ErrorAction SilentlyContinue).$v
    if ($null -eq $val) { $val = '<unset>' }
    Write-Host ('  {0,-14}= {1}' -f $v, $val)
}
Write-Host ''
Write-Host ' Restart Hermes from your desktop / Start Menu shortcut.'
Write-Host '============================================================'
