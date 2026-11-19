[CmdletBinding()]
param([string]$ViewerPath)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$settings = Get-Content -LiteralPath (Join-Path $projectRoot '.local\install.json') -Raw | ConvertFrom-Json
$loginUri = "http://127.0.0.1:$([int]$settings.worldPort)"
if (-not $ViewerPath) {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'AuroraViewer\Aurora.exe'),
        (Join-Path $env:ProgramFiles 'Aurora Viewer\Aurora.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Aurora Viewer\Aurora.exe')
    )
    $ViewerPath = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (-not $ViewerPath) { throw 'Aurora Viewer was not found. Run with -ViewerPath "C:\path\to\Aurora.exe".' }
if (-not (Test-Path -LiteralPath $ViewerPath -PathType Leaf)) { throw "Viewer executable not found: $ViewerPath" }
Start-Process -FilePath $ViewerPath -ArgumentList @('--loginuri', $loginUri)
Write-Output "Started Aurora with local login URI $loginUri. This command does not import or alter avatar inventory."
