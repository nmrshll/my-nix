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
  version = "0.42.1";
  src = fetchFromGitHub {
    owner = "Comfy-Org";
    repo = "ComfyUI";
    tag = "v0.42.1";
    hash = "sha256-/thkdznvXdpT2rgsyZ1NoH5jG1ox+pAjJCrj4glurSI=";
  };
  # The upstream dependency dry-run and CPU startup checks remain enabled.
  passthru = old.passthru // {
    sourceRevision = "63be2f9b82ad0dac88a7ceaa28a9cf3154125a18";
  };
  meta = upstream.meta // { platforms = lib.platforms.darwin; };
})
