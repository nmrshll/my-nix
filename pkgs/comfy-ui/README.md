# ComfyUI on macOS

`pkgs.own.comfy-ui` installs the official Comfy Desktop 1.1.7 app and a packaged
ComfyUI 0.42.3 backend. Both were checked online on 2026-10-21: Desktop is the latest stable
release and ComfyUI is the newest upstream tag (the release endpoint lags tags). Desktop and the ComfyUI instance have independent
version numbers. The old ToDesktop ComfyUI DMG has been replaced.

The backend extends nixpkgs-unstable's derivation: neither nix-home's pinned
0.37.0 nor current nixpkgs 0.39.2 contains MOSS Image support. `backend.nix`
retains the upstream writable-directory patch, dependency dry-run, and CPU
startup install checks. `python-pins.json` pins matching PyPI wheels; the pure
Python kitchen/aimdo wheels use the macOS fallback backends. Remove this override
when nixpkgs provides a tested release with MOSS Image support.

`comfy-ui.mkPkg { extraArgs = [ ... ]; }` adds fixed arguments to the foreground
`comfyui` CLI. Its `backend` passthru exposes the source and Python environment.
`comfyui-python` runs that Python environment with inherited Nix/Python search
paths cleared, for Desktop's adopted-instance launcher.

`comfyui-configure-desktop MANIFEST REGISTRY` merges one Nix-managed instance
into Desktop's mutable `installations.json`. It reuses the existing adopted
instance with the same data directory, preserves unrelated instances/fields,
backs up a changed registry, and replaces it atomically. Quit Desktop before
activation so its in-memory registry cannot overwrite the update. Home Manager
owns the separate manifest and source symlink; it does not symlink Desktop's
mutable registry. The source and dependencies are immutable; update through Nix
rather than Desktop's update/repair controls.

`pkgs.own.comfy-ui-model-downloader` provides `comfyui-models` and exposes plain
metadata through its `models` passthru. The weights are not Nix build inputs.
`model-manifest.nix` pins official Comfy-Org files with SHA-256 hashes:

- MOSS Image SFT BF16, Qwen3.5-9B BF16 encoder, and FLUX.2 small VAE at revision
  `ee64003102c8470ee32501cf883419235db81884` (about 29.7 GB).
- FLUX.2 Klein 4B distilled BF16, Qwen3-4B encoder, and FLUX.2 VAE at revision
  `533c4cbc3d3b89af1743d9466c434e89810391c0` (about 16.1 GB).

BF16 avoids CUDA-specific quantized kernels on Apple Silicon. Klein uses the
distilled four-step workflow with CFG 1; the similarly named base model is a
different, slower checkpoint.

Home Manager writes `~/.config/comfyui/models.json` containing `directory`, a
`files` array of `{path, url, sha256}`, and optional `search_roots`. Paths are
relative to model categories, such as `diffusion_models/example.safetensors`.
The one-off launchd job runs `comfyui-models` after activation has linked this
manifest. It stores weights in the writable model directory, outside `/nix/store`.
Run the command manually to retry; no persistent daemon or scheduled polling is
needed. Downloads resume in `.downloads/`, and only verified files are renamed
into the model categories. A per-directory lock prevents concurrent writers.
Different existing files are preserved with a `.before-model-sync-*` suffix;
already-correct files are skipped. The helper never deletes undeclared models.

`comfyui-models --remember-config OLD_CONFIG --state-dir STATE` records paths
from the previous HM-generated JSON/YAML before it is replaced. The sync job
checks these paths and `search_roots` for reusable files, then copies and verifies
them outside the store so garbage collection remains safe. The manifest only
declares downloads; no network transfer happens while evaluating or building Nix.

The downloader's regression checks use tiny loopback fixtures, not real weights:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 pkgs/comfy-ui/test_download_models.py
```

For a focused build without evaluating unrelated custom packages:

```sh
nix build --impure --expr 'let f = builtins.getFlake (toString ./.); in f.debug.allSystems.aarch64-darwin.ownPkgs.comfy-ui {}'
```

Sources: [Desktop](https://github.com/Comfy-Org/Comfy-Desktop/releases/tag/v1.1.7),
[ComfyUI](https://github.com/Comfy-Org/ComfyUI/releases/tag/v0.42.3),
[Klein weights](https://huggingface.co/Comfy-Org/Flux-2-Klein-4B),
[MOSS weights](https://huggingface.co/Comfy-Org/MOSS-Image), and
[official workflow](https://github.com/Comfy-Org/workflow_templates/blob/main/templates/image_moss_image_t2i.json).
