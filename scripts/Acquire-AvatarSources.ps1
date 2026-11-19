[CmdletBinding()]
param(
    [string[]]$System = @('Ruth2', 'Roth2', 'RuthToo', 'RothToo', 'Max')
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $projectRoot 'avatar-library\licensing-provenance\sources.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$packageRoot = Join-Path $projectRoot 'avatar-library\original-packages'
$sourceRoot = Join-Path $projectRoot 'avatar-library\source-meshes-development-kits'
$inventoryRoot = Join-Path $projectRoot 'avatar-library\inventory-archives'
$skinRoot = Join-Path $projectRoot 'avatar-library\skins-materials'
$clothingRoot = Join-Path $projectRoot 'avatar-library\clothing-accessories'
$evidenceRoot = Join-Path $projectRoot 'avatar-library\visual-evidence'
New-Item -ItemType Directory -Path $packageRoot, $sourceRoot, $inventoryRoot, $skinRoot, $clothingRoot, $evidenceRoot -Force | Out-Null

foreach ($name in $System) {
    $source = $manifest.sources | Where-Object id -eq $name | Select-Object -First 1
    if (-not $source) { throw "No pinned source record exists for '$name'." }
    $repoParts = $source.repository -split '/', 2
    $archiveDir = Join-Path $packageRoot $name
    $extractDir = Join-Path $sourceRoot $name
    $archive = Join-Path $archiveDir "$name-$($source.commit.Substring(0,8)).zip"
    New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null
    if (Test-Path -LiteralPath $archive) {
        $actual = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
        if ($actual -ne $source.sha256) { throw "Existing $name archive has a different hash. It was preserved; review it manually." }
        Write-Output "${name}: verified archive already present; no duplicate download."
    }
    else {
        $url = "https://github.com/$($repoParts[0])/$($repoParts[1])/archive/$($source.commit).zip"
        $temporary = "$archive.download"
        try {
            Invoke-WebRequest -Uri $url -OutFile $temporary
            $actual = (Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash
            if ($actual -ne $source.sha256) { throw "Downloaded $name hash does not match the pin. Expected $($source.sha256), got $actual." }
            Move-Item -LiteralPath $temporary -Destination $archive
        }
        finally { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
        Write-Output "${name}: downloaded and verified archive."
    }
    $record = Join-Path $extractDir '.source-record.json'
    if (-not (Test-Path -LiteralPath $record)) {
        if (Test-Path -LiteralPath $extractDir) {
            throw "$name extraction directory already exists without a provenance record. Preserved it; inspect before extracting again."
        }
        New-Item -ItemType Directory -Path $extractDir | Out-Null
        Expand-Archive -LiteralPath $archive -DestinationPath $extractDir
        $inner = Get-ChildItem -LiteralPath $extractDir -Directory | Select-Object -First 1
        if (-not $inner) { throw "The $name archive extracted without its expected repository folder." }
        $unpacked = Join-Path $sourceRoot "$name-extracted"
        Move-Item -LiteralPath $inner.FullName -Destination $unpacked
        Remove-Item -LiteralPath $extractDir -Force
        Move-Item -LiteralPath $unpacked -Destination $extractDir
        [System.IO.File]::WriteAllText($record, ($source | ConvertTo-Json), [System.Text.UTF8Encoding]::new($false))
    }
    else {
        $saved = Get-Content -LiteralPath $record -Raw | ConvertFrom-Json
        if ($saved.commit -ne $source.commit -or $saved.sha256 -ne $source.sha256) { throw "$name extraction provenance does not match the current pin." }
        Write-Output "${name}: source extraction already present; skipped."
    }
    $archiveInventory = Join-Path $inventoryRoot $name
    New-Item -ItemType Directory -Path $archiveInventory -Force | Out-Null
    foreach ($iar in @(Get-ChildItem -LiteralPath $extractDir -Filter '*.iar' -File -Recurse)) {
        $destination = Join-Path $archiveInventory $iar.Name
        $sourceHash = (Get-FileHash -LiteralPath $iar.FullName -Algorithm SHA256).Hash
        if (Test-Path -LiteralPath $destination) {
            if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $sourceHash) { throw "An inventory archive with a different hash already exists: $destination" }
        }
        else { Copy-Item -LiteralPath $iar.FullName -Destination $destination }
    }
}

Write-Output "Sources are under $packageRoot and $sourceRoot. They are excluded from Git. Review every package's own notices before importing or sharing its contents."
