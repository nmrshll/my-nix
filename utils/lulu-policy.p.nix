{ ... }:
let module = ../pkgs/lulu-policy/module.nix;
in {
  imports = [ module ];
  flake.flakeModuleGroups.essentials.luluPolicy = module;
}
