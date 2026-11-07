{ lib, buildNpmPackage, nodejs, makeWrapper }:

buildNpmPackage {
  pname = "puppeteer-browsers";
  version = "3.2.6";
  src = ./.;
  npmDepsHash = "sha256-WjKa7OMsCEyqSeBJDmHCm0bbty23Hds/T/+X/flB0nY=";
  inherit nodejs;
  nativeBuildInputs = [ makeWrapper ];
  dontNpmBuild = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/puppeteer-browsers" "$out/bin"
    cp -R node_modules "$out/lib/puppeteer-browsers/"
    makeWrapper ${nodejs}/bin/node "$out/bin/puppeteer-browsers" \
      --add-flags "$out/lib/puppeteer-browsers/node_modules/@puppeteer/browsers/lib/main-cli.js"
    runHook postInstall
  '';
  meta = {
    description = "Puppeteer browser management CLI";
    homepage = "https://github.com/puppeteer/puppeteer/tree/main/packages/browsers";
    license = lib.licenses.asl20;
    mainProgram = "puppeteer-browsers";
  };
}
