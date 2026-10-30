{ pkgs, lib }:
let
  version = "0.0.192";
  python = pkgs.python3;
  pythonClosure = pkgs.closureInfo { rootPaths = [ python ]; };
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
  # Keep the upstream signed Electron bundle intact; only the external backend
  # copy is patched. The outer app makes Finder launches use the same override.
  installPhase = old.installPhase + ''
    mkdir -p "$out/bin" "$out/libexec"
    mv "$out/Applications/Freebuff.app" "$out/libexec/Freebuff.app"
    app="$out/libexec/Freebuff.app"
    resources="$app/Contents/Resources"
    cp -a "$resources/orchestrator" "$out/libexec/orchestrator"
    chmod u+w "$out/libexec/orchestrator/orchestrator.js"
    ${python}/bin/python3 ${./patch-orchestrator.py} \
      "$out/libexec/orchestrator/orchestrator.js" \
      ${python}/bin/python3 ${pythonClosure}/store-paths
    cp ${pythonClosure}/store-paths "$out/libexec/python-store-paths"
    cp ${./patch-orchestrator.py} "$out/libexec/patch-orchestrator.py"
    cp ${./launcher.py} "$out/libexec/launcher.py"

    cat > "$out/libexec/freebuff-bun" <<EOF
    #!${pkgs.runtimeShell}
    exec ${python}/bin/python3 "$out/libexec/launcher.py" "$out" --bun "\$@"
    EOF
    chmod +x "$out/libexec/freebuff-bun"

    cat > "$out/bin/freebuff-desktop" <<EOF
    #!${pkgs.runtimeShell}
    exec ${python}/bin/python3 "$out/libexec/launcher.py" "$out" "\$@"
    EOF
    chmod +x "$out/bin/freebuff-desktop"

    launcher="$out/Applications/Freebuff.app/Contents"
    mkdir -p "$launcher/MacOS" "$launcher/Resources"
    ln -s "$out/bin/freebuff-desktop" "$launcher/MacOS/freebuff-desktop"
    cp "$resources/icon.icns" "$launcher/Resources/icon.icns"
    cat > "$launcher/Info.plist" <<EOF
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
      <key>CFBundleName</key><string>Freebuff</string>
      <key>CFBundleIdentifier</key><string>com.my-nix.freebuff-launcher</string>
      <key>CFBundleExecutable</key><string>freebuff-desktop</string>
      <key>CFBundlePackageType</key><string>APPL</string>
      <key>CFBundleShortVersionString</key><string>${version}</string>
      <key>CFBundleIconFile</key><string>icon.icns</string>
      <key>LSUIElement</key><true/>
    </dict></plist>
    EOF
  '';
  phases = old.phases ++ [ "installCheckPhase" ];
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -x "$out/Applications/Freebuff.app/Contents/MacOS/freebuff-desktop"
    test -x "$out/libexec/Freebuff.app/Contents/MacOS/Freebuff"
    test -f "$out/libexec/Freebuff.app/Contents/Resources/app.asar"
    test "$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - \
      "$out/libexec/Freebuff.app/Contents/Info.plist")" = "${version}"
    test -x "$out/bin/freebuff-desktop"
    ${pkgs.runtimeShell} -n "$out/bin/freebuff-desktop"
    ${pkgs.runtimeShell} -n "$out/libexec/freebuff-bun"
    ${python}/bin/python3 -c 'import ssl, sqlite3, ctypes; print(ssl.OPENSSL_VERSION)'
    runHook postInstallCheck
  '';
})
