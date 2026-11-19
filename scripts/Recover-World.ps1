[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param([switch]$ForceOwnedProcesses)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Import-Module -Name (Join-Path $projectRoot 'scripts\WorldDock.ProcessIdentity.psm1') -Force
$localRoot = Join-Path $projectRoot '.local'
$install = Get-Content -LiteralPath (Join-Path $localRoot 'install.json') -Raw | ConvertFrom-Json
$dotnet = Join-Path $projectRoot 'runtime\dotnet8\dotnet.exe'
$python = Join-Path $projectRoot 'runtime\python\python.exe'
if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
    $systemPython = Get-Command python.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($systemPython) { $python = $systemPython.Source }
}
$fixturePath = Join-Path $localRoot 'lifecycle-test-fixture.json'
$fixture = $null
try { if (Test-Path -LiteralPath $fixturePath) { $fixture = Get-Content -LiteralPath $fixturePath -Raw | ConvertFrom-Json } } catch { }
$opensimPath = Join-Path $localRoot 'opensim-process.json'
$registrationPath = Join-Path $localRoot 'registration-process.json'

function Get-Owners([ValidateSet('tcp','udp')][string]$Protocol, [int]$Port) {
    $netstat = Join-Path $env:SystemRoot 'System32\netstat.exe'; $owners = @()
    foreach ($line in (& $netstat -ano -p $Protocol 2>$null)) {
        $fields = $line.Trim() -split '\s+'
        if ($fields.Count -lt 3 -or $fields[0] -ine $Protocol.ToUpperInvariant() -or $fields[1] -notmatch (':' + [regex]::Escape([string]$Port) + '$')) { continue }
        if ($Protocol -eq 'tcp' -and ($fields.Count -lt 5 -or $fields[3] -ne 'LISTENING')) { continue }
        $id = 0; if ([int]::TryParse($fields[-1], [ref]$id)) { $owners += $id }
    }
    return @($owners | Sort-Object -Unique)
}
function Test-PortFree([ValidateSet('tcp','udp')][string]$Protocol, [int]$Port) {
    if ($Protocol -eq 'tcp') {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $Port)
        try { $listener.Start(); return $true } catch { return $false } finally { $listener.Stop() }
    }
    $udp = $null; try { $udp = [System.Net.Sockets.UdpClient]::new($Port); return $true } catch { return $false } finally { if ($udp) { $udp.Dispose() } }
}
function Get-Identity([int]$Id) {
    return Get-WorldDockProcessIdentity -ProcessId $Id
}
function Assert-Owned($Record, [string]$Executable, [string]$Needle, [int[]]$Ports, [bool[]]$UdpFlags) {
    $actual = Get-Identity ([int]$Record.ProcessId)
    if (-not $actual -or -not $actual.Path -or [System.IO.Path]::GetFullPath($actual.Path) -ine [System.IO.Path]::GetFullPath($Executable)) { throw "PID $($Record.ProcessId) no longer matches the recorded project's executable; refusing recovery." }
    if ($actual.CommandLine.IndexOf($Needle, [StringComparison]::OrdinalIgnoreCase) -lt 0) { throw "PID $($Record.ProcessId) command line no longer identifies $Needle; refusing recovery." }
    if ($Record.ProcessStartUtc -and $actual.StartedUtc -and ([DateTime]$Record.ProcessStartUtc).ToUniversalTime().ToString('o') -ne ([DateTime]$actual.StartedUtc).ToUniversalTime().ToString('o')) { throw "PID $($Record.ProcessId) has a different start time; refusing recovery of a reused PID." }
    for ($i=0; $i -lt $Ports.Count; $i++) {
        $owners = @(Get-Owners $(if ($UdpFlags[$i]) {'udp'} else {'tcp'}) $Ports[$i])
        if ($owners.Count -and ($owners | Where-Object { $_ -ne [int]$Record.ProcessId }).Count) { throw "Port $($Ports[$i]) has a listener not owned by PID $($Record.ProcessId); refusing recovery." }
    }
}
function Test-ServiceResponsive($Name, $Record) {
    if ($Name -eq 'Registration') {
        try { return (Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$([int]$install.registrationPort)/health" -TimeoutSec 2).StatusCode -eq 200 } catch { return $false }
    }
    if ($Record.TestFixture -and $fixture -and $fixture.Purpose -eq 'WOW-WORLDDOCK-LIFECYCLE-TEST') {
        try { return (Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$([int]$install.worldPort)/health" -TimeoutSec 2).StatusCode -eq 200 } catch { return $false }
    }
    $ini = Join-Path $projectRoot 'server\OpenSimulator-0.9.3.0\bin\OpenSim.ini'
    if (-not (Test-Path -LiteralPath $ini)) { return $false }
    $text = [System.IO.File]::ReadAllText($ini)
    $user = [regex]::Match($text, '(?m)^\s*ConsoleUser\s*=\s*"([^"]+)"')
    $pass = [regex]::Match($text, '(?m)^\s*ConsolePass\s*=\s*"([^"]+)"')
    if (-not $user.Success -or -not $pass.Success) { return $false }
    $session = $null
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$([int]$install.worldPort)/StartSession/" -Method Post -Body @{ USER=$user.Groups[1].Value; PASS=$pass.Groups[1].Value } -TimeoutSec 3
        [xml]$xml = $response.Content; $session = [string]$xml.ConsoleSession.SessionID
        return [bool]$session
    }
    catch { return $false }
    finally { if ($session) { try { Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$([int]$install.worldPort)/CloseSession/" -Method Post -Body @{ ID=$session } -TimeoutSec 2 | Out-Null } catch { } } }
}

$changed = $false
foreach ($spec in @(
    [pscustomobject]@{ Name='OpenSimulator'; Path=$opensimPath; Exe=$dotnet; Needle='OpenSim.dll'; Ports=@([int]$install.worldPort,[int]$install.worldPort,[int]$install.remoteAdminPort); Udp=@($false,$true,$false) },
    [pscustomobject]@{ Name='Registration'; Path=$registrationPath; Exe=$python; Needle='server.py'; Ports=@([int]$install.registrationPort); Udp=@($false) }
)) {
    if (-not (Test-Path -LiteralPath $spec.Path)) { continue }
    try { $record = Get-Content -LiteralPath $spec.Path -Raw | ConvertFrom-Json } catch { throw "$($spec.Name) state is unreadable; no record or process was changed." }
    $process = Get-Process -Id ([int]$record.ProcessId) -ErrorAction SilentlyContinue
    if (-not $process) {
        $anyOccupied = $false
        for ($i=0; $i -lt $spec.Ports.Count; $i++) { if (-not (Test-PortFree $(if ($spec.Udp[$i]) {'udp'} else {'tcp'}) $spec.Ports[$i])) { $anyOccupied = $true } }
        if ($anyOccupied) { throw "$($spec.Name) PID $($record.ProcessId) is gone but one or more service ports remain occupied. State was preserved; unrelated listeners were not touched." }
        Remove-Item -LiteralPath $spec.Path -Force
        if ($spec.Name -eq 'Registration') { Remove-Item -LiteralPath (Join-Path $localRoot 'registration-control-token.txt') -Force -ErrorAction SilentlyContinue }
        Write-Output "Cleared stale $($spec.Name) state after confirming PID and all service ports were gone."
        $changed = $true
        continue
    }
    if (-not $ForceOwnedProcesses) { Write-Output "$($spec.Name) PID $($record.ProcessId) is still active. No force action was requested."; continue }
    $expectedExe = $spec.Exe
    $needle = $spec.Needle
    if ($record.TestFixture -and $fixture -and $fixture.Purpose -eq 'WOW-WORLDDOCK-LIFECYCLE-TEST') {
        if ($spec.Name -eq 'OpenSimulator') { $expectedExe = [string]$fixture.PythonPath; $needle = 'WorldDockLifecycleWorker.py' }
        elseif ($record.PythonPath -and [System.IO.Path]::GetFullPath([string]$record.PythonPath) -ieq [System.IO.Path]::GetFullPath([string]$fixture.PythonPath)) { $expectedExe = [string]$fixture.PythonPath }
    }
    if ($record.CommandLineNeedle) { $needle = [string]$record.CommandLineNeedle }
    Assert-Owned $record $expectedExe $needle $spec.Ports $spec.Udp
    if (Test-ServiceResponsive $spec.Name $record) { throw "$($spec.Name) PID $($record.ProcessId) still passes its health check. Use graceful Stop or Restart instead of force recovery." }
    if ($PSCmdlet.ShouldProcess("$($spec.Name) PID $($record.ProcessId)", 'Force-stop a verified unresponsive project-owned process')) {
        Stop-Process -Id ([int]$record.ProcessId) -Force
        try { Wait-Process -Id ([int]$record.ProcessId) -Timeout 10 -ErrorAction SilentlyContinue } catch { }
        if (Get-Process -Id ([int]$record.ProcessId) -ErrorAction SilentlyContinue) { throw "$($spec.Name) PID $($record.ProcessId) did not exit; state was preserved." }
        for ($i=0; $i -lt $spec.Ports.Count; $i++) {
            if (-not (Test-PortFree $(if ($spec.Udp[$i]) {'udp'} else {'tcp'}) $spec.Ports[$i])) { throw "$($spec.Name) PID exited but port $($spec.Ports[$i]) remains occupied; state was preserved." }
        }
        Remove-Item -LiteralPath $spec.Path -Force
        if ($spec.Name -eq 'Registration') { Remove-Item -LiteralPath (Join-Path $localRoot 'registration-control-token.txt') -Force -ErrorAction SilentlyContinue }
        Write-Output "Recovered $($spec.Name) by stopping only verified PID $($record.ProcessId); its ports are clear."
        $changed = $true
    }
}
if (-not $changed) { Write-Output 'No stale records needed clearing and no verified process was force-stopped.' }
