# Third-party notices

The repository-level MIT and CC0 terms apply only to project-owned material in their stated scopes. They do not replace licences attached to upstream material.

## OpenSimulator configuration

`config/OpenSim.ini.template` is adapted from OpenSimulator 0.9.3.0 configuration defaults. It remains under OpenSimulator's BSD-3-Clause terms; the required notice and disclaimer are preserved in [`licenses/OpenSimulator-LICENSE.txt`](../licenses/OpenSimulator-LICENSE.txt). The region template is a project-local configuration file and does not include OpenSimulator binaries.

## Downloaded dependencies

The installer retrieves OpenSimulator, .NET, Python and SQLite from their upstream sources. Their licences and notices remain applicable to each downloaded package; the binaries are not committed here. Rust dependencies are pinned in `controller/Cargo.lock`; review the exact locked crate licences before redistributing a compiled Dock binary.

## Avatar and other creative assets

Avatar packages and IARs are excluded from Git. The pinned source catalogue records provenance and licence caveats. Downloading an asset does not grant permission to redistribute or transfer it. Review the notices included with each exact package and preserve them alongside local copies.
