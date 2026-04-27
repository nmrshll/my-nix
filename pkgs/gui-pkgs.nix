{ l, ... }: {

  pkgDefs.antigravity = rec {
    versions = {
      aarch64-darwin."1.16.5-6703236727046144".sha256 = "sha256:1nc2fsd4hmlvh1b5vh0ndffy6q7xng9xdb931c0dzkpz190alr0z";
    };
    mkPkg = { pkgs, version ? "1.16.5-6703236727046144", system ? pkgs.stdenv.hostPlatform.system, ... }:
      let
        url = pkgs.lib.forSystem {
          aarch64-darwin = "https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/${version}/darwin-arm/Antigravity.dmg";
        };
      in
      pkgs.lib.darwin.installDmg {
        inherit version url;
        sha256 = versions.${system}.${version}.sha256;
        appname = "Antigravity";
        meta = { description = "AI-powered IDE"; homepage = "https://antigravity.google/"; };
      };
  };

  pkgDefs.anytype = rec {
    versions = {
      aarch64-darwin."0.54.37-alpha".sha256 = "1ggjj7fc2qivlx0ywsxasnp8qf3ciqfk6bp3iicirl2ski3jqp95";
      aarch64-darwin."0.53.1".sha256 = "0v49qj232mkpx54z99nbmiafkvagkhk2xy8h8yyz95jizklhbh6g";
      aarch64-darwin."0.52.4".sha256 = "05syxapx4i5qrr2l5f12vs6wn74zixqn2d83mz0lxlhyi7x635kp";
      aarch64-darwin."0.47.3".sha256 = "1xs52cnr81fzqg4cp7cbvmlnjgi548nv8sxbvdsd4gvl3v09c3qj";
    };
    mkPkg = { pkgs, version ? l.latest versions.${system}, system ? pkgs.stdenv.hostPlatform.system, ... }:
      let
        url = pkgs.lib.forSystem {
          aarch64-darwin = "https://anytype-release.fra1.cdn.digitaloceanspaces.com/Anytype-${version}-mac-arm64.dmg";
        };
      in
      pkgs.lib.darwin.installDmg {
        inherit version url;
        sha256 = versions.${system}.${version}.sha256;
        appname = "AnyType";
        meta = { description = "A space for your thoughts, private, local, p2p & open"; homepage = "https://anytype.io/"; };
      };
  };

  pkgDefs.beeper = rec {
    versions = {
      aarch64-darwin."4.2.532".sha256 = "05indiqrfwsj6fx85l02ky57hf7kjkkkaic67i8wv4l9n3j4cvnj";
      aarch64-darwin."4.0.779".sha256 = "1z9z5aswx1fh2z8pd5761z4db6q8z4mbl4vshfh5wy055l0gvvp4";
    };
    mkPkg = { pkgs, l, version ? "4.2.532", system ? pkgs.stdenv.hostPlatform.system, ... }:
      let
        appname = "Beeper";
        url = pkgs.lib.forSystem {
          aarch64-darwin = "https://beeper-desktop.download.beeper.com/builds/Beeper-${version}-arm64-mac.zip";
          x86_64-linux = "https://download.beeper.com/versions/${version}/linux/appImage/x64";
        };
      in
      pkgs.stdenvNoCC.mkDerivation {
        inherit version;
        src = builtins.fetchurl { inherit url; sha256 = versions.${system}.${version}.sha256; };
        pname = l.slugify appname;
        nativeBuildInputs = [ pkgs.undmg ];
        buildInputs = [ pkgs.unzip ];
        unpackCmd = ''set -x
            echo "File to unpack: $curSrc"
            if ! [[ "$curSrc" =~ \.zip$ ]]; then echo "[ERROR] Expected a zip file"; return 1; fi
            runHook preUnpack
            echo "Unzipping $src to $PWD"
            unzip $src
            runHook postUnpack
          '';
        phases = [
          "unpackPhase"
          "installPhase"
        ];
        installPhase = ''
          mkdir -p "$out/Applications/${appname}.app"
          cp -a ./. "$out/Applications/${appname}.app/"
        '';
        meta = { description = "All your chats in one app"; homepage = "https://beeper.com"; };
      };
  };

  pkgDefs.opencode-desktop = rec {
    versions = {
      aarch64-darwin."1.2.27".sha256 = "1j6hp4pqm2rdz3s8j08ihylkhdgnb5kanxlkyqpshkf1d6dr0bha";
    };
    mkPkg = { pkgs, version ? "1.2.27", system ? pkgs.stdenv.hostPlatform.system, ... }:
      let
        appname = "opencode";
        url = "https://github.com/anomalyco/opencode/releases/download/v${version}/opencode-desktop-darwin-aarch64.app.tar.gz";
        sharedDrvAttrs = {
          inherit version;
          pname = appname;
          src = builtins.fetchurl {
            inherit url;
            sha256 = versions.${system}.${version}.sha256;
          };
          meta = {
            description = "AI-powered code editor and terminal";
            homepage = "https://opencode.ai";
            platforms = [ "aarch64-darwin" ];
          };
        };
      in
      if pkgs.stdenv.isDarwin then
        pkgs.stdenvNoCC.mkDerivation
          (sharedDrvAttrs // {
            # inherit version;
            # pname = appname;
            # src = builtins.fetchurl {
            #   inherit url;
            #   sha256 = versions.${system}.${version}.sha256;
            # };
            buildInputs = [ pkgs.bzip2 ];
            unpackCmd = ''
              echo "File to unpack: $curSrc"
              tar -xf "$curSrc"
            '';
            installPhase = ''
              mkdir -p "$out/Applications/${appname}.app"
              cp -a ./. "$out/Applications/${appname}.app/"
            '';
            # meta = {
            #   description = "AI-powered code editor and terminal";
            #   homepage = "https://opencode.ai";
            #   platforms = [ "aarch64-darwin" ];
            # };
          })
      else throw "Unsupported system: ${pkgs.stdenv.hostPlatform.system}";
  };


  pkgDefs.augment-intent = rec {
    versions = {
      aarch64-darwin."latest".sha256 = "03wkfzgf2k3nfikjrjsax8zf4j546w45cbnig66jhwsjaxiijlbj";
    };
    mkPkg = { pkgs, version ? "latest", system ? pkgs.stdenv.hostPlatform.system, ... }:
      let
        arch = if pkgs.stdenv.hostPlatform.isAarch64 then "arm64" else "x86_64";
        url = "https://cdn.augmentcode.com/stable/Intent-latest-${arch}.dmg";
      in
      pkgs.lib.darwin.installDmg {
        inherit version url;
        sha256 = versions.${system}.${version}.sha256;
        appname = "Intent by Augment";
        meta = {
          description = "AI-powered code completion and refactoring";
          homepage = "https://intent.ai";
          platforms = [ "aarch64-darwin" ];
        };
      };
  };

  # pkgDefs.ferdium =
  #   let
  #     version = "7.0.0";
  #     url = localLib.forSystem {
  #       aarch64-darwin = "https://github.com/ferdium/ferdium-app/releases/download/v${version}/Ferdium-mac-${version}-arm64.dmg";
  #     };
  #     src = localLib.forSystem {
  #       aarch64-darwin = { inherit url; sha = "sha256:1l89vpyx3pas1gij3a0cblbsda0m1vjv289wf8g6x9dq9kkrgxcj"; };
  #     };
  #   in
  #   localLib.installDmg {
  #     inherit url version; sha256 = src.sha;
  #     appname = "Ferdium";
  #     meta = { description = "All your services in one place built by the community"; homepage = "https://ferdium.org"; };
  #   };

  pkgDefs.transmission = rec {
    versions = {
      aarch64-darwin."4.0.6".sha256 = "sha256:06kw4zkn6a3hd8s66hk77v4k0b7z7mn5h0y69hwgbhp0abqmg676";
    };
    mkPkg = { pkgs, l, version ? "4.0.6", system ? pkgs.stdenv.hostPlatform.system, ... }:
      let
        url = "https://github.com/transmission/transmission/releases/download/${version}/Transmission-${version}.dmg";
      in
      pkgs.lib.darwin.installDmg {
        inherit version url;
        sha256 = versions.${system}.${version}.sha256;
        appname = "Transmission";
        meta = { description = "Cross-platform BitTorrent client"; homepage = "https://transmissionbt.com"; };
      };
  };

  pkgDefs.finicky = rec {
    versions = {
      aarch64-darwin."4.1.4".sha256 = "sha256:13ayk8jslvxdqaba1ay2kr3hw0g2hr4lpadll9cv4zglz94xj81b";
    };
    mkPkg = { pkgs, l, version ? "4.1.4", system ? pkgs.stdenv.hostPlatform.system, ... }:
      let
        # versionHashes = { aarch64-darwin."4.1.4" = "sha256:13ayk8jslvxdqaba1ay2kr3hw0g2hr4lpadll9cv4zglz94xj81b"; }.${pkgs.stdenv.hostPlatform.system};
        url = {
          aarch64-darwin = "https://github.com/johnste/finicky/releases/download/v${version}/Finicky.dmg";
        }.${pkgs.stdenv.hostPlatform.system};
      in
      pkgs.lib.darwin.installDmg {
        inherit url version;
        sha256 = versions.${system}.${version}.sha256;
        appname = "Finicky";
        meta = { description = "A macOS app for customizing which browser to start"; homepage = "https://github.com/johnste/finicky"; };
      };
  };

  pkgDefs.comfy-ui = rec {
    versions = {
      aarch64-darwin."241012ess7yxs0e".sha256 = "0fbiwl0kir80gyiqqm5xrvsdwqj4fjws0k2slcrq2g4xkn7cwv7g";
    };
    mkPkg = { pkgs, l, version ? "241012ess7yxs0e", system ? pkgs.stdenv.hostPlatform.system, ... }:
      let
        # versions = {
        #   aarch64-darwin."241012ess7yxs0e" = "0fbiwl0kir80gyiqqm5xrvsdwqj4fjws0k2slcrq2g4xkn7cwv7g";
        # }.${pkgs.stdenv.hostPlatform.system}.${version};
      in
      pkgs.lib.darwin.installDmg {
        inherit version;
        sha256 = versions.${system}.${version}.sha256;
        url = "https://dl.todesktop.com/${version}/mac/dmg/arm64";
        appname = "ComfyUI";
        meta = { description = "ComfyUI is a powerful, flexible, and user-friendly interface for Stable Diffusion."; homepage = "https://www.comfy.org/"; };
      };
  };

  # ABANDONED
  # pkgDefs.ito = { pkgs, version ? "0.9.0" }:
  #   let
  #     versionHashes = {
  #       aarch64-darwin."0.9.0" = "sha256:0ii3mgknaxyrk7xamzn6sqp2828v2rsq8w38s4yqrkfhs53aclq6";
  #     }.${pkgs.stdenv.hostPlatform.system};
  #     url = {
  #       aarch64-darwin = "https://github.com/heyito/ito/releases/download/v${version}/Ito-Installer.dmg";
  #     }.${pkgs.stdenv.hostPlatform.system};
  #   in
  #   localLib.installDmg {
  #     inherit url version;
  #     sha256 = versionHashes.${version};
  #     appname = "Ito";
  #     meta = { source = "https://github.com/heyito/ito"; description = "Type with your Voice"; homepage = "https://www.ito.ai/"; };
  #   };

  # ABANDONED
  # pkgDefs.tome = { pkgs, version ? "0.2.0" }:
  #   let
  #     versionHashes = {
  #       aarch64-darwin."0.2.0" = "sha256:1z1rxb0xavi9idf100i7mimsrgkivyh860818yy9zbryy2af2dv8";
  #     }.${pkgs.stdenv.hostPlatform.system};
  #     url = {
  #       aarch64-darwin = "https://github.com/joshkotrous/tome/releases/download/v${version}/tome-mac-arm64.dmg";
  #     }.${pkgs.stdenv.hostPlatform.system};
  #   in
  #   localLib.installDmg {
  #     inherit url version;
  #     sha256 = versionHashes.${version};
  #     appname = "Tome";
  #     meta = { source = "https://github.com/joshkotrous/tome"; description = "AI-native database client that translates natural language into perfect queries"; homepage = "https://tome.lang/"; };
  #   };

  # pkgDefs.kdeConnect = rec {
  #   versions = {
  #     aarch64-darwin."5415".sha256 = "1q3dsgnr6v1dwvffllfin19h7qq516da7iiqyxc0fkf71f1jvy70";
  #   };
  #   mkPkg = { pkgs, version ? "5415", system ? pkgs.stdenv.hostPlatform.system, ... }:
  #     let
  #       l = builtins // (pkgs.callPackage ../utils/utils.darwin.nix { });
  #       # sha256 = {
  #       #   aarch64-darwin."5415" = "1q3dsgnr6v1dwvffllfin19h7qq516da7iiqyxc0fkf71f1jvy70";
  #       # }.${pkgs.stdenv.hostPlatform.system}.${version};
  #     in
  #     pkgs.lib.darwin.installDmg {
  #       inherit version;
  #       sha256 = versions.${system}.${version}.sha256;
  #       url = pkgs.lib.forSystem {
  #         aarch64-darwin = "https://origin.cdn.kde.org/ci-builds/network/kdeconnect-kde/master/macos-arm64/kdeconnect-kde-master-${version}-macos-clang-arm64.dmg";
  #       };
  #       appname = "KDEConnect";
  #       meta = { source = "https://invent.kde.org/explore/groups"; description = "Enabling communication between all your devices"; homepage = "https://kdeconnect.kde.org/"; };
  #     };
  # };

  # pkgDefs.lulu = rec {
  #   versions = {
  #     aarch64-darwin."4.2.0".sha256 = "1yl75hw5psblcb6biwxdp2mjp3n4dclyaj961mh3f6v8bya6ylcj";
  #     aarch64-darwin."3.1.5".sha256 = "eFrOZv6KSZlmLtyPORrD2Low/e7m7HU1WeuT/w8Us7I=";
  #   };
  #   mkPkg = { pkgs, lib, version ? "4.2.0", system ? pkgs.stdenv.hostPlatform.system, ... }:
  #     let
  #       appName = "LuLu";
  #       pname = lib.toLower appName;
  #     in
  #     pkgs.stdenv.mkDerivation {
  #       inherit pname version;
  #       src = fetchurl {
  #         url = "https://github.com/objective-see/LuLu/releases/download/v${version}/LuLu_${version}.dmg";
  #         sha256 = versions.${system}.${version}.sha256;
  #       };
  #       sourceRoot = ".";
  #       nativeBuildInputs = [ pkgs.makeWrapper pkgs.undmg ];

  #       installPhase = ''
  #         mkdir -p $out/Applications
  #         cp -r *.app $out/Applications
  #         # makeWrapper $out/Applications/${appName}.app/Contents/MacOS/${appName} $out/bin/${pname}
  #       '';

  #       meta = with lib; {
  #         description = "LuLu is the free open-source macOS firewall";
  #         homepage = "https://github.com/objective-see/LuLu";
  #         license = licenses.gpl3Only;
  #         maintainers = [ ];
  #         platforms = platforms.darwin;
  #         sourceProvenance = [ sourceTypes.binaryNativeCode ];
  #         mainProgram = pname;
  #       };
  #     };
  # };

  pkgDefs.lulu-installer = rec {
    versions = {
      aarch64-darwin."4.2.0".sha256 = "1yl75hw5psblcb6biwxdp2mjp3n4dclyaj961mh3f6v8bya6ylcj";
    };
    mkPkg = { pkgs, lib, version ? "4.2.0", system ? pkgs.stdenv.hostPlatform.system, ... }:
      let
        src = builtins.fetchurl {
          url = "https://github.com/objective-see/LuLu/releases/download/v${version}/LuLu_${version}.dmg";
          sha256 = versions.${system}.${version}.sha256;
        };
        install-script = pkgs.writeText "install-lulu" ''
          set -euo pipefail # cleanup called on fail

          if [ -d "/Applications/LuLu.app" ]; then
            installed_version=$(defaults read /Applications/LuLu.app/Contents/Info.plist CFBundleShortVersionString)
            if [ "${version}" = "$installed_version" ]; then exit 0; fi
          fi

          MOUNT_POINT="/tmp/LuLu_Mount_$$"
          cleanup() {
            if [ -d "$MOUNT_POINT" ]; then
              hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
              rm -rf "$MOUNT_POINT"
            fi
          }
          trap cleanup EXIT

          mkdir -p "$MOUNT_POINT"
          hdiutil attach "${src}" -mountpoint "$MOUNT_POINT" -nobrowse -quiet
          sudo cp -R "$MOUNT_POINT/LuLu.app" /Applications/
        '';
      in
      # writeShellScriptBin doesn't expose version to caller -> mkDerivation
      pkgs.stdenvNoCC.mkDerivation {
        pname = "install-lulu";
        inherit version src;
        dontUnpack = true; # default is undmg
        sourceRoot = "."; # Prevent unpack errors
        installPhase = ''
          runHook preInstall
          mkdir -p $out/bin
          cat ${install-script} > $out/bin/install-lulu
          chmod +x $out/bin/install-lulu
          runHook postInstall
        '';
      };
  };

  pkgDefs.launchd-ui = rec {
    versions = {
      aarch64-darwin."1.0.9".sha256 = "11a03f7a9f1e17685943ad243f08dc86337df1c5a19dc75062804e45d0c41272";
    };
    mkPkg = { pkgs, l, version ? "1.0.9", system ? pkgs.stdenv.hostPlatform.system, ... }:
      let
        url = "https://github.com/azu/launchd-ui/releases/download/v${version}/launchd-ui_${version}_aarch64.dmg";
        sha256 = versions.${system}.${version}.sha256;
      in
      pkgs.lib.darwin.installDmg {
        inherit url version sha256;
        appname = "launchd-ui";
        meta = {
          source = "https://github.com/azu/launchd-ui";
          description = "A GUI application for managing macOS launchd agents and daemons";
          homepage = "https://github.com/azu/launchd-ui";
        };
      };
  };
}
