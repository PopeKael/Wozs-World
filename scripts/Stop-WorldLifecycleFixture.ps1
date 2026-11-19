[CmdletBinding()]
param([Parameter(Mandatory)][string]$ProjectRoot, [string]$RegistrationError, [int]$TimeoutSeconds = 20)
$ErrorActionPreference = 'Stop'
$identityModule = Join-Path $ProjectRoot 'scripts\WorldDock.ProcessIdentity.psm1'
Import-Module -Name $identityModule -Force
$localRoot = Join-Path $ProjectRoot '.local'
$statePath = Join-Path $localRoot 'opensim-process.json'
$fixture = Get-Content -LiteralPath (Join-Path $localRoot 'lifecycle-test-fixture.json') -Raw | ConvertFrom-Json
$ports = Get-Content -LiteralPath (Join-Path $localRoot 'install.json') -Raw | ConvertFrom-Json
function Get-Owners([ValidateSet('tcp','udp')][string]$Protocol, [int]$Port) {
    $netstat = Join-Path $env:SystemRoot 'System32\netstat.exe'; $ids = @()
    foreach ($line in (& $netstat -ano -p $Protocol 2>$null)) {
        $fields=$line.Trim() -split '\s+'
        if ($fields.Count -lt 3 -or $fields[0] -ine $Protocol.ToUpperInvariant() -or $fields[1] -notmatch (':' + [regex]::Escape([string]$Port) + '$')) { continue }
        if ($Protocol -eq 'tcp' -and ($fields.Count -lt 5 -or $fields[3] -ne 'LISTENING')) { continue }
        $id=0; if ([int]::TryParse($fields[-1],[ref]$id)) { $ids += $id }
    }
    return @($ids | Sort-Object -Unique)
}
function Test-Free([ValidateSet('tcp','udp')][string]$Protocol,[int]$Port) {
    if ($Protocol -eq 'tcp') { $l=[System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any,$Port); try{$l.Start();return $true}catch{return $false}finally{$l.Stop()} }
    $u=$null; try{$u=[System.Net.Sockets.UdpClient]::new($Port);return $true}catch{return $false}finally{if($u){$u.Dispose()}}
}
if (-not (Test-Path -LiteralPath $statePath)) {
    foreach ($port in @([int]$ports.worldPort,[int]$ports.remoteAdminPort)) { if (-not (Test-Free tcp $port)) { throw "Fixture state is absent but TCP/$port remains occupied; nothing was terminated." } }
    if (-not (Test-Free udp ([int]$ports.worldPort))) { throw 'Fixture state is absent but the world UDP port remains occupied; nothing was terminated.' }
    if ($RegistrationError) { throw "OpenSimulator fixture is stopped; registration could not be shut down: $RegistrationError" }
    Write-Output 'Fixture OpenSimulator is already stopped; its world and RemoteAdmin ports are released.'
    return
}
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
if (-not $state.TestFixture -or -not $fixture -or $fixture.Purpose -ne 'WOW-WORLDDOCK-LIFECYCLE-TEST') { throw 'Fixture shutdown state did not match its isolated marker.' }
$process = Get-Process -Id ([int]$state.ProcessId) -ErrorAction SilentlyContinue
if (-not $process) {
    foreach ($port in @([int]$ports.worldPort,[int]$ports.remoteAdminPort)) { if (-not (Test-Free tcp $port)) { throw "Fixture PID is gone but TCP/$port remains occupied; state preserved." } }
    if (-not (Test-Free udp ([int]$ports.worldPort))) { throw 'Fixture PID is gone but world UDP remains occupied; state preserved.' }
    Remove-Item -LiteralPath $statePath -Force
    if ($RegistrationError) { throw "Stale fixture state cleared; registration shutdown needs attention: $RegistrationError" }
    Write-Output 'Cleared stale fixture OpenSimulator state after confirming all ports were released.'
    return
}
$actual = Get-WorldDockProcessIdentity -ProcessId ([int]$state.ProcessId)
if (-not $actual -or [System.IO.Path]::GetFullPath($actual.Path) -ine [System.IO.Path]::GetFullPath([string]$fixture.PythonPath) -or $actual.CommandLine.IndexOf('WorldDockLifecycleWorker.py',[StringComparison]::OrdinalIgnoreCase) -lt 0) { throw 'Fixture process PID/executable/command line identity failed; refusing shutdown.' }
if ($state.ProcessStartUtc -and $process.StartTime.ToUniversalTime().ToString('o') -ne ([DateTime]$state.ProcessStartUtc).ToUniversalTime().ToString('o')) { throw 'Fixture PID start time changed; refusing a potentially reused PID.' }
foreach ($spec in @(@('tcp',[int]$ports.worldPort),@('udp',[int]$ports.worldPort),@('tcp',[int]$ports.remoteAdminPort))) {
    $owners = @(Get-Owners $spec[0] $spec[1])
    if ($owners.Count -and ($owners | Where-Object { $_ -ne [int]$state.ProcessId }).Count) { throw "Port $($spec[1]) has an unowned listener; fixture shutdown refused." }
}
$uri = "http://127.0.0.1:$([int]$ports.worldPort)"
$session = Invoke-WebRequest -UseBasicParsing -Uri "$uri/StartSession/" -Method Post -Body @{ USER='fixture'; PASS='fixture' } -TimeoutSec 3
[xml]$sessionXml = $session.Content
$sessionId = [string]$sessionXml.ConsoleSession.SessionID
if (-not $sessionId) { throw 'Fixture REST did not return a session identifier; process retained.' }
Invoke-WebRequest -UseBasicParsing -Uri "$uri/SessionCommand/" -Method Post -Body @{ ID=$sessionId; COMMAND='shutdown' } -TimeoutSec 3 | Out-Null
$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
while ([DateTime]::UtcNow -lt $deadline -and (Get-Process -Id ([int]$state.ProcessId) -ErrorAction SilentlyContinue)) { Start-Sleep -Milliseconds 250 }
if (Get-Process -Id ([int]$state.ProcessId) -ErrorAction SilentlyContinue) { throw "Fixture PID $($state.ProcessId) did not exit; it was not force-killed." }
foreach ($spec in @(@('tcp',[int]$ports.worldPort),@('udp',[int]$ports.worldPort),@('tcp',[int]$ports.remoteAdminPort))) {
    if (-not (Test-Free $spec[0] $spec[1]) -or (Get-Owners $spec[0] $spec[1]).Count) { throw "Fixture process exited but port $($spec[1]) remains occupied; state preserved." }
}
Remove-Item -LiteralPath $statePath -Force
Write-Output "Fixture OpenSimulator stopped gracefully (PID $($state.ProcessId)); world TCP/UDP $($ports.worldPort) and RemoteAdmin TCP $($ports.remoteAdminPort) are released."
if ($RegistrationError) { throw "OpenSimulator stopped but registration shutdown needs attention: $RegistrationError" }
