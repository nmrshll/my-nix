with builtins; {
  config.perSystem = { pkgs, lib, config, ... }: {

    ownPkgs.xcode-xip =
      let
        # downloaded from https://developer.apple.com/download/all/
        versions."26_2_Apple_silicon".sha256 = "0lmmyq12c3pkhs6cwf9v5pna1rvn7h8idxq0i78yh7v47ia1vwvd";
        versions."26_1_Apple_silicon".sha256 = "nsZrYLN3CwTEE1GtRGlOtWUHmDbFTimIM75MByUcUYs=";
        mkPkg = { version ? "26_1_Apple_silicon", ... }:
          let
            src = pkgs.fetchurl {
              url = "https://huggingface.co/datasets/nmarshall/nix-install-files/resolve/main/files/Xcode_${version}.xip?download=true";
              sha256 = versions.${version}.sha256;
              name = "Xcode_${version}.xip";
            };
          in
          src // {
            passthru = {
              inherit versions mkPkg src;
              version = lib.removeSuffix "_Universal" (lib.removeSuffix "_Apple_silicon" version);
            };
          };
      in
      mkPkg { };

    ownPkgs.install-xcode =
      let
        versions."26_2_Apple_silicon" = { };
        versions."26_1_Apple_silicon" = { };
        mkPkg = { version ? "26_1_Apple_silicon", ... }:
          let
            xip = config.ownPkgs.xcode-xip.passthru.mkPkg { inherit version; };
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

            if ! /usr/bin/xcodebuild -checkFirstLaunchStatus > /dev/null 2>&1; then
              yes agree | sudo xcodebuild -license accept
              /usr/bin/xcodebuild -runFirstLaunch
            else
              echo "XCode already initialized."
            fi
          '').overrideAttrs (oldAttrs: {
            passthru = (oldAttrs.passthru or { }) // {
              inherit version xcode_app versions mkPkg;
              src = xip;
            };
          });
      in
      mkPkg { };

    ownPkgs.install-xcode-global =
      let
        versions."26_2_Apple_silicon" = { };
        versions."26_1_Apple_silicon" = { };
        mkPkg = { version ? "26_1_Apple_silicon", ... }:
          let
            install-xcode-pkg = config.ownPkgs.install-xcode.passthru.mkPkg { inherit version; };
            store_path = install-xcode-pkg.xcode_app.expected_path;
            target_path = "/Applications/Xcode.app";
            DEV_DIR = "${target_path}/Contents/Developer";
            SDKROOT = "${DEV_DIR}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk";
            xcodebuild = "/usr/bin/xcodebuild";
          in
          (pkgs.writeShellScriptBin "install-xcode-global" ''set -x
            # 1. Ensure the Xcode bundle exists in the Nix Store
            if [ ! -d "${store_path}" ]; then
              ${install-xcode-pkg}/bin/install-xcode
            fi

            # 2. Copy to /Applications
            if [ "$(${xcodebuild} -version 2>&1)" != "$(DEVELOPER_DIR="${DEV_DIR}" ${xcodebuild} -version 2>&1)" ]; then
              sudo rm -rf "${target_path}"
              sudo rsync -rlptD --delete --stats "${store_path}/" "${target_path}/"
            fi

            # 3. Set $DEVELOPER_DIR and init Xcode
            if [ "$(xcode-select -print-path)" != "/Applications/Xcode.app/Contents/Developer" ]; then
              sudo xcode-select -s "${DEV_DIR}"
            fi

            if ! ${xcodebuild} -checkFirstLaunchStatus > /dev/null 2>&1; then
              yes agree | sudo ${xcodebuild} -license accept
              ${xcodebuild} -runFirstLaunch
            else
              echo "XCode already initialized."
            fi
          '').overrideAttrs (oldAttrs: {
            passthru = (oldAttrs.passthru or { }) // {
              inherit version DEV_DIR SDKROOT versions mkPkg;
              src = install-xcode-pkg.passthru.src;
            };
          });
      in
      mkPkg { };

  };
}
