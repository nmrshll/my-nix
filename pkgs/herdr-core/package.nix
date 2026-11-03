{ lib, stdenvNoCC, fetchurl }:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "herdr-core";
  version = "0.1.17";

  src = fetchurl {
    url = "https://releases.herdr.dev/core/${finalAttrs.version}/herdr-core-macos-aarch64.tar.gz";
    hash = "sha256-ztvU1Nm6E4VYgZjdTTxn0mVEePM63VtkRdTQ652l/PM=";
  };
  sourceRoot = ".";
  dontFixup = true; # Keep the upstream binary and its signature intact.

  installPhase = ''
    runHook preInstall
    install -Dm755 herdr-core "$out/bin/herdr-core"
    ln -s herdr-core "$out/bin/hc"
    install -Dm644 LICENSE "$out/share/licenses/herdr-core/LICENSE"
    install -Dm644 THIRD-PARTY-NOTICES "$out/share/licenses/herdr-core/THIRD-PARTY-NOTICES"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -x "$out/bin/herdr-core"
    test "$(readlink "$out/bin/hc")" = herdr-core
    /usr/bin/lipo "$out/bin/herdr-core" -verify_arch arm64
    runHook postInstallCheck
  '';

  meta = {
    description = "Persistent terminal and coding agent runtime for Herdr";
    homepage = "https://github.com/herdrdev/herdr-core";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "aarch64-darwin" ];
    mainProgram = "herdr-core";
  };
})
