[CmdletBinding()]
param(
    [ValidateRange(15,300)][int]$TimeoutSeconds = 120,
    [switch]$LifecycleTestFixture
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
& (Join-Path $PSScriptRoot 'Stop-World.ps1') -TimeoutSeconds $TimeoutSeconds -LifecycleTestFixture:$LifecycleTestFixture
$status = & (Join-Path $PSScriptRoot 'Get-WorldServiceStatus.ps1')
foreach ($name in @('OpenSimulator','Registration','RemoteAdmin')) {
    if ($status.Services.$name.Status -ne 'Stopped') { throw "Verified shutdown did not complete: $name is $($status.Services.$name.Status). Start was not attempted." }
}
Write-Output 'Verified shutdown complete; starting the services again.'
& (Join-Path $PSScriptRoot 'Start-World.ps1') -LifecycleTestFixture:$LifecycleTestFixture
$status = & (Join-Path $PSScriptRoot 'Get-WorldServiceStatus.ps1')
foreach ($name in @('OpenSimulator','Registration','RemoteAdmin')) {
    if ($status.Services.$name.Status -ne 'Running') { throw "Restart returned from startup, but $name is $($status.Services.$name.Status). Inspect its service-specific status and logs." }
}
Write-Output 'Restart verified: OpenSimulator, registration and RemoteAdmin are all healthy.'
