{
  perSystem = { pkgs, system, ... }: {
    # Nightly Cargo enables the unstable lock-aware global cache GC command.
    # Reuse the official Cargo component pinned by Blaze without its full toolchain.
    ownPkgs.cargo-nightly = { }:
      if system == "aarch64-darwin" then pkgs.callPackage ./cargo-nightly/package.nix { }
      else null;
    # The pinned nixpkgs Kache predates Blaze routing.
    ownPkgs.kache = { }: pkgs.callPackage ./kache/package.nix { };
    # nixpkgs' blaze is a C++ math library.
    ownPkgs.blaze = { }:
      if system == "aarch64-darwin" then pkgs.callPackage ./blaze/package.nix { }
      else null;
  };
}
