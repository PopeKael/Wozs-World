[CmdletBinding()]
param([Parameter(Mandatory)][string]$ProjectRoot)
$ErrorActionPreference = 'Stop'
$identityModule = Join-Path $ProjectRoot 'scripts\WorldDock.ProcessIdentity.psm1'
Import-Module -Name $identityModule -Force
$localRoot = Join-Path $ProjectRoot '.local'
$fixture = Get-Content -LiteralPath (Join-Path $localRoot 'lifecycle-test-fixture.json') -Raw | ConvertFrom-Json
if ($fixture.Purpose -ne 'WOW-WORLDDOCK-LIFECYCLE-TEST') { throw 'Refusing lifecycle fixture mode without its explicit test marker.' }
$ports = Get-Content -LiteralPath (Join-Path $localRoot 'install.json') -Raw | ConvertFrom-Json
$statePath = Join-Path $localRoot 'opensim-process.json'
$worker = Join-Path $ProjectRoot 'scripts\WorldDockLifecycleWorker.py'
$logs = Join-Path $ProjectRoot 'logs'
New-Item -ItemType Directory -Path $logs -Force | Out-Null

function Get-Owners([ValidateSet('tcp','udp')][string]$Protocol, [int]$Port) {
    $netstat = Join-Path $env:SystemRoot 'System32\netstat.exe'; $ids = @()
    foreach ($line in (& $netstat -ano -p $Protocol 2>$null)) {
        $fields = $line.Trim() -split '\s+'
        if ($fields.Count -lt 3 -or $fields[0] -ine $Protocol.ToUpperInvariant() -or $fields[1] -notmatch (':' + [regex]::Escape([string]$Port) + '$')) { continue }
        if ($Protocol -eq 'tcp' -and ($fields.Count -lt 5 -or $fields[3] -ne 'LISTENING')) { continue }
        $id = 0; if ([int]::TryParse($fields[-1], [ref]$id)) { $ids += $id }
    }
    return @($ids | Sort-Object -Unique)
}
function Test-Free([ValidateSet('tcp','udp')][string]$Protocol, [int]$Port) {
    if ($Protocol -eq 'tcp') { $listener=[System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any,$Port); try{$listener.Start();return $true}catch{return $false}finally{$listener.Stop()} }
    $udp=$null; try{$udp=[System.Net.Sockets.UdpClient]::new($Port);return $true}catch{return $false}finally{if($udp){$udp.Dispose()}}
}
function Test-Healthy([int]$Port) { try { (Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 2).StatusCode -eq 200 } catch { $false } }
function Test-TcpOpen([int]$Port) { $client=[System.Net.Sockets.TcpClient]::new(); try{$client.Connect('127.0.0.1',$Port);return $true}catch{return $false}finally{$client.Dispose()} }
function Test-UdpOpen([int]$Port) {
    $udp = [System.Net.Sockets.UdpClient]::new()
    try {
        $udp.Client.ReceiveTimeout = 750
        $bytes = [System.Text.Encoding]::ASCII.GetBytes('WOW-LIFECYCLE-PROBE')
        $null = $udp.Send($bytes, $bytes.Length, [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Loopback, $Port))
        $remote = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
        $reply = $udp.Receive([ref]$remote)
        return [System.Text.Encoding]::ASCII.GetString($reply) -eq 'WOW-LIFECYCLE-READY'
    } catch { return $false } finally { $udp.Dispose() }
}

$state = $null
if (Test-Path -LiteralPath $statePath) {
    try { $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json } catch { throw 'Fixture OpenSimulator state is unreadable.' }
    $existing = Get-Process -Id ([int]$state.ProcessId) -ErrorAction SilentlyContinue
    if ($existing) {
        $actual = Get-WorldDockProcessIdentity -ProcessId ([int]$state.ProcessId)
        if (-not $actual -or [System.IO.Path]::GetFullPath($actual.Path) -ine [System.IO.Path]::GetFullPath([string]$fixture.PythonPath) -or -not $actual.CommandLine.Contains('WorldDockLifecycleWorker.py', [StringComparison]::OrdinalIgnoreCase)) { throw 'The fixture OpenSimulator PID identity differs; refusing duplicate start or termination.' }
        if (-not (Test-Healthy ([int]$ports.worldPort)) -or -not (Test-TcpOpen ([int]$ports.remoteAdminPort)) -or -not (Test-UdpOpen ([int]$ports.worldPort))) { throw 'Fixture OpenSimulator is recorded but not responding on each service port; use the recovery path.' }
        Write-Output "Fixture OpenSimulator already ready (PID $($state.ProcessId)); duplicate start prevented."
    }
    else {
        foreach ($port in @([int]$ports.worldPort,[int]$ports.remoteAdminPort)) { if (-not (Test-Free tcp $port)) { throw "Fixture service TCP/$port remains occupied; stale state preserved." } }
        if (-not (Test-Free udp ([int]$ports.worldPort))) { throw "Fixture service UDP/$($ports.worldPort) remains occupied; stale state preserved." }
        Remove-Item -LiteralPath $statePath -Force
        $state = $null
    }
}
if (-not $state) {
    foreach ($port in @([int]$ports.worldPort,[int]$ports.remoteAdminPort)) { if (-not (Test-Free tcp $port)) { $owners = @(Get-Owners tcp $port); throw "Fixture start refused because TCP/$port is already occupied by PID(s): $($owners -join ', ')." } }
    if (-not (Test-Free udp ([int]$ports.worldPort))) { throw "Fixture start refused because UDP/$($ports.worldPort) is already occupied." }
    $stdout = Join-Path $logs 'fixture-opensim.stdout.log'; $stderr = Join-Path $logs 'fixture-opensim.stderr.log'
    $proc = Start-Process -FilePath $fixture.PythonPath -ArgumentList @(('"' + $worker + '"'),'--world-port',[string]$ports.worldPort,'--remote-admin-port',[string]$ports.remoteAdminPort) -WorkingDirectory $ProjectRoot -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    $started = $proc.StartTime.ToUniversalTime().ToString('o')
    $state = [ordered]@{ ProcessId=$proc.Id; DotnetPath=[System.IO.Path]::GetFullPath([string]$fixture.PythonPath); ServerBin=[System.IO.Path]::GetFullPath($worker); ProcessStartUtc=$started; CommandLineNeedle='WorldDockLifecycleWorker.py'; TestFixture=$true; StdoutLog=[System.IO.Path]::GetFullPath($stdout); StderrLog=[System.IO.Path]::GetFullPath($stderr); HttpPort=[int]$ports.worldPort; ReadyUtc=$null }
    [System.IO.File]::WriteAllText($statePath, ($state | ConvertTo-Json -Depth 5), [System.Text.UTF8Encoding]::new($false))
    $ready = $false
    for ($i=0; $i -lt 40; $i++) {
        if (-not (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) { break }
        if ((Test-Healthy ([int]$ports.worldPort)) -and (Test-TcpOpen ([int]$ports.remoteAdminPort)) -and (Test-UdpOpen ([int]$ports.worldPort))) { $ready=$true; break }
        Start-Sleep -Milliseconds 250
    }
    if (-not $ready) {
        $identity = Get-WorldDockProcessIdentity -ProcessId $proc.Id
        $healthNow = Test-Healthy ([int]$ports.worldPort)
        $remoteNow = Test-TcpOpen ([int]$ports.remoteAdminPort)
        $udpNow = Test-UdpOpen ([int]$ports.worldPort)
        $stderrTail = if (Test-Path -LiteralPath $stderr) { Get-Content -LiteralPath $stderr -Tail 12 | Out-String } else { '' }
        throw "Fixture OpenSimulator readiness failed (alive=$([bool](Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)); identity=$([bool]$identity); world-health=$healthNow; RemoteAdmin-TCP=$remoteNow; world-UDP=$udpNow). State retained at $statePath. $stderrTail"
    }
    $state.ReadyUtc = [DateTime]::UtcNow.ToString('o')
    [System.IO.File]::WriteAllText($statePath, ($state | ConvertTo-Json -Depth 5), [System.Text.UTF8Encoding]::new($false))
    Write-Output "Fixture OpenSimulator ready (PID $($proc.Id)); world TCP/UDP $($ports.worldPort), RemoteAdmin TCP $($ports.remoteAdminPort)."
}

try {
    & (Join-Path $ProjectRoot 'registration\Start-Registration.ps1') -LifecycleTestFixture -PythonPath ([string]$fixture.PythonPath)
}
catch {
    $startupError = $_.Exception.Message
    Write-Warning 'Fixture registration startup failed; attempting rollback of this project-owned fixture OpenSimulator process.'
    try { & (Join-Path $ProjectRoot 'scripts\Stop-World.ps1') -LifecycleTestFixture -TimeoutSeconds 15 } catch { Write-Warning "Fixture rollback result: $($_.Exception.Message)" }
    throw "Required registration fixture failed startup: $startupError"
}
Write-Output "All fixture services are ready: OpenSimulator, registration HTTP/$($ports.registrationPort), RemoteAdmin TCP/$($ports.remoteAdminPort)."
