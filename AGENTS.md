# Codex instructions for Woz's World

## Project intent

WOW is a Garage Alchemy learning project for AI-assisted 3D creation. The usual path is to make and inspect an asset in Blender, then test a copy in OpenSimulator, Aurora, Second Life, IMVU or a physical-print workflow. Explain steps for a curious creator, not only a systems administrator.

## Safety boundaries

- Keep each checkout and simulator instance independent. Resolve paths from the repository root; never assume a drive letter or username.
- Fresh installs use `StandaloneHypergrid.ini`, with `HomeURI` and `GatekeeperURI` set to the local loopback base URL. This initializes Hypergrid services without enabling remote access. Do not change `127.0.0.1`, firewall blocks, advertised region addresses, registration binding, RemoteAdmin binding or router settings to permit LAN/Internet access without a specific user request.
- Never read, copy, stage or publish `.local`, `server`, `runtime`, `downloads`, `data`, `backups`, `logs`, avatar packages, inventory archives, user screenshots, generated terrain or Blender personal preferences. The live world may contain private accounts and assets.
- Do not import assets into an existing world or replace an existing terrain/database during testing. Test in a separate clone directory and use backups before any operation that writes world state.
- Never put credentials, account UUIDs, viewer logs, machine paths, private profile data or local screenshots in tracked files. Generate credentials at install time and retain them only under ignored `.local`.
- Keep downloaded third-party packages unchanged. Verify pins and hashes, retain upstream notices, and do not redistribute an asset merely because it is free to download, free to wear or present in an IAR.
- Check each asset's specific licence and intended use before acquisition, import, modification or redistribution. Do not auto-download non-commercial or uncertain-rights items into the default starter set.
- Do not create custom avatar topology, rigging, weights, geometry repairs or skinning experiments unless the user asks for that work. Avatar source selection and wear tests are separate from mesh construction.

## Working practices

- Read `docs/DEPENDENCIES.md`, `docs/SECURITY.md` and the relevant installer before changing setup behavior.
- Prefer small, idempotent scripts. A rerun must not replace an existing database, region identity, credentials or terrain silently.
- Keep portable source, docs and source manifests in Git. Keep generated runtime files and third-party binaries out of Git.
- Validate changes in a new temporary checkout under a separate directory. Report what was actually tested and what remains untested; do not claim a viewer login from a server-only health check.
- When a current package/version/licence is material, check the upstream project's official documentation and record the check date and exact source.
- Before any public push, inspect the exact staged tree and full proposed commit history for secrets, private information, licences, generated files and absolute paths. Apply MIT to original software/documentation and CC0 1.0 to clearly identified project-created 3D assets/textures; third-party terms remain in force.
- Never reuse the original Woz's World Git history for the public repository. Build the release from a fresh sanitized root history; the working installation's history may contain private identifiers or machine details.
