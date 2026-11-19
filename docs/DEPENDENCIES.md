# Dependencies, versions and limitations

## Operational dependencies

| Component | Version | Role and status |
|---|---|---|
| Windows | Windows 11 build 26200 on the observed host | Target x64 platform. Other Windows builds are not yet validated. |
| PowerShell | 7.6.9 on the observed host | Install and lifecycle scripts. Runtime paths derive from the checkout. |
| OpenSimulator | 0.9.3.0 | Pinned standalone binary package; official stable version checked for this candidate. |
| .NET runtime | 8.0.34 x64 | Matches the isolated runtime used by the existing working world and the OpenSimulator 0.9.3.0 target. The archive is downloaded from Microsoft and checked against Microsoft's published SHA-512. |
| SQLite native DLL | 3.54.1 x64 | Pinned official SQLite archive; DLL SHA-256 is checked after extraction. |
| Python | 3.14.10 x64 embeddable | Standard-library-only account page and terrain generator. Download is hash-pinned. |
| Aurora Viewer | 0.9.11 observed on host | External viewer, not installed or configured by the repository. The launch helper passes a local login URI. |

OpenSimulator's package archive was pinned by a recorded SHA-256 because the upstream distribution page did not publish a publisher digest; the archive itself is delivered over HTTP, so the hash protects against changed bytes only if the pin was established correctly. .NET uses Microsoft's published SHA-512 checksum; Python uses the publisher hash. SQLite is fetched from its official HTTPS site and the extracted DLL OpenSimulator loads is checked against a pinned SHA-256. SQLite publishes an archive SHA3-256 too, but the bundled PowerShell hash provider does not support SHA3, so that archive digest is not claimed as an installer check. Exact URLs and values are in the install script.

The runtime compatibility, setup scripts and Windows firewall checks still need successful end-to-end execution in a clean independent directory before being called validated. The only observed local installation is not a substitute for that test.

## Version 1.0.0 validation checkpoint

The clean-directory run verified the pinned OpenSimulator, .NET 8.0.34, Python and SQLite packages; extracted them; generated a 512 × 512 island; and produced fresh local configuration and credentials. It then stopped at `Get-NetFirewallProfile` because this execution environment denied access to the Windows firewall CIM provider. OpenSimulator was not started in that clean copy. Database initialization, automatic owner-account creation, the registration HTTP flow, Aurora login and the World Dock build therefore remain unverified in an independent install. Run those checks on a normal Windows host before relying on a new installation.

## Optional creative and development tools

| Tool | Observed version | Role / status |
|---|---|---|
| Blender | 4.5.14 LTS | Creative workshop; not required by server setup. |
| Blender Collada add-on | None installed in observed Blender | No add-on is required by this server release. DAE import/export workflow is not yet tested. Blender 4.5 LTS add-on compatibility must be checked before asset authoring. |
| Rust / Cargo | 1.98.0 on observed host | Optional World Dock build only. `Cargo.lock` pins crate versions; Windows C++ build tools are also needed. |
| Aurora Blender integration | Not tested | Not a dependency and not claimed installed. |

No Blender add-on is currently a required dependency. Keep 3D export plug-ins, image editors and experimental AI tools separate from operational server requirements. Recheck current upstream support and compatibility when changing pinned versions.

## Known limitations

- OpenSimulator 0.9.3.0 and the existing working world use .NET 8.0.34. Microsoft ended .NET 8 support on 10 November 2026; this 1.0.0 reproduction baseline therefore receives no future .NET 8 security servicing. Keep the initial setup local-only and plan a tested runtime/OpenSimulator upgrade for 1.1 before enabling outside access. [Microsoft support policy](https://dotnet.microsoft.com/en-us/platform/support/policy/dotnet-core).
- The Windows firewall check is host-specific and does not inspect third-party endpoint products or router policies. This setup does not provide a public server.
- No TLS, external registration, email verification, account recovery, abuse throttling, Hypergrid or Second Life/IMVU/print export workflow is included.
- Aurora launch and network connection require manual viewer acceptance. Viewer command-line behavior can vary by build.
- Acquisition only downloads source packages. It does not select or auto-wear a complete male/female starter set. Full avatar diversity, wearable outfits, inventory restore and clean-install visual comparison remain roadmap work.
- Blender rigged-DAE export, skin and animation portability, and Hypergrid portability are not confirmed by server configuration checks.
