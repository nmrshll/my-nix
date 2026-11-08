{ lib, stdenvNoCC, fetchurl, unzip }:
stdenvNoCC.mkDerivation rec {
  pname = "urbanterror";
  version = "4.3.4";
  src = fetchurl {
    url = "https://mirror2.urbanterror.info/UrbanTerror${lib.replaceStrings [ "." ] [ "" ] version}_full.zip";
    hash = "sha256-cWZpzGxSVmO3kYUuUf+clNlvOCvjknnatghN3ay1pOc=";
  };
  nativeBuildInputs = [ unzip ];
  sourceRoot = "UrbanTerror43";
  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/urbanterror" "$out/Applications" "$out/bin"
    cp -R Quake3-UrT.app q3ut4 "$out/share/urbanterror/"
    # The official layout keeps q3ut4 beside the app; retain that relationship.
    ln -s "$out/share/urbanterror/Quake3-UrT.app" "$out/Applications/Urban Terror.app"
    cat > "$out/bin/urbanterror" <<EOF
    #!${stdenvNoCC.shell}
    cd "$out/share/urbanterror"
    exec "$out/share/urbanterror/Quake3-UrT.app/Contents/MacOS/Quake3-UrT.x86_64" \
      +set fs_basepath "$out/share/urbanterror" "\$@"
    EOF
    chmod +x "$out/bin/urbanterror"
    runHook postInstall
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    app="$out/Applications/Urban Terror.app"
    test -x "$app/Contents/MacOS/Quake3-UrT.x86_64"
    test -f "$app/Contents/MacOS/libSDL-1.2.0.dylib"
    test -f "$out/share/urbanterror/q3ut4/zUrT43_021.pk3"
    test -f "$out/share/urbanterror/q3ut4/zUrT43_qvm.pk3"
    test "$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - \
      "$app/Contents/Info.plist")" = "com.frozensand.quake3-urt"
    "$SHELL" -n "$out/bin/urbanterror"
    runHook postInstallCheck
  '';
  meta = {
    description = "Multiplayer tactical FPS (complete official macOS release)";
    homepage = "https://www.urbanterror.info/";
    license = with lib.licenses; [ gpl2Plus unfreeRedistributable ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "urbanterror";
    platforms = lib.platforms.darwin;
  };
}
