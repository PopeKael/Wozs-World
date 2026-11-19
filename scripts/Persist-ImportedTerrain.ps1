[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$TerrainPath
)

# Run only after Import-IslandTerrain.ps1 and a graceful simulator shutdown.
# This explicit offline step promotes the validated baked row to OpenSim's
# primary startup terrain row; it is never called by normal server startup.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$statePath = Join-Path $projectRoot '.local\opensim-process.json'
$python = Join-Path $projectRoot 'runtime\python\python.exe'
$persistScript = Join-Path $projectRoot 'terrain\persist_imported_heightmap.py'
$terrainPath = [System.IO.Path]::GetFullPath($TerrainPath)

if (Test-Path -LiteralPath $statePath) {
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    if (Get-Process -Id ([int]$state.ProcessId) -ErrorAction SilentlyContinue) {
        throw 'OpenSimulator is still running. Use scripts\Stop-World.ps1 before persisting the imported terrain.'
    }
}

$install = Get-Content -LiteralPath (Join-Path $projectRoot '.local\install.json') -Raw | ConvertFrom-Json
$listener = Get-NetTCPConnection -State Listen -LocalPort ([int]$install.worldPort) -ErrorAction SilentlyContinue | Select-Object -First 1
if ($listener) {
    throw "The world TCP port is still listening (PID $($listener.OwningProcess)); refusing to edit a live region database."
}

if (-not (Test-Path -LiteralPath $python -PathType Leaf)) { throw "Project-local Python is missing: $python" }
& $python $persistScript --r32 $terrainPath
if ($LASTEXITCODE -ne 0) { throw "Terrain persistence helper failed with exit code $LASTEXITCODE." }
