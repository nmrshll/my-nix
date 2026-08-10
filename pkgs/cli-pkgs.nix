with builtins; {
  config.perSystem = { pkgs, l, system, ... }: {

    ownPkgs.atlassian-cli =
      let
        versions."1.2.5-stable".sha256 = "sha256:1xij39cv16af7cs5pwyg3fb56kdmf2kvvrg0hizs4m0cly3pv00a";
        mkPkg = { version ? "1.2.5-stable", ... }:
          if pkgs.stdenv.hostPlatform.system != "aarch64-darwin" then null
          else
          let
            sysShort = { aarch64-darwin = "darwin"; x86_64-linux = "linux"; }.${pkgs.stdenv.hostPlatform.system};
            sysLong = { aarch64-darwin = "darwin_arm64"; x86_64-linux = "linux-x64"; }.${pkgs.stdenv.hostPlatform.system};
            src = fetchTarball {
              url = "https://acli.atlassian.com/${sysShort}/${version}/acli_${version}_${sysLong}.tar.gz";
              sha256 = versions.${version}.sha256;
            };
          in
          pkgs.stdenv.mkDerivation {
            inherit version;
            pname = "atlassian-cli";
            inherit src;
            installPhase = ''
              mkdir -p $out/bin
              cp -r $src/acli $out/bin/acli
            '';
            passthru = { inherit versions mkPkg src; };
            meta = { description = "Atlassian CLI"; homepage = "https://acli.atlassian.com/"; };
          };
      in
      mkPkg { };

    ownPkgs.leveldb-viewer =
      let
        versions."master".sha256 = "DLP4gVoC9Nb/0iIjkNG1mwCIAfxH1KPbrDm/ueE3fFk=";
        mkPkg = { version ? "master", ... }:
          let
            src = pkgs.fetchFromGitHub {
              owner = "arkantos1482";
              repo = "leveldb-viewer";
              rev = version;
              sha256 = versions.${version}.sha256;
            };
          in
          pkgs.buildGoModule {
            pname = "leveldb-viewer";
            inherit version src;

            vendorHash = "sha256-2I5oxQo9bINJ+BjGO4FHOkRx1W2O315rx6MUGRZh3xo=";

            passthru = { inherit versions mkPkg src; };
          };
      in
      mkPkg { };


    # TODO package https://github.com/ErfanY/krust

    ownPkgs.beads-rust =
      let
        versions."0.1.34" = {
          sha256 = "sha256-h3YomeRFeekp6PZwDSqibaQudyiZB8ewNEACjfHk96A=";
          cargoHash = "sha256-gVvHXT507yNNUWUbLjfk9i93U72hnMqxuS8y7TnZyw0=";
          frankensqlite = { rev = "a49c137d5f61a0753926e82217e9e293e071bd6a"; hash = "sha256-eA9ZK+cNh8MCjKbLVJwSgtT/40spacTRaNdLW9GESUE="; };
          asupersync = { rev = "662284ad4b6ff64fdf7f25b31293d2bbbbd465e4"; hash = "sha256-LjiS63gEtY2QH3j+2UGi1BYHpfxM9+GpCuGHFDEYsto="; };
        };
        mkPkg = { version ? "0.1.34", ... }:
          let
            data = versions.${version};

            # Upstream uses [patch.crates-io] with local path deps pointing at sibling
            # checkouts of frankensqlite and asupersync.  Fetch them separately and place
            # them where Cargo expects.
            # https://github.com/Dicklesworthstone/beads_rust/issues/183
            frankensqlite = pkgs.fetchFromGitHub {
              owner = "Dicklesworthstone";
              repo = "frankensqlite";
              inherit (data.frankensqlite) rev hash;
            };

            # frankensqlite workspace depends on asupersync via path = "../asupersync"
            asupersync = pkgs.fetchFromGitHub {
              owner = "Dicklesworthstone";
              repo = "asupersync";
              inherit (data.asupersync) rev hash;
            };

            src = pkgs.fetchFromGitHub {
              owner = "Dicklesworthstone";
              repo = "beads_rust";
              tag = "v${version}";
              inherit (data) sha256;
            };
          in
          pkgs.rustPlatform.buildRustPackage {
            pname = "beads-rust";
            inherit (data) cargoHash;
            inherit version src;

            postUnpack = ''
              cp -r ${frankensqlite} frankensqlite
              chmod -R u+w frankensqlite
              cp -r ${asupersync} asupersync
              chmod -R u+w asupersync
            '';

            # fsqlite uses #![feature(peer_credentials_unix_socket)] which requires nightly.
            # RUSTC_BOOTSTRAP=1 enables nightly features on stable rustc.
            env.RUSTC_BOOTSTRAP = 1;

            # Disable self_update feature — doesn't make sense in Nix
            buildNoDefaultFeatures = true;

            # Tests require a git repository context
            doCheck = false;

            doInstallCheck = true;
            nativeInstallCheckInputs = [ pkgs.versionCheckHook ];

            passthru = { inherit versions mkPkg; category = "Workflow & Project Management"; };

            meta = with l; {
              description = "Fast Rust port of beads - a local-first issue tracker for git repositories";
              homepage = "https://github.com/Dicklesworthstone/beads_rust";
              changelog = "https://github.com/Dicklesworthstone/beads_rust/releases/tag/v${version}";
              downloadPage = "https://github.com/Dicklesworthstone/beads_rust/releases";
              license = licenses.mit;
              sourceProvenance = with sourceTypes; [ fromSource ];
              maintainers = with flake.lib.maintainers; [ afterthought ];
              mainProgram = "br";
              platforms = platforms.unix;
            };
          };
      in
      mkPkg { };

    ownPkgs.dumap =
      let
        versions."1.1.0" = { sha256 = "nVG9A+QBTRo+M4ogwHOARRvihsWka/I4CPzY5M9yONc="; };

        mkPkg = { version ? (l.latest versions), ... }:
          let
            vData = versions.${version} or (throw "Unsupported system or version: ${system} / ${version}");
            src = pkgs.fetchFromGitHub {
              owner = "jrobhoward";
              repo = "dumap";
              tag = "v${version}";
              sha256 = vData.sha256;
            };
          in
          pkgs.rustPlatform.buildRustPackage {
            pname = "dumap";
            inherit src version;
            cargoLock.lockFile = "${src}/Cargo.lock";
            doCheck = false;
            passthru = { inherit versions mkPkg src; };
          };
      in
      mkPkg { };

    ownPkgs.tilth =
      let
        versions."0.6.3".sha256 = "xP9zsOmzAJKbQBeRFdbWqt3CGjj7rJpbCIvIo+f6efc=";
        mkPkg = { version ? (l.latest versions), ... }:
          let
            vData = versions.${version} or (throw "Unsupported system or version: ${system} / ${version}");
            src = pkgs.fetchFromGitHub {
              owner = "jahala";
              repo = "tilth";
              tag = "v${version}";
              sha256 = vData.sha256;
            };
          in
          pkgs.rustPlatform.buildRustPackage {
            pname = "tilth";
            inherit src version;
            doCheck = false;
            cargoLock.lockFile = "${src}/Cargo.lock";
            passthru = { inherit versions mkPkg src; };
            meta = {
              description = "Smart(er) code reading for humans and AI agents";
              homepage = "https://github.com/jahala/tilth";
              license = pkgs.lib.licenses.mit;
              mainProgram = "tilth";
            };
          };
      in
      mkPkg { };

    ownPkgs.rmrfrs =
      let
        versions."0.8.8" = { sha256 = "1QF1l6V6YmKDPqlbXpMeWg3Pt5AonBHelD63mJkSWNM="; cargoHash = "sha256-mPQN/JN6b9/1xo1JSj0LpVjb7rGTwrfU0PY7pbENdg4="; };
        mkPkg = { version ? (l.latest versions), ... }:
          let
            vData = versions.${version};
            src = pkgs.fetchFromGitHub {
              owner = "trinhminhtriet";
              repo = "rmrfrs";
              tag = "v${version}";
              sha256 = vData.sha256;
            };
          in
          pkgs.rustPlatform.buildRustPackage (finalAttrs: {
            pname = "rmrfrs";
            inherit version src;

            cargoHash = vData.cargoHash;

            passthru = { inherit versions mkPkg src; updateScript = nix-update-script { }; };

            meta = {
              description = "Powerful filesystem cleaning tool designed to optimize storage by identifying and removing unnecessary files within known project structures";
              homepage = "https://github.com/trinhminhtriet/rmrfrs";
              downloadPage = "https://github.com/trinhminhtriet/rmrfrs";
              changelog = "https://github.com/trinhminhtriet/rmrfrs/blob/v${finalAttrs.version}/CHANGELOG.md";
              license = l.licenses.mit;
              maintainers = with l.maintainers; [ adda ];
              mainProgram = "rmrfrs";
              platforms = with l.platforms; windows ++ darwin ++ linux;
            };
          });
      in
      mkPkg { };

    ownPkgs.oxmgr =
      let
        versions."0.4.0".sha256 = "0bk9i5l72r83ilg7akdnf2kcfw72xk7yfy7ssz3inagnwyhsr9pv";

        mkPkg = { version ? (l.latest versions), ... }:
          let
            vData = versions.${version} or (throw "Unsupported system or version: ${system} / ${version}");
            src = pkgs.fetchFromGitHub {
              owner = "Vladimir-Urik";
              repo = "OxMgr";
              tag = "v${version}";
              sha256 = vData.sha256;
            };
          in
          pkgs.rustPlatform.buildRustPackage {
            pname = "oxmgr";
            inherit src version;
            cargoLock.lockFile = "${src}/Cargo.lock";
            doCheck = false;
            passthru = { inherit versions mkPkg src; };
            meta = {
              description = "Lightweight cross-platform process manager written in Rust, a PM2 alternative";
              homepage = "https://github.com/Vladimir-Urik/OxMgr";
              license = pkgs.lib.licenses.mit;
              mainProgram = "oxmgr";
            };
          };
      in
      mkPkg { };

  };
}
