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
          overrides = lib.mkOption {
            type = lib.types.lazyAttrsOf (lib.types.anything);
            default = { stdenv = pkgs.stdenvNoCC; };
            description = "Overrides for the dev shell environment.";
          };
        };
      };


      config.devShells.default = (pkgs.mkShell.override config.myDevShell.overrides {
        # env = config.myDevShell.env;
        env = lib.mapAttrs (_: v: if (isBool v) then (if v then "true" else "false") else v) config.myDevShell.env;
        buildInputs = config.myDevShell.buildInputs;
        shellHook = lib.concatStringsSep "\n" (attrValues config.myDevShell.shellHooks);
      });
    };
  };

in
{
  flake.flakeModules = flakeModules // { utils = flakeModules; essentials = flakeModules; };
  imports = (attrValues flakeModules);
}
