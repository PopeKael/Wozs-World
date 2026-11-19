[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$privateRoot = Join-Path $projectRoot '.local'
$settings = Get-Content -LiteralPath (Join-Path $privateRoot 'install.json') -Raw | ConvertFrom-Json
$profiles = @(Get-NetFirewallProfile -PolicyStore ActiveStore)
$unsafeProfiles = @($profiles | Where-Object { -not $_.Enabled -or [string]$_.DefaultInboundAction -ne 'Block' })
if (-not $profiles.Count -or $unsafeProfiles.Count) {
    $summary = @($unsafeProfiles | ForEach-Object { "$($_.Name) (enabled=$($_.Enabled), inbound=$($_.DefaultInboundAction))" }) -join ', '
    if (-not $summary) { $summary = 'no effective profiles were returned' }
    throw "Local-only startup requires enabled Windows Firewall profiles with inbound default Block: $summary. No firewall settings were changed."
}

$remotePort = [int]$settings.remoteAdminPort
$openSimIni = Join-Path $projectRoot 'server\OpenSimulator-0.9.3.0\bin\OpenSim.ini'
if (Test-Path -LiteralPath $openSimIni) {
    $ini = [IO.File]::ReadAllText($openSimIni)
    if ($ini -notmatch '(?im)^\s*access_ip_addresses\s*=\s*["'']?127\.0\.0\.1["'']?\s*$') { throw 'RemoteAdmin is not restricted to 127.0.0.1.' }
    if ($ini -notmatch '(?im)^\s*bind_ip_address\s*=\s*["'']127\.0\.0\.1["'']\s*$') { throw 'RemoteAdmin is not bound to 127.0.0.1.' }
}
$regionsIni = Join-Path $projectRoot 'server\OpenSimulator-0.9.3.0\bin\Regions\Regions.ini'
if (Test-Path -LiteralPath $regionsIni) {
    $regionConfig = [IO.File]::ReadAllText($regionsIni)
    if ($regionConfig -notmatch '(?im)^\s*InternalAddress\s*=\s*127\.0\.0\.1\s*$') { throw 'The region UDP listener is not bound to 127.0.0.1.' }
    if ($regionConfig -notmatch '(?im)^\s*ExternalHostName\s*=\s*127\.0\.0\.1\s*$') { throw 'The region is not advertising 127.0.0.1.' }
}
$registration = [IO.File]::ReadAllText((Join-Path $projectRoot 'registration\server.py'))
if ($registration -notmatch "ThreadingHTTPServer\(\('127\.0\.0\.1', port\)") { throw 'The registration service is not bound to loopback.' }

# Windows Firewall's active profiles use inbound-default-deny unless a matching
# allow rule exists. Check there is no explicit allow rule for this installation's
# dedicated TCP/UDP or RemoteAdmin ports; never add allow rules or router mappings.
$ports = @([int]$settings.worldPort, [int]$settings.registrationPort, $remotePort)
$dotnetPath = [System.IO.Path]::GetFullPath((Join-Path $projectRoot 'runtime\dotnet8\dotnet.exe'))
$allowRules = Get-NetFirewallRule -PolicyStore ActiveStore -Enabled True -Direction Inbound -Action Allow
foreach ($rule in $allowRules) {
    $portFilter = Get-NetFirewallPortFilter -AssociatedNetFirewallRule $rule
    if (-not $portFilter -or $portFilter.Protocol -notin @('TCP', 'UDP', '6', '17', 'Any', '256')) { continue }
    $matchesPort = $false
    foreach ($entry in @($portFilter.LocalPort)) {
        foreach ($part in ([string]$entry -split ',')) {
            if ($part -eq 'Any') { $matchesPort = $true; break }
            if ($part -match '^([0-9]+)-([0-9]+)$') {
                if (@($ports | Where-Object { $_ -ge [int]$Matches[1] -and $_ -le [int]$Matches[2] }).Count) { $matchesPort = $true; break }
            }
            elseif ($part -match '^\d+$' -and $ports -contains [int]$part) { $matchesPort = $true; break }
        }
        if ($matchesPort) { break }
    }
    if ($matchesPort) {
        $applicationFilter = Get-NetFirewallApplicationFilter -AssociatedNetFirewallRule $rule
        $serviceFilter = Get-NetFirewallServiceFilter -AssociatedNetFirewallRule $rule
        $program = [string]$applicationFilter.Program
        $package = [string]$applicationFilter.Package
        $service = [string]$serviceFilter.Service
        if ($package) { continue }
        if ($program -and $program -ne 'Any' -and [System.IO.Path]::GetFullPath($program) -ine $dotnetPath) { continue }
        if ($service -and $service -ne 'Any') { continue }
        throw "Enabled inbound allow rule '$($rule.DisplayName)' may expose a selected local service port. Disable or narrow that rule before starting this world."
    }
}
Write-Output 'Local-only boundary checks passed: Windows Firewall profiles are enabled, registration and RemoteAdmin are loopback-restricted, and this installation does not add inbound allow rules or router mappings.'
