with builtins; {
  config.perSystem = { pkgs, l, lib, config, system, ... }: {

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

    # TODO try ? https://github.com/AtomicBot-ai/Atomic-Chat

    # TODO package bifrost: https://github.com/capsohq/bifrost/blob/4418dc8fa1ca6f606061edb356cf49efe99f4da5/nix/modules/bifrost.nix

  };
}
