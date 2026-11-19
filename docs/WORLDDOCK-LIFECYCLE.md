# World Dock lifecycle

World Dock manages the local world through a short ordered sequence. It does not kill arbitrary processes to make a port look clear.

## Service order

OpenSimulator owns the world listener (TCP and UDP) and its RemoteAdmin listener (TCP). The registration website is a separate process. On the existing Woz's World configuration, these are world **9000**, registration **9080**, and RemoteAdmin **19001**. New independent installs use the port values generated in ignored `.local/install.json`.

**Start:** check OpenSimulator and RemoteAdmin; start OpenSimulator only if its recorded process is absent and its ports are free; wait until the region, authenticated REST console, world port and RemoteAdmin are ready; then check registration and start it only if its health endpoint is not already ready. Finish by checking all three service roles again. An occupied port with no verified project process is reported as unmanaged, never adopted.

**Stop:** gracefully stop registration first and verify its HTTP port is released; then request OpenSimulator shutdown over its authenticated REST console and verify its world TCP/UDP and RemoteAdmin TCP ports are released. If one shutdown fails, continue with the other owned service and report the failure. No normal stop force-kills a process.

**Restart:** run Stop, require all three service roles to report stopped, then run Start and require all three to report ready.

**Recovery:** stale records are cleared only when their PID is absent and their service ports are free. Force recovery is a separate confirmed action: it verifies executable path, command line, process start time and every relevant port owner, and rejects any process that still answers its health check. A different port owner is never stopped.

## Dock controls

- The main window shows OpenSimulator, RemoteAdmin and registration status separately.
- Start, Stop and Restart are available in the window and system tray. The tray icon colour and tooltip show overall status; its menu also provides Open and Exit.
- Closing the window minimizes it to the tray. Exit closes World Dock only; Stop World shuts down the services.
- If a service is partly ready or unhealthy, the Dock retains Stop/Restart access so the operator can recover it instead of leaving it unmanaged.
- PowerShell scripts in `scripts/` provide the same lifecycle outside the Dock. Process records, registration control token and service logs stay under ignored local state.
- New installs use their bundled Python runtime. Existing installations without that runtime may use `python.exe` from `PATH`; the selected executable and process identity are recorded and checked before Stop or recovery.

## Verification record

Date: 2026-11-19. The lifecycle regression harness ran against disposable local service fixtures; it did not start, stop or modify the existing world, its accounts, inventory, region, terrain or database.

| Scenario | Observed result |
|---|---|
| Start all services, then Start again | Passed. All health checks became ready; the second Start retained the same simulator and registration PIDs. |
| Only registration stopped; press Start | Passed. Registration restarted and the existing OpenSimulator PID remained unchanged. |
| Only OpenSimulator stopped; press Start | Passed. OpenSimulator restarted and the existing registration PID remained unchanged. |
| Stop, then Stop again | Passed. World TCP/UDP, RemoteAdmin TCP and registration HTTP were released; the second Stop was idempotent. |
| Two successive restarts | Passed. Each Restart verified shutdown before startup and received a new fixture simulator PID. |
| Registration startup failure after simulator startup | Passed. Startup failed and rolled back only the simulator it had started; the unrelated listener holding the registration port remained alive. |
| Stale process records | Passed. Stale OpenSimulator and registration records were cleared only after confirming their PIDs were absent and ports free. |
| Recovery of a responsive service | Passed. Force recovery refused; graceful Stop remained available. |
| Unresponsive owned fixture | Passed. Recovery stopped it only after PID, executable, command line, start time and port ownership matched. |
| Reused/forged PID record | Passed. Recovery refused and left the unrelated process running. |
| Release build | Passed with `cargo build --release --locked`. |

The fixtures exercise the actual PowerShell lifecycle entry points and HTTP control paths, but they do not impersonate OpenSimulator's full region startup or Aurora login. The viewer and live-world start/stop path remain for a separate acceptance check; the lifecycle test did not touch the live world.

## Installed-world checkpoint

Date: 2026-11-19. The existing Start menu shortcut still targets `controller/target/release/woz-world-dock.exe`; the updated executable was deployed at that path and its SHA-256 matched the release build. A local-only `.local/install.json` was added with a new installation identifier and the existing ports (9000, 9080, 19001); no account, inventory, region, terrain or database files were changed.

The Dock's first live status check exposed a Windows PowerShell output-encoding issue: a non-ASCII dash in the registration status text was corrupted when PowerShell ran hidden, making the JSON invalid. The status string now uses ASCII, and the exact hidden-process invocation returned valid JSON with all three services stopped.

The prior registration process had no authenticated shutdown route. Its executable, exact project script path, start time, loopback binding and ownership of 9080 were checked before a one-time stop. The replacement registration service then started from this installation, passed `GET /health`, and stopped through the new authenticated shutdown path; the final status was fully stopped. No registration or simulator accounts were created.

Full installed-world acceptance is still pending. The active host firewall policy contains inbound allow rules broader than the project's local-only boundary. The startup guard refuses to continue under that policy; no firewall rules were changed and OpenSimulator was not started. The Dock window was observed, but live tray-menu selection and close-to-tray acceptance have not been completed; no successful in-world lifecycle cycle is claimed.
