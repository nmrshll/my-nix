with builtins; let

  mkLibDarwin = { pkgs, l, ... }: {
    installDmg = { version, url, sha256, appname, meta }: pkgs.stdenvNoCC.mkDerivation {
      inherit version;
      meta = meta // {
        platforms = [ "aarch64-darwin" ];
      };
      src = fetchurl { inherit url sha256; };
      pname = l.slugify appname;
      nativeBuildInputs = [ pkgs.undmg ];
      buildInputs = [ pkgs.unzip ];
      unpackCmd = ''
        echo "File to unpack: $curSrc"
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
    };
  };

  flakeModules.darwinPkgsLib = { ... }: {
    config.perSystem = { system, pkgs, l, ... }: {
      config.pkgs.extraLib.darwin = l.mkIf (l.hasInfix "darwin" system) (mkLibDarwin { inherit pkgs l; });
    };
  };

in
{
  flake.flakeModules = { utils = flakeModules; essentials = flakeModules; };
  imports = (attrValues flakeModules);
}
