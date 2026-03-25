with builtins; let

  flakeModules.devShell = { lib, pkgs, options, l, ... }: {
    perSystem = { lib, pkgs, config, options, ... }: {
      options = {
        devShellParts = {
          buildInputs = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = (attrValues config.packages);
            description = "Packages to add to the dev shell environment.";
          };
          # TODO rename to shellHooks
          shellHookParts = lib.mkOption {
            type = lib.types.lazyAttrsOf (lib.types.oneOf [ lib.types.lines lib.types.str ]);
            default = { };
            description = "Named lines to add to the shell hook script.";
          };
          env = lib.mkOption {
            type = lib.types.lazyAttrsOf (lib.types.oneOf [ lib.types.str lib.types.int ]);
            default = { };
            description = "Environment variables to set in the dev shell.";
          };
        };
      };

      config.devShells.default = lib.mkDefault (pkgs.mkShell {
        env = config.devShellParts.env;
        buildInputs = config.devShellParts.buildInputs;
        shellHook = lib.concatStringsSep "\n" (attrValues config.devShellParts.shellHookParts);
      });
    };
  };

in
{
  flake.flakeModules = { utils = flakeModules; essentials = flakeModules; };
  imports = (attrValues flakeModules);
}
