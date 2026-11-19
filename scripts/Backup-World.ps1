[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$serverRoot = Join-Path $projectRoot 'server\OpenSimulator-0.9.3.0'
$serverBin = Join-Path $serverRoot 'bin'
$statePath = Join-Path $projectRoot '.local\opensim-process.json'
$backupRoot = Join-Path $projectRoot 'backups'
$tar = Join-Path $env:WINDIR 'System32\tar.exe'

if (-not (Test-Path -LiteralPath (Join-Path $serverBin 'OpenSim.dll'))) {
    throw "OpenSimulator binaries were not found under '$serverBin'."
}
if (Test-Path -LiteralPath $statePath) {
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    if (Get-Process -Id ([int]$state.ProcessId) -ErrorAction SilentlyContinue) {
        throw "The simulator is running (PID $($state.ProcessId)). Stop it with scripts\Stop-World.ps1 before a cold backup."
    }
}

$install = Get-Content -LiteralPath (Join-Path $projectRoot '.local\install.json') -Raw | ConvertFrom-Json
$tcpProbe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, [int]$install.worldPort)
$tcpFree = $false
try {
    $tcpProbe.Start()
    $tcpFree = $true
}
catch { }
finally { $tcpProbe.Stop() }
if (-not $tcpFree) {
    throw "TCP/$($install.worldPort) is still occupied. Refusing a cold backup of a live or unrelated simulator, even if this PowerShell context cannot connect to it."
}
if (-not (Test-Path -LiteralPath $tar)) {
    throw "Windows tar.exe was not found at '$tar'."
}

New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$archivePath = Join-Path $backupRoot "WozsWorld-$timestamp.zip"
if (Test-Path -LiteralPath $archivePath) { throw "Backup already exists: $archivePath" }

& $tar -a -c -f $archivePath -C $serverRoot bin
if ($LASTEXITCODE -ne 0) { throw "tar.exe failed with exit code $LASTEXITCODE. The archive may be incomplete: $archivePath" }

$listing = & $tar -t -f $archivePath
if ($LASTEXITCODE -ne 0) { throw "Could not list the new archive: $archivePath" }
if (-not ($listing -match 'bin[/\\]OpenSim\.dll')) { throw 'Backup archive is missing the OpenSimulator executable.' }
if (-not ($listing -match 'bin[/\\]Regions[/\\]Regions\.ini')) { throw 'Backup archive is missing the region configuration.' }

$info = Get-Item -LiteralPath $archivePath
$hash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
Write-Output "Cold backup created and listed: $archivePath"
Write-Output "Bytes: $($info.Length)"
Write-Output "SHA-256: $hash"
Write-Output 'Contents include the complete server bin tree: binaries, local config, region state, SQLite stores, and asset data.'
