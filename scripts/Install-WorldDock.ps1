[CmdletBinding()]
param([switch]$CreateDesktopShortcut)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$cargo = Get-Command cargo -ErrorAction SilentlyContinue
if (-not $cargo) { throw 'The optional World Dock requires Rust/Cargo. Install Rustup from https://rustup.rs/ and the Visual Studio C++ build tools, then rerun this script.' }
& (Join-Path $projectRoot 'controller\scripts\Build-World-Dock.ps1')
if ($LASTEXITCODE -ne 0) { throw 'World Dock build failed.' }
if ($CreateDesktopShortcut) { & (Join-Path $projectRoot 'controller\scripts\Install-World-DockShortcut.ps1') }
