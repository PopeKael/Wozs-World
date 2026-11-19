# Avatar library workflow

The Git repository contains provenance and search notes only. Source ZIPs, IARs, extracted meshes, skins, clothing, visual evidence and imports remain local under ignored `avatar-library/` subdirectories.

Use `scripts/Acquire-AvatarSources.ps1` to retrieve the pinned Ruth2, Roth2, RuthToo, RothToo and Max archives. The script keeps each original ZIP, verifies the recorded digest, extracts into a system-specific folder, and copies upstream notices. It never imports into a running or existing grid. Acquisition of mixed-license packages does not grant redistribution rights.

Install and evaluate in a fresh OpenSimulator account/world. Follow the candidate's own setup notes; import IARs with the package's intended folder structure and wear its own shape, skin, alpha and mesh parts. Capture Aurora screenshots for front, side, face, standing and movement. Record a candidate as compatible only after clean-install import succeeds. Keep the unclothed base-body review separate from supplied clothing tests. Do not edit third-party skeletons, weights or geometry as part of this project stage.

The shortlist and evidence status are in `../avatar-library/catalogue/AVATAR-CATALOGUE.md`. Preserve the untouched packages and their original copyright and license files. A future default-avatar choice needs a bill of materials that names the creator and terms for each body, skin, head, eyes, hair, clothing, animation and AO component.
