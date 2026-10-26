{ fetchurl, linkFarm, lib }:
let
  # Distilled four-step variant; BF16 avoids CUDA-only quantized kernels on Mac.
  revision = "533c4cbc3d3b89af1743d9466c434e89810391c0";
  files = {
    "diffusion_models/flux-2-klein-4b.safetensors" = "ec3d4e733a771f61c052fb4856c48b336c55eaf2c65487c2a1faeb9bbda7a343";
    "text_encoders/qwen_3_4b.safetensors" = "6c671498573ac2f7a5501502ccce8d2b08ea6ca2f661c458e708f36b36edfc5a";
    "vae/flux2-vae.safetensors" = "868fe7b343cc8f3a19dbcfcafbc3d5f888802be3f89bd81b65b3621a066ce8f3";
  };
in linkFarm "flux2-klein-4b-${builtins.substring 0 7 revision}" (lib.mapAttrsToList (name: sha256: {
  inherit name;
  path = fetchurl {
    url = "https://huggingface.co/Comfy-Org/Flux-2-Klein-4B/resolve/${revision}/split_files/${name}";
    inherit sha256;
  };
}) files)
