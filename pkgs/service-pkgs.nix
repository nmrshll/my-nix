with builtins; {
  config.perSystem = { pkgs, l, lib, config, system, ... }: {

    ownPkgs.handy =
      let
        versions."0.9.4".aarch64-darwin.sha256 = "sha256:0xi4wxszpb6scpcadns2fxhhxr405i9v2pi5nsnc6kg4zm6fry5v";
        versions."0.8.2".aarch64-darwin.sha256 = "1a2156h5sfnr5mydps7b6r701nqzkpmhb8m1wpizdppchy563vnp";
        versions."0.7.11".aarch64-darwin.sha256 = "0ill0rsmvxy81yhgdp4wk39nvb60r2qhcv12fywb1z5ppab4d1za";
        versions."0.7.9".aarch64-darwin.sha256 = "0hsrklmphdd14za0d7n1c96xbw9g3n6bfg1jn7jvjwysh17affbv";
        versions."0.6.5".aarch64-darwin.sha256 = "1vmrbj35cjrxlqq8d2a12chhmg41z2fb3dvp51dm3hg795sr8rwb";
        versions."0.6.4" = {
          x86_64-linux.sha256 = "tItYRJL0e5mQMRufWBh8zcqJPDkbLf98jW9yjB50Z4Q=";
          x86_64-darwin.sha256 = "yTRNaH/P5nMKT2oYk9b9oRH8s6PAi30Vtfw9TgE7WnE=";
          aarch64-darwin.sha256 = "9trjwzQIqM5Okvnj2GAlBxKajyBiM0HbNmw4JukUsF4=";
        };
        mkPkg = { version ? (l.latest (l.filterAttrs (name: v: v ? "${system}") versions)), ... }:
          let
            arch = elemAt (split "-" system) 0;
            url =
              if pkgs.stdenv.isDarwin then "https://github.com/cjpais/Handy/releases/download/v${version}/Handy_${arch}.app.tar.gz"
              else "https://github.com/cjpais/Handy/releases/download/v${version}/Handy_${version}_amd64.deb";
            src = fetchurl {
              inherit url; sha256 = versions.${version}.${system}.sha256;
            };
            pname = "handy";

          in
          pkgs.stdenv.mkDerivation {
            inherit pname version src;

            nativeBuildInputs =
              pkgs.lib.optionals pkgs.stdenv.isLinux [
                pkgs.autoPatchelfHook
                pkgs.dpkg
                pkgs.copyDesktopItems
              ]
              ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
                pkgs.makeWrapper
              ];

            buildInputs = pkgs.lib.optionals pkgs.stdenv.isLinux [
              pkgs.gcc-unwrapped.lib
              pkgs.alsa-lib
              pkgs.cairo
              pkgs.gdk-pixbuf
              pkgs.glib
              pkgs.gtk3
              pkgs.libsoup_3
              pkgs.openssl
              pkgs.vulkan-loader
              pkgs.webkitgtk_4_1
            ];

            runtimeDependencies = pkgs.lib.optionals pkgs.stdenv.isLinux [
              pkgs.stdenv.cc.cc.lib
              pkgs.libayatana-appindicator
            ];

            desktopItems = pkgs.lib.optionals pkgs.stdenv.isLinux [
              (pkgs.makeDesktopItem {
                name = "handy";
                desktopName = "Handy";
                comment = "Fast and accurate local transcription app";
                exec = "handy";
                icon = "handy";
                categories = [ "Audio" "AudioVideo" "Utility" ];
                startupNotify = true;
              })
            ];

            unpackPhase =
              if pkgs.stdenv.isLinux then ''
                runHook preUnpack
                dpkg -x $src .
                runHook postUnpack
              ''
              else ''
                runHook preUnpack
                mkdir -p ./unpacked
                tar -xzf $src -C ./unpacked
                runHook postUnpack
              '';
            installPhase =
              if pkgs.stdenv.isLinux then ''
                runHook preInstall
                # Install the binary
                install -Dm755 usr/bin/handy $out/bin/handy
                # Install resources
                mkdir -p $out/lib/Handy/resources
                cp -r usr/lib/Handy/resources/* $out/lib/Handy/resources/
                # Install icons
                mkdir -p $out/share/icons/hicolor
                if [ -d usr/share/icons/hicolor ]; then
                  cp -r usr/share/icons/hicolor/* $out/share/icons/hicolor/
                fi
                runHook postInstall
              ''
              else ''
                runHook preInstall
                mkdir -p $out/Applications
                cp -r ./unpacked/Handy.app $out/Applications/
                # Create a wrapper script in bin
                mkdir -p $out/bin
                makeWrapper $out/Applications/Handy.app/Contents/MacOS/Handy $out/bin/handy
                runHook postInstall
              '';

            passthru = { inherit versions mkPkg src; };

            meta = with pkgs.lib; {
              description = "Fast and accurate local transcription app using AI models";
              homepage = "https://handy.computer/";
              changelog = "https://github.com/cjpais/Handy/releases/tag/v${version}";
              sourceProvenance = with sourceTypes; [ binaryNativeCode ];
              maintainers = [ ];
              platforms = [ "x86_64-linux" "x86_64-darwin" "aarch64-darwin" ];
              mainProgram = "handy";
            };
          };
      in
      mkPkg { };

    ownPkgs.orbstack =
      let
        versions."1.11.3_19358".sha256 = "1p3qazha4q1ihqa4154jynp11kw9vqw4cyvpkdad4c9dcy9a6fzz";
        versions."2.0.3_19876".sha256 = "03pjk4zvvpnxgnk3bnbaxri211ji4khgdl9f9pkiz0c46p9mrynw";
        mkPkg = { version ? "2.0.3_19876", ... }:
          if pkgs.stdenv.hostPlatform.system != "aarch64-darwin" then null
          else
          with builtins; let
            appname = "OrbStack";
            arch = { aarch64-darwin = "arm64"; x86_64-darwin = "amd64"; }.${system} or throwSystem;
            src = fetchurl {
              url = "https://cdn-updates.orbstack.dev/${arch}/OrbStack_v${version}_${arch}.dmg";
              sha256 = versions.${version}.sha256;
            };
          in
          pkgs.stdenv.mkDerivation {
            inherit version src;
            pname = "orbstack";
            nativeBuildInputs = [ pkgs.undmg ];
            buildInputs = [ pkgs.unzip ];
            unpackCmd = ''
              echo "File to unpack: $curSrc"
              # if ! [[ "$curSrc" =~ \.dmg$ ]]; then return 1; fi
              mnt=$(mktemp -d -t ci-XXXXXXXXXX)

              function finish {
                echo "Detaching $mnt"
                /usr/bin/hdiutil detach $mnt -force
                rm -rf $mnt
              }
              trap finish EXIT

              echo "Attaching $mnt"
              /usr/bin/hdiutil attach -nobrowse -readonly $src -mountpoint $mnt

              echo "What's in the mount dir"?
              ls -la $mnt/

              echo "Copying contents"
              shopt -s extglob
              DEST="$PWD"
              (cd "$mnt"; cp -a !(Applications) "$DEST/")
            '';
            phases = [
              "unpackPhase"
              "installPhase"
            ];
            sourceRoot = "${appname}.app";
            installPhase = ''
              mkdir -p "$out/Applications/${appname}.app"
              cp -a ./. "$out/Applications/${appname}.app/"
            '';
            passthru = { inherit versions mkPkg src; };
            meta = {
              description = "Run Docker and Linux on your Mac seamlessly and efficiently.";
              homepage = "https://orbstack.dev/";
              platforms = [ "aarch64-darwin" ];
            };
          };
      in
      mkPkg { };

    # TODO use python314Packages.mlx-lm -> dep unzip is broken
    # TODO below beautifulsoup is also broken
    # ownPkgs.mlx-lm =
    #   let
    #     versions."0.31.1".sha256 = "5KGXLpzGEmyay6HvEM8qOe5zUmFRo1VbZKzOQvfr7Sk=";
    #     versions."0.31.0".sha256 = "1YZt2HtHyhP4h3WOcSytbN0sN2x58OYAmQtoxisNt1o=";
    #     mkPkg = { version ? (l.latest versions), ... }:
    #       let
    #         versionInfo = versions.${version};
    #         pyPkgs = pkgs.python314Packages;
    #       in
    #       pyPkgs.buildPythonApplication rec {
    #         pname = "mlx-lm";
    #         inherit version;
    #         pyproject = true;
    #
    #         src = pkgs.fetchFromGitHub {
    #           owner = "ml-explore";
    #           repo = "mlx-lm";
    #           tag = "v${version}";
    #           hash = "sha256-${versionInfo.sha256}";
    #         };
    #
    #         build-system = [ pyPkgs.setuptools ];
    #         dependencies = [
    #           pyPkgs.mlx
    #           pyPkgs.transformers
    #           pyPkgs.protobuf
    #           pyPkgs.jinja2
    #         ];
    #         pythonRelaxDeps = [ "transformers" ];
    #         doCheck = false; # Tests require additional dependencies
    #
    #         meta = {
    #           description = "LLM access to models using MLX";
    #           homepage = "https://github.com/ml-explore/mlx-lm";
    #           # license = lib.licenses.mit;
    #           # maintainers = with lib.maintainers; [ jwiegley ];
    #         };
    #       };
    #   in
    #   mkPkg { };

    ownPkgs.omlx =
      let
        versions."0.2.24-macos15-sequoia" = { sha256 = "07g4wqydlczcqhx7ahvdrsp1ygxnm8dqmqlifvq2xx071p3d11iz"; number = "0.2.24"; };
        # versions."0.3.0rc1-macos15-sequoia" = { sha256 = "1q1lndzayf7j7h658gigg3107hh8qbkvwwiibqazywgxjjggfrc6"; number = "0.3.0rc1"; };
        mkPkg = { version ? (l.latest versions), ... }:
          if pkgs.stdenv.hostPlatform.system != "aarch64-darwin" then null
          else
          let
            versionInfo = versions.${version};
            url = "https://github.com/jundot/omlx/releases/download/v${versionInfo.number}/oMLX-${version}.dmg";
            src = pkgs.fetchurl { inherit url; sha256 = versionInfo.sha256; };
            dotApp = pkgs.lib.darwin.installDmg {
              inherit url;
              inherit version;
              sha256 = versionInfo.sha256;
              appname = "oMLX";
              meta = { description = "Local AI inference for Apple MLX."; homepage = "https://github.com/jundot/omlx"; };
            };
          in
          (pkgs.symlinkJoin {
            name = "omlx-${version}";
            paths = [ dotApp ];
            nativeBuildInputs = [ pkgs.makeWrapper ];
            postBuild = ''
              mkdir -p $out/bin

              # Define the path to the actual binary inside the app bundle
              APP_BIN="$out/Applications/oMLX.app/Contents/MacOS/omlx-cli"

              # Create a wrapper instead of a symlink.
              # This prefixes the PATH with the location of python3 and the app's internal MacOS folder
              # so that the script can find 'python3' and its sibling files.
              makeWrapper "$APP_BIN" "$out/bin/omlx" \
                --prefix PATH : "${lib.makeBinPath [ pkgs.python3 ]}:$(dirname "$APP_BIN")"
            '';
          }) // { passthru = { inherit versions mkPkg src; }; };
      in
      mkPkg { };

    # TEMP BROKEN
    # ownPkgs.anemll =
    #   let
    #     versions."0.3.5".sha256 = "";
    #     mkPkg = { version ? (l.latest versions), ... }:
    #       pkgs.python3.pkgs.buildPythonApplication rec {
    #         pname = "anemll";
    #         version = "0.3.5";
    #         pyproject = true;
    #         nativeBuildInputs = with pkgs.python3.pkgs; [ setuptools ];
    #
    #         src = pkgs.fetchFromGitHub {
    #           owner = "Anemll";
    #           repo = "Anemll";
    #           rev = "refs/tags/v${version}";
    #           hash = "sha256-${versions.${version}.sha256}";
    #         };
    #
    #         propagatedBuildInputs = with pkgs.python3.pkgs; [ coremltools numpy tqdm transformers torch scikit-learn sentencepiece psutil ];
    #         nativeCheckInputs = with pkgs.python3.pkgs; [ pytest pytest-cov ];
    #         meta = {
    #           description = "Open-source pipeline for accelerating LLMs on Apple Neural Engine (ANE)";
    #           homepage = "https://anemll.com";
    #           documentation = "https://anemll.com/docs";
    #           license = lib.licenses.mit;
    #           maintainers = [ ];
    #           platforms = lib.platforms.darwin; # macOS only (requires Apple Neural Engine)
    #           broken = !pkgs.stdenv.isDarwin;
    #         };
    #       };
    #   in
    #   mkPkg { };

    # TODO try ? https://github.com/AtomicBot-ai/Atomic-Chat

    # TODO package bifrost: https://github.com/capsohq/bifrost/blob/4418dc8fa1ca6f606061edb356cf49efe99f4da5/nix/modules/bifrost.nix

  };
}
