# Development roadmap

## Version phases

- **1.0.0:** Reproduce the current working local world with independent runtime state, account registration, procedural terrain and the existing Aurora workflow. Outstanding clean-install and viewer validation are documented as known limitations.
- **1.1:** Refine the installation process, choose and test starter avatars, and simplify account-to-world onboarding.

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

## 3. Original creative assets

- Use Blender as the collaborative workshop for original props, scenes, clothing, textures, hair and diverse original avatars.
- Keep the Blender version and required export add-ons documented. Label project-created models and textures CC0 1.0; retain source and provenance, and keep third-party terms attached to their assets.
- Keep OpenSimulator/Second Life Collada export, IMVU delivery and 3D-print manifold/scale validation as separate, tested targets.

## 4. Broader destinations

- Test export/import with a disposable OpenSimulator region first.
- Add Second Life, IMVU and physical-print workflows only after format and creator-rights checks.
- Preserve source files and provenance so assets can be reused without tying them to one vendor or grid.
