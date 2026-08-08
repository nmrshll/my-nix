with builtins; let

  flakeModules.devShell = { ... }: {
    perSystem = { lib, pkgs, config, ... }: {
      options = {
        myDevShell = {
          buildInputs = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = (attrValues config.packages);
            description = "Packages to add to the dev shell environment.";
          };
          shellHooks = lib.mkOption {
            type = lib.types.lazyAttrsOf (lib.types.oneOf [ lib.types.lines lib.types.str ]);
            default = { };
            description = "Named lines to add to the shell hook script.";
          };
          env = lib.mkOption {
            type = lib.types.lazyAttrsOf (lib.types.oneOf [ lib.types.str lib.types.int lib.types.bool ]);
            default = { };
            description = "Environment variables to set in the dev shell.";
          };
          cleanups = lib.mkOption {
            type = lib.types.lazyAttrsOf (lib.types.oneOf [
              lib.types.str
              (lib.types.submodule {
                options = {
                  path = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    description = "Path to clean up.";
                  };
                  script = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    description = "Custom cleanup script.";
                  };
                  type = lib.mkOption {
                    type = lib.types.enum [ "symlink" "file" "dir" "script" ];
                    default = "script";
                    description = "Type of item: symlink, file, dir, or script.";
                  };
                };
              })
            ]);
            default = { };
            description = "AttrSet of paths/lines or { path|script, type } objects to clean up in devShell.";
          };
          scripts = lib.mkOption {
            type = lib.types.lazyAttrsOf (lib.types.oneOf [ lib.types.lines lib.types.str ]);
            default = { };
            description = "AttrSet of shell script lines to map to binaries via pkgs.writeShellScriptBin and include in devShell.";
          };
          overrides = lib.mkOption {
            type = lib.types.lazyAttrsOf (lib.types.anything);
            default = { stdenv = pkgs.stdenvNoCC; };
            description = "Overrides for the dev shell environment.";
          };
        };
      };

      config =
        let
          cleanupsList = attrValues config.myDevShell.cleanups;
          genCleanupCmd = item:
            if isString item then ''
              if [ -L "${item}" ]; then unlink "${item}"
              elif [ -f "${item}" ]; then rm -f "${item}"
              elif [ -d "${item}" ]; then rm -rf "${item}"
              fi
            ''
            else if item.type == "script" || item.script != null then item.script
            else if item.type == "symlink" then '' [ -L "${item.path}" ] && unlink "${item.path}" ''
            else if item.type == "file" then '' [ -f "${item.path}" ] && rm -f "${item.path}" ''
            else if item.type == "dir" then '' [ -d "${item.path}" ] && rm -rf "${item.path}" ''
            else "";
          cleanupScript = pkgs.writeShellScriptBin "devshell-cleanup" (
            lib.concatMapStringsSep "\n" genCleanupCmd cleanupsList
          );
          scriptPackages = attrValues (lib.mapAttrs pkgs.writeShellScriptBin config.myDevShell.scripts);
        in
        {
          devShells.default = (pkgs.mkShell.override config.myDevShell.overrides {
            env = lib.mapAttrs (_: v: if (isBool v) then (if v then "true" else "false") else v) config.myDevShell.env;
            buildInputs = config.myDevShell.buildInputs ++ [ cleanupScript ] ++ scriptPackages;
            shellHook = lib.concatStringsSep "\n" (attrValues config.myDevShell.shellHooks);
          });
        };
    };
  };

in
{
  flake.flakeModules = flakeModules // { utils = flakeModules; essentials = flakeModules; };
  imports = (attrValues flakeModules);
}
