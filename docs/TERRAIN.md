# Procedural island terrain

`terrain/generate_terrain.py` uses only the Python standard library and writes a native OpenSimulator R32 file, a PNG preview and metadata. All templates are 512 × 512 samples; each installation receives a cryptographically random seed and chooses a template unless `-Template` is supplied to the installer.

The three templates are:

- **Atoll:** a broken ring with a sheltered lagoon.
- **Archipelago:** four distinct islands around a central channel.
- **Mountain:** one central island with a raised summit and ridges.

Generate a preview without touching a world by running:

```powershell
python .\terrain\generate_terrain.py --template random --output-dir .\terrain\generated
```

Generated files are ignored by Git. An explicit terrain import requires a separate argument and is never run on an already-installed world automatically. See the installation guide for the import and rollback sequence. Terrain generation is deterministic for a chosen seed; the default installation chooses a fresh seed and refuses to overwrite existing generated outputs.
