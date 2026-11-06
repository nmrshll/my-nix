{
  perSystem = { pkgs, system, ... }: {
    # The pinned nixpkgs Kache predates Blaze routing.
    ownPkgs.kache = { }: pkgs.callPackage ./kache/package.nix { };
    # nixpkgs' blaze is a C++ math library.
    ownPkgs.blaze = { }:
      if system == "aarch64-darwin" then pkgs.callPackage ./blaze/package.nix { }
      else null;
  };
}
