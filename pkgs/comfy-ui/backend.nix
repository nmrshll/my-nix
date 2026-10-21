{ lib, fetchFromGitHub, fetchurl, upstream }:
let
  pins = builtins.fromJSON (builtins.readFile ./python-pins.json);
  python = upstream.python.override {
    packageOverrides = final: prev: lib.mapAttrs (name: pin:
      if prev.${name}.version == pin.version then prev.${name}
      else final.buildPythonPackage {
        pname = name;
        inherit (pin) version;
        format = "wheel";
        src = fetchurl { inherit (pin) url sha256; };
        dependencies = map (dep: final.${dep}) (pin.dependencies or [ ])
          ++ lib.optional (name == "comfy-kitchen") final.torch;
        pythonImportsCheck = [ (builtins.replaceStrings [ "-" ] [ "_" ] name) ];
        meta = prev.${name}.meta;
      }
    ) pins;
  };
in (upstream.override { python3 = python; }).overrideAttrs (old: {
  version = "0.42.3";
  src = fetchFromGitHub {
    owner = "Comfy-Org";
    repo = "ComfyUI";
    tag = "v0.42.3";
    hash = "sha256-QepSnLNO7RSQcOjKkRBzfcxMwGYRDs/NVr2WUp4KD6c=";
  };
  # The upstream dependency dry-run and CPU startup checks remain enabled.
  passthru = old.passthru // {
    sourceRevision = "edb3db00fd88f059e748c8a400391b5eab76266b";
  };
  meta = upstream.meta // { platforms = lib.platforms.darwin; };
})
