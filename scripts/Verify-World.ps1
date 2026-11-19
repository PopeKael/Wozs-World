[CmdletBinding()]
param(
    [switch]$RequireRunning
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$serverBin = Join-Path $projectRoot 'server\OpenSimulator-0.9.3.0\bin'
$openSimIni = Join-Path $serverBin 'OpenSim.ini'
$regionsIni = Join-Path $serverBin 'Regions\Regions.ini'
$sqliteDll = Join-Path $serverBin 'sqlite3.dll'
$install = Get-Content -LiteralPath (Join-Path $projectRoot '.local\install.json') -Raw | ConvertFrom-Json
$worldPort = [int]$install.worldPort

foreach ($requiredPath in @($openSimIni, $regionsIni, $sqliteDll)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) { throw "Required config is missing: $requiredPath" }
}

$sqliteHash = (Get-FileHash -LiteralPath $sqliteDll -Algorithm SHA256).Hash
if ($sqliteHash -ne '4B59D3CDED9DC1608544160F3B4B10AC974C6AC0D6FFC23064E5F4C8DBD05AEA') {
    throw "The project-local SQLite runtime failed its SHA-256 check: $sqliteHash"
}

$regionText = [System.IO.File]::ReadAllText($regionsIni)
$regionSections = [regex]::Matches($regionText, '(?m)^\s*\[([^\]]+)\]\s*$')
if ($regionSections.Count -ne 1 -or $regionSections[0].Groups[1].Value -ne "Woz's World") {
    throw "Expected exactly one [Woz's World] region section; found $($regionSections.Count)."
}
foreach ($requiredSetting in @('SizeX = 512', 'SizeY = 512', "InternalPort = $worldPort", 'InternalAddress = 127.0.0.1', 'ExternalHostName = 127.0.0.1', 'AllowAlternatePorts = False')) {
    if ($regionText -notmatch ('(?im)^\s*' + [regex]::Escape($requiredSetting) + '\s*$')) {
        throw "Region configuration is missing or changes a required setting: $requiredSetting"
    }
}

$openSimText = [System.IO.File]::ReadAllText($openSimIni)
if ($openSimText -notmatch '(?im)^\s*BaseHostname\s*=\s*"127\.0\.0\.1"\s*$') { throw 'BaseHostname is not loopback.' }
if ($openSimText -notmatch ('(?im)^\s*PublicPort\s*=\s*"' + $worldPort + '"\s*$')) { throw 'Standalone PublicPort does not match this install.' }
if ($openSimText -notmatch ('(?im)^\s*http_listener_port\s*=\s*' + $worldPort + '\s*$')) { throw 'HTTP listener port does not match this install.' }
if ($openSimText -notmatch ('(?im)^\s*access_ip_addresses\s*=\s*127\.0\.0\.1\s*$')) { throw 'RemoteAdmin is not restricted to loopback.' }
if ($openSimText -match '__GENERATE_') { throw 'An unexpanded configuration marker remains.' }
if ($openSimText -notmatch '(?im)^\s*Include-Architecture\s*=\s*"config-include/Standalone\.ini"\s*$') { throw 'The stock Standalone architecture is not active.' }
if ($openSimText -match '(?im)^\s*Include-Architecture\s*=\s*"config-include/StandaloneHypergrid\.ini"\s*$') { throw 'Hypergrid architecture is active, which is outside this milestone.' }

Write-Output 'Configuration checks passed: one 512 x 512 m loopback standalone region, stock SQLite architecture, verified SQLite C runtime, no Hypergrid architecture.'

if ($RequireRunning) {
    $tcp = [System.Net.Sockets.TcpClient]::new()
    try {
        $connect = $tcp.BeginConnect([System.Net.IPAddress]::Loopback, $worldPort, $null, $null)
        if (-not $connect.AsyncWaitHandle.WaitOne(2000)) { throw "No TCP/$worldPort connection was accepted." }
        $tcp.EndConnect($connect)
    }
    finally { $tcp.Dispose() }

    $userMatch = [regex]::Match($openSimText, '(?m)^\s*ConsoleUser\s*=\s*"([^"]+)"')
    $passMatch = [regex]::Match($openSimText, '(?m)^\s*ConsolePass\s*=\s*"([^"]+)"')
    if (-not $userMatch.Success -or -not $passMatch.Success) { throw 'REST console credentials are missing from the local config.' }
    $sessionId = $null
    try {
        $sessionResponse = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$worldPort/StartSession/" -Method Post -Body @{ USER = $userMatch.Groups[1].Value; PASS = $passMatch.Groups[1].Value } -TimeoutSec 10
        [xml]$sessionXml = $sessionResponse.Content
        $sessionId = [string]$sessionXml.ConsoleSession.SessionID
        if (-not $sessionId) { throw 'The REST console did not return a session ID.' }
    }
    finally {
        if ($sessionId) {
            try { Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$worldPort/CloseSession/" -Method Post -Body @{ ID = $sessionId } -TimeoutSec 10 | Out-Null }
            catch { Write-Warning "Could not close the temporary REST console session $sessionId." }
        }
    }

    Write-Output "Runtime checks passed: TCP/$worldPort accepts loopback connections and the loopback REST console authenticates. Aurora login is still required to verify viewer UDP connectivity."
    $registrationUri = "http://127.0.0.1:$([int]$install.registrationPort)/login"
    $registrationResponse = Invoke-WebRequest -UseBasicParsing -Uri $registrationUri -TimeoutSec 5
    if ($registrationResponse.StatusCode -ne 200 -or $registrationResponse.Content -notmatch 'Create account') { throw 'The loopback registration page did not return its expected form.' }
    Write-Output "Registration page check passed: $registrationUri"
}
