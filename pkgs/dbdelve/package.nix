{ pkgs, lib }:
let
  version = "0.6.1";
in
(pkgs.lib.darwin.installDmg {
  inherit version;
  url = "https://github.com/ShayanAbbas1/dbdelve/releases/download/v${version}/DBDelve-${version}.dmg";
  sha256 = "sha256-Y8hRlfsr+Jk3PpbDsdEVHvSr/7Z6N8dlk6v8TPOCrmE=";
  appname = "DBDelve";
  meta = {
    description = "Native multi-engine database client built with Rust and GPUI";
    homepage = "https://github.com/ShayanAbbas1/dbdelve";
    license = lib.licenses.gpl3Only;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "dbdelve";
  };
}).overrideAttrs (old: {
  # Keep the complete upstream bundle, including its ad-hoc code signature.
  installPhase = old.installPhase + ''
    mkdir -p "$out/bin"
    cat > "$out/bin/dbdelve" <<EOF
    #!${pkgs.runtimeShell}
    exec "$out/Applications/DBDelve.app/Contents/MacOS/DBDelve" "\$@"
    EOF
    chmod +x "$out/bin/dbdelve"
  '';
  phases = old.phases ++ [ "installCheckPhase" ];
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    app="$out/Applications/DBDelve.app"
    test -x "$app/Contents/MacOS/DBDelve"
    test -f "$app/Contents/Resources/DBDelve.icns"
    test -f "$app/Contents/Resources/NOTICES.md"
    test -d "$app/Contents/Resources/licenses"
    test "$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - \
      "$app/Contents/Info.plist")" = "com.shayanabbas.dbdelve"
    test "$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - \
      "$app/Contents/Info.plist")" = "${version}"
    /usr/bin/lipo "$app/Contents/MacOS/DBDelve" -verify_arch arm64
    /usr/bin/codesign --verify --deep --strict "$app"
    "$SHELL" -n "$out/bin/dbdelve"
    runHook postInstallCheck
  '';
})
