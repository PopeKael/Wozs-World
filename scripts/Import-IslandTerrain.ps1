[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$TerrainPath
)

# Explicit operation for one installation only. It is deliberately not called
# by Start-World.ps1. After a graceful stop, also run Persist-ImportedTerrain.ps1.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$serverBin = Join-Path $projectRoot 'server\OpenSimulator-0.9.3.0\bin'
$openSimIni = Join-Path $serverBin 'OpenSim.ini'
$statePath = Join-Path $projectRoot '.local\opensim-process.json'
$baseUri = $null
$terrainPath = [System.IO.Path]::GetFullPath($TerrainPath)

if (-not (Test-Path -LiteralPath $terrainPath -PathType Leaf)) {
    throw "Terrain file not found: $terrainPath"
}
if ((Get-Item -LiteralPath $terrainPath).Length -ne 1048576) {
    throw 'Expected one native 512 x 512 R32 heightmap (1,048,576 bytes).'
}
if (-not (Test-Path -LiteralPath $statePath)) {
    throw 'No managed simulator is recorded. Start it with scripts\Start-World.ps1 first.'
}

$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
$baseUri = "http://127.0.0.1:$([int]$state.HttpPort)"
$serverProcess = Get-Process -Id ([int]$state.ProcessId) -ErrorAction SilentlyContinue
$dotnet = Join-Path $projectRoot 'runtime\dotnet8\dotnet.exe'
if (-not $serverProcess -or -not $serverProcess.Path -or
    [System.IO.Path]::GetFullPath($serverProcess.Path) -ne [System.IO.Path]::GetFullPath($dotnet)) {
    throw 'The recorded project-local simulator process is not running.'
}

$iniText = [System.IO.File]::ReadAllText($openSimIni)
$userMatch = [regex]::Match($iniText, '(?m)^\s*ConsoleUser\s*=\s*"([^"]+)"')
$passMatch = [regex]::Match($iniText, '(?m)^\s*ConsolePass\s*=\s*"([^"]+)"')
if (-not $userMatch.Success -or -not $passMatch.Success -or
    $passMatch.Groups[1].Value -eq '__GENERATE_LOCAL_ONLY__') {
    throw 'The loopback REST console credentials are missing from the ignored local configuration.'
}

function Read-SharedLog([string]$Path) {
    $stream = [System.IO.FileStream]::new(
        $Path,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite
    )
    $reader = [System.IO.StreamReader]::new($stream)
    try { return $reader.ReadToEnd() }
    finally { $reader.Dispose() }
}

$sessionId = $null
try {
    $sessionResponse = Invoke-WebRequest -UseBasicParsing -Uri "$baseUri/StartSession/" `
        -Method Post -Body @{ USER = $userMatch.Groups[1].Value; PASS = $passMatch.Groups[1].Value } -TimeoutSec 10
    [xml]$sessionXml = $sessionResponse.Content
    $sessionId = [string]$sessionXml.ConsoleSession.SessionID
    if (-not $sessionId) { throw 'The REST console did not return a session ID.' }

    $commands = @(
        ('terrain load "' + $terrainPath + '"'),
        'set terrain heights -1 28 70',
        'terrain stats'
    )
    $logPath = [string]$state.StdoutLog
    $startOffset = (Read-SharedLog $logPath).Length
    foreach ($consoleCommand in $commands) {
        $commandResponse = Invoke-WebRequest -UseBasicParsing -Uri "$baseUri/SessionCommand/" `
            -Method Post -Body @{ ID = $sessionId; COMMAND = $consoleCommand } -TimeoutSec 10
        [xml]$commandXml = $commandResponse.Content
        if ([string]$commandXml.ConsoleSession.Result -ne 'OK') {
            throw "REST console rejected command: $consoleCommand"
        }
    }

    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    $statsMatch = $null
    while ([DateTime]::UtcNow -lt $deadline) {
        $logText = Read-SharedLog $logPath
        if ($logText.Length -gt $startOffset) {
            $newText = $logText.Substring($startOffset)
            $statsMatch = [regex]::Match(
                $newText,
                '(?s)terrain stats\s+Channel 512x512\s+max/min/avg/sum:\s*([-+0-9.]+)/([-+0-9.]+)/'
            )
            if ($statsMatch.Success) { break }
        }
        Start-Sleep -Milliseconds 200
    }
    if (-not $statsMatch -or -not $statsMatch.Success) {
        throw "No 512 x 512 terrain statistics followed the import. Inspect $logPath."
    }

    $maximum = [double]::Parse($statsMatch.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture)
    $minimum = [double]::Parse($statsMatch.Groups[2].Value, [Globalization.CultureInfo]::InvariantCulture)
if ($maximum -le 25 -or $minimum -ge 20) {
        throw "Unexpected terrain range from OpenSimulator: $minimum to $maximum m. Inspect $logPath."
    }

    Write-Output "Imported: $terrainPath"
    Write-Output "OpenSimulator channel: 512 x 512; terrain range: $minimum to $maximum m."
    Write-Output 'Texture thresholds set to 28 m and 70 m at all four corners.'
    Write-Output "Console log: $logPath"
}
finally {
    if ($sessionId) {
        try {
            Invoke-WebRequest -UseBasicParsing -Uri "$baseUri/CloseSession/" `
                -Method Post -Body @{ ID = $sessionId } -TimeoutSec 10 | Out-Null
        }
        catch { Write-Warning "Could not close the temporary REST console session $sessionId." }
    }
}
