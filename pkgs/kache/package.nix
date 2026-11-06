{ lib, stdenvNoCC, fetchurl }:
let
  release = {
    aarch64-darwin = {
      target = "aarch64-apple-darwin";
      hash = "sha256-tGE599QolcYpYkUIht019FVMF1MSCeppstsFPSoUK8s=";
    };
    x86_64-darwin = {
      target = "x86_64-apple-darwin";
      hash = "sha256-Criyn2WdFZ3nj3A3bG/6dzCHnxj83jl1Z7aDeW61/XM=";
    };
    aarch64-linux = {
      target = "aarch64-unknown-linux-musl";
      hash = "sha256-jFyk0dS2/GblF1yKEVDh2qhQmQgGRjIgWNkIPHKYa7o=";
    };
    x86_64-linux = {
      target = "x86_64-unknown-linux-musl";
      hash = "sha256-bFlmX68bFNCUQ5Hm8qG1EBlea+ksYwYKnRdw7QBnaCQ=";
    };
  };
  inherit (release.${stdenvNoCC.hostPlatform.system}) target hash;
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "kache";
  version = "2.0.0";
  src = fetchurl {
    url = "https://github.com/kunobi-ninja/kache/releases/download/v${finalAttrs.version}/kache-${target}.tar.gz";
    inherit hash;
  };

  sourceRoot = ".";
  dontStrip = true;
  installPhase = ''
    runHook preInstall
    install -Dm755 kache "$out/bin/kache"
    install -Dm755 kache-engine "$out/bin/kache-engine"
    mkdir -p "$out/shims"
    ln -s ../bin/kache "$out/shims/cargo"
    runHook postInstall
  '';

  meta = {
    description = "Content-addressed compiler cache";
    homepage = "https://github.com/kunobi-ninja/kache";
    license = lib.licenses.asl20;
    platforms = builtins.attrNames release;
    mainProgram = "kache";
  };
})
