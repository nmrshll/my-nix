{ lib, stdenvNoCC, fetchurl, unzip }:
stdenvNoCC.mkDerivation rec {
  pname = "openspades";
  version = "0.1.3";

  src = fetchurl {
    url = "https://github.com/yvt/openspades/releases/download/v${version}/OpenSpades-${version}-OSX.zip";
    hash = "sha256-+PAoy8NeFiQQfme6wGV7H01h68wYz+ubkTqiBSMKEWM=";
  };

  nativeBuildInputs = [ unzip ];
  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;
  # The app ships its own frameworks and resources; preserve their paths.
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/Applications" "$out/bin"
    cp -R OpenSpades.app "$out/Applications/"
    cat > "$out/bin/openspades" <<EOF
    #!${stdenvNoCC.shell}
    exec "$out/Applications/OpenSpades.app/Contents/MacOS/OpenSpades" "\$@"
    EOF
    chmod +x "$out/bin/openspades"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    app="$out/Applications/OpenSpades.app"
    test -x "$app/Contents/MacOS/OpenSpades"
    test -f "$app/Contents/Resources/pak000-Nonfree.pak"
    test -f "$app/Contents/Frameworks/SDL2.framework/SDL2"
    test -f "$app/Contents/Frameworks/SDL2_image.framework/SDL2_image"
    test "$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - \
      "$app/Contents/Info.plist")" = "${version}"
    "$SHELL" -n "$out/bin/openspades"
    runHook postInstallCheck
  '';

  meta = {
    description = "Compatible client of Ace of Spades 0.75 (official macOS app)";
    homepage = "https://openspades.yvt.jp/";
    license = with lib.licenses; [ gpl3 unfreeRedistributable ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "openspades";
    # Upstream's Intel app also runs on Apple Silicon through Rosetta 2.
    platforms = lib.platforms.darwin;
  };
}
