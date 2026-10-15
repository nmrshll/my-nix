{ ... }:
let
  flakeModules.bash = { config, lib, ... }:
    let
      sharedBash = config.bash;
      bashOption = lib.mkOption {
        type = lib.types.lazyAttrsOf lib.types.lines;
        default = { };
        description = ''
          Named Bash fragments to interpolate into scripts using the bash
          module argument. Definitions from multiple modules merge per name.
          Same-name fragments concatenate lines; mkBefore and mkAfter control
          their order. Built-in fragments can be overridden normally.
          Per-system fragments inherit the shared fragments as defaults.
        '';
      };
    in
    {
      options.bash = bashOption;
      config = {
        bash = lib.mapAttrs (_: lib.mkDefault) {
          wd = "$(git rev-parse --show-toplevel)";
          sh_use_dbg = (import ./lib.p.nix { inherit lib; }).extraLib.sh_use_dbg;
        };
        _module.args.bash = config.bash;

        perSystem = { config, ... }: {
          options.bash = bashOption;
          config = {
            bash = lib.mapAttrs (_: lib.mkDefault) sharedBash;
            _module.args.bash = config.bash;
          };
        };
      };
    };
in
{
  flake.flakeModules = flakeModules;
  flake.flakeModuleGroups = { utils = flakeModules; essentials = flakeModules; };
  imports = builtins.attrValues flakeModules;
}
