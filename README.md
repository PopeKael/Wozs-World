# Woz's World (WOW)

**Release:** `1.1.0` — current stable baseline. Starter-avatar selection and simplified onboarding remain on the roadmap.

Woz's World is an open creative workshop from [Garage Alchemy](https://garage.dia.net.au/), exploring what we can build when 3D artists, hobbyists and AI work together.

I've always enjoyed the building side of games and virtual worlds. Quite often, building the house is more interesting than fighting the monsters. So why not make the building itself the point?

Blender is our common workshop. OpenSimulator gives us an independent virtual world in which to explore, build and test our creations. Second Life, IMVU and 3D printing are other creative destinations we'd like to explore, each with its own formats and permissions.

The idea is to keep our minds active, learn new skills and enjoy making things together, without everyone needing to become a programmer or systems administrator first. The tools should serve the hobby, not become the hobby.

> Take AI into the garage and see if it actually works.

## Status

This repository is a Windows-local OpenSimulator setup and creative-workflow research project. Its installer creates a separate Standalone Hypergrid world with loopback Home and Gatekeeper URIs, generates fresh credentials and a region identity, chooses a procedural 512 × 512 island, initializes its database, starts a local account page and can launch Aurora. Pinned avatar packages can be fetched to ignored local folders. They are not redistributed here. Starter-avatar selection and a finished avatar-choice portal remain future work.

The intended first use is a contributor's own cloned directory. It does not connect to the existing Woz's World instance, copy its accounts or inventory, configure a router, or advertise an externally reachable Hypergrid endpoint. Hypergrid services initialize locally, but the loopback URIs are not reachable by other grids. Do not expose the local-only defaults to a network.

## Clone and install

You can work with the scripts directly or ask Codex to help set up your world. Give it the repository URL and ask it to clone the project into a new directory, read [AGENTS.md](AGENTS.md) and follow the [installation guide](docs/INSTALLATION.md). You do not need access to anyone else's world or accounts.

Prerequisites: 64-bit Windows, PowerShell 7 and Git. Internet is needed for first-run downloads. World Dock leaves the host's existing Windows Firewall settings untouched. Aurora is separately installed. The installer uses the same local .NET 8.0.34 runtime as the existing working world. .NET 8 reached end of support on 10 November 2026; the compatibility trade-off and local-only boundary are documented in [dependencies and limitations](docs/DEPENDENCIES.md).

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

## Version 1.1.0

The original local world is running. The independent installer is a first release, not yet an end-to-end verified deployment on a separate machine. The [validation checkpoint](docs/DEPENDENCIES.md#version-100-validation-checkpoint) explains what has been tested and what remains to be checked.

Version 1.1.0 is the current stable baseline, including the approved World Dock service lifecycle and presentation. Starter-avatar selection, a simple first-login onboarding flow and broader avatar diversity remain future work on the roadmap. External Hypergrid access remains separate future work. Known viewer and network limitations are recorded in `docs/DEPENDENCIES.md` and `docs/SECURITY.md`.

## Licences

Original software and documentation are provided under [MIT](LICENSE). Original 3D assets and textures that are explicitly identified as project-created are dedicated under [CC0 1.0](LICENSE-CC0-1.0.txt). The OpenSim-derived configuration template retains its [upstream BSD-3-Clause terms](docs/THIRD-PARTY-NOTICES.md). Third-party assets retain their own licences and are not relicensed by this repository; see [licensing and provenance](docs/LICENSING.md).

## Project layout

- `scripts/`, `registration/`, `config/` — local install, account page, configuration templates and lifecycle helpers.
- `terrain/` — three source presets and a standard-library procedural R32 generator.
- `avatar-library/` — candidate catalogue, source pins and license/provenance notes. Acquired binaries and inventory archives remain ignored.
- `controller/` — optional Windows World Dock (Rust); not required to run the simulator.
- `docs/` — install, security, dependency, licensing and roadmap notes.

Operational requirements and optional creative/development tools are separated in [dependency notes](docs/DEPENDENCIES.md). Read [Codex operating instructions](AGENTS.md) before making changes.

## Built on the work of others

This project draws on the work of the OpenSimulator, Aurora Viewer, Blender and Ruth2/Roth2 communities, alongside other open-source projects and creative contributors. The [upstream references and acknowledgements](docs/UPSTREAMS.md) provide links and further details. Our work does not replace or claim ownership of theirs.

## Join the workshop

You don't have to be an engineer to contribute. Ideas, 3D models, textures, avatar designs, installation feedback and discoveries are all welcome. Use the [GitHub issues](https://github.com/PopeKael/Wozs-World/issues) to share ideas or report problems. Please include source and licensing information when contributing assets.

## Support the workshop ☕

Woz's World is a Garage Alchemy experiment shared openly for others to explore and build upon. There is no obligation to pay for participation. If you enjoy the work and would like to support future experiments, you are welcome to [Buy Me a Coffee](https://buymeacoffee.com/warrengerdes) or [Join the Tribe on Patreon](https://www.patreon.com/c/chanyawazza).

**Build something useful. Give it away. Let appreciation take care of itself.**
