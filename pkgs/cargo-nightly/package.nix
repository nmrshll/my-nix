{ lib, stdenvNoCC, fetchurl }:
stdenvNoCC.mkDerivation {
  pname = "cargo-nightly";
  version = "2026-10-27";
  src = fetchurl {
    url = "https://static.rust-lang.org/dist/2026-10-27/cargo-nightly-aarch64-apple-darwin.tar.xz";
    hash = "sha256-SbVVyaMxHjlm4CB6HSRy2mqp2qJ1WCDsflmAUar4gRI=";
  };
  dontFixup = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin"
    cp cargo/bin/cargo "$out/bin/cargo"
    runHook postInstall
  '';
  meta = {
    description = "Nightly Cargo for lock-aware global cache cleanup";
    homepage = "https://doc.rust-lang.org/cargo/";
    license = with lib.licenses; [ mit asl20 ];
    platforms = [ "aarch64-darwin" ];
    mainProgram = "cargo";
  };
}
