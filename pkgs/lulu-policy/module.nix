{ ... }: {
  perSystem = { pkgs, ... }: {
    ownPkgs.lulu-policy = { }: pkgs.callPackage ./package.nix { };
  };
}
