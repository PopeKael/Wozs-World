# Licensing and redistribution

## Project-owned work

- Original software and documentation are licensed under MIT; see the repository [LICENSE](../LICENSE). The OpenSimulator-derived configuration template is an explicit exception and retains the upstream BSD-3-Clause terms in [third-party notices](THIRD-PARTY-NOTICES.md).
- Project-created 3D models and textures placed in `assets/original/` are dedicated under CC0 1.0 Universal; see [the canonical legal code](../LICENSE-CC0-1.0.txt) and the [CC0 asset instructions](../assets/original/README.md). No original 3D models or textures are included in version 1.0.0.
- The World Dock icon ships as a software resource and is covered by the repository MIT licence.
- These grants apply only to work the project controls. Do not apply either licence to third-party material or imply that a contributor can waive someone else's rights.

Contributions should retain their source provenance and licence. A contribution without clear rights information must not be included in a distributable asset package. See [upstream acknowledgements](UPSTREAMS.md) for operational and optional dependencies.

## Third-party avatar assets

Avatar source ZIPs and IARs are not committed. `Acquire-AvatarSources.ps1` obtains them from pinned upstream commits into ignored local directories and retains the original ZIP and all included attribution/licence files. The source catalogue records which components have AGPL, CC BY, CC BY-NC or varying terms. Check the exact component before use or redistribution.

The acquisition script excludes non-commercial and uncertain-rights packages from the default starter set. “Free download,” “free to wear,” full permissions on a distribution box, and permission to transfer an asset into one local grid do not automatically permit redistribution of the entire repository snapshot. No third-party avatar data is placed in the public Git repository.

## Software dependencies

OpenSimulator, .NET, Python, Rust crates and SQLite are retrieved from their respective upstreams and are not bundled as binaries in Git. Their upstream licences remain applicable. Rust dependency versions are locked; before distributing a built Dock binary, generate and review a third-party licence notice for the exact Cargo graph.
