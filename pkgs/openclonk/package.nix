{ lib, stdenvNoCC, fetchurl, unzip }:
stdenvNoCC.mkDerivation rec {
  pname = "openclonk";
  version = "8.0";
  src = fetchurl {
    url = "https://www.openclonk.org/builds/release/${version}/openclonk-${version}-x64.app.zip";
    hash = "sha256-y6UN65NqcPC6ADMTZZuRw2XyMaP52G0Q5pGMPzLHvO0=";
  };
  nativeBuildInputs = [ unzip ];
  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/Applications" "$out/bin"
    cp -R openclonk-85d9c2c-darwin-amd64-clang.app "$out/Applications/OpenClonk.app"
    cat > "$out/bin/openclonk" <<EOF
    #!${stdenvNoCC.shell}
    exec "$out/Applications/OpenClonk.app/Contents/MacOS/openclonk" "\$@"
    EOF
    chmod +x "$out/bin/openclonk"
    runHook postInstall
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    app="$out/Applications/OpenClonk.app"
    test -x "$app/Contents/MacOS/openclonk"
    test -f "$app/Contents/Frameworks/QtCore"
    test -f "$app/Contents/Resources/System.ocg"
    test -f "$app/Contents/Resources/Objects.ocd"
    test -f "$app/Contents/Resources/Tutorials.ocf"
    test "$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - \
      "$app/Contents/Info.plist")" = "org.openclonk.openclonk"
    test "$(/usr/bin/plutil -extract CFBundleVersion raw -o - \
      "$app/Contents/Info.plist")" = "8.0"
    "$SHELL" -n "$out/bin/openclonk"
    runHook postInstallCheck
  '';
  meta = {
    description = "Multiplayer action and construction game (official macOS app)";
    homepage = "https://www.openclonk.org/";
    license = lib.licenses.isc;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "openclonk";
    platforms = lib.platforms.darwin;
  };
}
