# Woz's World Dock

Optional Windows desktop controller for the simulator in this checkout. It starts and gracefully stops the repository scripts, displays a live status and can stay on top. It is not a server dependency.

## Build and install

From the project root, run:

```powershell
pwsh -NoProfile -File .\scripts\Install-WorldDock.ps1
```

This builds from the locked `controller/Cargo.lock` into ignored `controller/target/` and `.local/cargo/`. The Rust stable toolchain and Visual Studio C++ build tools must already be installed. Add `-CreateDesktopShortcut` to create a shortcut. The shortcut does not add the Dock to Windows startup.

## Behavior

- Start/Stop calls the project's `scripts/Start-World.ps1` and `scripts/Stop-World.ps1`.
- Running status requires the recorded project-local .NET process, completed region initialization, authenticated REST check and the instance's configured TCP port.
- Each clean install chooses its own port set; the Dock reads `.local/install.json` and `.local/opensim-process.json` rather than assuming port 9000.
- The Create account form sends credentials through the child process's standard input to the local OpenSimulator RemoteAdmin service. It does not put the account password on a command line or save it in Dock settings/logs.
- Closing the panel leaves the simulator running. Use Stop for graceful shutdown.
- Start and stop output is written under ignored local logs.
