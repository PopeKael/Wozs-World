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
- Closing the window minimizes it to the tray. Exit closes immediately when a recent check confirms all services are stopped; otherwise it runs verified graceful shutdown before closing.
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

The fixtures exercise the actual PowerShell lifecycle entry points and HTTP control paths, but they do not impersonate OpenSimulator's full region startup or Aurora login. The live-world checks below separately exercise the real simulator process and local registration service.

## Installed-world checkpoint

Date: 2026-11-19. The existing Start menu shortcut still targets `controller/target/release/woz-world-dock.exe`. The live `.local/install.json` retains the existing ports (9000, 9080, 19001). The installed OpenSimulator config remains Standalone Hypergrid with loopback HomeURI and GatekeeperURI; no firewall settings were changed.

The startup blocker was in World Dock's registration script compatibility. The Dock invokes Windows PowerShell 5.1/.NET Framework, where `RandomNumberGenerator.Fill`, `Convert.ToHexString`, and the two-argument `string.Contains` overload are unavailable. Registration failed before starting, and the rollback hit the same unsupported string overload. The scripts now use APIs available in Windows PowerShell 5.1, and registration startup reports the last health result, listener owner and process identity when readiness fails. The normal Start path no longer calls the Windows Firewall profile/rule audit; it continues to use the existing loopback configuration.

The registration scripts were independently started and stopped under Windows PowerShell 5.1 in the normal host context. `/health` returned ready on loopback TCP/9080, authenticated shutdown completed, and the port was released.

The actual installed world was then exercised through its PowerShell service scripts under Windows PowerShell 5.1. Start attached to the already-running OpenSimulator process without duplicating it, started registration, and reported OpenSimulator, RemoteAdmin and registration ready. A repeated Start retained both existing process IDs. Stop shut registration down first, then OpenSimulator, and verified TCP/UDP 9000, TCP 19001 and HTTP 9080 released. Restart verified shutdown before starting new OpenSimulator and registration processes; a final Stop again left all three roles stopped. No accounts were created and no avatar, inventory, terrain or region configuration was edited. OpenSimulator regenerated its normal map cache during startup and appended service logs.

The isolated lifecycle harness was rerun under Windows PowerShell 5.1 after the compatibility fixes. All ten cases passed: duplicate-safe Start, each partial-start recovery, idempotent Stop, two Restarts, partial startup rollback with an unrelated port owner preserved, stale state cleanup, refusing recovery of a responsive service, recovery of an owned unresponsive fixture and rejection of a forged PID record.

The Dock source keeps Start/Stop/Restart operations serialized, shows the latest operation result and actual errors, and makes Exit run verified Stop before closing. A failed Stop leaves the Dock open. The executable was deployed at the unchanged Start menu shortcut target.

## Manual acceptance approval

Date: 2026-11-19. The user confirmed that World Dock passed manual acceptance testing and approved the release. The accepted baseline includes service lifecycle controls, tray behavior, single-instance activation, Exit handling, and centred colour-coded operation messages synchronized with the three service indicators. This record reflects the user's confirmation; no additional tests were run for release publication.
