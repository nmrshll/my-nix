{ lib, stdenvNoCC, fetchurl, unzip, makeWrapper }:
let
  versions."0.22.0".hash = "sha256-HKytKO9C07THrCZS9UQLF8K8qnF0aYpLzkP/+7go0j0=";
  mkPkg = { version ? "0.22.0" }:
    stdenvNoCC.mkDerivation {
      pname = "zed-delta";
      inherit version;
      src = fetchurl {
        url = "https://releases.delta.dev/releases/stable/${version}/macos/aarch64/Delta.app.zip";
        inherit (versions.${version}) hash;
      };

      nativeBuildInputs = [ unzip makeWrapper ];
      sourceRoot = ".";
      dontConfigure = true;
      dontBuild = true;
      # Preserve the upstream signed app and its native executables.
      dontFixup = true;

      installPhase = ''
        runHook preInstall
        mkdir -p "$out/Applications" "$out/bin"
        cp -R Delta.app "$out/Applications/"
        # Keep nixpkgs' unrelated git-delta free to own the `delta` command.
        makeWrapper "$out/Applications/Delta.app/Contents/MacOS/delta" "$out/bin/zed-delta" \
          --set DELTA_UPDATE_EXPLANATION "Delta is managed by Nix; update the zed-delta package in my-nix."
        cat > "$out/bin/delta-app" <<EOF
        #!${stdenvNoCC.shell}
        exec "$out/bin/zed-delta" open "\$@"
        EOF
        chmod +x "$out/bin/delta-app"
        runHook postInstall
      '';

      doInstallCheck = true;
      installCheckPhase = ''
        runHook preInstallCheck
        app="$out/Applications/Delta.app"
        test -x "$app/Contents/MacOS/delta-app"
        test -f "$app/Contents/Resources/AppIcon.icns"
        test "$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - \
          "$app/Contents/Info.plist")" = "com.zed-industries.delta"
        # Upstream's Info.plist still says 0.1.0; the CLI has the release version.
        # Run a standalone copy until Nix finalizes the signed output bundle's
        # metadata; running it in-place can trigger macOS App Management.
        cp "$app/Contents/MacOS/delta" ./delta-cli-check
        test "$(./delta-cli-check --version)" = "delta ${version}"
        ./delta-cli-check open --help >/dev/null
        "$SHELL" -n "$out/bin/zed-delta"
        "$SHELL" -n "$out/bin/delta-app"
        runHook postInstallCheck
      '';

      passthru = { inherit versions mkPkg; };
      meta = {
        description = "Zed's multiplayer environment for coding with agents";
        homepage = "https://delta.dev";
        downloadPage = "https://delta.dev/download";
        license = lib.licenses.unfree;
        sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
        platforms = [ "aarch64-darwin" ];
        mainProgram = "delta-app";
      };
    };
in mkPkg { }
