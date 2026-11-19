[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$serverBin = Join-Path $projectRoot 'server\OpenSimulator-0.9.3.0\bin'
$openSimIni = Join-Path $serverBin 'OpenSim.ini'
$regionsIni = Join-Path $serverBin 'Regions\Regions.ini'
$openSimTemplate = Join-Path $projectRoot 'config\OpenSim.ini.template'
$regionsTemplate = Join-Path $projectRoot 'config\Regions.ini.template'
$standaloneCommonIni = Join-Path $serverBin 'config-include\StandaloneCommon.ini'
$standaloneCommonExample = "$standaloneCommonIni.example"
$runtimeConfig = Join-Path $serverBin 'OpenSim.runtimeconfig.json'
$sqliteSource = Join-Path $projectRoot 'runtime\sqlite3\sqlite3.dll'
$sqliteTarget = Join-Path $serverBin 'sqlite3.dll'
$privateRoot = Join-Path $projectRoot '.local'
$ownerCredentials = Join-Path $privateRoot 'owner-credentials.txt'
$installRecord = Join-Path $privateRoot 'install.json'
$expectedStockIniHash = '42ADC22FAD0B80B568C3E8B71FFB1BE86784FBC85E87F5DDBD61DA29B2488DBC'
$expectedSqliteHash = '4B59D3CDED9DC1608544160F3B4B10AC974C6AC0D6FFC23064E5F4C8DBD05AEA'

if (-not (Test-Path -LiteralPath $runtimeConfig)) {
    throw "OpenSimulator 0.9.3.0 is not installed under '$serverBin'."
}

if (-not (Test-Path -LiteralPath $installRecord)) {
    function Test-InstallPortSet([int]$Candidate) {
        $ports = @($Candidate, $Candidate + 80, $Candidate + 10000)
        foreach ($port in $ports) {
            $tcp = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $port)
            try { $tcp.Start() } catch { return $false } finally { $tcp.Stop() }
            $udp = $null
            try { $udp = [System.Net.Sockets.UdpClient]::new($port) } catch { return $false } finally { if ($udp) { $udp.Dispose() } }
        }
        return $true
    }
    $selectedPort = $null
    foreach ($candidate in 9000..10000) {
        if (Test-InstallPortSet $candidate) { $selectedPort = $candidate; break }
    }
    if ($null -eq $selectedPort) { throw 'No free local world port set was found in the supported 9000-10000 range.' }
    New-Item -ItemType Directory -Path $privateRoot -Force | Out-Null
    $install = [ordered]@{
        schemaVersion = 1
        instanceId = [guid]::NewGuid().ToString()
        worldPort = [int]$selectedPort
        registrationPort = [int]($selectedPort + 80)
        remoteAdminPort = [int]($selectedPort + 10000)
        generatedUtc = [DateTime]::UtcNow.ToString('o')
    }
    [System.IO.File]::WriteAllText($installRecord, ($install | ConvertTo-Json), [System.Text.UTF8Encoding]::new($false))
}
$install = Get-Content -LiteralPath $installRecord -Raw | ConvertFrom-Json
foreach ($portName in @('worldPort', 'registrationPort', 'remoteAdminPort')) {
    if ([int]$install.$portName -lt 1024 -or [int]$install.$portName -gt 65535) { throw "Invalid local port in ${installRecord}: $portName" }
}

if (-not (Test-Path -LiteralPath $sqliteSource)) {
    throw "The verified official SQLite x64 runtime is missing: $sqliteSource"
}
$sqliteSourceHash = (Get-FileHash -LiteralPath $sqliteSource -Algorithm SHA256).Hash
if ($sqliteSourceHash -ne $expectedSqliteHash) {
    throw "The SQLite runtime SHA-256 does not match the verified 3.54.1 DLL ($sqliteSourceHash)."
}
if (Test-Path -LiteralPath $sqliteTarget) {
    $sqliteTargetHash = (Get-FileHash -LiteralPath $sqliteTarget -Algorithm SHA256).Hash
    if ($sqliteTargetHash -ne $expectedSqliteHash) {
        throw "A different sqlite3.dll is already present at '$sqliteTarget'. Refusing to overwrite it."
    }
}
else {
    Copy-Item -LiteralPath $sqliteSource -Destination $sqliteTarget
}

if ((Test-Path -LiteralPath $openSimIni) -and (Test-Path -LiteralPath $regionsIni)) {
    Write-Output 'Local world configuration already exists; nothing was changed.'
    return
}

if (Test-Path -LiteralPath $ownerCredentials) {
    throw "A local owner credential record already exists at '$ownerCredentials'. Refusing to generate a different owner password. Inspect and back up the incomplete installation first."
}

if (Test-Path -LiteralPath $regionsIni) {
    throw 'A region configuration exists without the local OpenSim.ini pair. Refusing to replace either file; inspect and back up the current server state first.'
}
if (-not (Test-Path -LiteralPath $openSimIni)) {
    throw "The stock OpenSim.ini is missing from '$serverBin'."
}

foreach ($requiredPath in @($openSimTemplate, $regionsTemplate)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required template is missing: $requiredPath"
    }
}

$stockHash = (Get-FileHash -LiteralPath $openSimIni -Algorithm SHA256).Hash
if ($stockHash -ne $expectedStockIniHash) {
    throw "The installed OpenSim.ini is not the expected untouched 0.9.3.0 default (SHA-256 $stockHash). Refusing to overwrite it."
}

$openSimText = [System.IO.File]::ReadAllText($openSimTemplate)
$regionsText = [System.IO.File]::ReadAllText($regionsTemplate)
$activeArchitecture = [regex]::Matches($openSimText, '(?m)^[ \t]*Include-Architecture[ \t]*=[ \t]*"config-include/StandaloneHypergrid\.ini"[ \t]*$')
if ($activeArchitecture.Count -ne 1) {
    throw 'The OpenSim template must select StandaloneHypergrid.ini exactly once for new installations.'
}

$commonSource = if (Test-Path -LiteralPath $standaloneCommonIni) { $standaloneCommonIni } else { $standaloneCommonExample }
if (-not (Test-Path -LiteralPath $commonSource)) {
    throw "The OpenSimulator package is missing its StandaloneCommon.ini.example: $standaloneCommonExample"
}
$standaloneCommonText = [System.IO.File]::ReadAllText($commonSource)
$hypergridSections = [regex]::Matches($standaloneCommonText, '(?ms)(^[ \t]*\[Hypergrid\][ \t]*\r?\n)(?<body>.*?)(?=^[ \t]*\[[^\]\r\n]+\][ \t]*\r?$|\z)')
if ($hypergridSections.Count -ne 1) {
    throw 'StandaloneCommon.ini must contain exactly one [Hypergrid] section.'
}
$hypergridSection = $hypergridSections[0]
$hypergridBody = $hypergridSection.Groups['body'].Value
foreach ($key in @('HomeURI', 'GatekeeperURI')) {
    $keyPattern = '(?m)^[ \t]*;?[ \t]*' + [regex]::Escape($key) + '[ \t]*=.*$'
    $keyLines = [regex]::Matches($hypergridBody, $keyPattern)
    if ($keyLines.Count -ne 1) {
        throw "StandaloneCommon.ini [Hypergrid] must contain exactly one $key setting; found $($keyLines.Count)."
    }
    $replacement = '    ' + $key + ' = "${Const|BaseURL}:${Const|PublicPort}"'
    $keyLine = $keyLines[0]
    $hypergridBody = $hypergridBody.Substring(0, $keyLine.Index) + $replacement + $hypergridBody.Substring($keyLine.Index + $keyLine.Length)
}
$commonBodyStart = $hypergridSection.Index + $hypergridSection.Groups[1].Length
$standaloneCommonText = $standaloneCommonText.Substring(0, $commonBodyStart) + $hypergridBody + $standaloneCommonText.Substring($commonBodyStart + $hypergridSection.Groups['body'].Length)
if (([regex]::Matches($openSimText, '__GENERATE_LOCAL_ONLY__')).Count -ne 1) {
    throw 'The OpenSim template must contain exactly one local console-password marker.'
}
if (([regex]::Matches($regionsText, '__GENERATE_REGION_UUID__')).Count -ne 1) {
    throw 'The region template must contain exactly one region-UUID marker.'
}
if (([regex]::Matches($regionsText, '__GENERATE_LANDING__')).Count -ne 1) {
    throw 'The region template must contain exactly one terrain landing marker.'
}
foreach ($marker in @('__GENERATE_WORLD_PORT__')) {
    if (([regex]::Matches($openSimText, [regex]::Escape($marker))).Count -ne 2) { throw "OpenSim.ini must contain exactly two $marker markers." }
    if (([regex]::Matches($regionsText, [regex]::Escape($marker))).Count -ne 1) { throw "Regions.ini must contain exactly one $marker marker." }
}
if (([regex]::Matches($openSimText, '__GENERATE_REMOTEADMIN_PORT__')).Count -ne 1) { throw 'OpenSim.ini must contain exactly one remote admin port marker.' }
foreach ($marker in @('__GENERATE_ESTATE_PASSWORD__', '__GENERATE_REMOTEADMIN_PASSWORD__')) {
    if (([regex]::Matches($openSimText, [regex]::Escape($marker))).Count -ne 1) {
        throw "The OpenSim template must contain exactly one $marker marker."
    }
}
foreach ($marker in @('__GENERATE_CERT_PASSWORD__')) {
    if (([regex]::Matches($openSimText, [regex]::Escape($marker))).Count -ne 1) {
        throw "The OpenSim template must contain exactly one $marker marker."
    }
}

$randomBytes = New-Object byte[] 32
[System.Security.Cryptography.RandomNumberGenerator]::Fill($randomBytes)
$consolePassword = [Convert]::ToHexString($randomBytes)
[System.Security.Cryptography.RandomNumberGenerator]::Fill($randomBytes)
$estatePassword = [Convert]::ToHexString($randomBytes)
[System.Security.Cryptography.RandomNumberGenerator]::Fill($randomBytes)
$remoteAdminPassword = [Convert]::ToHexString($randomBytes)
[System.Security.Cryptography.RandomNumberGenerator]::Fill($randomBytes)
$certificatePassword = [Convert]::ToHexString($randomBytes)
$regionUuid = [guid]::NewGuid().ToString()
$terrainMetadata = @(Get-ChildItem -LiteralPath (Join-Path $privateRoot 'generated-terrain') -Filter 'wow-*.json' -File -ErrorAction SilentlyContinue)
if ($terrainMetadata.Count -ne 1) {
    throw "Expected exactly one generated terrain metadata file under '$privateRoot\generated-terrain'; found $($terrainMetadata.Count). Generate terrain in this new installation before configuring it."
}
$terrainRecord = Get-Content -LiteralPath $terrainMetadata[0].FullName -Raw | ConvertFrom-Json
if ($terrainRecord.size[0] -ne 512 -or $terrainRecord.size[1] -ne 512) {
    throw 'The generated terrain metadata is not for a 512 x 512 region.'
}
$landing = '<{0},{1},{2}>' -f [int]$terrainRecord.landing_m[0], [int]$terrainRecord.landing_m[1], [Math]::Ceiling([double]$terrainRecord.landing_m[2])
$openSimText = $openSimText.Replace('__GENERATE_LOCAL_ONLY__', $consolePassword)
$openSimText = $openSimText.Replace('__GENERATE_WORLD_PORT__', [string]$install.worldPort).Replace('__GENERATE_REMOTEADMIN_PORT__', [string]$install.remoteAdminPort)
$openSimText = $openSimText.Replace('__GENERATE_ESTATE_PASSWORD__', $estatePassword)
$openSimText = $openSimText.Replace('__GENERATE_REMOTEADMIN_PASSWORD__', $remoteAdminPassword)
$openSimText = $openSimText.Replace('__GENERATE_CERT_PASSWORD__', $certificatePassword)
$regionsText = $regionsText.Replace('__GENERATE_REGION_UUID__', $regionUuid).Replace('__GENERATE_LANDING__', $landing).Replace('__GENERATE_WORLD_PORT__', [string]$install.worldPort)
$utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($openSimIni, $openSimText, $utf8WithoutBom)
[System.IO.Directory]::CreateDirectory((Split-Path -Parent $regionsIni)) | Out-Null
[System.IO.File]::WriteAllText($regionsIni, $regionsText, $utf8WithoutBom)
[System.IO.File]::WriteAllText($standaloneCommonIni, $standaloneCommonText, $utf8WithoutBom)

New-Item -ItemType Directory -Path $privateRoot -Force | Out-Null
New-Item -ItemType File -Path $ownerCredentials -ErrorAction Stop | Out-Null
$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$systemSid = [System.Security.Principal.SecurityIdentifier]::new([System.Security.Principal.WellKnownSidType]::LocalSystemSid, $null)
$fileAcl = [System.Security.AccessControl.FileSecurity]::new()
$fileAcl.SetAccessRuleProtection($true, $false)
$fileAcl.SetOwner($identity.User)
$fileAcl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new($identity.User, [System.Security.AccessControl.FileSystemRights]::FullControl, [System.Security.AccessControl.AccessControlType]::Allow))
$fileAcl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new($systemSid, [System.Security.AccessControl.FileSystemRights]::FullControl, [System.Security.AccessControl.AccessControlType]::Allow))
Set-Acl -LiteralPath $ownerCredentials -AclObject $fileAcl
$ownerRecord = "First name: World`r`nLast name: Owner`r`nPassword: $estatePassword`r`n"
[System.IO.File]::WriteAllText($ownerCredentials, $ownerRecord, $utf8WithoutBom)

Write-Output 'Created local standalone configuration.'
Write-Output "Region: Woz's World (512 x 512 m)"
Write-Output "Region UUID: $regionUuid"
Write-Output "Local ports: world $($install.worldPort), registration $($install.registrationPort), RemoteAdmin $($install.remoteAdminPort)"
Write-Output "Terrain: $($terrainRecord.template) (seed $($terrainRecord.seed)); landing $landing"
Write-Output 'The REST console and RemoteAdmin passwords are stored only in the ignored server configuration.'
Write-Output 'The first estate-owner password is in the ACL-restricted ignored .local\owner-credentials.txt file.'
