[CmdletBinding()]
param([Parameter(ValueFromPipeline = $true)][string]$RequestJson)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$settings = Get-Content -LiteralPath (Join-Path $root '.local\install.json') -Raw | ConvertFrom-Json
$iniPath = Join-Path $root 'server\OpenSimulator-0.9.3.0\bin\OpenSim.ini'
$ini = [IO.File]::ReadAllText($iniPath)
$adminMatch = [regex]::Match($ini, '(?m)^\s*access_password\s*=\s*"([^"]+)"')
if (-not $adminMatch.Success) { throw 'Local account service credentials are not configured.' }
$requestText = if ($PSBoundParameters.ContainsKey('RequestJson')) { $RequestJson } else { [Console]::In.ReadToEnd() }
$request = $requestText | ConvertFrom-Json
if ($request.password.Length -lt 8 -or $request.password.Length -gt 128 -or $request.password -match '[\x00-\x1f]') { throw 'Password does not meet the local account form rules.' }
foreach ($field in @('first_name', 'last_name')) {
    if ([string]$request.$field -notmatch '^[A-Za-z0-9_-]{1,31}$') { throw 'Account names may contain letters, numbers, hyphens and underscores, up to 31 characters.' }
}
if ([string]$request.email -match '[\x00-\x1f]' -or ([string]$request.email).Length -gt 254) { throw 'Email address is too long or contains a control character.' }
$payload = [ordered]@{
    url = "http://127.0.0.1:$([int]$settings.remoteAdminPort)/"
    admin_password = $adminMatch.Groups[1].Value
    user_firstname = [string]$request.first_name
    user_lastname = [string]$request.last_name
    user_password = [string]$request.password
    user_email = [string]$request.email
    start_region_x = 1000
    start_region_y = 1000
}
$json = $payload | ConvertTo-Json -Compress
$python = Join-Path $root 'runtime\python\python.exe'
$code = 'import json,sys,xmlrpc.client; d=json.load(sys.stdin); p=d.pop("url"); r=xmlrpc.client.ServerProxy(p,allow_none=True).admin_create_user({"password":d.pop("admin_password"),**d}); print("ACCOUNT_CREATED" if r.get("success") else "ACCOUNT_NOT_CREATED"); sys.exit(0 if r.get("success") else 2)'
$previousEncoding = $OutputEncoding
try {
    $OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $json | & $python -c $code
}
finally { $OutputEncoding = $previousEncoding }
if ($LASTEXITCODE -ne 0) { throw 'OpenSimulator did not confirm account creation. Check the name and current simulator state before trying again.' }
