$ErrorActionPreference = 'Stop'
$registrationRoot = $PSScriptRoot
$projectRoot = Split-Path -Parent $registrationRoot
$python = Join-Path $projectRoot 'runtime\python\python.exe'
if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
    throw "The project-local Python runtime is missing: $python. Run scripts\Install-World.ps1 first."
}
$install = Get-Content -LiteralPath (Join-Path $projectRoot '.local\install.json') -Raw | ConvertFrom-Json
$port = [int]$install.registrationPort
$probe = [System.Net.Sockets.TcpClient]::new()
try {
    $probe.Connect('127.0.0.1', $port)
    Write-Output "Registration port $port is already in use; no second service was started."
    return
}
catch { }
finally { $probe.Dispose() }
Start-Process -FilePath $python -ArgumentList @('"' + (Join-Path $registrationRoot 'server.py') + '"') -WorkingDirectory $registrationRoot -WindowStyle Hidden
Start-Sleep -Milliseconds 500
$check = [System.Net.Sockets.TcpClient]::new()
try {
    $check.Connect('127.0.0.1', $port)
}
catch {
    throw "The local registration service did not start on 127.0.0.1:$port."
}
finally { $check.Dispose() }
Write-Output "Registration service started at http://127.0.0.1:$port/login"
