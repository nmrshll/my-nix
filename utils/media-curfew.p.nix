{ ... }:
let module = ../pkgs/media-curfew/module.nix;
in {
  imports = [ module ];
  flake.flakeModuleGroups.essentials.mediaCurfew = module;
}
