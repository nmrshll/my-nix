{ fetchurl, linkFarm, lib }:
let
  # Official single-file BF16 weights work without CUDA quantization kernels.
  revision = "ee64003102c8470ee32501cf883419235db81884";
  files = {
    "diffusion_models/moss_image_sft_bf16.safetensors" = "f96738d8116d78b7316b57c663d8c98591ddafab7488f48e3099b7655e34ab6f";
    "text_encoders/qwen3.5_9b_bf16.safetensors" = "7e6e9f08d598f829cb940e60ac0c698e1f1c27a47daffd7e598cd78c78b4cc53";
    "vae/flux2-vae_small.safetensors" = "d8d52ba036475f5fb07c8b435e176d3d97ebfa82f0d1a1c317f9cc1e25bd013b";
  };
in linkFarm "moss-image-sft-${builtins.substring 0 7 revision}" (lib.mapAttrsToList (name: sha256: {
  inherit name;
  path = fetchurl {
    url = "https://huggingface.co/Comfy-Org/MOSS-Image/resolve/${revision}/${name}";
    inherit sha256;
  };
}) files)
