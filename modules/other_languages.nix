# thisFlake:
# Optional per-language editor config. Import only what you use, e.g.:
#   imports = [ inputs.my-nix.flakeModules.noir ];
with builtins; let
  flakeModules.noir = { ... }: {
    perSystem = { pkgs, config, lib, ... }:
      with builtins; let
        wd = "$(git rev-parse --show-toplevel)";
        bin = mapAttrs (n: pkg: "${pkg}/bin/${n}") { inherit (pkgs) jq; };
        scripts = mapAttrs (n: t: pkgs.writeShellScriptBin n t) {
          configure-vscode-noir = ''
            if command -v code >/dev/null 2>&1; then
              SETTINGS_PATH="${wd}/.vscode/settings.json"; mkdir -p "$(dirname "$SETTINGS_PATH")";
              if [ -f "$SETTINGS_PATH" ]; then
                ORIGINAL_SETTINGS=$(if [[ $(file --mime "$SETTINGS_PATH") =~ "application/json" ]]; then cat "$SETTINGS_PATH"; else echo "{}"; fi)
              else
                ORIGINAL_SETTINGS="{}"
              fi
              NEW_SETTINGS=$(echo "$ORIGINAL_SETTINGS" \
                | ${bin.jq} --arg nargo "$(command -v nargo || echo nargo)" \
                  '."noir.nargoPath" |= $nargo | ."noir.enableLSP" |= true')
              if [ ! -f "$SETTINGS_PATH" ] || [ "$(cat "$SETTINGS_PATH")" != "$NEW_SETTINGS" ]; then
                echo "$NEW_SETTINGS" >| "$SETTINGS_PATH"
              fi
            fi'';
        };
      in
      {
        options.noir.nargoPackage = lib.mkOption {
          type = lib.types.nullOr lib.types.package;
          default = pkgs.nargo or null;
          description = "Nargo package providing the Noir toolchain.";
        };
        config = {
          inherit bin;
          expose.packages = scripts;
          myDevShell.buildInputs = (attrValues scripts);
          # Declarative path (preferred): merged by configure-vscode.
          vscode.settings = {
            "noir.enableLSP" = true;
          } // lib.optionalAttrs (config.noir.nargoPackage != null) {
            "noir.nargoPath" = "${config.noir.nargoPackage}/bin/nargo";
          };
          # Imperative fallback for repos that already have settings.json flows.
          myDevShell.shellHooks.configure-vscode-noir =
            "${scripts.configure-vscode-noir}/bin/configure-vscode-noir";
        };
      };
  };

in
{
  flake.flakeModules = flakeModules;
  imports = (attrValues flakeModules);
}
