[CmdletBinding()]
param(
    [ValidateRange(5, 300)]
    [int]$TimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$serverBin = Join-Path $projectRoot 'server\OpenSimulator-0.9.3.0\bin'
$dotnet = Join-Path $projectRoot 'runtime\dotnet8\dotnet.exe'
$openSimIni = Join-Path $serverBin 'OpenSim.ini'
$statePath = Join-Path $projectRoot '.local\opensim-process.json'
$baseUri = $null

function Get-PortOwners {
    param(
        [Parameter(Mandatory)][ValidateSet('tcp', 'udp')][string]$Protocol,
        [Parameter(Mandatory)][int]$Port
    )
    $netstatPath = Join-Path $env:SystemRoot 'System32\netstat.exe'
    $owners = @()
    foreach ($line in (& $netstatPath -ano -p $Protocol 2>$null)) {
        $fields = $line.Trim() -split '\s+'
        if ($fields.Count -lt 3 -or $fields[0] -ine $Protocol.ToUpperInvariant()) { continue }
        if ($fields[1] -notmatch (':' + [regex]::Escape([string]$Port) + '$')) { continue }
        if ($Protocol -eq 'tcp' -and ($fields.Count -lt 5 -or $fields[3] -ne 'LISTENING')) { continue }
        $owner = 0
        if ([int]::TryParse($fields[-1], [ref]$owner)) { $owners += $owner }
    }
    return @($owners | Sort-Object -Unique)
}

function Test-TcpPortFree {
    param([Parameter(Mandatory)][int]$Port)
    $probe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $Port)
    try {
        $probe.Start()
        return $true
    }
    catch { return $false }
    finally { $probe.Stop() }
}

if (-not (Test-Path -LiteralPath $statePath)) {
    throw 'No managed OpenSimulator process is recorded. Start it with scripts\Start-World.ps1 before using graceful shutdown.'
}
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
$baseUri = "http://127.0.0.1:$([int]$state.HttpPort)"
$serverProcess = Get-Process -Id ([int]$state.ProcessId) -ErrorAction SilentlyContinue
if (-not $serverProcess) {
    if (-not (Test-TcpPortFree -Port ([int]$state.HttpPort))) {
        throw "Recorded PID $($state.ProcessId) is not visible to this PowerShell context, but TCP/$($state.HttpPort) is still occupied. The process record was preserved; run graceful stop from the desktop Dock or a normal host PowerShell session."
    }
    Remove-Item -LiteralPath $statePath
    Write-Output "No simulator process was running; removed the stale PID $($state.ProcessId) record. Check its logs for the exit reason."
    return
}
if (-not $serverProcess.Path -or ([System.IO.Path]::GetFullPath($serverProcess.Path) -ne [System.IO.Path]::GetFullPath($dotnet))) {
    throw 'The recorded PID does not point to the project-local .NET host. Refusing to stop an unrelated process.'
}

$iniText = [System.IO.File]::ReadAllText($openSimIni)
$userMatch = [regex]::Match($iniText, '(?m)^\s*ConsoleUser\s*=\s*"([^"]+)"')
$passMatch = [regex]::Match($iniText, '(?m)^\s*ConsolePass\s*=\s*"([^"]+)"')
if (-not $userMatch.Success -or -not $passMatch.Success -or $passMatch.Groups[1].Value -eq '__GENERATE_LOCAL_ONLY__') {
    throw 'The active REST console credentials could not be read from the ignored server configuration.'
}

$sessionId = $null
$lastControlError = 'The loopback REST console has not responded yet.'
$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
while ([DateTime]::UtcNow -lt $deadline -and -not $sessionId) {
    $serverProcess = Get-Process -Id ([int]$state.ProcessId) -ErrorAction SilentlyContinue
    if (-not $serverProcess) {
        Remove-Item -LiteralPath $statePath -ErrorAction SilentlyContinue
        Write-Output "PID $($state.ProcessId) exited before the REST console accepted a graceful shutdown request."
        return
    }
    if (-not $serverProcess.Path -or ([System.IO.Path]::GetFullPath($serverProcess.Path) -ne [System.IO.Path]::GetFullPath($dotnet))) {
        throw 'The recorded PID changed identity while waiting. Refusing to send a shutdown command.'
    }

    try {
        $sessionResponse = Invoke-WebRequest -UseBasicParsing -Uri "$baseUri/StartSession/" -Method Post -Body @{ USER = $userMatch.Groups[1].Value; PASS = $passMatch.Groups[1].Value } -TimeoutSec 2
        [xml]$sessionXml = $sessionResponse.Content
        $sessionId = [string]$sessionXml.ConsoleSession.SessionID
        if (-not $sessionId) { throw 'The REST console returned no session ID.' }
    }
    catch {
        $lastControlError = $_.Exception.Message
        Start-Sleep -Milliseconds 750
    }
}

if (-not $sessionId) {
    throw "Graceful shutdown could not reach the REST console within $TimeoutSeconds seconds. The simulator remains running. Last error: $lastControlError"
}

$shutdownAccepted = $false
$shutdownError = $null
try {
    Invoke-WebRequest -UseBasicParsing -Uri "$baseUri/SessionCommand/" -Method Post -Body @{ ID = $sessionId; COMMAND = 'shutdown' } -TimeoutSec 5 | Out-Null
    $shutdownAccepted = $true
}
catch {
    $shutdownError = $_.Exception.Message
}
finally {
    try { Invoke-WebRequest -UseBasicParsing -Uri "$baseUri/CloseSession/" -Method Post -Body @{ ID = $sessionId } -TimeoutSec 2 | Out-Null }
    catch { }
}

$stopped = $false
for ($attempt = 0; $attempt -lt $TimeoutSeconds; $attempt++) {
    if (-not (Get-Process -Id ([int]$state.ProcessId) -ErrorAction SilentlyContinue)) {
        $stopped = $true
        break
    }
    Start-Sleep -Seconds 1
}

if (-not $stopped) {
    throw "The simulator did not exit within $TimeoutSeconds seconds. It was not force-killed; inspect $($state.StdoutLog) and $($state.StderrLog)."
}

$portsClear = $false
for ($attempt = 0; $attempt -lt 10; $attempt++) {
    $tcpOwners = @(Get-PortOwners -Protocol tcp -Port ([int]$state.HttpPort))
    $udpOwners = @(Get-PortOwners -Protocol udp -Port ([int]$state.HttpPort))
    $tcpFree = Test-TcpPortFree -Port ([int]$state.HttpPort)
    if ($tcpOwners.Count -eq 0 -and $udpOwners.Count -eq 0 -and $tcpFree) {
        $portsClear = $true
        break
    }
    Start-Sleep -Seconds 1
}

Remove-Item -LiteralPath $statePath -ErrorAction SilentlyContinue
if (-not $portsClear) {
    $owners = (@($tcpOwners) + @($udpOwners) | Sort-Object -Unique) -join ', '
    throw "The simulator PID exited, but a listener/endpoint remains on port $($state.HttpPort) (owner PID(s): $owners). Check for another process using the region port."
}
if (-not $shutdownAccepted) {
    throw "The simulator exited after the shutdown request, but the REST response could not confirm acceptance: $shutdownError. The process and port checks are clear; review the server log before calling this graceful."
}
Write-Output "Woz's World stopped gracefully (PID $($state.ProcessId)); TCP and UDP port $($state.HttpPort) are clear."
