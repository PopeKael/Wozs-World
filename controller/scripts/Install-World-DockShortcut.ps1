[CmdletBinding()]
param(
    [string]$Name = "Woz's World Dock"
)

$ErrorActionPreference = 'Stop'
$controllerRoot = Split-Path -Parent $PSScriptRoot
$worldRoot = Split-Path -Parent $controllerRoot
$binary = Join-Path $controllerRoot 'target\current\woz-world-dock.exe'
$icon = Join-Path $controllerRoot 'assets\world-dock.ico'

if (-not (Test-Path -LiteralPath $binary)) {
    throw "Build the controller first with scripts\Build-World-Dock.ps1. Missing: $binary"
}

$desktop = [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
$shortcutPath = Join-Path $desktop "$Name.lnk"
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $binary
$shortcut.WorkingDirectory = $worldRoot
$shortcut.Description = "Start and monitor the locally hosted Woz's World simulator"
$shortcut.IconLocation = "$icon,0"
$shortcut.Save()

Write-Output "Created desktop shortcut: $shortcutPath"
Write-Output "The controller starts only when opened; it does not add itself to Windows startup."
