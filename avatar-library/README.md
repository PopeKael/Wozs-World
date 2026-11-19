# Local avatar library

This folder separates upstream provenance from private downloaded content. Git tracks the catalogue and provenance only. The acquisition helper creates these machine-local categories:

- `original-packages/` — untouched downloaded archives.
- `source-meshes-development-kits/` — extracted editable source and setup documentation.
- `inventory-archives/` — unchanged IAR files copied from the source packages for direct import.
- `skins-materials/` — separately acquired skins, eyes and materials after license review.
- `clothing-accessories/` — separately acquired clothing, hair, animation and accessory packages after license review.
- `visual-evidence/` — in-world screenshots and evaluation notes; inspect for avatar/account identity before any sharing.
- `catalogue/` and `licensing-provenance/` — tracked public research and upstream references.

These machine-local categories are ignored by Git. Preserve original package archives and their licenses. Never copy personal inventory, private screenshots, credentials or avatar exports from another world into the repository.
