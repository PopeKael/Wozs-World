[CmdletBinding()]
param([switch]$AsJson)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$localRoot = Join-Path $projectRoot '.local'
$installPath = Join-Path $localRoot 'install.json'
$fixturePath = Join-Path $localRoot 'lifecycle-test-fixture.json'
$fixture = $null
try { if (Test-Path -LiteralPath $fixturePath) { $fixture = Get-Content -LiteralPath $fixturePath -Raw | ConvertFrom-Json } } catch { }
$install = if (Test-Path -LiteralPath $installPath) { Get-Content -LiteralPath $installPath -Raw | ConvertFrom-Json } else { $null }

function Test-TcpOpen([int]$Port) {
    if ($Port -lt 1) { return $false }
    $client = [System.Net.Sockets.TcpClient]::new()
    try { $client.Connect('127.0.0.1', $Port); return $true }
    catch { return $false }
    finally { $client.Dispose() }
}

function Get-ListenerOwners([ValidateSet('tcp','udp')][string]$Protocol, [int]$Port) {
    if ($Port -lt 1) { return @() }
    $netstat = Join-Path $env:SystemRoot 'System32\netstat.exe'
    $owners = @()
    foreach ($line in (& $netstat -ano -p $Protocol 2>$null)) {
        $fields = $line.Trim() -split '\s+'
        if ($fields.Count -lt 3 -or $fields[0] -ine $Protocol.ToUpperInvariant()) { continue }
        if ($fields[1] -notmatch (':' + [regex]::Escape([string]$Port) + '$')) { continue }
        if ($Protocol -eq 'tcp' -and ($fields.Count -lt 5 -or $fields[3] -ne 'LISTENING')) { continue }
        $owner = 0
        if ([int]::TryParse($fields[-1], [ref]$owner)) { $owners += $owner }
    }
    return @($owners | Sort-Object -Unique)
}

function Get-ProcessInfo([int]$ProcessId) {
    $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $process) { return $null }
    $path = $process.Path
    $startedUtc = $null
    try { $startedUtc = (Get-Process -Id $ProcessId -ErrorAction Stop).StartTime.ToUniversalTime().ToString('o') } catch { }
    [pscustomobject]@{ Path = $path; CommandLine = ''; StartedUtc = $startedUtc }
}

function Test-RecordedProcess($Record, [string]$ExpectedPath, [string]$CommandNeedle) {
    if (-not $Record -or -not $Record.ProcessId) { return $false }
    $actual = Get-ProcessInfo -ProcessId ([int]$Record.ProcessId)
    if (-not $actual -or -not $actual.Path) { return $false }
    if ([System.IO.Path]::GetFullPath($actual.Path) -ine [System.IO.Path]::GetFullPath($ExpectedPath)) { return $false }
    if ($actual.CommandLine -and $actual.CommandLine.IndexOf($CommandNeedle, [StringComparison]::OrdinalIgnoreCase) -lt 0) { return $false }
    if ($Record.ProcessStartUtc -and $actual.StartedUtc -and ([DateTime]$Record.ProcessStartUtc).ToUniversalTime().ToString('o') -ne ([DateTime]$actual.StartedUtc).ToUniversalTime().ToString('o')) { return $false }
    return $true
}

$worldPort = if ($install) { [int]$install.worldPort } else { 0 }
$registrationPort = if ($install) { [int]$install.registrationPort } else { 0 }
$remoteAdminPort = if ($install) { [int]$install.remoteAdminPort } else { 0 }
$openSimState = $null
$registrationState = $null
try { if (Test-Path (Join-Path $localRoot 'opensim-process.json')) { $openSimState = Get-Content (Join-Path $localRoot 'opensim-process.json') -Raw | ConvertFrom-Json } } catch { }
try { if (Test-Path (Join-Path $localRoot 'registration-process.json')) { $registrationState = Get-Content (Join-Path $localRoot 'registration-process.json') -Raw | ConvertFrom-Json } } catch { }

$dotnet = Join-Path $projectRoot 'runtime\dotnet8\dotnet.exe'
$openSimNeedle = 'OpenSim.dll'
if ($fixture -and $fixture.Purpose -eq 'WOW-WORLDDOCK-LIFECYCLE-TEST' -and $openSimState -and $openSimState.TestFixture) {
    $dotnet = [string]$fixture.PythonPath
    $openSimNeedle = 'WorldDockLifecycleWorker.py'
}
$serverBin = Join-Path $projectRoot 'server\OpenSimulator-0.9.3.0\bin'
$opensimOwned = Test-RecordedProcess $openSimState $dotnet $openSimNeedle
$opensimPort = Test-TcpOpen $worldPort
$opensim = if ($opensimOwned -and $opensimPort -and $openSimState.ReadyUtc) { 'Running' } elseif ($opensimOwned -and $opensimPort) { 'Starting' } elseif ($opensimOwned) { 'Unresponsive' } elseif ($opensimPort) { 'Unmanaged' } else { 'Stopped' }
$openSimDetail = if ($openSimState) { "PID $($openSimState.ProcessId), TCP/$worldPort" } else { "TCP/$worldPort" }

$remoteOwners = @(Get-ListenerOwners tcp $remoteAdminPort)
$remoteOpen = Test-TcpOpen $remoteAdminPort
$fixtureOwned = [bool]($fixture -and $fixture.Purpose -eq 'WOW-WORLDDOCK-LIFECYCLE-TEST' -and $openSimState -and $openSimState.TestFixture)
$remoteOwnerVerified = if ($fixtureOwned) { $opensimOwned } else { $opensimOwned -and $remoteOwners -contains [int]$openSimState.ProcessId }
$remoteAdmin = if ($remoteOpen -and $remoteOwnerVerified) { 'Running' } elseif ($remoteOpen) { 'Unmanaged' } elseif ($opensimOwned) { 'Unresponsive' } else { 'Stopped' }
$remoteDetail = "TCP/$remoteAdminPort; owner PID(s): $($remoteOwners -join ', ')"

$python = Join-Path $projectRoot 'runtime\python\python.exe'
if ($registrationState -and $registrationState.PythonPath -and $fixture -and $fixture.Purpose -eq 'WOW-WORLDDOCK-LIFECYCLE-TEST' -and [System.IO.Path]::GetFullPath([string]$registrationState.PythonPath) -ieq [System.IO.Path]::GetFullPath([string]$fixture.PythonPath)) {
    $python = [string]$fixture.PythonPath
}
elseif (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
    $systemPython = Get-Command python.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($systemPython) { $python = $systemPython.Source }
}
elseif ($registrationState -and $registrationState.PythonPath -and [System.IO.Path]::GetFullPath([string]$registrationState.PythonPath) -ieq [System.IO.Path]::GetFullPath($python)) {
    $python = [string]$registrationState.PythonPath
}
$registrationOwners = @(Get-ListenerOwners tcp $registrationPort)
$registrationHealth = $false
try { $response = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$registrationPort/health" -TimeoutSec 2; $registrationHealth = $response.StatusCode -eq 200 -and $response.Content -match '"status"\s*:\s*"ready"' } catch { }
$registrationOwned = Test-RecordedProcess $registrationState $python 'server.py'
$registrationOwnerVerified = if ($fixture -and $fixture.Purpose -eq 'WOW-WORLDDOCK-LIFECYCLE-TEST') { $registrationOwned } else { $registrationOwned -and $registrationOwners -contains [int]$registrationState.ProcessId }
$registration = if ($registrationHealth -and $registrationOwnerVerified) { 'Running' } elseif ($registrationHealth) { 'Unmanaged' } elseif ($registrationOwned) { 'Unresponsive' } elseif ($registrationOwners.Count -gt 0) { 'Unmanaged' } else { 'Stopped' }
$registrationDetail = "HTTP/$registrationPort; PID $(if ($registrationState) { $registrationState.ProcessId } else { 'not recorded' })"

$result = [pscustomobject]@{
    CheckedUtc = [DateTime]::UtcNow.ToString('o')
    Overall = if ($opensim -eq 'Running' -and $remoteAdmin -eq 'Running' -and $registration -eq 'Running') { 'Running' } elseif ($opensim -eq 'Stopped' -and $remoteAdmin -eq 'Stopped' -and $registration -eq 'Stopped') { 'Stopped' } else { 'Attention' }
    Services = [pscustomobject]@{
        OpenSimulator = [pscustomobject]@{ Status = $opensim; ProcessId = if ($openSimState) { $openSimState.ProcessId } else { $null }; Port = $worldPort; Detail = $openSimDetail }
        Registration = [pscustomobject]@{ Status = $registration; ProcessId = if ($registrationState) { $registrationState.ProcessId } else { $null }; Port = $registrationPort; Detail = $registrationDetail }
        RemoteAdmin = [pscustomobject]@{ Status = $remoteAdmin; ProcessId = if ($opensimOwned) { $openSimState.ProcessId } else { $null }; Port = $remoteAdminPort; Detail = $remoteDetail }
    }
}
if ($AsJson) { $result | ConvertTo-Json -Depth 8 -Compress } else { $result }
