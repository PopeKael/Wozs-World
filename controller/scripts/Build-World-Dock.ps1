[CmdletBinding()]
param(
    [ValidateSet('debug', 'release')]
    [string]$Configuration = 'release'
)

$ErrorActionPreference = 'Stop'
$controllerRoot = Split-Path -Parent $PSScriptRoot
$worldRoot = Split-Path -Parent $controllerRoot
$manifest = Join-Path $controllerRoot 'Cargo.toml'
$cargoHome = Join-Path $worldRoot '.local\cargo'
$buildTarget = Join-Path $controllerRoot 'target\build'
$installedDir = Join-Path $controllerRoot 'target\current'
$previousCargoHome = $env:CARGO_HOME
$previousCargoTarget = $env:CARGO_TARGET_DIR

try {
    New-Item -ItemType Directory -Path $cargoHome -Force | Out-Null
    $env:CARGO_HOME = $cargoHome
    $env:CARGO_TARGET_DIR = $buildTarget
    cargo build --manifest-path $manifest --$Configuration
    if ($LASTEXITCODE -ne 0) {
        throw "Cargo build failed with exit code $LASTEXITCODE."
    }
}
finally {
    if ($null -eq $previousCargoHome) {
        Remove-Item Env:CARGO_HOME -ErrorAction SilentlyContinue
    }
    else {
        $env:CARGO_HOME = $previousCargoHome
    }
    if ($null -eq $previousCargoTarget) {
        Remove-Item Env:CARGO_TARGET_DIR -ErrorAction SilentlyContinue
    }
    else {
        $env:CARGO_TARGET_DIR = $previousCargoTarget
    }
}

$builtBinary = Join-Path $buildTarget "$Configuration\woz-world-dock.exe"
if (-not (Test-Path -LiteralPath $builtBinary)) {
    throw "The build completed but the expected executable is missing: $builtBinary"
}

New-Item -ItemType Directory -Path $installedDir -Force | Out-Null
$binary = Join-Path $installedDir 'woz-world-dock.exe'
try {
    Copy-Item -LiteralPath $builtBinary -Destination $binary -Force
}
catch {
    throw "Build succeeded at '$builtBinary', but the installed Dock could not be replaced at '$binary'. Close the Dock window and rerun the build. $($_.Exception.Message)"
}

Write-Output "Built Woz's World Dock: $binary"
