{ lib, stdenvNoCC, fetchurl, makeWrapper, callPackage }:
let
  # Update this toolchain with the release below (upstream harness/toolchain).
  rust = callPackage ./toolchain.nix { };
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "blaze";
  version = "0.20261027.0";
  src = fetchurl {
    url = "https://github.com/indexable-inc/blaze/releases/download/v${finalAttrs.version}/blaze-v${finalAttrs.version}-aarch64-apple-darwin.tar.gz";
    hash = "sha256-R9ro6Dh2WTHtjiFqlOTXVFRGn6bDlQ0cAuuihBvI2tU=";
  };

  nativeBuildInputs = [ makeWrapper ];
  dontStrip = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin" "$out/libexec/blaze"
    install -m755 blaze blaze-proc-macro-srv cargo-blaze cargo-ra-jit \
      ra-jit ra-jit-rustc ra-jit-rustc-first "$out/libexec/blaze/"
    for launcher in "$out/libexec/blaze/"*; do
      makeWrapper "$launcher" "$out/bin/''${launcher##*/}" \
        --prefix PATH : "${rust}/bin" \
        --set RUSTC "${rust}/bin/rustc" \
        --set RUSTDOC "${rust}/bin/rustdoc"
    done
    runHook postInstall
  '';

  passthru.toolchain = rust;

  meta = {
    description = "Incremental Rust compiler and build tool";
    homepage = "https://github.com/indexable-inc/blaze";
    license = with lib.licenses; [ mit asl20 ];
    platforms = [ "aarch64-darwin" ];
    mainProgram = "blaze";
  };
})
