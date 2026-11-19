[CmdletBinding()]
param([ValidateRange(5,120)][int]$TimeoutSeconds = 20)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Import-Module -Name (Join-Path $projectRoot 'scripts\WorldDock.ProcessIdentity.psm1') -Force
$localRoot = Join-Path $projectRoot '.local'
$statePath = Join-Path $localRoot 'registration-process.json'
$tokenPath = Join-Path $localRoot 'registration-control-token.txt'
$install = Get-Content -LiteralPath (Join-Path $localRoot 'install.json') -Raw | ConvertFrom-Json
$port = [int]$install.registrationPort

function Test-TcpOpen([int]$Port) {
    $client = [System.Net.Sockets.TcpClient]::new()
    try { $client.Connect('127.0.0.1', $Port); return $true } catch { return $false } finally { $client.Dispose() }
}
function Get-TcpOwners([int]$Port) {
    $netstat = Join-Path $env:SystemRoot 'System32\netstat.exe'; $owners = @()
    foreach ($line in (& $netstat -ano -p tcp 2>$null)) {
        $fields = $line.Trim() -split '\s+'
        if ($fields.Count -lt 5 -or $fields[0] -ine 'TCP' -or $fields[1] -notmatch (':' + [regex]::Escape([string]$Port) + '$') -or $fields[3] -ne 'LISTENING') { continue }
        $owner = 0; if ([int]::TryParse($fields[-1], [ref]$owner)) { $owners += $owner }
    }
    return @($owners | Sort-Object -Unique)
}
function Get-Identity([int]$Id) {
    return Get-WorldDockProcessIdentity -ProcessId $Id
}

if (-not (Test-Path -LiteralPath $statePath)) {
    if (Test-TcpOpen $port) { $owners = @(Get-TcpOwners $port); throw "Registration HTTP/$port is open without a project record (PID(s): $($owners -join ', ')); refusing to terminate an unverified listener." }
    Write-Output 'Registration service is already stopped; no process record exists.'
    return
}
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
$process = Get-Process -Id ([int]$state.ProcessId) -ErrorAction SilentlyContinue
if (-not $process) {
    if (Test-TcpOpen $port) { $owners = @(Get-TcpOwners $port); throw "Recorded registration PID $($state.ProcessId) is gone but HTTP/$port remains occupied by PID(s) $($owners -join ', '). State was preserved." }
    Remove-Item -LiteralPath $statePath, $tokenPath -Force -ErrorAction SilentlyContinue
    Write-Output 'Removed a stale registration record after confirming its process and port were gone.'
    return
}

$python = Join-Path $projectRoot 'runtime\python\python.exe'
$approvedPythonPaths = @()
if (Test-Path -LiteralPath $python -PathType Leaf) { $approvedPythonPaths += [System.IO.Path]::GetFullPath($python) }
$systemPython = Get-Command python.exe -ErrorAction SilentlyContinue | Select-Object -First 1
if ($systemPython) { $approvedPythonPaths += [System.IO.Path]::GetFullPath($systemPython.Source) }
$recordPython = [string]$state.PythonPath
if ($recordPython -and -not ($approvedPythonPaths | Where-Object { $_ -ieq [System.IO.Path]::GetFullPath($recordPython) })) {
    throw 'The recorded registration Python path is not an approved project-local or system Python executable; refusing shutdown.'
}
if ($recordPython) { $python = [System.IO.Path]::GetFullPath($recordPython) }
$fixturePath = Join-Path $localRoot 'lifecycle-test-fixture.json'
$fixtureMode = $false
if (Test-Path -LiteralPath $fixturePath) {
    $fixture = Get-Content -LiteralPath $fixturePath -Raw | ConvertFrom-Json
    if ($fixture.Purpose -eq 'WOW-WORLDDOCK-LIFECYCLE-TEST' -and $state.PythonPath -and [System.IO.Path]::GetFullPath([string]$state.PythonPath) -ieq [System.IO.Path]::GetFullPath([string]$fixture.PythonPath)) { $python = [string]$fixture.PythonPath; $fixtureMode = $true }
}
$identity = Get-Identity ([int]$state.ProcessId)
if (-not $identity -or -not $identity.Path -or [System.IO.Path]::GetFullPath($identity.Path) -ine [System.IO.Path]::GetFullPath($python) -or $identity.CommandLine.IndexOf('server.py', [StringComparison]::OrdinalIgnoreCase) -lt 0) {
    throw "Recorded registration PID $($state.ProcessId) does not match the project Python executable and server.py command line. Refusing to stop it."
}
if ($state.ProcessStartUtc -and $identity.StartedUtc -and ([DateTime]$state.ProcessStartUtc).ToUniversalTime().ToString('o') -ne ([DateTime]$identity.StartedUtc).ToUniversalTime().ToString('o')) {
    throw "Registration PID $($state.ProcessId) has a different start time; refusing to act on a reused PID."
}
$owners = @(Get-TcpOwners $port)
if (-not $fixtureMode -and $owners.Count -and $owners -notcontains [int]$state.ProcessId) { throw "Registration HTTP/$port also has unowned listener PID(s) $($owners -join ', '); refusing shutdown while ownership is ambiguous." }
if (-not (Test-Path -LiteralPath $tokenPath)) { throw 'The registration shutdown token is missing; process is retained for safe recovery.' }
$token = (Get-Content -LiteralPath $tokenPath -Raw).Trim()
try {
    Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$port/__worlddock/shutdown" -Method Post -Headers @{ 'X-WOW-Control-Token' = $token } -TimeoutSec 3 | Out-Null
}
catch { throw "Graceful registration shutdown was not accepted: $($_.Exception.Message)" }

$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
while ([DateTime]::UtcNow -lt $deadline -and (Get-Process -Id ([int]$state.ProcessId) -ErrorAction SilentlyContinue)) { Start-Sleep -Milliseconds 250 }
if (Get-Process -Id ([int]$state.ProcessId) -ErrorAction SilentlyContinue) { throw "Registration PID $($state.ProcessId) did not exit within $TimeoutSeconds seconds; it was not force-killed." }
for ($attempt = 0; $attempt -lt 12 -and (Test-TcpOpen $port); $attempt++) { Start-Sleep -Milliseconds 250 }
if (Test-TcpOpen $port) { $owners = @(Get-TcpOwners $port); throw "Registration process exited but HTTP/$port is still open (PID(s): $($owners -join ', ')); state retained." }
Remove-Item -LiteralPath $statePath, $tokenPath -Force -ErrorAction SilentlyContinue
Write-Output "Registration service stopped gracefully (PID $($state.ProcessId)); HTTP/$port is released."
