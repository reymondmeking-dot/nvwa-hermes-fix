[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$fixture = Join-Path ([IO.Path]::GetTempPath()) ("nvwa-hermes-bat-" + [guid]::NewGuid().ToString('N'))
$oldPath = $env:PATH

try {
    New-Item -ItemType Directory -Path $fixture | Out-Null
    @'
@echo off
if /i "%~1"=="query" (
  echo HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Internet Settings
  if /i "%~4"=="ProxyServer" echo     ProxyServer    REG_SZ    http://proxy-user:super-secret@proxy.invalid:8080
  if /i "%~4"=="ProxyEnable" echo     ProxyEnable    REG_DWORD    0x1
  if /i "%~4"=="AutoConfigURL" echo     AutoConfigURL    REG_SZ    https://pac.invalid/config.pac?token=pac-secret
  exit /b 0
)
echo MUTATION_CALLED
exit /b 99
'@ | Set-Content -LiteralPath (Join-Path $fixture 'reg.cmd') -Encoding Ascii

    $env:PATH = "$fixture;$oldPath"
    Push-Location $root
    try {
        $output = (& .\Fix-Hermes-Proxy.bat --dry-run --no-kill --no-pause 2>&1) -join "`n"
        if ($LASTEXITCODE -ne 0) {
            throw "Batch dry run failed with exit code $LASTEXITCODE`n$output"
        }
    } finally {
        Pop-Location
    }

    foreach ($secret in 'proxy-user', 'super-secret', 'pac-secret', 'MUTATION_CALLED') {
        if ($output.Contains($secret)) {
            throw "Batch output disclosed or executed forbidden fixture value: $secret"
        }
    }
    foreach ($expected in '[configured; value redacted]', 'enabled (0x1)', 'DRY-RUN') {
        if (-not $output.Contains($expected)) {
            throw "Batch output did not contain expected marker: $expected`n$output"
        }
    }
} finally {
    $env:PATH = $oldPath
    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
}
