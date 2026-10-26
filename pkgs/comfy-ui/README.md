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

`pkgs.own.comfy-ui-moss-image` pins the official Comfy-Org MOSS Image SFT BF16
diffusion model, Qwen3.5-9B BF16 encoder, and FLUX.2 small VAE at revision
`ee64003102c8470ee32501cf883419235db81884`, checking each file's SHA-256.
The download is about 29.7 GB. `linkFarm` exposes model category directories
without copying the weights. BF16 avoids CUDA-specific quantized kernels on
Apple Silicon. Configure `extra_model_paths.yaml` to reference this store path.

`pkgs.own.comfy-ui-klein-4b` pins Comfy-Org's FLUX.2 Klein 4B distilled
BF16 model, Qwen3-4B encoder, and FLUX.2 VAE at revision
`533c4cbc3d3b89af1743d9466c434e89810391c0`. It checks each file's SHA-256
and exposes the same category directories through a link farm. The download is
about 16.1 GB. Use the distilled four-step workflow with CFG 1; the similarly
named base model is a different, slower checkpoint.

For a focused build without evaluating unrelated custom packages:

```sh
nix build --impure --expr 'let f = builtins.getFlake (toString ./.); in f.debug.allSystems.aarch64-darwin.ownPkgs.comfy-ui {}'
```

Sources: [Desktop](https://github.com/Comfy-Org/Comfy-Desktop/releases/tag/v1.1.7),
[ComfyUI](https://github.com/Comfy-Org/ComfyUI/releases/tag/v0.42.3),
[Klein weights](https://huggingface.co/Comfy-Org/Flux-2-Klein-4B),
[MOSS weights](https://huggingface.co/Comfy-Org/MOSS-Image), and
[official workflow](https://github.com/Comfy-Org/workflow_templates/blob/main/templates/image_moss_image_t2i.json).
