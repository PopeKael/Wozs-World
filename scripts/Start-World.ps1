[CmdletBinding()]
param(
    [switch]$Follow
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$serverBin = Join-Path $projectRoot 'server\OpenSimulator-0.9.3.0\bin'
$dotnet = Join-Path $projectRoot 'runtime\dotnet8\dotnet.exe'
$sqliteDll = Join-Path $serverBin 'sqlite3.dll'
$openSimIni = Join-Path $serverBin 'OpenSim.ini'
$regionsIni = Join-Path $serverBin 'Regions\Regions.ini'
$statePath = Join-Path $projectRoot '.local\opensim-process.json'
$logsRoot = Join-Path $projectRoot 'logs'
$installConfig = Join-Path $projectRoot '.local\install.json'
if (-not (Test-Path -LiteralPath $installConfig)) { throw 'Local install settings are missing. Run scripts\Install-World.ps1 first.' }
$port = [int](Get-Content -LiteralPath $installConfig -Raw | ConvertFrom-Json).worldPort

foreach ($requiredPath in @($serverBin, $dotnet, $sqliteDll, $openSimIni, $regionsIni)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required path is missing: $requiredPath. Run Initialize-WorldConfig.ps1 after installing the official runtime and binary package."
    }
}

& (Join-Path $projectRoot 'scripts\Install-LocalFirewallBoundary.ps1')

$sqliteHash = (Get-FileHash -LiteralPath $sqliteDll -Algorithm SHA256).Hash
if ($sqliteHash -ne '4B59D3CDED9DC1608544160F3B4B10AC974C6AC0D6FFC23064E5F4C8DBD05AEA') {
    throw "The project-local SQLite runtime is not the verified 3.54.1 binary (SHA-256 $sqliteHash)."
}

$runtimeList = (& $dotnet --list-runtimes 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0 -or $runtimeList -notmatch 'Microsoft\.NETCore\.App 8\.0\.34') {
    throw "The project-local .NET 8.0.34 runtime used by the working world is missing or could not start: $runtimeList"
}

function Write-ManagedState {
    param([Parameter(Mandatory)]$Value)
    $temporaryPath = "$statePath.tmp"
    $json = $Value | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText($temporaryPath, $json, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporaryPath -Destination $statePath -Force
}

function Read-SharedLog {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    $stream = $null
    $reader = $null
    try {
        $share = [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
        $stream = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, $share)
        $reader = [System.IO.StreamReader]::new($stream)
        return $reader.ReadToEnd()
    }
    finally {
        if ($reader) { $reader.Dispose() }
        elseif ($stream) { $stream.Dispose() }
    }
}

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

$process = $null
$state = $null
$stdoutLog = $null
$stderrLog = $null
$startMutex = [System.Threading.Mutex]::new($false, 'Local\WozWorldOpenSimStart')
$ownsStartMutex = $false
try {
    try { $ownsStartMutex = $startMutex.WaitOne(0) }
    catch [System.Threading.AbandonedMutexException] { $ownsStartMutex = $true }
    if (-not $ownsStartMutex) {
        throw "Another Woz's World start command is already creating or attaching to the simulator. Wait for it to finish, then refresh the Dock."
    }

    if (Test-Path -LiteralPath $statePath) {
        $previousState = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        $previousProcess = Get-Process -Id ([int]$previousState.ProcessId) -ErrorAction SilentlyContinue
        if ($previousProcess) {
            $previousPath = $previousProcess.Path
            if (-not $previousPath -or ([System.IO.Path]::GetFullPath($previousPath) -ine [System.IO.Path]::GetFullPath($dotnet))) {
                throw "PID $($previousState.ProcessId) is occupied by a different process. Refusing to act on it."
            }
            $process = $previousProcess
            $state = $previousState
            $stdoutLog = [string]$state.StdoutLog
            $stderrLog = [string]$state.StderrLog
            if (-not $stdoutLog -or -not $stderrLog) {
                throw 'The running simulator record has no log paths; refusing to claim it is ready.'
            }
            if ($state.PSObject.Properties.Name -contains 'ReadyUtc') { $state.ReadyUtc = $null }
            else { $state | Add-Member -NotePropertyName ReadyUtc -NotePropertyValue $null }
            Write-ManagedState -Value $state
        }
        else {
            if (-not (Test-TcpPortFree -Port $port)) {
                $ownerPids = @(Get-PortOwners -Protocol tcp -Port $port)
                $owner = if ($ownerPids.Count) { " Owner PID(s): $($ownerPids -join ', ')." } else { '' }
                throw "PID $($previousState.ProcessId) is not visible to this PowerShell context, but TCP/$port is still occupied.$owner The managed record was preserved; use the desktop Dock or a normal host PowerShell session."
            }
            Remove-Item -LiteralPath $statePath
        }
    }

    if (-not $process) {
        $probe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $port)
        try { $probe.Start() }
        catch {
            $ownerPids = @(Get-PortOwners -Protocol tcp -Port $port)
            $owner = if ($ownerPids.Count) { "; listener owner PID(s) $($ownerPids -join ', ')" } else { '' }
            throw "TCP port $port cannot be bound$owner. A different process may have started while the Dock was refreshing. $($_.Exception.Message)"
        }
        finally { $probe.Stop() }

        New-Item -ItemType Directory -Path $logsRoot -Force | Out-Null
        $runStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $stdoutLog = Join-Path $logsRoot "opensim-$runStamp.stdout.log"
        $stderrLog = Join-Path $logsRoot "opensim-$runStamp.stderr.log"
        $process = Start-Process -FilePath $dotnet -ArgumentList @('OpenSim.dll', '-console=rest') -WorkingDirectory $serverBin -WindowStyle Hidden -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog -PassThru
        $state = [ordered]@{
            ProcessId = $process.Id
            DotnetPath = [System.IO.Path]::GetFullPath($dotnet)
            ServerBin = [System.IO.Path]::GetFullPath($serverBin)
            StartedUtc = [DateTime]::UtcNow.ToString('o')
            StdoutLog = [System.IO.Path]::GetFullPath($stdoutLog)
            StderrLog = [System.IO.Path]::GetFullPath($stderrLog)
            HttpPort = $port
            ReadyUtc = $null
        }
        Write-ManagedState -Value $state
    }
}
finally {
    if ($ownsStartMutex) { $startMutex.ReleaseMutex() }
    $startMutex.Dispose()
}

$iniText = [System.IO.File]::ReadAllText($openSimIni)
$userMatch = [regex]::Match($iniText, '(?m)^\s*ConsoleUser\s*=\s*"([^"]+)"')
$passMatch = [regex]::Match($iniText, '(?m)^\s*ConsolePass\s*=\s*"([^"]+)"')
if (-not $userMatch.Success -or -not $passMatch.Success -or $passMatch.Groups[1].Value -eq '__GENERATE_LOCAL_ONLY__') {
    throw 'The active REST console credentials could not be read from the ignored server configuration.'
}

$ready = $false
$regionInitialized = $false
$lastControlError = 'The loopback REST console has not responded yet.'
$sessionId = $null
for ($attempt = 0; $attempt -lt 120; $attempt++) {
    $running = Get-Process -Id $process.Id -ErrorAction SilentlyContinue
    if (-not $running) { break }

    if (-not $regionInitialized) {
        $startupOutput = Read-SharedLog -Path $stdoutLog
        $regionInitialized = $startupOutput.Contains("INITIALIZATION COMPLETE FOR Woz's World - LOGINS ENABLED")
    }

    if ($regionInitialized) {
        $tcp = [System.Net.Sockets.TcpClient]::new()
        $portReady = $false
        try {
            $connect = $tcp.BeginConnect([System.Net.IPAddress]::Loopback, $port, $null, $null)
            if ($connect.AsyncWaitHandle.WaitOne(500)) {
                $tcp.EndConnect($connect)
                $portReady = $true
            }
        }
        catch { }
        finally { $tcp.Dispose() }

        if ($portReady) {
            try {
                $sessionResponse = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$port/StartSession/" -Method Post -Body @{ USER = $userMatch.Groups[1].Value; PASS = $passMatch.Groups[1].Value } -TimeoutSec 3
                [xml]$sessionXml = $sessionResponse.Content
                $sessionId = [string]$sessionXml.ConsoleSession.SessionID
                if (-not $sessionId) { throw 'The REST console returned no session ID.' }
                $ready = $true
                break
            }
            catch { $lastControlError = $_.Exception.Message }
        }
    }
    Start-Sleep -Seconds 1
}

if ($sessionId) {
    try { Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$port/CloseSession/" -Method Post -Body @{ ID = $sessionId } -TimeoutSec 3 | Out-Null }
    catch { Write-Warning "Could not close temporary REST console session $sessionId." }
}

if (-not $ready) {
    $running = Get-Process -Id $process.Id -ErrorAction SilentlyContinue
    if (-not $running) {
        Remove-Item -LiteralPath $statePath -ErrorAction SilentlyContinue
    }
    Write-Output "OpenSimulator did not pass all readiness checks within 120 seconds. Region marker: $regionInitialized; last REST-console response: $lastControlError."
    foreach ($logPath in @($stdoutLog, $stderrLog)) {
        if (Test-Path -LiteralPath $logPath) {
            Write-Output "--- $logPath ---"
            Get-Content -LiteralPath $logPath -Tail 40
        }
    }
    throw 'Startup readiness check failed. A live process record is retained so graceful stop remains available.'
}

$state.ReadyUtc = [DateTime]::UtcNow.ToString('o')
Write-ManagedState -Value $state
Write-Output "Woz's World is ready (PID $($process.Id)); TCP/$port is reachable."
Write-Output 'The region initialization marker and authenticated loopback REST console check passed.'
Write-Output "Stdout: $stdoutLog"
Write-Output "Stderr: $stderrLog"
try { & (Join-Path $projectRoot 'registration\Start-Registration.ps1') }
catch { Write-Warning 'Registration page could not be started. The simulator remains running.' }
if ($Follow) { Get-Content -LiteralPath @($stdoutLog, $stderrLog) -Wait }
