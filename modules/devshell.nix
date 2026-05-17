with builtins; let

  flakeModules.devShell = { lib, pkgs, options, l, ... }: {
    perSystem = { lib, pkgs, config, options, ... }: {
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
            type = lib.types.lazyAttrsOf (lib.types.oneOf [ lib.types.str lib.types.int ]);
            default = { };
            description = "Environment variables to set in the dev shell.";
          };
          overrides = lib.mkOption {
            type = lib.types.lazyAttrsOf (lib.types.oneOf [ lib.types.str lib.types.int ]);
            default = { };
            description = "Overrides for the dev shell environment.";
          };
        };
      };


      config.devShells.default = lib.mkDefault (pkgs.mkShell.override { stdenv = pkgs.stdenvNoCC; } {
        env = config.myDevShell.env;
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
