{ pkgs, lib }:
let
  version = "0.0.192";
in
(pkgs.lib.darwin.installDmg {
  inherit version;
  url = "https://github.com/CodebuffAI/codebuff-community/releases/download/freebuff-desktop-v${version}/Freebuff-${version}-mac-arm64.dmg";
  sha256 = "sha256-dRr3Tpc13PPTxAkcx+dUTodMV0wAfBgdXkDSGsmH8ZM=";
  appname = "Freebuff";
  meta = {
    description = "Desktop app for the Freebuff coding agent";
    homepage = "https://freebuff.com";
    downloadPage = "https://freebuff.com/api/desktop/download/mac-arm64";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "freebuff-desktop";
  };
}).overrideAttrs (old: {
  pname = "freebuff-desktop";
  # Keep the upstream signed Electron bundle intact; installDmg skips fixup.
  installPhase = old.installPhase + ''
    mkdir -p "$out/bin"
    cat > "$out/bin/freebuff-desktop" <<EOF
    #!${pkgs.runtimeShell}
    exec /usr/bin/open -a "$out/Applications/Freebuff.app" --args "\$@"
    EOF
    chmod +x "$out/bin/freebuff-desktop"
  '';
  phases = old.phases ++ [ "installCheckPhase" ];
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -x "$out/Applications/Freebuff.app/Contents/MacOS/Freebuff"
    test -f "$out/Applications/Freebuff.app/Contents/Resources/app.asar"
    test "$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - \
      "$out/Applications/Freebuff.app/Contents/Info.plist")" = "${version}"
    test -x "$out/bin/freebuff-desktop"
    runHook postInstallCheck
  '';
})
