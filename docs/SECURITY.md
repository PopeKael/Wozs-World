# Security and privacy

## Default network boundary

The default install is local-only. Registration binds to loopback; the region advertises and binds its UDP endpoint to `127.0.0.1`; RemoteAdmin binds to loopback and allows loopback callers only. New installs use the Standalone Hypergrid architecture, but `HomeURI` and `GatekeeperURI` resolve to the local loopback base URL. Startup does not inspect, change or add Windows Firewall rules, and it does not configure port forwards or externally reachable Hypergrid addresses. Keep the host's existing firewall policy in place; do not weaken it to make a local simulator start.

OpenSimulator's HTTP listener may still bind a wildcard interface internally; advertising loopback does not itself constrain that socket. Confirm service bindings and the host's firewall policy before enabling any LAN or external access. The project does not inspect every endpoint security product or network policy. Do not publish the host or enable LAN/external access without a separate design, TLS, authentication, rate limiting and review. Version 1.0.0 uses the proven .NET 8.0.34 runtime from the working world. .NET 8 reached end of support on 10 November 2026; keep this installation local-only and revalidate a supported runtime before any external-access design. See [dependencies](DEPENDENCIES.md).

## Private runtime data

Git ignores `.local/`, `server/`, `runtime/`, `downloads/`, `data/`, `backups/`, `logs/`, avatar packages/IARs, generated terrain and Dock build output. `.local/` contains generated credentials and IDs. `server/` holds account and inventory databases, configuration and asset stores. Backups may contain all of these. Keep them private; do not force-add ignored files.

Before a release, inspect the exact tracked tree and every proposed Git object. A credential or personal identifier in old history is still public after deleting the current file, so a first public release must use a fresh, sanitized Git root history. Rotate any credential that was exposed.

## Secrets and account creation

Passwords and UUIDs are generated for each independent installation. Do not pass passwords on command lines or log form data. The owner password is saved only in the ignored ACL-restricted local file and OpenSim configuration. The browser registration server suppresses request logs and binds only to loopback. This is a local testing page; it has no public abuse protections, TLS or account recovery.
