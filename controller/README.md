# Woz's World Dock

Optional Windows desktop controller for the simulator in this checkout. It manages OpenSimulator and the local registration service as independent services, including RemoteAdmin health as part of OpenSimulator. It is not a server dependency.

## Build and install

From the project root, run:

```powershell
pwsh -NoProfile -File .\scripts\Install-WorldDock.ps1
```

This builds from the locked `controller/Cargo.lock` into ignored `controller/target/` and `.local/cargo/`. The Rust stable toolchain and Visual Studio C++ build tools must already be installed. Add `-CreateDesktopShortcut` to create a shortcut. The shortcut does not add the Dock to Windows startup.

## Lifecycle controls

- **Start World** starts OpenSimulator and registration, waits for readiness, and rejects duplicate processes or occupied service ports.
- **Stop World** requests a graceful registration shutdown and OpenSimulator shutdown, then checks world TCP/UDP, RemoteAdmin TCP and registration HTTP ports are released.
- **Restart World** completes and verifies Stop before starting again.
- **Safe recovery** clears stale records only after their recorded process is absent and ports are free. The optional force route requires confirmation, verifies executable, command line, start time and port ownership, and refuses to kill a service that still passes health checks.
- The Dock independently displays simulator, RemoteAdmin and registration health. Its tray icon colour and tooltip follow world status; the tray menu provides **Open**, **Start**, **Stop**, **Restart** and **Exit**.
- World Dock is single-instance per installation. Launching it again signals the existing Dock to show and focus its window, then the duplicate exits.
- Closing the window hides it to the system tray. **Exit** closes immediately when a recent service check confirms everything is stopped; otherwise it immediately shows the Dock, verifies service state and performs the graceful Stop sequence before closing. If shutdown fails, the Dock stays open and reports the error.
- The same lifecycle is available through `scripts/Start-World.ps1`, `scripts/Stop-World.ps1`, `scripts/Restart-World.ps1`, `scripts/Get-WorldServiceStatus.ps1` and `scripts/Recover-World.ps1`.
- Each clean install chooses its own port set; the Dock reads `.local/install.json` and project-local process records rather than assuming port 9000.
- New installs use their bundled Python for registration. Existing installations without that runtime may use `python.exe` from `PATH`; the selected executable is recorded and verified before shutdown or recovery.
- The Create account form sends credentials through the child process's standard input to the local OpenSimulator RemoteAdmin service. It does not put the account password on a command line or save it in Dock settings/logs.
- Service output and identity records are stored under ignored project-local `.local/` and `logs/` directories.

## Verification

The isolated lifecycle regression harness and its recorded results are in [World Dock lifecycle verification](../docs/WORLDDOCK-LIFECYCLE.md). It uses disposable service fixtures and does not restart or modify the live world.
