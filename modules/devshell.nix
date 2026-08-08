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
          cleanupPaths = lib.mkOption {
            type = lib.types.lazyAttrsOf (lib.types.oneOf [
              lib.types.str
              (lib.types.submodule {
                options = {
                  path = lib.mkOption {
                    type = lib.types.str;
                    description = "Path to clean up.";
                  };
                  type = lib.mkOption {
                    type = lib.types.enum [ "symlink" "file" "dir" ];
                    description = "Type of item: symlink, file, or dir.";
                  };
                };
              })
            ]);
            default = { };
            description = "AttrSet of paths/lines or { path, type } objects to clean up in devShell.";
          };
          overrides = lib.mkOption {
            type = lib.types.lazyAttrsOf (lib.types.anything);
            default = { stdenv = pkgs.stdenvNoCC; };
            description = "Overrides for the dev shell environment.";
          };
        };
      };

      config = let
        cleanupPathsList = attrValues config.myDevShell.cleanupPaths;
        genCleanupCmd = item:
          if isString item then ''
            if [ -L "${item}" ]; then
              unlink "${item}"
            elif [ -f "${item}" ]; then
              rm -f "${item}"
            elif [ -d "${item}" ]; then
              rm -rf "${item}"
            fi
          ''
          else if item.type == "symlink" then ''
            [ -L "${item.path}" ] && unlink "${item.path}"
          ''
          else if item.type == "file" then ''
            [ -f "${item.path}" ] && rm -f "${item.path}"
          ''
          else if item.type == "dir" then ''
            [ -d "${item.path}" ] && rm -rf "${item.path}"
          ''
          else "";
        cleanupScript = pkgs.writeShellScriptBin "devshell-cleanup" (
          lib.concatMapStringsSep "\n" genCleanupCmd cleanupPathsList
        );
      in {
        devShells.default = (pkgs.mkShell.override config.myDevShell.overrides {
          # env = config.myDevShell.env;
          env = lib.mapAttrs (_: v: if (isBool v) then (if v then "true" else "false") else v) config.myDevShell.env;
          buildInputs = config.myDevShell.buildInputs ++ [ cleanupScript ];
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
