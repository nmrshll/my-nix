with builtins; let

  mkLibDarwin = { pkgs, l, ... }: {
    # Any extra args (e.g. passthru) are forwarded to mkDerivation below and take
    # precedence over the built-in defaults. version/url/sha256/appname/meta are
    # consumed here and never forwarded.
    installDmg = args@{ version, url, sha256, appname, meta, ... }: pkgs.stdenvNoCC.mkDerivation (
      (removeAttrs args [ "version" "url" "sha256" "appname" "meta" ]) // {
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
      }
    );
  };

  flakeModules.darwinPkgsLib = { ... }: {
    config.perSystem = { system, pkgs, l, ... }: {
      # NOTE: defined on all systems (not just darwin) so that forcing `pkgs.lib`
      # (e.g. while evaluating ownPkgs on linux) doesn't hit an undefined option.
      # installDmg is only *called* by packages that null-guard themselves to darwin.
      config.pkgs.extraLib.darwin = mkLibDarwin { inherit pkgs l; };
    };
  };

in
{
  flake.flakeModules = flakeModules // { utils = flakeModules; essentials = flakeModules; };
  imports = (attrValues flakeModules);
}
