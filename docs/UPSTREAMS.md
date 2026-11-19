# Upstream projects and acknowledgements

Versions below describe the intended local setup or the tool version observed on the original host; they are not a claim that each combination has completed clean-clone validation.

| Project | Use in WOW | Version / license reference |
|---|---|---|
| [OpenSimulator](https://opensimulator.dev/) | Local world server and account/inventory services | 0.9.3.0; BSD-3-Clause. The adapted OpenSim config template and required notice are identified in [third-party notices](THIRD-PARTY-NOTICES.md); see the [upstream license](https://github.com/opensim/opensim/blob/master/LICENSE.txt) and [download page](https://opensimulator.dev/wiki/Download). |
| [.NET](https://dotnet.microsoft.com/) | Runtime used by the pinned OpenSimulator build | 8.0.34 x64, matching the working local installation and OpenSimulator 0.9.3.0's declared target; [runtime license](https://github.com/dotnet/runtime/blob/main/LICENSE.TXT). .NET 8 reached end of support on 10 November 2026; see [OpenSim 0.9.3.0 requirements](https://opensimulator.dev/wiki/0.9.3.0) and [Microsoft lifecycle](https://dotnet.microsoft.com/en-us/platform/support/policy/dotnet-core). |
| [SQLite](https://sqlite.org/) | Native database runtime used by OpenSimulator | 3.54.1 x64; [SQLite is public domain](https://sqlite.org/copyright.html). |
| [Python](https://www.python.org/) | Local registration service and terrain tooling | 3.14.10 x64 embeddable; [Python license](https://docs.python.org/3.14/license.html) and [release files/checksums](https://www.python.org/downloads/release/python-31410/). |
| [Aurora Viewer](https://github.com/Aurora-Viewer/Aurora-Viewer) | Optional client, separately installed by the contributor | 0.9.11 observed locally; upstream identifies its project code as GPLv3. WOW neither bundles nor changes the viewer. |
| [Blender](https://www.blender.org/) | Shared creative workshop; optional | 4.5.14 LTS observed locally; [official license](https://www.blender.org/about/license/). No add-on is required by this repository. |
| [Rust](https://www.rust-lang.org/) and [egui/eframe](https://github.com/emilk/egui) | Optional World Dock source build | rustc/Cargo 1.98.0 observed locally; crate versions are pinned in `controller/Cargo.lock`. Review the licenses from the exact locked dependency graph before redistributing a compiled Dock. |
| Ruth2 / Roth2 / RuthToo / RothToo / Max | Optional third-party avatar research sources | Commit pins, archive hashes and package-level license caveats in `avatar-library/licensing-provenance/PROVENANCE.md`. |

The official OpenSimulator binary URL currently uses HTTP. WOW verifies the archive against its recorded local SHA-256, but that pin is not a publisher signature. Recheck the upstream URL, release, hash and license before changing any pin.
