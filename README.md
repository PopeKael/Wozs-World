# Woz's World (WOW)

**Release:** `1.0.0` — current working-world baseline. The next development phase is `1.1`.

Woz's World is a Garage Alchemy project for AI-assisted 3D creation, collaborative learning and creative experimentation. Blender is our shared workshop; OpenSimulator is the first local testing destination. Second Life, IMVU and 3D printing are possible later destinations, each with different formats and permissions.

We want people to enjoy making things, keep their minds active and join in without first becoming programmers or systems administrators. The motto is: “Take AI into the garage and see if it actually works.”

## Status

This repository is a Windows-local OpenSimulator setup and creative-workflow research project. Its installer creates a separate standalone world, generates fresh credentials and a region identity, chooses a procedural 512 × 512 island, initializes its database, starts a local account page and can launch Aurora. Pinned avatar packages can be fetched to ignored local folders. They are not redistributed here. Starter-avatar selection and a finished avatar-choice portal remain future work.

The intended first use is a contributor's own cloned directory. It does not connect to the existing Woz's World instance, copy its accounts or inventory, configure a router, or enable Hypergrid. Do not expose the local-only defaults to a network.

## Clone and install

Prerequisites: 64-bit Windows, PowerShell 7, Git, and Windows Firewall enabled with inbound default set to Block. Internet is needed for first-run downloads. Aurora is separately installed. The installer uses the same local .NET 8.0.34 runtime as the existing working world. .NET 8 reached end of support on 10 November 2026; the compatibility trade-off and local-only boundary are documented in [dependencies and limitations](docs/DEPENDENCIES.md).

```powershell
git clone https://github.com/PopeKael/Wozs-World.git
Set-Location Wozs-World
pwsh -NoProfile -File .\scripts\Install-World.ps1
```

Choose a terrain template or fetch the pinned avatar source packages as part of installation:

```powershell
pwsh -NoProfile -File .\scripts\Install-World.ps1 -Template atoll -AcquireAvatarSources
```

The three templates are `atoll`, `archipelago` and `mountain`; omit `-Template` to choose a template and new seed at random. A new install uses unoccupied instance-specific ports so it can coexist with other local worlds.

After the install completes, it prints the local registration URL. Create a regular account there. The generated owner credential is stored in ignored `.local\owner-credentials.txt`. Aurora launch:

```powershell
pwsh -NoProfile -File .\scripts\Open-Aurora.ps1
```

Optional World Dock build:

```powershell
pwsh -NoProfile -File .\scripts\Install-WorldDock.ps1
```

## Version 1.0.0 and next phase

Version 1.0.0 represents the current working local world and its independent-install baseline. The intended 1.1 phase will refine installation, select starter avatars and simplify onboarding. Known viewer, Dock and network limitations are recorded in `docs/DEPENDENCIES.md` and `docs/SECURITY.md`.

## Licences

Original software and documentation are provided under [MIT](LICENSE). Original 3D assets and textures that are explicitly identified as project-created are dedicated under [CC0 1.0](LICENSE-CC0-1.0.txt). The OpenSim-derived configuration template retains its [upstream BSD-3-Clause terms](docs/THIRD-PARTY-NOTICES.md). Third-party assets retain their own licences and are not relicensed by this repository; see [licensing and provenance](docs/LICENSING.md).

## Project layout

- `scripts/`, `registration/`, `config/` — local install, account page, configuration templates and lifecycle helpers.
- `terrain/` — three source presets and a standard-library procedural R32 generator.
- `avatar-library/` — candidate catalogue, source pins and license/provenance notes. Acquired binaries and inventory archives remain ignored.
- `controller/` — optional Windows World Dock (Rust); not required to run the simulator.
- `docs/` — install, security, dependency, licensing and roadmap notes.

Operational requirements and optional creative/development tools are separated in [dependency notes](docs/DEPENDENCIES.md). Read [Codex operating instructions](AGENTS.md) before making changes. Original code/documentation use MIT; explicitly identified project-created models and textures use CC0 1.0. Third-party licensing conditions remain in force; see [licensing and provenance](docs/LICENSING.md).
