{ lib, flake-parts }:
let
  bashModule = (import ../utils/bash.p.nix { }).flake.flakeModules.bash;
  eval = modules: (flake-parts.lib.evalFlakeModule {
    inputs.self.outPath = ../.;
  } {
    imports = [ bashModule ] ++ modules;
    systems = [ "x86_64-linux" "aarch64-darwin" ];
  }).config;

  defaults = eval [ ];
  extended = eval [
    ({ bash, ... }: {
      bash.project = "project-fragment";
      flake.fragmentsFromArg = bash;
      perSystem = { bash, system, ... }: {
        bash.system = system;
        legacyPackages.fragmentsFromArg = bash;
      };
    })
    { bash.another = "another-fragment"; }
  ];
  overridden = eval [ {
    bash.wd = "/shared";
    perSystem = { bash, system, ... }: {
      bash.wd = "/${system}";
      bash.target = "${bash.wd}/target";
    };
  } ];
  appended = eval [
    { bash.setup = lib.mkBefore "first"; }
    { bash.setup = lib.mkAfter "second"; }
  ];
  invalid = eval [ { bash.invalid = 42; } ];

  checks = {
    default-wd = defaults.bash.wd == "$(git rev-parse --show-toplevel)";
    default-debug = defaults.bash.sh_use_dbg == (import ../utils/lib.p.nix { inherit lib; }).extraLib.sh_use_dbg;
    per-system-defaults = defaults.allSystems.x86_64-linux.bash == defaults.bash;
    extended-keeps-defaults = extended.bash.wd == defaults.bash.wd && extended.bash.sh_use_dbg == defaults.bash.sh_use_dbg;
    modules-add-fragments = extended.bash.project == "project-fragment" && extended.bash.another == "another-fragment";
    shared-argument = extended.flake.fragmentsFromArg == extended.bash;
    per-system-inheritance = extended.allSystems.x86_64-linux.bash.project == "project-fragment";
    per-system-argument = extended.allSystems.aarch64-darwin.legacyPackages.fragmentsFromArg == extended.allSystems.aarch64-darwin.bash;
    per-system-isolation = extended.allSystems.x86_64-linux.bash.system == "x86_64-linux" && extended.allSystems.aarch64-darwin.bash.system == "aarch64-darwin";
    shared-override = overridden.bash.wd == "/shared";
    per-system-override = overridden.allSystems.x86_64-linux.bash.wd == "/x86_64-linux";
    fragment-composition = overridden.allSystems.x86_64-linux.bash.target == "/x86_64-linux/target";
    lines-merge = appended.bash.setup == "first\nsecond";
    rejects-non-strings = !(builtins.tryEval (builtins.deepSeq invalid.bash true)).success;
  };
in
lib.mapAttrs (name: passed: assert lib.assertMsg passed "Bash fragments check failed: ${name}"; passed) checks
