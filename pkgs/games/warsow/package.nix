{ pkgs, lib }:
let
  version = "2.1.2";
in
(pkgs.lib.darwin.installDmg {
  inherit version;
  url = "https://warsow.net/warsow-${version}.dmg";
  sha256 = "sha256-F2sDcYbk2KHA/HQP6GYM2WAzn8Tuyl5equxAKLm9aro=";
  appname = "Warsow";
  meta = {
    description = "Fast-paced arena first-person shooter (official macOS app)";
    homepage = "https://warsow.net/";
    license = with lib.licenses; [ gpl2Plus cc-by-sa-40 cc-by-nd-40 ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "warsow";
  };
}).overrideAttrs (old: {
  # Preserve the bundled Intel frameworks and the complete Resources/basewsw.
  installPhase = old.installPhase + ''
    mkdir -p "$out/bin"
    cat > "$out/bin/warsow" <<EOF
    #!${pkgs.runtimeShell}
    exec "$out/Applications/Warsow.app/Contents/MacOS/Warsow" "\$@"
    EOF
    chmod +x "$out/bin/warsow"
  '';
  phases = old.phases ++ [ "installCheckPhase" ];
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    app="$out/Applications/Warsow.app"
    test -x "$app/Contents/MacOS/Warsow"
    test -f "$app/Contents/Resources/basewsw/data0_21.pk3"
    test -f "$app/Contents/Resources/basewsw/data2_21pure.pk3"
    test -f "$app/Contents/Resources/libs/libref_gl_mac.dylib"
    test -f "$app/Contents/Frameworks/SDL2.framework/SDL2"
    test "$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - \
      "$app/Contents/Info.plist")" = "org.picmip.Warsow"
    "$SHELL" -n "$out/bin/warsow"
    runHook postInstallCheck
  '';
  meta = old.meta // { platforms = lib.platforms.darwin; };
})
