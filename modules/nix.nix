# thisFlake:
with builtins; let
  flakeModules.nix = { config, pkgs, ... }: {
    perSystem = { config, pkgs, lib, ... }:
      with builtins; let
        scripts = mapAttrs (n: t: pkgs.writeShellScriptBin n t) {
          # NIX commands
          nshow = ''set -x; nix flake show --impure --show-trace --refresh --no-eval-cache $NIX_OVERRIDES'';
          neval = ''set -x; nix eval .#"$1" --show-trace --refresh --no-eval-cache $NIX_OVERRIDES'';
          attrNames = ''nix eval .#"$1" --apply builtins.attrNames $NIX_OVERRIDES'';
          nfresh = ''nix flake update . $NIX_OVERRIDES'';
          ndev = ''nix develop . --show-trace --impure "$${nixOverrides[@]}" '';
          nup = ''set -x; nix flake update --show-trace --refresh --no-eval-cache $NIX_OVERRIDES'';
          ncheck = ''set -x; nix flake check --impure --show-trace . $NIX_OVERRIDES'';
          nclean = ''find . -maxdepth 1 -type l -name 'result*' -exec unlink {} +'';
          nbuild = ''nix build ".#$1" --impure --show-trace --accept-flake-config $NIX_OVERRIDES'';
        };

        bin = scripts;

      in
      {
        config.bin = bin;
        config.expose.packages = scripts;
        config.myDevShell.buildInputs = attrValues scripts;
      };
  };

in
{
  flake.flakeModules = flakeModules // { utils = flakeModules; essentials = flakeModules; };
  imports = (attrValues flakeModules);
}
