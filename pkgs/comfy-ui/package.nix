{ pkgs, lib, comfyui, python3, ... }:
let
  mkPkg = { backend ? comfyui, extraArgs ? [ ], port ? 8188 }:
    pkgs.lib.darwin.installDmg {
      version = "1.1.7";
      url = "https://download.comfy.org/261013p26tnl6re/mac/dmg/arm64";
      sha256 = "sha256-m52UAzsjXwf5rxGPXpNH5YKs7OgkD9NQHvbDHgnplhA=";
      appname = "Comfy Desktop";
      installPhase = ''
        mkdir -p "$out/Applications/Comfy Desktop.app" "$out/bin"
        cp -a ./. "$out/Applications/Comfy Desktop.app/"
        ln -s ${pkgs.writeShellScript "comfyui" ''
          exec ${lib.getExe backend} ${lib.escapeShellArgs extraArgs} "$@"
        ''} "$out/bin/comfyui"
        ln -s ${pkgs.writeShellScript "comfyui-python" ''
          unset NIX_PYTHONPATH PYTHONPATH
          exec ${lib.getExe backend.pythonEnv} "$@"
        ''} "$out/bin/comfyui-python"
        install -m755 ${pkgs.replaceVars ./configure-desktop.py { python = lib.getExe python3; }} "$out/bin/comfyui-configure-desktop"
      '';
      passthru = { inherit mkPkg backend; };
      meta = {
        description = "Official Comfy Desktop with a Nix-packaged ComfyUI backend";
        homepage = "https://github.com/Comfy-Org/Comfy-Desktop";
        mainProgram = "comfyui";
      };
    };
in mkPkg { }
