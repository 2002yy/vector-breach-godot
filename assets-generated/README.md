# Reproducible asset intermediates

`assets-generated/` is a staging area for reproducible outputs created by Blender, Krita, conversion scripts, validators, or future Prism publish adapters before an asset is approved for the Godot runtime layer.

## Contract

- Contents are disposable and must be reproducible from source assets plus pipeline tools.
- Generated intermediates are ignored by Git by default.
- This directory contains `.gdignore`; Godot must not import staging artifacts.
- Promotion into runtime `assets/` is an explicit publish/review action, not an automatic consequence of generation.
- Evidence and validation reports should remain separate from runtime assets unless a specific pipeline step defines otherwise.

Only this README and `.gdignore` are expected to be tracked in this directory.
