# thisFlake:
with builtins; let
  flakeModules.editors = { ... }: {
    # TODO
    perSystem = { pkgs, config, lib, ... }:
      with builtins; let
        # l = lib // builtins;
        # editorPkgs = lib.mapAttrs (name: mkPkg: pkgs.callPackage mkPkg { }) (import ../pkgs/editor-pkgs.nix);
        bin = mapAttrs (n: pkg: "${pkg}/bin/${n}") (scripts // { inherit (pkgs) jq; });


        nuWd = "(git rev-parse --show-toplevel)";
        # TODO if attrs, then mapAttrs, but if one element, then just transform
        mkNuScripts = pkgs.lib.mapAttrs (name: text:
          let scriptFile = pkgs.writeScriptBin "${name}" ''${text}'';
          in pkgs.writeScriptBin "${name}" ''${pkgs.nushell}/bin/nu -n "${scriptFile}/bin/${name}" "$@" ''
        );
        mkNuScript = (name: text:
          let scriptFile = pkgs.writeScriptBin "${name}" ''${text}'';
          in pkgs.writeScriptBin "${name}" ''${pkgs.nushell}/bin/nu -n "${scriptFile}/bin/${name}" "$@" ''
        );

        paramScripts = {
          cvc = extraSettings: mkNuScript "cvc" ''
            let SETTINGS_FILE = "${nuWd}/.vscode/settings.json"
            let a = try { open $SETTINGS_FILE } catch { echo '{}' } | from json
            $a
          '';
        };

        nuScripts = mkNuScripts {
          # cvc = ''let SETTINGS_FILE = "${nuWd}/.vscode/settings.json"
          # 	let a = try { open $SETTINGS_FILE } catch { echo '{}' } | from json
          # 	$a
          #   # if ('${nuWd}/.vscode/settings.json' | path exists) {
          #   # 	mkdir "${nuWd}/.cache/backups"; cp $SETTINGS_FILE $"${nuWd}/.cache/backups/vscode.settings.json.bak_(date now | format date "%Y%m%d%H%M%S")"
          # 	# 	exit 0
          # 	# 	let config_pre = open $SETTINGS_FILE | from json
          # 	# 	echo $config_pre
          # 	# 	let obj1 = {name: "Alice", age: 30}
          # 	# 	let obj2 = {title: "Astronaut", age: 31, rank:3 }

          # 	# 	($obj1 | merge $obj2) | to json | save --append $SETTINGS_FILE
          #   # } else {
          #   # 	echo "File doesn't exist"
          #   # }
          # '';
        };

        wd = "$(git rev-parse --show-toplevel)";
        scripts = mapAttrs (n: t: pkgs.writeShellScriptBin n t) {
          configure-editors = ''
            if (code --help | grep -q "Visual Studio Code"); then
              ${bin.configure-vscode}
            fi
          '';
          configure-vscode = ''
            if (code --help | grep -q "Visual Studio Code"); then
              SETTINGS_PATH="${wd}/.vscode/settings.json";
              ORIGINAL_SETTINGS=$(if [[ -f "$SETTINGS_PATH" && $(file --mime "$SETTINGS_PATH") =~ "application/json" ]]; then cat "$SETTINGS_PATH"; else echo "{}"; fi);
              MERGED_SETTINGS=$(echo "$ORIGINAL_SETTINGS" | ${bin.jq} --argjson new_data '${toJSON config.vscode.settings}' '. * $new_data');
              mkdir -p "$(dirname "$SETTINGS_PATH")";
              echo "$MERGED_SETTINGS" >| "$SETTINGS_PATH";
            fi
          '';
          configure-zed = ''
            if command -v zed >/dev/null 2>&1; then
              SETTINGS_PATH="${wd}/.zed/settings.json";
              ORIGINAL_SETTINGS=$(if [[ -f "$SETTINGS_PATH" && $(file --mime "$SETTINGS_PATH") =~ "application/json" ]]; then cat "$SETTINGS_PATH"; else echo "{}"; fi);
              MERGED_SETTINGS=$(echo "$ORIGINAL_SETTINGS" | ${bin.jq} --argjson new_data '${toJSON config.zed.settings}' '. * $new_data');
              mkdir -p "$(dirname "$SETTINGS_PATH")";
              echo "$MERGED_SETTINGS" >| "$SETTINGS_PATH";
            fi
          '';
        };

      in
      {
        options.vscode.settings = lib.mkOption {
          type = lib.types.attrs;
          default = { };
          description = "VSCode settings (local to repo)";
        };
        options.zed.settings = lib.mkOption {
          type = lib.types.attrs;
          default = { };
          description = "Zed settings (local to repo, merged into .zed/settings.json)";
        };
        config = {
          inherit bin;
          # packages = scripts;
          expose.packages = scripts;
          myDevShell.buildInputs = (attrValues scripts);
          myDevShell.shellHooks.configure-editors = bin.configure-editors;
          myDevShell.shellHooks.configure-zed = "${scripts.configure-zed}/bin/configure-zed";
        };
      };
  };

in
{
  flake.flakeModules = flakeModules;
  flake.flakeModuleGroups = { utils = flakeModules; essentials = flakeModules; };
  imports = (attrValues flakeModules);
}
