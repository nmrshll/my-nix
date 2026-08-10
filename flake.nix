{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
  inputs.fp.url = "github:hercules-ci/flake-parts";
  inputs.rust-overlay = { url = "github:oxalica/rust-overlay"; inputs.nixpkgs.follows = "nixpkgs"; };
  inputs.crane = { url = "github:ipetkov/crane"; };
  inputs.tools = { url = "git+ssh://git@gitlab.com/nmrshll/tools.git"; inputs.nixpkgs.follows = "nixpkgs"; inputs.parts.follows = "fp"; inputs.my-nix.follows = "/"; };

  nixConfig.experimental-features = [ "flakes" "nix-command" ];
  nixConfig.allow-unsafe-native-code-during-evaluation = true;
  nixConfig.allow-import-from-derivation = true;

  outputs = inputs@{ fp, ... }: fp.lib.mkFlake { inherit inputs; } ({ lib, ... }: let
    l = (import ./utils/lib.p.nix { lib = lib; }).extraLib;

    # # NOTE: importApply injects thisFlake into module args (to distinguish from caller flake)
    # flakeModules = mapAttrs (n: file: flake-parts-lib.importApply file { inherit inputs; }) {
    #   cli-tools = ./modules/cli-tools.nix;
    #   git = ./modules/git.nix;
    #   editors = ./modules/editors.nix;
    #   services = ./modules/services.nix;
    #   rust = ./modules/rust.nix;
    #   devshell = ./modules/devshell.nix;
    # };
    # pkgModules = [
    #   (import ./pkgs/cli-pkgs.nix)
    #   (import ./pkgs/editor-pkgs.nix)
    #   (import ./pkgs/gui-pkgs.nix)
    #   (import ./pkgs/libs-pkgs.nix)
    #   (import ./pkgs/service-pkgs.nix)
    # ];
    parts = lib.flatten (map (dir: l.findNixFilesRec dir) [ /* ./pkgs */ ./utils ./modules ]);
    # utilsModules = [
    #   (import ./utils/lib.p.nix)
    #   (import ./utils/util-options.p.nix)
    #   (import ./utils/lib.darwin.p.nix)
    # ];
    extraFlakeModules.exposeInputs = { options.flakeInputsOf.my-nix = l.constOpt inputs; /* expose this flake's inputs to consumers */ };


  in
  {
    debug = true;
    systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
    imports = parts ++ [ extraFlakeModules.exposeInputs ];

    perSystem = { config, l, self', ... }: {
      packages = l.flatMapPkgs config.expose.packages;
      # This tells Nix: "To check this flake, try to build all my packages"
      checks = self'.packages;
    };

    flake.flakeModules = {
      utils = extraFlakeModules;
      essentials = extraFlakeModules;
    };
  });
}
