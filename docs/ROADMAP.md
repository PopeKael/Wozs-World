# Development roadmap

## Version phases

- **1.0.0:** Reproduce the current working local world with independent runtime state, account registration, procedural terrain and the existing Aurora workflow. Outstanding clean-install and viewer validation are documented as known limitations.
- **1.1:** Refine the installation process, standardize a loopback-only Standalone Hypergrid architecture, choose and test starter avatars, and simplify account-to-world onboarding. External Hypergrid access remains a separate, security-reviewed future task.

## 1.1 architecture checkpoint — 2026-11-19

- Target architecture: OpenSimulator standalone with Hypergrid support (`config-include/StandaloneHypergrid.ini`), retaining the existing standalone database and region identity. Enable and test this mode locally before adopting it as the installer default.
- Configure the `[Hypergrid]` GatekeeperURI and HomeURI in the installed `config-include/StandaloneCommon.ini` to use the instance's existing base URL and public port. Keep loopback addressing, the existing firewall restrictions and private RemoteAdmin settings during this phase.
- Welcome page: local account creation, existing resident login and a Hypergrid visitor option (coming soon). Foreign residents authenticate on their home grid, not through our registration form.
- Acceptance: successful local restart, existing avatar/inventory persistence, registration and starter outfit provisioning under standalone Hypergrid mode. Test inbound and outbound Hypergrid travel separately when external networking and a supported runtime have been reviewed.
- Status: architecture decision recorded; live configuration change and verification pending. Version 1.0.0 installer defaults remain unchanged until local validation.

## 1. Reliable starter experience

- Select two male and two female starter packages from licensed, compatible sources; include genuinely different body/skin/hair combinations rather than four clones.
- Test each in a clean local inventory: body, shape, skin, eyes, hair, alpha, animation override, supplied sample outfit and restorable outfit folder. Compare base bodies separately from clothing.
- Build a browser choice page with consistent preview cards. Keep account registration separate from starter-avatar selection.
- Apply the chosen inventory package and a consistent animation override and optional region meter only after confirming creator permission and restore behavior.
- Provide a clear first-login welcome and a safe reset/retry route.

## 2. Browser registration and Aurora

- The local loopback registration page already creates regular accounts. Improve it with recovery guidance, abuse limits for any future public form and privacy information before remote use.
- Integrate Aurora login more smoothly, including a verified launcher/grid entry and a post-registration link without sending passwords through command-line arguments or logs.
- Only design remote registration after TLS, abuse controls, privacy notice, email policy, account deletion and public network boundaries are reviewed.

## 3. World Dock service lifecycle (implemented for 1.1)

- Implemented: the simulator and local registration service are managed independently, with separate process identity, readiness, port health and logs. RemoteAdmin has its own health and shutdown-port checks.
- Implemented: repeated Start is duplicate-safe; Stop is graceful and verifies ports are released; Restart verifies shutdown before starting; recovery clears stale records and only force-stops verified unresponsive project-owned processes.
- Implemented and manually accepted: system tray status and controls, close-to-tray behavior, per-installation single-instance activation, verified-shutdown Exit, and operation messages synchronized with service status. See [World Dock lifecycle verification](WORLDDOCK-LIFECYCLE.md).
- Keep future Hypergrid and optional account/asset services separately observable; a healthy registration page must not imply that the simulator is healthy.

## 4. Original creative assets

- Use Blender as the collaborative workshop for original props, scenes, clothing, textures, hair and diverse original avatars.
- Keep the Blender version and required export add-ons documented. Label project-created models and textures CC0 1.0; retain source and provenance, and keep third-party terms attached to their assets.
- Keep OpenSimulator/Second Life Collada export, IMVU delivery and 3D-print manifold/scale validation as separate, tested targets.

## 5. Broader destinations

- Test export/import with a disposable OpenSimulator region first.
- Add Second Life, IMVU and physical-print workflows only after format and creator-rights checks.
- Preserve source files and provenance so assets can be reused without tying them to one vendor or grid.
