{ lib, stdenvNoCC, fetchFromGitHub, nodejs }:

stdenvNoCC.mkDerivation {
  pname = "herdr-paddock";
  version = "0-unstable-2026-11-02";

  src = fetchFromGitHub {
    owner = "choam2426";
    repo = "herdr-paddock";
    rev = "540e3d20d7b960ac325fd5a5401f905b40e93953";
    hash = "sha256-KHDv8e89YcOTm0Uny1tvxnsYjokZdZTZwYBBTRapl4w=";
  };

  nativeCheckInputs = [ nodejs ];
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    node tests/projects.test.mjs
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/herdr-app/mods" "$out/share/licenses/herdr-paddock"
    cp -R mods/paddock "$out/share/herdr-app/mods/"
    cp LICENSE NOTICE "$out/share/licenses/herdr-paddock/"
    runHook postInstall
  '';

  meta = {
    description = "Persistent directory projects sidebar for Herdr desktop";
    homepage = "https://github.com/choam2426/herdr-paddock";
    license = [ lib.licenses.asl20 lib.licenses.isc ];
    platforms = lib.platforms.unix;
  };
}
