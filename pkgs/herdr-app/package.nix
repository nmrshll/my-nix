{ lib, stdenvNoCC, fetchurl }:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "herdr-app";
  version = "0.1.12";

  src = fetchurl {
    url = "https://releases.herdr.dev/app/${finalAttrs.version}/herdr-app-macos-aarch64.tar.gz";
    hash = "sha256-AGpPaECaeVSNGqbF+Z2okRt9FJEO8qxr0aPc5jTKXQM=";
  };
  sourceRoot = ".";
  dontFixup = true; # Preserve the complete Developer ID signed app bundle.

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/Applications" "$out/bin"
    cp -a Herdr.app "$out/Applications/"
    ln -s "$out/Applications/Herdr.app/Contents/MacOS/Herdr" "$out/bin/herdr-app"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    app="$out/Applications/Herdr.app"
    test "$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$app/Contents/Info.plist")" = "dev.herdr.app"
    test "$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$app/Contents/Info.plist")" = "${finalAttrs.version}"
    /usr/bin/lipo "$app/Contents/MacOS/Herdr" -verify_arch arm64
    test -f "$app/Contents/Resources/Herdr.icns"
    test -f "$app/Contents/Resources/LICENSE"
    test -f "$app/Contents/Resources/THIRD-PARTY-NOTICES"
    test -x "$out/bin/herdr-app"
    runHook postInstallCheck
  '';

  meta = {
    description = "Desktop app for terminals and coding agents";
    homepage = "https://github.com/herdrdev/herdr-app";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "aarch64-darwin" ];
    mainProgram = "herdr-app";
  };
})
