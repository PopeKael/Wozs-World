[CmdletBinding()]
param([switch]$KeepArtifacts)

$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path -Parent $PSScriptRoot
$pythonCommand = Get-Command python.exe -ErrorAction Stop
$pythonPath = $pythonCommand.Source
$tempBase = [System.IO.Path]::GetFullPath('F:\OpenGrid').TrimEnd('\') + '\'
$testRoot = Join-Path 'F:\OpenGrid' ('.worlddock-lifecycle-test-' + [guid]::NewGuid().ToString('N'))
$spawned = [System.Collections.Generic.List[int]]::new()
$results = [System.Collections.Generic.List[string]]::new()

function Assert([bool]$Condition, [string]$Message) { if (-not $Condition) { throw "ASSERTION FAILED: $Message" } }
function Assert-ServiceState($Expected, $Name) {
    $status = & (Join-Path $testRoot 'scripts\Get-WorldServiceStatus.ps1')
    Assert ($status.Services.$Name.Status -eq $Expected) "$Name status expected '$Expected', found '$($status.Services.$Name.Status)'"
    return $status
}
function Find-FreePortSet {
    foreach ($base in (Get-Random -Minimum 25000 -Maximum 39000)..40000) {
        $ports = @($base, $base + 80, $base + 10000)
        $free = $true
        foreach ($port in $ports) {
            $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $port)
            try { $listener.Start() } catch { $free = $false } finally { $listener.Stop() }
            if (-not $free) { break }
        }
        if (-not $free) { continue }
        $udp = $null
        try { $udp = [System.Net.Sockets.UdpClient]::new($base) } catch { $free = $false } finally { if ($udp) { $udp.Dispose() } }
        if ($free) { return $base }
    }
    throw 'Could not find an isolated free test port set.'
}
function Start-ForeignListener([int]$Port) {
    $script = Join-Path $testRoot 'scripts\WorldDockLifecycleForeignListener.py'
    $proc = Start-Process -FilePath $pythonPath -ArgumentList @(('"' + $script + '"'),'--port',[string]$Port) -WindowStyle Hidden -PassThru
    $spawned.Add($proc.Id)
    $deadline = [DateTime]::UtcNow.AddSeconds(5)
    while ([DateTime]::UtcNow -lt $deadline) {
        try { $response = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 1; if ($response.StatusCode -eq 200) { return $proc } } catch { }
        Start-Sleep -Milliseconds 100
    }
    throw "Foreign test listener failed to bind TCP/$Port."
}

try {
    New-Item -ItemType Directory -Path (Join-Path $testRoot '.local'), (Join-Path $testRoot 'logs'), (Join-Path $testRoot 'scripts'), (Join-Path $testRoot 'registration'), (Join-Path $testRoot 'server\OpenSimulator-0.9.3.0\bin') -Force | Out-Null
    $scriptNames = @('Start-World.ps1','Start-WorldLifecycleFixture.ps1','WorldDockLifecycleWorker.py','WorldDockLifecycleForeignListener.py','WorldDock.ProcessIdentity.psm1','Stop-World.ps1','Stop-WorldLifecycleFixture.ps1','Restart-World.ps1','Recover-World.ps1','Get-WorldServiceStatus.ps1')
    foreach ($name in $scriptNames) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $testRoot 'scripts' $name) }
    foreach ($name in @('Start-Registration.ps1','Stop-Registration.ps1','server.py')) { Copy-Item -LiteralPath (Join-Path $sourceRoot 'registration' $name) -Destination (Join-Path $testRoot 'registration' $name) }
    $basePort = Find-FreePortSet
    $install = [ordered]@{ schemaVersion=1; instanceId=[guid]::NewGuid().ToString(); worldPort=$basePort; registrationPort=($basePort+80); remoteAdminPort=($basePort+10000) }
    [System.IO.File]::WriteAllText((Join-Path $testRoot '.local\install.json'), ($install | ConvertTo-Json), [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText((Join-Path $testRoot 'server\OpenSimulator-0.9.3.0\bin\OpenSim.ini'), "[RemoteAdmin]`naccess_password = `"fixture-password`"`n", [System.Text.UTF8Encoding]::new($false))
    $fixture = [ordered]@{ Purpose='WOW-WORLDDOCK-LIFECYCLE-TEST'; PythonPath=$pythonPath }
    [System.IO.File]::WriteAllText((Join-Path $testRoot '.local\lifecycle-test-fixture.json'), ($fixture | ConvertTo-Json), [System.Text.UTF8Encoding]::new($false))

    $start = Join-Path $testRoot 'scripts\Start-World.ps1'
    $stop = Join-Path $testRoot 'scripts\Stop-World.ps1'
    $restart = Join-Path $testRoot 'scripts\Restart-World.ps1'
    $recover = Join-Path $testRoot 'scripts\Recover-World.ps1'
    $statePath = Join-Path $testRoot '.local\opensim-process.json'
    $regStatePath = Join-Path $testRoot '.local\registration-process.json'

    $null = & $start -LifecycleTestFixture
    $first = Assert-ServiceState 'Running' 'OpenSimulator'
    Assert ($first.Services.Registration.Status -eq 'Running') 'Registration must report healthy independently.'
    Assert ($first.Services.RemoteAdmin.Status -eq 'Running') 'RemoteAdmin must report healthy independently.'
    $firstPid = [int]$first.Services.OpenSimulator.ProcessId
    $firstRegPid = [int]$first.Services.Registration.ProcessId
    $null = & $start -LifecycleTestFixture
    $second = Assert-ServiceState 'Running' 'OpenSimulator'
    Assert ([int]$second.Services.OpenSimulator.ProcessId -eq $firstPid) 'Repeated start must not create a duplicate simulator.'
    Assert ([int]$second.Services.Registration.ProcessId -eq $firstRegPid) 'Repeated start must not create a duplicate registration process.'
    $results.Add('PASS: start all three health checks; repeat start retained both process IDs without duplicates.')

    & (Join-Path $testRoot 'registration\Stop-Registration.ps1')
    $simulatorOnly = Assert-ServiceState 'Stopped' 'Registration'
    Assert ($simulatorOnly.Services.OpenSimulator.Status -eq 'Running') 'Stopping registration alone must leave a healthy OpenSimulator process running.'
    $simulatorPidBeforeRepair = [int]$simulatorOnly.Services.OpenSimulator.ProcessId
    $null = & $start -LifecycleTestFixture
    $registrationRepaired = Assert-ServiceState 'Running' 'OpenSimulator'
    Assert ([int]$registrationRepaired.Services.OpenSimulator.ProcessId -eq $simulatorPidBeforeRepair) 'Starting a missing registration service must not duplicate or restart OpenSimulator.'
    Assert ([int]$registrationRepaired.Services.Registration.ProcessId -ne $firstRegPid) 'Start must create the missing registration service.'
    $results.Add('PASS: with OpenSimulator already healthy and registration stopped, Start created only registration and retained the simulator PID.')

    & (Join-Path $testRoot 'scripts\Stop-WorldLifecycleFixture.ps1') -ProjectRoot $testRoot -TimeoutSeconds 15
    $registrationOnly = Assert-ServiceState 'Stopped' 'OpenSimulator'
    Assert ($registrationOnly.Services.Registration.Status -eq 'Running') 'Stopping the simulator fixture alone must leave registration running.'
    $registrationPidBeforeRepair = [int]$registrationOnly.Services.Registration.ProcessId
    $null = & $start -LifecycleTestFixture
    $simulatorRepaired = Assert-ServiceState 'Running' 'OpenSimulator'
    Assert ([int]$simulatorRepaired.Services.OpenSimulator.ProcessId -ne $simulatorPidBeforeRepair) 'Start must create the missing OpenSimulator process.'
    Assert ([int]$simulatorRepaired.Services.Registration.ProcessId -eq $registrationPidBeforeRepair) 'Starting a missing simulator must not duplicate registration.'
    $results.Add('PASS: with registration already healthy and OpenSimulator stopped, Start created only OpenSimulator and retained the registration PID.')

    $null = & $stop -LifecycleTestFixture -TimeoutSeconds 15
    $null = Assert-ServiceState 'Stopped' 'OpenSimulator'
    Assert-ServiceState 'Stopped' 'Registration' | Out-Null
    Assert-ServiceState 'Stopped' 'RemoteAdmin' | Out-Null
    $null = & $stop -LifecycleTestFixture -TimeoutSeconds 15
    $results.Add('PASS: graceful stop released world TCP/UDP, RemoteAdmin TCP and registration HTTP; repeat stop was idempotent.')

    $null = & $restart -LifecycleTestFixture -TimeoutSeconds 15
    $afterRestart = Assert-ServiceState 'Running' 'OpenSimulator'
    Assert ([int]$afterRestart.Services.OpenSimulator.ProcessId -ne $firstPid) 'Restart must start a fresh process after verified shutdown.'
    $restartPid = [int]$afterRestart.Services.OpenSimulator.ProcessId
    $null = & $restart -LifecycleTestFixture -TimeoutSeconds 15
    $afterSecondRestart = Assert-ServiceState 'Running' 'OpenSimulator'
    Assert ([int]$afterSecondRestart.Services.OpenSimulator.ProcessId -ne $restartPid) 'A second restart must also replace the prior process after shutdown.'
    $null = & $stop -LifecycleTestFixture -TimeoutSeconds 15
    $results.Add('PASS: two consecutive restart cycles completed verified stop-before-start and produced new simulator PIDs.')

    $foreign = Start-ForeignListener ([int]$install.registrationPort)
    $failedAsExpected = $false
    try { $null = & $start -LifecycleTestFixture } catch { $failedAsExpected = $_.Exception.Message -match 'registration fixture failed startup|Registration service' }
    Assert $failedAsExpected 'Registration port conflict should fail startup rather than report a partial success.'
    Assert ([bool](Get-Process -Id $foreign.Id -ErrorAction SilentlyContinue)) 'Rollback must leave the unrelated registration-port listener alive.'
    Assert (-not (Test-Path -LiteralPath $statePath)) 'Partial registration startup failure must roll back the newly started simulator.'
    Assert (-not (Test-Path -LiteralPath $regStatePath)) 'No registration process record should be written for a refused unowned listener.'
    Stop-Process -Id $foreign.Id -Force; $spawned.Remove($foreign.Id) | Out-Null
    $null = Assert-ServiceState 'Stopped' 'OpenSimulator'
    $results.Add('PASS: reserved registration port caused startup failure; only the new simulator rolled back, and the unrelated listener remained running.')

    $stale = [ordered]@{ ProcessId=2147483647; DotnetPath=$pythonPath; ServerBin='stale'; ProcessStartUtc='2000-01-01T00:00:00.0000000Z'; CommandLineNeedle='WorldDockLifecycleWorker.py'; TestFixture=$true; HttpPort=$install.worldPort; ReadyUtc=$null }
    [System.IO.File]::WriteAllText($statePath, ($stale | ConvertTo-Json), [System.Text.UTF8Encoding]::new($false))
    $staleReg = [ordered]@{ ProcessId=2147483647; PythonPath=$pythonPath; ProcessStartUtc='2000-01-01T00:00:00.0000000Z'; Port=$install.registrationPort }
    [System.IO.File]::WriteAllText($regStatePath, ($staleReg | ConvertTo-Json), [System.Text.UTF8Encoding]::new($false))
    $null = & $recover -Confirm:$false
    Assert (-not (Test-Path -LiteralPath $statePath) -and -not (Test-Path -LiteralPath $regStatePath)) 'Recovery should clear only records with absent PIDs and free ports.'
    $results.Add('PASS: recovery removed stale OpenSimulator and registration records only after confirming absent PIDs and released ports.')

    $responsive = & $start -LifecycleTestFixture
    $healthyPid = [int](Assert-ServiceState 'Running' 'OpenSimulator').Services.OpenSimulator.ProcessId
    $refusedResponsiveRecovery = $false
    try { $null = & $recover -ForceOwnedProcesses -Confirm:$false } catch { $refusedResponsiveRecovery = $_.Exception.Message -match 'still passes its health check' }
    Assert $refusedResponsiveRecovery 'Force recovery must refuse to stop a responsive project-owned service.'
    Assert ([bool](Get-Process -Id $healthyPid -ErrorAction SilentlyContinue)) 'Responsive OpenSimulator process must remain alive after recovery refusal.'
    $null = & $stop -LifecycleTestFixture -TimeoutSeconds 15
    $results.Add('PASS: recovery refused to force-stop a responsive OpenSimulator process; graceful stop remained available.')

    $worker = Join-Path $testRoot 'scripts\WorldDockLifecycleWorker.py'
    $unresponsive = Start-Process -FilePath $pythonPath -ArgumentList @(('"' + $worker + '"'),'--world-port',[string]$install.worldPort,'--remote-admin-port',[string]$install.remoteAdminPort,'--unresponsive') -WorkingDirectory $testRoot -WindowStyle Hidden -PassThru
    $spawned.Add($unresponsive.Id)
    Start-Sleep -Milliseconds 400
    $unresponsiveState = [ordered]@{ ProcessId=$unresponsive.Id; DotnetPath=$pythonPath; ServerBin=$worker; ProcessStartUtc=$unresponsive.StartTime.ToUniversalTime().ToString('o'); CommandLineNeedle='WorldDockLifecycleWorker.py'; TestFixture=$true; HttpPort=$install.worldPort; ReadyUtc='2000-01-01T00:00:00Z' }
    [System.IO.File]::WriteAllText($statePath, ($unresponsiveState | ConvertTo-Json), [System.Text.UTF8Encoding]::new($false))
    $null = & $recover -ForceOwnedProcesses -Confirm:$false
    Assert (-not (Get-Process -Id $unresponsive.Id -ErrorAction SilentlyContinue)) 'Verified unresponsive owned process should be recovered.'
    Assert (-not (Test-Path -LiteralPath $statePath)) 'Recovered unresponsive process record should be removed after verification.'
    $spawned.Remove($unresponsive.Id) | Out-Null
    $results.Add('PASS: explicit recovery stopped an unresponsive fixture process only after PID, executable, command line, start time and port ownership checks passed.')

    $foreign = Start-ForeignListener ($install.registrationPort + 1)
    $unsafeState = [ordered]@{ ProcessId=$foreign.Id; PythonPath=$pythonPath; ProcessStartUtc=(Get-Process -Id $foreign.Id).StartTime.ToUniversalTime().ToString('o'); Port=$install.registrationPort }
    [System.IO.File]::WriteAllText($regStatePath, ($unsafeState | ConvertTo-Json), [System.Text.UTF8Encoding]::new($false))
    $refusedForeign = $false
    try { $null = & $recover -ForceOwnedProcesses -Confirm:$false } catch { $refusedForeign = $_.Exception.Message -match 'does not match|does not identify|refusing recovery' }
    Assert $refusedForeign 'Recovery must reject a record whose PID executable does not match the project-owned service.'
    Assert ([bool](Get-Process -Id $foreign.Id -ErrorAction SilentlyContinue)) 'Recovery must not terminate an unrelated process.'
    Remove-Item -LiteralPath $regStatePath -Force
    Stop-Process -Id $foreign.Id -Force; $spawned.Remove($foreign.Id) | Out-Null
    $results.Add('PASS: recovery rejected a forged/reused PID record and left the unrelated process running.')

    Write-Output 'WORLDDOCK LIFECYCLE FIXTURE RESULTS'
    $results | ForEach-Object { Write-Output $_ }
    Write-Output 'All isolated lifecycle checks passed.'
}
finally {
    foreach ($id in @($spawned)) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue }
    $resolved = [System.IO.Path]::GetFullPath($testRoot)
    if ($KeepArtifacts) { Write-Warning "Lifecycle test artifacts retained at $resolved" }
    elseif ($resolved.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolved)) { Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue }
}
