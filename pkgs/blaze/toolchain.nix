{ lib, stdenvNoCC, fetchurl }:
let
  date = "2026-10-27";
  dist = "https://static.rust-lang.org/dist/${date}";
  fetch = name: hash: fetchurl {
    url = "${dist}/${name}";
    inherit hash;
  };

  # Blaze v0.20261027.0 crates/ra-jit/src/cargo/toolchain/pins.txt.
  components = {
    "rustc-nightly-aarch64-apple-darwin" = "sha256-r4WkAnb31gOpLVO+zLkbp7wwAqHRw1nSInFndgbPOtA=";
    "cargo-nightly-aarch64-apple-darwin" = "sha256-SbVVyaMxHjlm4CB6HSRy2mqp2qJ1WCDsflmAUar4gRI=";
    "rust-std-nightly-aarch64-apple-darwin" = "sha256-IWb8YT2mFf26q9oWzXH2cPcNcKQe1jAU3jrDaqHHQac=";
    "rust-std-nightly-wasm32-wasip1" = "sha256-9DKDl3fz1ptoEW07F1CXhWvZCF8m9401+ZDx3jhHvq0=";
    "rust-src-nightly" = "sha256-qTcC31WT9F/lSbOOxYnTP1A/qZZsG7/ZM/+Ni0mXcmw=";
  };
  manifest = fetch "channel-rust-nightly.toml" "sha256-NPPZvwRkCgguVhMQ8/JYhGOX9M9korz+vOqW6/GOJXI=";
in
stdenvNoCC.mkDerivation {
  pname = "blaze-rust-nightly";
  version = date;
  srcs = lib.mapAttrsToList (name: hash: fetch "${name}.tar.xz" hash) components;
  sourceRoot = ".";

  # Preserve the upstream binaries and the rustup records Blaze reads.
  dontFixup = true;
  installPhase = ''
    runHook preInstall
    records="$out/lib/rustlib"
    mkdir -p "$records"
    for archive in ${lib.escapeShellArgs (builtins.attrNames components)}; do
      name="''${archive/-nightly/}"
      while IFS= read -r component; do
        payload="$archive/$component"
        mv "$payload/manifest.in" "$records/manifest-$name"
        cp -R "$payload/." "$out/"
      done < "$archive/components"
      printf '%s\n' "$name" >> "$records/components"
    done
    cp ${manifest} "$records/multirust-channel-manifest.toml"
    runHook postInstall
  '';
}
