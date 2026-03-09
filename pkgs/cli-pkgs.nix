with builtins; {

  pkgDefs.atlassian-cli = rec {
    versions = {
      aarch64-darwin."1.2.5-stable".sha256 = "sha256:1xij39cv16af7cs5pwyg3fb56kdmf2kvvrg0hizs4m0cly3pv00a";
    };
    mkPkg = { pkgs, version ? "1.2.5-stable", system ? pkgs.stdenv.hostPlatform.system, ... }:
      let
        sysShort = { aarch64-darwin = "darwin"; x86_64-linux = "linux"; }.${pkgs.stdenv.hostPlatform.system};
        sysLong = { aarch64-darwin = "darwin_arm64"; x86_64-linux = "linux-x64"; }.${pkgs.stdenv.hostPlatform.system};
      in
      pkgs.stdenv.mkDerivation {
        inherit version;
        pname = "atlassian-cli";
        src = fetchTarball {
          url = "https://acli.atlassian.com/${sysShort}/${version}/acli_${version}_${sysLong}.tar.gz";
          sha256 = versions.${system}.${version}.sha256;
        };
        installPhase = ''
          mkdir -p $out/bin
          cp -r $src/acli $out/bin/acli
        '';
        meta = { description = "Atlassian CLI"; homepage = "https://acli.atlassian.com/"; };
      };
  };

  pkgDefs.leveldb-viewer = rec {
    versions = {
      aarch64-darwin."master".sha256 = "DLP4gVoC9Nb/0iIjkNG1mwCIAfxH1KPbrDm/ueE3fFk=";
    };
    mkPkg = { pkgs, version ? "master", system ? pkgs.stdenv.hostPlatform.system, ... }:
      pkgs.buildGoModule {
        pname = "leveldb-viewer";
        inherit version;

        vendorHash = "sha256-2I5oxQo9bINJ+BjGO4FHOkRx1W2O315rx6MUGRZh3xo=";

        src = pkgs.fetchFromGitHub {
          owner = "arkantos1482";
          repo = "leveldb-viewer";
          rev = version;
          sha256 = versions.${system}.${version}.sha256;
        };
      };
  };

  # TODO package https://github.com/ErfanY/krust

}
