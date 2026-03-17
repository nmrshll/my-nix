{

  pkgDefs.handy = rec {
    versions = {
      aarch64-darwin."0.7.9".sha256 = "0hsrklmphdd14za0d7n1c96xbw9g3n6bfg1jn7jvjwysh17affbv";
      aarch64-darwin."0.6.5".sha256 = "1vmrbj35cjrxlqq8d2a12chhmg41z2fb3dvp51dm3hg795sr8rwb";
      x86_64-linux."0.6.4".sha256 = "tItYRJL0e5mQMRufWBh8zcqJPDkbLf98jW9yjB50Z4Q=";
      x86_64-darwin."0.6.4".sha256 = "yTRNaH/P5nMKT2oYk9b9oRH8s6PAi30Vtfw9TgE7WnE=";
      aarch64-darwin."0.6.4".sha256 = "9trjwzQIqM5Okvnj2GAlBxKajyBiM0HbNmw4JukUsF4=";
    };
    mkPkg = { pkgs, version ? "0.7.9", system ? pkgs.stdenv.hostPlatform.system, ... }:
      with builtins; let
        arch = elemAt (split "-" system) 0;
        url =
          if pkgs.stdenv.isDarwin then "https://github.com/cjpais/Handy/releases/download/v${version}/Handy_${arch}.app.tar.gz"
          else "https://github.com/cjpais/Handy/releases/download/v${version}/Handy_${version}_amd64.deb";
        src = fetchurl {
          inherit url; sha256 = versions.${system}.${version}.sha256;
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
  };

  pkgDefs.orbstack = rec {
    versions = {
      aarch64-darwin."1.11.3_19358".sha256 = "1p3qazha4q1ihqa4154jynp11kw9vqw4cyvpkdad4c9dcy9a6fzz";
      aarch64-darwin."2.0.3_19876".sha256 = "03pjk4zvvpnxgnk3bnbaxri211ji4khgdl9f9pkiz0c46p9mrynw";
    };
    mkPkg = { pkgs, version ? "2.0.3_19876", system ? pkgs.stdenv.hostPlatform.system, ... }:
      with builtins; let
        appname = "OrbStack";
        arch = { aarch64-darwin = "arm64"; x86_64-darwin = "amd64"; }.${system} or throwSystem;
      in
      pkgs.stdenv.mkDerivation {
        inherit version;
        src = fetchurl {
          url = "https://cdn-updates.orbstack.dev/${arch}/OrbStack_v${version}_${arch}.dmg";
          sha256 = versions.${pkgs.system}.${version}.sha256;
        };
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
        meta = {
          description = "Run Docker and Linux on your Mac seamlessly and efficiently.";
          homepage = "https://orbstack.dev/";
          platforms = [ "aarch64-darwin" ];
        };
      };
  };

}
