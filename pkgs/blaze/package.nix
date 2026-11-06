{ lib, stdenvNoCC, fetchurl }:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "blaze";
  version = "0.20261027.0";
  src = fetchurl {
    url = "https://github.com/indexable-inc/blaze/releases/download/v${finalAttrs.version}/blaze-v${finalAttrs.version}-aarch64-apple-darwin.tar.gz";
    hash = "sha256-R9ro6Dh2WTHtjiFqlOTXVFRGn6bDlQ0cAuuihBvI2tU=";
  };

  dontStrip = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin"
    install -m755 blaze blaze-proc-macro-srv cargo-blaze cargo-ra-jit \
      ra-jit ra-jit-rustc ra-jit-rustc-first "$out/bin/"
    runHook postInstall
  '';

  meta = {
    description = "Incremental Rust compiler and build tool";
    homepage = "https://github.com/indexable-inc/blaze";
    license = with lib.licenses; [ mit asl20 ];
    platforms = [ "aarch64-darwin" ];
    mainProgram = "blaze";
  };
})
