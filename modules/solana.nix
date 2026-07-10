with builtins; let
  flakeModules.solana = part@{ config, ... }: {
    perSystem = { pkgs, lib, ... }:
      let
        crane = part.config.flakeInputsOf.my-nix.crane;
        craneLib = crane.mkLib pkgs;
        inherit (pkgs) stdenv;

        ownPkgs = {
          agave-src =
            let
              versions = {
                "3.0.12".sha256 = "sha256-Zubu7cTSJrJFSuguCo3msdas/QshFpo1+T6DVQyqrhY=";
                "2.3.0".sha256 = "sha256-JrK8U0yYq2IS2luC1nbSM0nOC0XZLYKgtv7GBEPtCns=";
                "2.2.3".sha256 = "sha256-nRCamrwzoPX0cAEcP6p0t0t9Q41RjM6okupOPkJH5lQ=";
              };
              mkPkg = { version ? "3.0.12" }:
                let v = versions.${version}; in pkgs.fetchFromGitHub {
                  inherit (v) sha256; owner = "anza-xyz";
                  repo = "agave";
                  rev = "v${version}";
                  fetchSubmodules = true;
                  passthru = { inherit mkPkg versions; };
                };
            in
            mkPkg { };

          spl-token =
            let
              versions."5.6.1" = { sha256 = "sha256-7gOP19SESZMnfLPZfOP588TUstc01SRedn7uO7zrd4U="; cargoHash = "sha256-kbpIyV4GFhebrZzVodnAxiJhgHnwb06JzGcRZCjchq0="; };
              mkPkg = { version ? "5.6.1" }:
                let v = versions.${version};
                in pkgs.rustPlatform.buildRustPackage {
                  pname = "spl-token";
                  inherit version;
                  src = pkgs.fetchFromGitHub { owner = "solana-program"; repo = "token-2022"; rev = "cli@v${version}"; sha256 = v.sha256; };
                  cargoHash = v.cargoHash;
                  strictDeps = true;
                  doCheck = false;
                  nativeBuildInputs = [
                    (pkgs.writeShellScriptBin "sw_vers" '' echo "15.0" '')
                    pkgs.protobuf
                    pkgs.pkg-config
                    pkgs.clang
                  ];
                  buildInputs = [
                    pkgs.openssl
                    pkgs.libusb1
                    pkgs.rustPlatform.bindgenHook
                    pkgs.libclang
                  ];
                  env = {
                    LIBCLANG_PATH = "${pkgs.libclang.lib}/lib";
                    PROTOC = "${pkgs.protobuf}/bin/protoc";
                    LIBUSB_NO_VENDOR = 1;
                    OPENSSL_NO_VENDOR = 1;
                    CPPFLAGS = lib.optionals stdenv.isDarwin "-isystem ${lib.getInclude stdenv.cc.libcxx}/include/c++/v1";
                    LDFLAGS = lib.optionals stdenv.isDarwin "-L${lib.getLib stdenv.cc.libcxx}/lib";
                  };
                  passthru = { inherit versions mkPkg; };
                };
            in
            mkPkg { };


          cargo-build-sbf-unwrapped =
            let
              versions."4.1.0" = {
                sha256 = "sha256-pqsR0vh2uixfyG3VgC1lFFgx+0/6UwKmWfNy+Et6H4s=";
                cargoHash = "";
              };
              mkPkg = { version ? "4.1.0" }:
                let
                  v = versions.${version};
                  src = pkgs.fetchFromGitHub {
                    owner = "anza-xyz";
                    repo = "cargo-build-sbf";
                    tag = "cargo-build-sbf@v${version}";
                    sha256 = v.sha256;
                  };
                  commonArgs = rec {
                    pname = "cargo-build-sbf";
                    inherit version src;
                    strictDeps = true;
                    cargoExtraArgs = "--bin=${pname}";
                    doCheck = false;
                    nativeBuildInputs = [ pkgs.protobuf pkgs.pkg-config pkgs.clang ];
                    buildInputs = [
                      pkgs.openssl
                      pkgs.rustPlatform.bindgenHook
                      pkgs.makeWrapper
                    ]
                    ++ lib.optionals stdenv.isLinux [ pkgs.udev ]
                    ++ lib.optionals stdenv.isDarwin [ pkgs.libcxx ];
                    PROTOC = "${pkgs.protobuf}/bin/protoc";
                    CXXFLAGS = "-std=c++11";
                    ROCKSDB_LIB_DIR = "${pkgs.rocksdb_8_11}/lib";
                    ROCKSDB_INCLUDE_DIR = "${pkgs.rocksdb_8_11}/include";
                    CPPFLAGS = lib.optionals stdenv.isDarwin "-isystem ${lib.getDev pkgs.libcxx}/include/c++/v1";
                    LDFLAGS = lib.optionals stdenv.isDarwin "-L${lib.getLib pkgs.libcxx}/lib";
                    OPENSSL_NO_VENDOR = 1;
                  };
                  cargoArtifacts = craneLib.buildDepsOnly commonArgs;
                in
                craneLib.buildPackage (commonArgs // {
                  inherit cargoArtifacts;
                  # preBuild = '' ${pkgs.tree}/bin/tree -a -L 4 . '';
                  patches = [ ../pkgs/cargo-build-sbf_4.1+.patch ];
                  passthru = { inherit versions mkPkg src; };
                });
            in
            mkPkg { };

          cargo-build-sbf-wrapper =
            let
              versions = {
                "4.1.0" = { platform-tools-version = "1.54"; };
              };
              mkPkg = { version ? "4.1.0" }:
                let
                  v = versions.${version};
                  unwrapped = ownPkgs.cargo-build-sbf-unwrapped;
                  platform-tools = ownPkgs.platform-tools.passthru.mkPkg { version = v.platform-tools-version; };
                in
                (pkgs.writeShellScriptBin "cargo-build-sbf" ''
                  SBF_SDK_PATH="${platform-tools}/bin/platform-tools-sdk/sbf"
                  PT_DIR="$SBF_SDK_PATH/dependencies/platform-tools"

                  for p in "$PT_DIR/rust" "$PT_DIR/rust/bin" "$PT_DIR/rust/bin/rustc" "$PT_DIR/rust/bin/cargo"; do
                      if [ ! -e "$p" ]; then
                          echo "ERROR: missing $p"
                          ls -la "$PT_DIR/" 2>/dev/null || echo "  (directory does not exist)"
                          ls -la "$PT_DIR/rust/bin/" 2>/dev/null || echo "  rust/bin does not exist"
                          exit 1
                      fi
                  done

                  required_flags=( "--no-rustup-override" "--skip-tools-install" )
                  seen_flags=""
                  extraArgs=()
                  cleanArgs=()
                  for arg in "$@"; do
                      if [ "$arg" = "build-sbf" ]; then
                          continue
                      fi
                      found=0
                      for flag in "''${required_flags[@]}"; do
                          if [ "$arg" = "$flag" ]; then
                              seen_flags="$seen_flags $flag"
                              found=1
                              break
                          fi
                      done
                      if [ "$found" = "0" ]; then
                          cleanArgs+=("$arg")
                      fi
                  done
                  for flag in "''${required_flags[@]}"; do
                      echo "$seen_flags" | grep -qw -- "$flag" || extraArgs+=("$flag")
                  done
                  export SBF_SDK_PATH
                  export SOLANA_PLATFORM_TOOLS_DIR="$PT_DIR"
                  export RUSTC="$PT_DIR/rust/bin/rustc"
                  set -x
                  exec ${unwrapped}/bin/cargo-build-sbf "''${cleanArgs[@]}" "''${extraArgs[@]}"
                '') // { passthru = { inherit versions mkPkg; }; };
            in
            mkPkg { };


          anchor-cli =
            let
              versions."0.31.1" = {
                sha256 = "sha256-c+UybdZCFL40TNvxn0PHR1ch7VPhhJFDSIScetRpS3o=";
                rust-nightly = pkgs.rust-bin.nightly."2025-04-21".minimal;
                platform-tools = ownPkgs.platform-tools.passthru.mkPkg { version = "1.45"; };
                patches = [ (pkgs.fetchurl { url = "https://raw.githubusercontent.com/arijoon/solana-nix/87bea8cac979d14c758c24d2b9178c44a6e95b39/patches/anchor-cli/0.31.1.patch"; sha256 = "sha256:0w07q4cszg54pf5511qxy9fmj1ywqbmqszjl1hsb56dq3xrpax87"; }) ];
              };
              versions."1.1.2" = {
                sha256 = "";
                rust-nightly = pkgs.rust-bin.nightly.latest.minimal;
                platform-tools = ownPkgs.platform-tools.passthru.mkPkg { version = "1.54"; };
                patches = [ (pkgs.fetchurl { url = "https://raw.githubusercontent.com/arijoon/solana-nix/87bea8cac979d14c758c24d2b9178c44a6e95b39/patches/anchor-cli/0.31.1.patch"; sha256 = "sha256:0w07q4cszg54pf5511qxy9fmj1ywqbmqszjl1hsb56dq3xrpax87"; }) ];
              };
              mkPkg = { version ? "1.1.2" }:
                let
                  v = versions.${version};
                  pname = "anchor-cli";
                  originalSrc = pkgs.fetchFromGitHub {
                    owner = "coral-xyz";
                    repo = "anchor";
                    rev = "v${version}";
                    hash = v.sha256;
                  };
                  patchedSrc = stdenv.mkDerivation {
                    name = "anchor-cli-patched";
                    src = originalSrc;
                    phases = [ "unpackPhase" "patchPhase" "installPhase" ];
                    patches = v.patches;
                    installPhase = ''
                      runHook preInstall
                      mkdir -p $out
                      cp -r ./* $out/
                      runHook postInstall
                    '';
                  };
                  commonArgs = {
                    inherit pname version;
                    src = patchedSrc;
                    strictDeps = true;
                    doCheck = false;
                    nativeBuildInputs = [ pkgs.protobuf pkgs.pkg-config pkgs.makeWrapper ];
                    buildInputs = [ ]
                      ++ lib.optionals stdenv.isLinux [ pkgs.udev ];
                  };

                in
                craneLib.buildPackage (commonArgs // {
                  postInstall =
                    let
                      cargo-nightly = pkgs.runCommand "cargo-nightly"
                        { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
                        mkdir -p $out/bin
                        ln -s ${v.rust-nightly}/bin/cargo $out/bin/cargo
                        wrapProgram $out/bin/cargo \
                          --prefix PATH : "${v.rust-nightly}/bin"
                      '';
                    in
                    ''
                      rust=${v.platform-tools}/bin/platform-tools-sdk/sbf/dependencies/platform-tools/rust/bin
                      wrapProgram $out/bin/anchor \
                        --prefix PATH : "$rust" ${if v ? rust-nightly then "--set RUST_NIGHTLY_BIN \"${cargo-nightly}/bin\"" else ""}
                    '';
                  cargoExtraArgs = "-p ${pname}";
                  meta = { mainProgram = "anchor"; description = "Anchor cli"; };
                });
            in
            mkPkg { };

          avm =
            let
              baseUrl = "https://anchor-releases.s3-eu-west-1.amazonaws.com";
              # versions."nightly-20260701-abe3cb9" = {
              #   aarch64-darwin = "sha256-5731bbb5cbf812a83c4ea53ed759d6c8df325ac568bc9a87c702d97fe015918c";
              #   x86_64-darwin = "sha256-e93879b18958009bf56e6f1d42c878dd62d506f773b91fd18d1e390a18cbfcd4";
              #   x86_64-linux = "sha256-b51f9ea3f7891a01148424054a54ca5fc868053178c8c7a99f9f6d6995c7cfea";
              # };
              mapSystem = {
                aarch64-darwin = "aarch64-apple-darwin";
                x86_64-darwin = "x86_64-apple-darwin";
                x86_64-linux = "x86_64-unknown-linux-gnu";
              };
              mkPkg = { version ? "nightly-20260701-abe3cb9" }:
                let
                  v = versions.${version};
                  sysStr = mapSystem.${pkgs.stdenv.hostPlatform.system};
                in
                pkgs.stdenv.mkDerivation {
                  pname = "avm";
                  inherit version;
                  src = pkgs.fetchurl {
                    url = "${baseUrl}/nightly/latest/${sysStr}/avm.tar.gz";
                    sha256 = v.${pkgs.stdenv.hostPlatform.system};
                  };
                  nativeBuildInputs = pkgs.lib.optionals pkgs.stdenv.isLinux [ pkgs.autoPatchelfHook ];
                  buildInputs = pkgs.lib.optionals pkgs.stdenv.isLinux [ pkgs.stdenv.cc.cc.lib ];
                  dontBuild = true;
                  installPhase = ''
                    mkdir -p $out/bin
                    tar -xzf $src --strip-components=0 -C $out/bin
                    chmod +x $out/bin/avm
                  '';
                  passthru = { inherit versions mkPkg; };
                  meta.mainProgram = "avm";
                };
            in
            mkPkg { };

          anchor-cli-binary =
            let
              versions."1.1.2".aarch64-darwin.sha256 = "sha256-ZOZKdB16jwmwVe/l1E6QBZz0593SJa7pU1SVhQWvf0o=";

              mapSystem = {
                aarch64-darwin = "aarch64-apple-darwin";
                x86_64-darwin = "x86_64-apple-darwin";
                x86_64-linux = "x86_64-unknown-linux-gnu";
              };
              mkPkg = { version ? "1.1.2" }:
                let
                  v = versions.${version};
                  sysStr = mapSystem.${pkgs.stdenv.hostPlatform.system};
                in
                pkgs.stdenv.mkDerivation {
                  pname = "anchor";
                  inherit version;
                  src = pkgs.fetchurl {
                    url = "https://github.com/otter-sec/anchor/releases/download/v1.1.2/anchor-1.1.2-${sysStr}";
                    # url = "https://anchor-releases.s3-eu-west-1.amazonaws.com/nightly/latest/${sysStr}/anchor.tar.gz";
                    sha256 = v.${pkgs.stdenv.hostPlatform.system}.sha256;
                  };
                  dontUnpack = true;
                  nativeBuildInputs = pkgs.lib.optionals pkgs.stdenv.isLinux [ pkgs.autoPatchelfHook ];
                  buildInputs = pkgs.lib.optionals pkgs.stdenv.isLinux [ pkgs.stdenv.cc.cc.lib ];
                  dontBuild = true;
                  installPhase = ''
                    mkdir -p $out/bin
                    cp $src $out/bin/anchor
                    chmod +x $out/bin/anchor
                  '';
                  passthru = { inherit versions mkPkg; };
                  meta.mainProgram = "anchor";
                };
            in
            mkPkg { };


          platform-tools =
            let
              versions = {
                "1.45".x86_64-linux.sha256 = "sha256-QGm7mOd3UnssYhPt8RSSRiS5LiddkXuDtWuakpak0Y0=";
                "1.45".aarch64-linux.sha256 = "sha256-UzOekFBdjtHJzzytmkQETd6Mrb+cdAsbZBA0kzc75Ws=";
                "1.45".x86_64-darwin.sha256 = "sha256-EE7nVJ+8a/snx4ea7U+zexU/vTMX16WoU5Kbv5t2vN8=";
                "1.45".aarch64-darwin.sha256 = "sha256-aJjYD4vhsLcBMAC8hXrecrMvyzbkas9VNF9nnNxtbiE=";
                "1.52".aarch64-darwin.sha256 = "sha256-+seEpShbkN87ECsL7XeMF8oixqqLtO9aR2lmc+qssSY=";
                "1.54".aarch64-darwin.sha256 = "sha256-tqsZQNPSTeCmZXbw/NwvDNodO0FbVJXx51yO+YsN3ag=";
              };
              mkPkg = { version ? "1.54" }:
                let
                  v = versions.${version}.${pkgs.stdenv.hostPlatform.system};
                  agaveSrc = ownPkgs.agave-src.mkPkg { version = "2.2.3"; };
                  sysStr = {
                    x86_64-linux = "linux-x86_64";
                    aarch64-linux = "linux-aarch64";
                    x86_64-darwin = "osx-x86_64";
                    aarch64-darwin = "osx-aarch64";
                  }.${pkgs.stdenv.hostPlatform.system};
                  src = pkgs.fetchzip {
                    url = "https://github.com/anza-xyz/platform-tools/releases/download/v${version}/platform-tools-${sysStr}.tar.bz2";
                    sha256 = v.sha256;
                    stripRoot = false;
                  };
                in
                stdenv.mkDerivation {
                  inherit version src;
                  pname = "solana-platform-tools";
                  doCheck = false;
                  dontCheckForBrokenSymlinks = true;
                  nativeBuildInputs = lib.optionals stdenv.isLinux [ pkgs.autoPatchelfHook ];
                  buildInputs = [
                    pkgs.libedit
                    pkgs.zlib
                    stdenv.cc.cc
                    pkgs.libclang.lib
                    pkgs.xz
                    pkgs.python315
                  ] ++ lib.optionals stdenv.isLinux [ pkgs.udev ];
                  installPhase = ''
                    platformtools=$out/bin/platform-tools-sdk/sbf/dependencies/platform-tools
                    mkdir -p $platformtools
                    cp -r $src/llvm $platformtools
                    cp -r $src/rust $platformtools
                    chmod 0755 -R $out
                    touch $platformtools-${version}.md

                    criterion=$out/bin/platform-tools-sdk/sbf/dependencies/criterion
                    mkdir $criterion
                    ln -s ${pkgs.criterion.dev}/include $criterion/include
                    ln -s ${pkgs.criterion}/lib $criterion/lib
                    ln -s ${pkgs.criterion}/share $criterion/share
                    touch $criterion-v${pkgs.criterion.version}.md

                    cp -ar ${agaveSrc}/platform-tools-sdk/sbf/* $out/bin/platform-tools-sdk/sbf/
                  '';
                  postFixup = lib.optionals stdenv.isLinux ''
                    patchelf --replace-needed libedit.so.2 libedit.so $out/bin/platform-tools-sdk/sbf/dependencies/platform-tools/llvm/lib/liblldb.so.18.1.7-rust-dev
                  '';
                  stripExclude = [ "*.rlib" ];
                  passthru = { inherit versions mkPkg src; };
                };
            in
            mkPkg { };

          solana-cli =
            let
              versions."3.0.12" = {
                hash = "sha256-Zubu7cTSJrJFSuguCo3msdas/QshFpo1+T6DVQyqrhY=";
                cargoHash = "sha256-qnZbFkyzE2hdy/ynZQZmCs5kCeTUMci9f/pVKID/mRQ=";
                platformToolsVersion = "1.52";
              };
              mkPkg = { version ? "3.0.12", solanaPkgs ? null }:
                let
                  v = versions.${version};
                  solanaCrates = if solanaPkgs != null then solanaPkgs else [
                    # "cargo-build-sbf"
                    "cargo-test-sbf"
                    "solana"
                    "solana-bench-tps"
                    "solana-faucet"
                    "solana-gossip"
                    "agave-install"
                    "solana-keygen"
                    "agave-ledger-tool"
                    "solana-net-shaper"
                    "agave-validator"
                    "solana-test-validator"
                  ] ++ [ "solana-genesis" ]; # Ensure `solana-genesis` is built LAST!  # See https://github.com/solana-labs/solana/issues/5826
                  platformToolsSrc = (ownPkgs.platform-tools.mkPkg { version = v.platformToolsVersion; }).src;
                in
                pkgs.rustPlatform.buildRustPackage {
                  pname = "solana-cli";
                  inherit version;
                  src = pkgs.fetchFromGitHub {
                    owner = "anza-xyz";
                    repo = "agave";
                    tag = "v${version}";
                    hash = v.hash;
                  };
                  cargoHash = v.cargoHash;
                  strictDeps = true;
                  cargoBuildFlags = map (n: "--bin=${n}") solanaCrates;
                  RUSTFLAGS = "-A warnings";
                  LIBCLANG_PATH = "${pkgs.libclang.lib}/lib";
                  doCheck = false;
                  nativeBuildInputs = [
                    pkgs.installShellFiles
                    pkgs.protobuf
                    pkgs.pkg-config
                  ];
                  buildInputs = [
                    pkgs.openssl
                    pkgs.clang
                    pkgs.libclang
                    pkgs.rustPlatform.bindgenHook
                  ] ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.udev ];
                  doInstallCheck = true;
                  nativeInstallCheckInputs = [ pkgs.versionCheckHook ];
                  versionCheckProgram = "${placeholder "out"}/bin/solana";
                  versionCheckProgramArg = "--version";
                  postInstall = pkgs.lib.optionalString (pkgs.stdenv.buildPlatform.canExecute pkgs.stdenv.hostPlatform) ''
                    installShellCompletion --cmd solana \
                      --bash <($out/bin/solana completion --shell bash) \
                      --fish <($out/bin/solana completion --shell fish)
                    mkdir -p $out/bin/platform-tools-sdk
                    cp -r ./platform-tools-sdk/sbf $out/bin/platform-tools-sdk
                    mkdir -p $out/bin/deps
                    find . -name libsolana_program.dylib -exec cp {} $out/bin/deps \;
                    find . -name libsolana_program.rlib -exec cp {} $out/bin/deps \;
                  '' + pkgs.lib.optionalString (platformToolsSrc != null) ''
                    mkdir -p $out/bin/platform-tools-sdk/sbf/dependencies/platform-tools
                    cp -r ${platformToolsSrc}/* $out/bin/platform-tools-sdk/sbf/dependencies/platform-tools/
                    chmod -R u+w $out/bin/platform-tools-sdk/sbf/dependencies/platform-tools
                    find $out/bin/platform-tools-sdk/sbf/dependencies/platform-tools -type l ! -exec test -e {} \; -delete
                  '';
                  ROCKSDB_LIB_DIR = "${pkgs.rocksdb}/lib";
                  CPPFLAGS = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin "-isystem ${pkgs.lib.getInclude pkgs.stdenv.cc.libcxx}/include/c++/v1";
                  LDFLAGS = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin "-L${pkgs.lib.getLib pkgs.stdenv.cc.libcxx}/lib";
                  OPENSSL_NO_VENDOR = 1;
                  passthru = { inherit versions mkPkg; };
                };
            in
            mkPkg { };

        };

        buildInputs = [
          (pkgs.rust-bin.stable."1.87.0".default.override {
            extensions = [ "rust-src" "rust-analyzer" ];
          })
        ] ++ lib.optionals stdenv.isDarwin [ ];

        scripts = mapAttrs (n: t: pkgs.writeShellScriptBin n t) {
          sol = ''solana --keypair "$KEY" $@'';
          set-devnet = ''solana config set --url devnet'';
          new-wallet = ''
            if [ ! -f "$KEY" ]; then
              solana-keygen new --no-bip39-passphrase --outfile "$KEY"
            fi
          '';
          addr = ''solana address --keypair "$KEY"'';
          airdrop = ''sol airdrop 2'';
          token = ''spl-token $@ '';
          validator = ''solana-test-validator'';

          anchor-init = ''anchor init reinit --no-git --no-install --template single --anchor-version v2 --test-template mocha --package-manager yarn  '';

          capture-cargo-build-sbf-src = ''
            DEST="$(git rev-parse --show-toplevel)/patch/cargo-build-sbf"
            mkdir -p "$DEST"
            cp -r "${ownPkgs.cargo-build-sbf-unwrapped.src}/cargo-build-sbf" "$DEST/"
            echo "Source copied to $DEST"
          '';
          diff-build-sbf = ''
            SRC="$(git rev-parse --show-toplevel)/.cache/cargo-build-sbf-src"
            if [ ! -d "$SRC" ]; then
              echo "Run capture-cargo-build-sbf-src first"
              exit 1
            fi
            for f in "$@"; do
              echo "=== $f ==="
              diff -u "$SRC/$f" "$f" || true
            done
          '';
        };

        env = {
          # RUST_BACKTRACE = "1";
          KEYS_DIR = "$(git rev-parse --show-toplevel)/.cache/keys";
          KEY = "$(git rev-parse --show-toplevel)/.cache/keys/main.json";
          IDL_DIR = "$(git rev-parse --show-toplevel)/.cache/idl";
        };


      in
      {
        # imports = [ part.config.flakeModules.rust ];
        pkgs.overlays = [ (import part.config.flakeInputsOf.my-nix.rust-overlay) ];

        packages = ownPkgs;

        myDevShell.env = env;
        myDevShell.buildInputs = buildInputs ++ [
          ownPkgs.spl-token
          ownPkgs.solana-cli
          ownPkgs.anchor-cli-binary
          ownPkgs.cargo-build-sbf-wrapper
          # ownPkgs.anchor-cli-binary
          # ownPkgs.avm
          pkgs.surfpool
        ] ++ (attrValues scripts);
      };
  };

in
{
  flake.flakeModules = flakeModules;
  imports = (attrValues flakeModules);
}
