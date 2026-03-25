with builtins; rec {
  pkgDefs.xcode-xip = rec {
    # downloaded from https://developer.apple.com/download/all/
    versions = {
      aarch64-darwin."26_2_Apple_silicon".sha256 = "0lmmyq12c3pkhs6cwf9v5pna1rvn7h8idxq0i78yh7v47ia1vwvd";
      aarch64-darwin."26_1_Apple_silicon".sha256 = "nsZrYLN3CwTEE1GtRGlOtWUHmDbFTimIM75MByUcUYs=";
    };
    mkPkg = { pkgs, version ? "26_1_Apple_silicon", system ? pkgs.stdenv.hostPlatform.system, lib, ... }: (pkgs.fetchurl {
      url = "https://huggingface.co/datasets/nmarshall/nix-install-files/resolve/main/files/Xcode_${version}.xip?download=true";
      sha256 = versions.${system}.${version}.sha256;
      name = "Xcode_${version}.xip";
      passthru = {
        version = lib.removeSuffix "_Universal" (lib.removeSuffix "_Apple_silicon" version);
      };
    });
  };

  pkgDefs.install-xcode = {
    versions = {
      aarch64-darwin."26_2_Apple_silicon" = { };
      aarch64-darwin."26_1_Apple_silicon" = { };
    };
    mkPkg = { pkgs, version ? "26_1_Apple_silicon", system ? pkgs.stdenv.hostPlatform.system, lib, ... }:
      let
        xip = pkgDefs.xcode-xip.mkPkg { inherit version pkgs system lib; };
        xcode_app.versions = {
          "26_2_Apple_silicon".sha256 = "YxMVppJwRzTA6xWOILxVjLdl0bNmtZSifG/KQx6inRE=";
          "26_1_Apple_silicon".sha256 = "xFMknk3RxxJi/5IOb2mmw7vyC1xOaY5ZwCZ09AARtJU=";
        };
        xcode_app.sha256 = xcode_app.versions.${version}.sha256;
        expect-path = pkgs.runCommand "XCODE_APP_STORE_PATH_EXPECTED" { } ''
          ${pkgs.nix}/bin/nix-store --print-fixed-path --recursive sha256 "${xcode_app.sha256}" "Xcode.app" > $out
        '';
        xcode_app.expected_path = lib.strings.trim (readFile expect-path);
        DEV_DIR = "${xcode_app.expected_path}/Contents/Developer";
      in
      (pkgs.writeShellScriptBin "install-xcode" ''
        WD=$(mktemp -d)
        cd "$WD"

        if [ ! -e "${xcode_app.expected_path}" ]; then
            echo "Xcode not found in store. Expanding..."
            install -m 644 "${xip}" "$WD/XCode_${version}.xip"
            /usr/bin/xip --expand "$WD/XCode_${version}.xip"
            nix-store --add-fixed --recursive sha256 Xcode.app
        else
            echo "Xcode already exists at ${xcode_app.expected_path}. Skipping expansion."
        fi
        sudo xcode-select -s "${DEV_DIR}"

        if ! xcodebuild -checkFirstLaunchStatus > /dev/null 2>&1; then
          yes agree | sudo xcodebuild -license accept
          xcodebuild -runFirstLaunch
        else
          echo "XCode already initialized."
        fi
      '').overrideAttrs (oldAttrs: {
        passthru = (oldAttrs.passthru or { }) // {
          inherit version xcode_app;
        };
      });
  };

  pkgDefs.install-xcode-global = {
    mkPkg = { pkgs, version ? "26_1_Apple_silicon", lib, ... }:
      let
        install-xcode-pkg = pkgDefs.install-xcode.mkPkg { inherit pkgs version lib; };
        store_path = install-xcode-pkg.xcode_app.expected_path;
        target_path = "/Applications/Xcode.app";
        DEV_DIR = "${target_path}/Contents/Developer";
        SDKROOT = "${DEV_DIR}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk";
      in
      (pkgs.writeShellScriptBin "install-xcode-global" ''set -x
        # 1. Ensure the Xcode bundle exists in the Nix Store
        if [ ! -d "${store_path}" ]; then
          ${install-xcode-pkg}/bin/install-xcode
        fi

        # 2. Copy to /Applications
        if [ "$(xcodebuild -version 2>&1)" != "$(DEVELOPER_DIR="${DEV_DIR}" xcodebuild -version 2>&1)" ]; then
          sudo rm -rf "${target_path}"
          sudo rsync -rlptD --delete --stats "${store_path}/" "${target_path}/"
        fi

        # 3. Set $DEVELOPER_DIR and init Xcode
        if [ "$(xcode-select -print-path)" != "/Applications/Xcode.app/Contents/Developer"]; then
          sudo xcode-select -s "${DEV_DIR}"
        fi

        if ! xcodebuild -checkFirstLaunchStatus > /dev/null 2>&1; then
          yes agree | sudo xcodebuild -license accept
          xcodebuild -runFirstLaunch
        else
          echo "XCode already initialized."
        fi
      '').overrideAttrs (oldAttrs: {
        passthru = (oldAttrs.passthru or { }) // {
          inherit version DEV_DIR SDKROOT;
        };
      });

  };

  # xcode = {
  #   mkPkg = { pkgs, version ? "26_2_Apple_silicon", system ? pkgs.stdenv.hostPlatform.system, lib, ... }:
  #     let xip = xcode-xip.mkPkg { inherit version pkgs system lib; };
  #     in pkgs.stdenv.mkDerivation {
  #       pname = "XCode.app";
  #       inherit version;
  #       src = xip;
  #       # __noChroot = true; # break the nix sandbox. For '/usr/bin/xip --expand'. Doesn't work.
  #       dontUnpack = true;
  #       buildPhase =
  #         # if pkgs.stdenv.buildPlatform.isDarwin then ''set -x;
  #         #   cp "${xip}" ./Xcode_${version}.xip
  #         #   chmod +w Xcode_${version}.xip
  #         #   /usr/bin/xip --expand Xcode_${version}.xip
  #         #   ls -la
  #         #   exit 1
  #         # '' else
  #         ''
  #           ${pkgs.xar}/bin/xar -xf ${xip}
  #           ${pkgs.pbzx}/bin/pbzx -n Content | ${pkgs.cpio}/bin/cpio -i --verbose --preserve-modification-time --make-directories
  #           rm Metadata Content
  #           ${pkgs.rcodesign}/bin/rcodesign verify Xcode.app/Contents/MacOS/Xcode
  #         '';
  #       installPhase = ''mv Xcode.app $out'';
  #       # postFixup = '' # Doesn't work. tried self-signing binaries. xcodebuild doesn't accept that.
  #       #   find $out -type f \( -perm -u=x -o -name "*.so" -o -name "*.dylib" \) -exec \
  #       #     /usr/bin/codesign --force --sign - {} +
  #       # '';

  #       meta = {
  #         description = "Automatically extracted Xcode from xip";
  #         platforms = pkgs.lib.platforms.darwin;
  #       };
  #     };
  # };
}
