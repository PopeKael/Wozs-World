[CmdletBinding()]
param([switch]$LifecycleTestFixture, [string]$PythonPath)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$python = Join-Path $projectRoot 'runtime\python\python.exe'
$pythonIsProjectLocal = Test-Path -LiteralPath $python -PathType Leaf
if (-not $pythonIsProjectLocal) {
    $systemPython = Get-Command python.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $systemPython) { throw 'Python is unavailable. Install the project-local runtime or make python.exe available on PATH.' }
    $python = $systemPython.Source
}
$fixturePath = Join-Path $projectRoot '.local\lifecycle-test-fixture.json'
if ($LifecycleTestFixture) {
    if (-not (Test-Path -LiteralPath $fixturePath)) { throw 'The lifecycle fixture marker is missing.' }
    $fixture = Get-Content -LiteralPath $fixturePath -Raw | ConvertFrom-Json
    if ($fixture.Purpose -ne 'WOW-WORLDDOCK-LIFECYCLE-TEST' -or -not $PythonPath -or [System.IO.Path]::GetFullPath($PythonPath) -ine [System.IO.Path]::GetFullPath([string]$fixture.PythonPath)) { throw 'The fixture Python override is not authorized by the isolated lifecycle fixture marker.' }
    $python = [System.IO.Path]::GetFullPath($PythonPath)
}
$scriptPath = Join-Path $PSScriptRoot 'server.py'
$localRoot = Join-Path $projectRoot '.local'
$identityModule = Join-Path $projectRoot 'scripts\WorldDock.ProcessIdentity.psm1'
Import-Module -Name $identityModule -Force
$statePath = Join-Path $localRoot 'registration-process.json'
$tokenPath = Join-Path $localRoot 'registration-control-token.txt'
$logsRoot = Join-Path $projectRoot 'logs'

if (-not (Test-Path -LiteralPath $python -PathType Leaf)) { throw "The registration Python executable is missing: $python." }
$install = Get-Content -LiteralPath (Join-Path $localRoot 'install.json') -Raw | ConvertFrom-Json
$port = [int]$install.registrationPort

function Get-RegistrationIdentity([int]$ProcessId) {
    return Get-WorldDockProcessIdentity -ProcessId $ProcessId
}

function Test-RegistrationIdentity($Record) {
    if (-not $Record -or -not $Record.ProcessId) { return $false }
    $actual = Get-RegistrationIdentity ([int]$Record.ProcessId)
    if (-not $actual -or -not $actual.Path) { return $false }
    if ([System.IO.Path]::GetFullPath($actual.Path) -ine [System.IO.Path]::GetFullPath($python)) { return $false }
    if ($actual.CommandLine.IndexOf('server.py', [StringComparison]::OrdinalIgnoreCase) -lt 0) { return $false }
    if ($Record.ProcessStartUtc -and $actual.StartedUtc -and ([DateTime]$Record.ProcessStartUtc).ToUniversalTime().ToString('o') -ne ([DateTime]$actual.StartedUtc).ToUniversalTime().ToString('o')) { return $false }
    return $true
}

function Test-TcpOpen([int]$Port) {
    $probe = [System.Net.Sockets.TcpClient]::new()
    try { $probe.Connect('127.0.0.1', $Port); return $true } catch { return $false } finally { $probe.Dispose() }
}

function Get-TcpOwners([int]$Port) {
    $netstat = Join-Path $env:SystemRoot 'System32\netstat.exe'
    $owners = @()
    foreach ($line in (& $netstat -ano -p tcp 2>$null)) {
        $fields = $line.Trim() -split '\s+'
        if ($fields.Count -lt 5 -or $fields[0] -ine 'TCP' -or $fields[1] -notmatch (':' + [regex]::Escape([string]$Port) + '$') -or $fields[3] -ne 'LISTENING') { continue }
        $owner = 0
        if ([int]::TryParse($fields[-1], [ref]$owner)) { $owners += $owner }
    }
    return @($owners | Sort-Object -Unique)
}

function Write-State($Value) {
    $tmp = "$statePath.tmp"
    [System.IO.File]::WriteAllText($tmp, ($Value | ConvertTo-Json -Depth 5), [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination $statePath -Force
}

New-Item -ItemType Directory -Path $localRoot, $logsRoot -Force | Out-Null
$state = $null
if (Test-Path -LiteralPath $statePath) {
    try { $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json } catch { throw 'The registration process record is unreadable; use Recover-World.ps1 after checking its listener.' }
    if (Test-RegistrationIdentity $state) {
        if (-not (Test-TcpOpen $port)) { throw "Registration PID $($state.ProcessId) is owned by this project but HTTP/$port is not responding; use safe recovery." }
        if (-not $LifecycleTestFixture -and @(Get-TcpOwners $port) -notcontains [int]$state.ProcessId) { throw "Registration PID $($state.ProcessId) does not own the configured HTTP/$port listener; no second process was started." }
        $healthy = $false
        try { $healthy = (Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$port/health" -TimeoutSec 2).StatusCode -eq 200 } catch { }
        if (-not $healthy) { throw "Registration PID $($state.ProcessId) is present but its health endpoint failed; use safe recovery." }
        Write-Output "Registration service is already ready (PID $($state.ProcessId)); no duplicate process was started."
        return
    }
    $recordedPidAlive = [bool](Get-Process -Id ([int]$state.ProcessId) -ErrorAction SilentlyContinue)
    if ($recordedPidAlive) { throw "Recorded registration PID $($state.ProcessId) no longer matches the expected Python/script identity. Refusing to start or stop it." }
    if (Test-TcpOpen $port) { throw "Registration HTTP/$port is occupied but its recorded process is gone. Refusing to adopt or terminate that listener." }
    Remove-Item -LiteralPath $statePath -Force
}

if (Test-TcpOpen $port) {
    $owners = @(Get-TcpOwners $port)
    throw "Registration HTTP/$port is already owned by an unrecorded process (PID(s): $($owners -join ', ')). No duplicate service was started."
}

$tokenBytes = New-Object byte[] 32
$random = [System.Security.Cryptography.RandomNumberGenerator]::Create()
try {
    $random.GetBytes($tokenBytes)
    $token = (($tokenBytes | ForEach-Object { $_.ToString('x2') }) -join '')
}
finally { $random.Dispose() }
[System.IO.File]::WriteAllText($tokenPath, $token, [System.Text.Encoding]::ASCII)
[Array]::Clear($tokenBytes, 0, $tokenBytes.Length)
$stdout = Join-Path $logsRoot 'registration.stdout.log'
$stderr = Join-Path $logsRoot 'registration.stderr.log'
$process = Start-Process -FilePath $python -ArgumentList @('"' + $scriptPath + '"') -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
$identity = $null
for ($identityAttempt = 0; $identityAttempt -lt 10; $identityAttempt++) {
    $identity = Get-RegistrationIdentity $process.Id
    if ($identity -and $identity.Path -and [System.IO.Path]::GetFullPath($identity.Path) -ieq [System.IO.Path]::GetFullPath($python) -and $identity.CommandLine.IndexOf('server.py', [StringComparison]::OrdinalIgnoreCase) -ge 0) { break }
    if (-not (Get-Process -Id $process.Id -ErrorAction SilentlyContinue)) { break }
    Start-Sleep -Milliseconds 100
}
if (-not $identity -or -not $identity.Path -or [System.IO.Path]::GetFullPath($identity.Path) -ine [System.IO.Path]::GetFullPath($python) -or $identity.CommandLine.IndexOf('server.py', [StringComparison]::OrdinalIgnoreCase) -lt 0) {
    $stderrTail = if (Test-Path -LiteralPath $stderr) { Get-Content -LiteralPath $stderr -Tail 12 | Out-String } else { '' }
    throw "Could not verify the newly started registration process identity for PID $($process.Id) (alive=$([bool](Get-Process -Id $process.Id -ErrorAction SilentlyContinue)); error log: $stderr). $stderrTail"
}
$startUtc = if ($identity.StartedUtc) { $identity.StartedUtc } else { $process.StartTime.ToUniversalTime().ToString('o') }
$state = [ordered]@{ ProcessId = $process.Id; PythonPath = [System.IO.Path]::GetFullPath($python); ScriptPath = [System.IO.Path]::GetFullPath($scriptPath); ProcessStartUtc = $startUtc; StartedUtc = [DateTime]::UtcNow.ToString('o'); Port = $port; StdoutLog = [System.IO.Path]::GetFullPath($stdout); StderrLog = [System.IO.Path]::GetFullPath($stderr) }
Write-State $state

$ready = $false
$lastHealthCheck = 'No HTTP health response was received.'
$lastOwners = @()
$lastIdentityMatch = $false
for ($attempt = 0; $attempt -lt 20; $attempt++) {
    if (-not (Get-Process -Id $process.Id -ErrorAction SilentlyContinue)) { break }
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$port/health" -TimeoutSec 1
        $lastHealthCheck = "HTTP $($response.StatusCode): $($response.Content)"
        $lastOwners = @(Get-TcpOwners $port)
        $lastIdentityMatch = Test-RegistrationIdentity $state
        if ($response.StatusCode -eq 200 -and $response.Content -match '"status"\s*:\s*"ready"' -and ($LifecycleTestFixture -or ($lastOwners -contains [int]$process.Id)) -and $lastIdentityMatch) { $ready = $true; break }
    } catch { $lastHealthCheck = $_.Exception.Message }
    Start-Sleep -Milliseconds 500
}
if (-not $ready) {
    $stillOwned = Test-RegistrationIdentity $state
    if ($stillOwned) { Stop-Process -Id $process.Id -ErrorAction SilentlyContinue; Wait-Process -Id $process.Id -Timeout 5 -ErrorAction SilentlyContinue }
    if (-not (Test-TcpOpen $port)) { Remove-Item -LiteralPath $statePath, $tokenPath -Force -ErrorAction SilentlyContinue }
    $alive = [bool](Get-Process -Id $process.Id -ErrorAction SilentlyContinue)
    $ownerSummary = if ($lastOwners.Count) { $lastOwners -join ', ' } else { 'none reported' }
    throw "Registration service failed readiness on HTTP/$port. Last health result: $lastHealthCheck; listener owner PID(s): $ownerSummary; recorded process alive: $alive; identity verified: $lastIdentityMatch. See $stdout and $stderr."
}
Write-Output "Registration service is ready at http://127.0.0.1:$port/login (PID $($process.Id)); health endpoint passed."
