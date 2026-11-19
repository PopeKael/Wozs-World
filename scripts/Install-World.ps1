[CmdletBinding()]
param(
    [ValidateSet('random', 'atoll', 'archipelago', 'mountain')]
    [string]$Template = 'random',
    [switch]$AcquireAvatarSources,
    [switch]$InstallDock
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$downloads = Join-Path $projectRoot 'downloads'
$runtimeRoot = Join-Path $projectRoot 'runtime'
$serverRoot = Join-Path $projectRoot 'server\OpenSimulator-0.9.3.0'
$pythonRoot = Join-Path $runtimeRoot 'python'
$dotnetRoot = Join-Path $runtimeRoot 'dotnet8'
$sqliteRoot = Join-Path $runtimeRoot 'sqlite3'
$privateRoot = Join-Path $projectRoot '.local'
$terrainRoot = Join-Path $privateRoot 'generated-terrain'

if (Test-Path -LiteralPath (Join-Path $privateRoot 'install.json')) {
    Write-Output 'This independent copy already has an install record. No package or world data was replaced.'
    & (Join-Path $PSScriptRoot 'Verify-World.ps1')
    return
}
foreach ($path in @($serverRoot, $pythonRoot, $dotnetRoot)) {
    if (Test-Path -LiteralPath $path) { throw "Found an existing install directory at '$path'. This installer refuses to overwrite an existing world or runtime." }
}

function Get-PinnedFile([string]$Uri, [string]$Path, [string]$Algorithm, [string]$Expected) {
    if (Test-Path -LiteralPath $Path) {
        $actual = (Get-FileHash -LiteralPath $Path -Algorithm $Algorithm).Hash
        if ($actual -ne $Expected) { throw "Cached package hash mismatch for $([IO.Path]::GetFileName($Path)); preserved the file." }
        return
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    $temporary = "$Path.download"
    try {
        Invoke-WebRequest -Uri $Uri -OutFile $temporary
        $actual = (Get-FileHash -LiteralPath $temporary -Algorithm $Algorithm).Hash
        if ($actual -ne $Expected) { throw "Downloaded package hash mismatch for $([IO.Path]::GetFileName($Path))." }
        Move-Item -LiteralPath $temporary -Destination $Path
    }
    finally { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
}

New-Item -ItemType Directory -Path $downloads, $runtimeRoot, $privateRoot, $terrainRoot, (Join-Path $projectRoot 'logs') -Force | Out-Null
$packages = @(
    @{ Name='OpenSimulator 0.9.3.0'; Uri='http://opensimulator.org/dist/opensim-0.9.3.0.zip'; File='opensim-0.9.3.0.zip'; Algorithm='SHA256'; Hash='5EB6E03C22A3F245AC365A8600EA3F963A11755385EADF33844031748C75F78E' },
    @{ Name='.NET runtime 8.0.34 (working-world baseline)'; Uri='https://builds.dotnet.microsoft.com/dotnet/Runtime/8.0.34/dotnet-runtime-8.0.34-win-x64.zip'; File='dotnet-runtime-8.0.34-win-x64.zip'; Algorithm='SHA512'; Hash='D86D165A29DCDB71DF23DD150A3FC5DB6386FA55DA5CB18C0C22889A0DAB5071A3A2D852572E6CEBFECF12B489870AC76243AE35665A746ED5B1011E7C68979D' },
    @{ Name='Python embeddable 3.14.10'; Uri='https://www.python.org/ftp/python/3.14.10/python-3.14.10-embed-amd64.zip'; File='python-3.14.10-embed-amd64.zip'; Algorithm='SHA256'; Hash='90905E64A840557D8C1BC4F5B74DB3D7EE85E3FFB217611CAC1C7813ACEA4159' },
    @{ Name='SQLite 3.54.1 x64'; Uri='https://www.sqlite.org/2026/sqlite-dll-win-x64-3540100.zip'; File='sqlite-dll-win-x64-3540100.zip'; Algorithm='DLL-SHA256'; Hash='4B59D3CDED9DC1608544160F3B4B10AC974C6AC0D6FFC23064E5F4C8DBD05AEA' }
)
foreach ($package in $packages) {
    if ($package.Algorithm -eq 'DLL-SHA256') {
        $archive = Join-Path $downloads $package.File
        if (-not (Test-Path -LiteralPath $archive)) {
            try { Invoke-WebRequest -Uri $package.Uri -OutFile "$archive.download"; Move-Item "$archive.download" $archive }
            finally { Remove-Item -LiteralPath "$archive.download" -Force -ErrorAction SilentlyContinue }
        }
        $sqliteTemp = Join-Path $runtimeRoot 'sqlite-extract'
        if (Test-Path $sqliteTemp) { Remove-Item -LiteralPath $sqliteTemp -Recurse -Force }
        Expand-Archive -LiteralPath $archive -DestinationPath $sqliteTemp
        $sqliteDll = Get-ChildItem -LiteralPath $sqliteTemp -Filter sqlite3.dll -File -Recurse | Select-Object -First 1
        if (-not $sqliteDll -or (Get-FileHash -LiteralPath $sqliteDll.FullName -Algorithm SHA256).Hash -ne $package.Hash) { throw 'Extracted SQLite DLL failed its pinned SHA-256 check.' }
        New-Item -ItemType Directory -Path $sqliteRoot -Force | Out-Null
        Copy-Item -LiteralPath $sqliteDll.FullName -Destination (Join-Path $sqliteRoot 'sqlite3.dll')
        Remove-Item -LiteralPath $sqliteTemp -Recurse -Force
    }
    else {
        Get-PinnedFile $package.Uri (Join-Path $downloads $package.File) $package.Algorithm $package.Hash
    }
    Write-Output "Verified $($package.Name)."
}

$openSimExtract = Join-Path $downloads 'opensim-extract'
New-Item -ItemType Directory -Path $openSimExtract -Force | Out-Null
Expand-Archive -LiteralPath (Join-Path $downloads 'opensim-0.9.3.0.zip') -DestinationPath $openSimExtract
$simBin = Get-ChildItem -LiteralPath $openSimExtract -Filter OpenSim.dll -File -Recurse | Select-Object -First 1 | ForEach-Object Directory
if (-not $simBin -or -not (Test-Path (Join-Path $simBin.FullName 'OpenSim.runtimeconfig.json'))) { throw 'The verified OpenSimulator archive did not contain the expected managed runtime files.' }
$simPackageRoot = $simBin.Parent.FullName
New-Item -ItemType Directory -Path (Split-Path -Parent $serverRoot) -Force | Out-Null
Move-Item -LiteralPath $simPackageRoot -Destination $serverRoot
if (-not (Test-Path (Join-Path $serverRoot 'bin\OpenSim.dll'))) { throw 'OpenSimulator extraction layout was unexpected.' }
Remove-Item -LiteralPath $openSimExtract -Recurse -Force

New-Item -ItemType Directory -Path $dotnetRoot -Force | Out-Null
Expand-Archive -LiteralPath (Join-Path $downloads 'dotnet-runtime-8.0.34-win-x64.zip') -DestinationPath $dotnetRoot
New-Item -ItemType Directory -Path $pythonRoot -Force | Out-Null
Expand-Archive -LiteralPath (Join-Path $downloads 'python-3.14.10-embed-amd64.zip') -DestinationPath $pythonRoot
& (Join-Path $pythonRoot 'python.exe') -c 'import argparse, configparser, json, pathlib, struct, urllib.parse, xmlrpc.client'
if ($LASTEXITCODE -ne 0) { throw 'The isolated Python runtime cannot load required standard-library modules.' }

$generator = Join-Path $projectRoot 'terrain\generate_terrain.py'
& (Join-Path $pythonRoot 'python.exe') $generator --template $Template --output-dir $terrainRoot
if ($LASTEXITCODE -ne 0) { throw 'Procedural terrain generation failed.' }
& (Join-Path $PSScriptRoot 'Initialize-WorldConfig.ps1')
& (Join-Path $PSScriptRoot 'Start-World.ps1')
$generatedTerrain = Get-ChildItem -LiteralPath $terrainRoot -Filter 'wow-*.r32' -File | Select-Object -First 1
if (-not $generatedTerrain) { throw 'No generated R32 terrain file was found for initial import.' }
& (Join-Path $PSScriptRoot 'Import-IslandTerrain.ps1') -TerrainPath $generatedTerrain.FullName
& (Join-Path $PSScriptRoot 'Stop-World.ps1')
& (Join-Path $PSScriptRoot 'Persist-ImportedTerrain.ps1') -TerrainPath $generatedTerrain.FullName
& (Join-Path $PSScriptRoot 'Start-World.ps1')
& (Join-Path $PSScriptRoot 'Verify-World.ps1') -RequireRunning

$settings = Get-Content -LiteralPath (Join-Path $privateRoot 'install.json') -Raw | ConvertFrom-Json
$ownerCredentials = [IO.File]::ReadAllText((Join-Path $privateRoot 'owner-credentials.txt'))
$ownerPasswordMatch = [regex]::Match($ownerCredentials, '(?m)^Password: ([A-F0-9]{64})\r?$')
if (-not $ownerPasswordMatch.Success) { throw 'The generated local owner credential record is missing a valid random password.' }
$ownerRequest = [ordered]@{
    first_name = 'World'
    last_name = 'Owner'
    password = $ownerPasswordMatch.Groups[1].Value
    email = 'world-owner@localhost.invalid'
} | ConvertTo-Json -Compress
$accountResult = $ownerRequest | & (Join-Path $PSScriptRoot 'Create-World-Account.ps1')
if ($accountResult -notcontains 'ACCOUNT_CREATED') { throw 'OpenSimulator did not confirm creation of the initial World Owner account.' }
Write-Output 'Created the initial World Owner account.'

& (Join-Path $projectRoot 'registration\Start-Registration.ps1')
$registrationUrl = "http://127.0.0.1:$([int]$settings.registrationPort)/login"
$registrationPage = Invoke-WebRequest -Uri $registrationUrl -TimeoutSec 10
if ($registrationPage.StatusCode -ne 200 -or $registrationPage.Content -notmatch 'Create account') {
    throw 'The local registration page did not return the expected account form.'
}

if ($AcquireAvatarSources) { & (Join-Path $PSScriptRoot 'Acquire-AvatarSources.ps1') }
if ($InstallDock) { & (Join-Path $PSScriptRoot 'Install-WorldDock.ps1') }
Write-Output "Independent local OpenSimulator installation completed. Create visitor accounts at $registrationUrl"
Write-Output 'The generated owner password is in the ACL-restricted ignored .local\owner-credentials.txt file.'
