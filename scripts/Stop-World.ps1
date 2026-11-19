[CmdletBinding()]
param(
    [ValidateRange(5, 300)]
    [int]$TimeoutSeconds = 120,
    [switch]$LifecycleTestFixture
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Import-Module -Name (Join-Path $projectRoot 'scripts\WorldDock.ProcessIdentity.psm1') -Force
$serverBin = Join-Path $projectRoot 'server\OpenSimulator-0.9.3.0\bin'
$dotnet = Join-Path $projectRoot 'runtime\dotnet8\dotnet.exe'
$openSimIni = Join-Path $serverBin 'OpenSim.ini'
$statePath = Join-Path $projectRoot '.local\opensim-process.json'
$install = Get-Content -LiteralPath (Join-Path $projectRoot '.local\install.json') -Raw | ConvertFrom-Json
$remoteAdminPort = [int]$install.remoteAdminPort
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

function Test-UdpPortFree([int]$Port) {
    $probe = $null
    try { $probe = [System.Net.Sockets.UdpClient]::new($Port); return $true }
    catch { return $false }
    finally { if ($probe) { $probe.Dispose() } }
}

$registrationError = $null
try { & (Join-Path $projectRoot 'registration\Stop-Registration.ps1') }
catch { $registrationError = $_.Exception.Message }
if ($LifecycleTestFixture) {
    $fixturePath = Join-Path $projectRoot '.local\lifecycle-test-fixture.json'
    if (-not (Test-Path -LiteralPath $fixturePath) -or (Get-Content -LiteralPath $fixturePath -Raw | ConvertFrom-Json).Purpose -ne 'WOW-WORLDDOCK-LIFECYCLE-TEST') { throw 'Refusing fixture shutdown without the isolated lifecycle test marker.' }
    & (Join-Path $projectRoot 'scripts\Stop-WorldLifecycleFixture.ps1') -ProjectRoot $projectRoot -RegistrationError $registrationError -TimeoutSeconds $TimeoutSeconds
    return
}

if (-not (Test-Path -LiteralPath $statePath)) {
    $occupied = @()
    if (-not (Test-TcpPortFree -Port ([int]$install.worldPort))) { $occupied += "TCP/$($install.worldPort)" }
    if (-not (Test-UdpPortFree -Port ([int]$install.worldPort))) { $occupied += "UDP/$($install.worldPort)" }
    if (-not (Test-TcpPortFree -Port $remoteAdminPort)) { $occupied += "RemoteAdmin TCP/$remoteAdminPort" }
    if ($occupied.Count) { throw "No OpenSimulator process is recorded, but $($occupied -join ', ') remain occupied. Refusing to terminate an unverified process. $registrationError" }
    if ($registrationError) { throw "OpenSimulator is already stopped; registration shutdown needs attention: $registrationError" }
    Write-Output 'OpenSimulator and registration service are already stopped; all configured ports are released.'
    return
}
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
$baseUri = "http://127.0.0.1:$([int]$state.HttpPort)"
$serverProcess = Get-Process -Id ([int]$state.ProcessId) -ErrorAction SilentlyContinue
if (-not $serverProcess) {
    if (-not (Test-TcpPortFree -Port ([int]$state.HttpPort)) -or -not (Test-UdpPortFree -Port ([int]$state.HttpPort)) -or -not (Test-TcpPortFree -Port $remoteAdminPort)) {
        throw "Recorded PID $($state.ProcessId) is not visible to this PowerShell context, but a world or RemoteAdmin port remains occupied. The process record was preserved; run graceful stop from the desktop Dock or a normal host PowerShell session."
    }
    Remove-Item -LiteralPath $statePath
    Write-Output "No simulator process was running; removed the stale PID $($state.ProcessId) record. Check its logs for the exit reason."
    return
}
if (-not $serverProcess.Path -or ([System.IO.Path]::GetFullPath($serverProcess.Path) -ne [System.IO.Path]::GetFullPath($dotnet))) {
    throw 'The recorded PID does not point to the project-local .NET host. Refusing to stop an unrelated process.'
}
$identity = Get-WorldDockProcessIdentity -ProcessId $serverProcess.Id
if (-not $identity -or -not $identity.CommandLine.Contains('OpenSim.dll', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The recorded process command line does not identify this project OpenSimulator instance. Refusing to stop it.'
}
if ($state.ProcessStartUtc -and $serverProcess.StartTime.ToUniversalTime().ToString('o') -ne ([DateTime]$state.ProcessStartUtc).ToUniversalTime().ToString('o')) {
    throw 'The recorded PID has a different process start time. Refusing to stop a reused PID.'
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
        $tcpOwners = @(Get-PortOwners -Protocol tcp -Port ([int]$state.HttpPort))
        $udpOwners = @(Get-PortOwners -Protocol udp -Port ([int]$state.HttpPort))
        $remoteOwners = @(Get-PortOwners -Protocol tcp -Port $remoteAdminPort)
        if ($tcpOwners.Count -or $udpOwners.Count -or $remoteOwners.Count -or -not (Test-TcpPortFree ([int]$state.HttpPort)) -or -not (Test-UdpPortFree ([int]$state.HttpPort)) -or -not (Test-TcpPortFree $remoteAdminPort)) {
            throw "OpenSimulator PID $($state.ProcessId) exited before the REST console accepted shutdown, but one or more world or RemoteAdmin ports remain occupied. Process state was preserved."
        }
        Remove-Item -LiteralPath $statePath -ErrorAction SilentlyContinue
        if ($registrationError) { throw "OpenSimulator exited and its ports are clear, but registration shutdown needs attention: $registrationError" }
        Write-Output "OpenSimulator PID $($state.ProcessId) exited before the REST console accepted shutdown; its ports are clear. Check logs for the exit reason."
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
    $remoteOwners = @(Get-PortOwners -Protocol tcp -Port $remoteAdminPort)
    $tcpFree = Test-TcpPortFree -Port ([int]$state.HttpPort)
    $remoteFree = Test-TcpPortFree -Port $remoteAdminPort
    $udpFree = Test-UdpPortFree -Port ([int]$state.HttpPort)
    if ($tcpOwners.Count -eq 0 -and $udpOwners.Count -eq 0 -and $remoteOwners.Count -eq 0 -and $tcpFree -and $remoteFree -and $udpFree) {
        $portsClear = $true
        break
    }
    Start-Sleep -Seconds 1
}

if (-not $portsClear) {
    $owners = (@($tcpOwners) + @($udpOwners) + @($remoteOwners) | Sort-Object -Unique) -join ', '
    throw "The simulator PID exited, but a world or RemoteAdmin listener remains (owner PID(s): $owners). Process state was preserved for diagnosis."
}
Remove-Item -LiteralPath $statePath -ErrorAction SilentlyContinue
if (-not $shutdownAccepted) {
    throw "The simulator exited after the shutdown request, but the REST response could not confirm acceptance: $shutdownError. The process and port checks are clear; review the server log before calling this graceful."
}
if ($registrationError) { throw "OpenSimulator stopped gracefully, but registration shutdown needs attention: $registrationError" }
Write-Output "OpenSimulator stopped gracefully (PID $($state.ProcessId)); world TCP/UDP $($state.HttpPort) and RemoteAdmin TCP $remoteAdminPort are released."
