# Local installation

## Prerequisites

- 64-bit Windows 10/11, PowerShell 7 and Git.
- Internet on first run for pinned OpenSimulator, .NET, Python and SQLite packages.
- Windows Firewall configured according to the host owner's policy. World Dock does not inspect or change firewall rules and does not add router mappings.
- Aurora Viewer for in-world use. It is detected from common install locations or can be provided by path.
- Optional World Dock: Rust stable/Cargo and the Windows C++ build tools. Optional Blender is not a server dependency.

## Fresh checkout

Clone to a new directory, then run:

```powershell
pwsh -NoProfile -File .\scripts\Install-World.ps1
```

Choose a fixed terrain template if desired:

```powershell
pwsh -NoProfile -File .\scripts\Install-World.ps1 -Template archipelago
```

Optional source acquisition (pinned, excluded from Git) and optional Dock build:

```powershell
pwsh -NoProfile -File .\scripts\Install-World.ps1 -AcquireAvatarSources -InstallDock
```

The installer refuses to overwrite an existing local install. It downloads to `downloads/`, verifies publisher or recorded hashes, installs everything under this checkout, allocates a free port set, generates fresh console/estate/RemoteAdmin credentials, assigns a new region UUID, creates a fresh standalone database, generates a unique island, imports that terrain into this new database, restarts and checks the simulator, creates the initial `World Owner` account, then starts and checks the local registration page. It does not read another checkout or copy any existing world state. If a partial install stops, preserve the directory for diagnosis; do not point the installer at an existing world directory.

The initial `World Owner` account uses the generated estate password in ignored `.local/owner-credentials.txt`, protected by a Windows ACL limited to the current user and LocalSystem. Browser-created visitor accounts are independent. The registration URL uses the generated port and is printed at completion; the service binds to `127.0.0.1` only. World Dock also has its own account form.

Fresh installs use `config-include/StandaloneHypergrid.ini`. The installer creates `StandaloneCommon.ini` from the OpenSimulator package's `.example` file and sets both `HomeURI` and `GatekeeperURI` to the clone's local `BaseURL` and public port. This starts the Hypergrid-capable standalone services while keeping their advertised address on loopback. It does not make the world reachable from another computer or grid. External Hypergrid access would require externally resolvable service and region addresses, corresponding login-service URIs, reachable ports, and a separate firewall/router/security review; none are configured here. See the [upstream Hypergrid instructions](https://opensimulator.dev/wiki/Installing_and_Running_Hypergrid).

The 1.0.0 clean-copy validation reached configuration generation but did not complete the full simulator, account-creation and Aurora-login flow in an independent copy; see the [validation checkpoint](DEPENDENCIES.md#version-100-validation-checkpoint).

Open Aurora using the repository helper:

```powershell
pwsh -NoProfile -File .\scripts\Open-Aurora.ps1
```

Use `-ViewerPath` if Aurora is installed in a nonstandard directory. The helper passes the local login URI through Aurora's command line; it does not change viewer preferences or log in with stored credentials.

## Run and stop

```powershell
pwsh -NoProfile -File .\scripts\Start-World.ps1
pwsh -NoProfile -File .\scripts\Stop-World.ps1
pwsh -NoProfile -File .\scripts\Verify-World.ps1 -RequireRunning
```

The database, configuration, logs, credentials, packages and backups are private runtime state. `Backup-World.ps1` creates an archive under ignored `backups/`; treat it as containing secrets and personal inventory.

## Optional avatar library

Run `scripts/Acquire-AvatarSources.ps1` or pass `-AcquireAvatarSources` during setup. It fetches exact commit snapshots for Ruth2, Roth2, RuthToo, RothToo and Max, verifies archive hashes and skips verified existing archives and extractions. It puts source archives, extracted kits and IAR files in their separate ignored library directories. R3, Skins and Extras can be requested explicitly, for example `pwsh -NoProfile -File .\scripts\Acquire-AvatarSources.ps1 -System R3,Skins,Extras`; these contain non-commercial or mixed creator terms and need per-item review. Acquisition does not import assets into the simulator or grant permission to redistribute them. See [the acquisition record](../avatar-library/licensing-provenance/PROVENANCE.md).

## Optional World Dock

```powershell
pwsh -NoProfile -File .\scripts\Install-WorldDock.ps1
pwsh -NoProfile -File .\scripts\Install-WorldDock.ps1 -CreateDesktopShortcut
```

The Dock is a convenience UI, not required for the world to run. It builds from the locked Cargo graph and stores build/cache output under ignored paths. It does not install itself at startup.

## Recovery and portability

Each clone chooses unique ports and identity values; database and inventory state remain inside that clone. If startup checks fail, inspect `.local/opensim-process.json` and `logs/`. Do not copy `.local/` or `server/` from another world. To reset an install, stop it, back up the entire private directory, then use a new clone path. Local Hypergrid service initialization is configured, but remote Hypergrid interoperability is untested and the loopback endpoints intentionally prevent external access.
