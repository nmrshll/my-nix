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
                "2.3.0".sha256 = "sha256-JrK8U0yYq2IS2luC1nbSM0nOC0XZLYKgtv7GBEPtCns=";
                "2.2.3".sha256 = "sha256-nRCamrwzoPX0cAEcP6p0t0t9Q41RjM6okupOPkJH5lQ=";
              };
              mkPkg = { version ? "2.3.0" }:
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


          cargo-build-sbf =
            let
              versions = {
                "2.3.0".sha256 = "";
              };
              mkPkg = { version ? "2.3.0" }:
                let
                  platform-tools = ownPkgs.platform-tools;
                  srcPatched = stdenv.mkDerivation {
                    name = "cargo-build-sbf-patched";
                    src = ownPkgs.agave-src.mkPkg { inherit version; };
                    phases = [ "unpackPhase" "patchPhase" "installPhase" ];
                    patches = [ ../pkgs/cargo-build-sbf-main.patch ];
                    postPatch = ''
                      # Remove empty client-test workspace member (cargo 1.95+ rejects it)
                      sed -i '/"client-test"/d' Cargo.toml
                      rm -rf client-test
                    '';
                    installPhase = ''
                      runHook preInstall
                      mkdir -p $out
                      cp -r ./* $out/
                      runHook postInstall
                    '';
                  };
                  commonArgs = rec {
                    pname = "cargo-build-sbf";
                    inherit version;
                    src = srcPatched;
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
                    CXX = "clang++";
                    CXXFLAGS = "-std=c++11";
                    ROCKSDB_LIB_DIR = "${pkgs.rocksdb_8_11}/lib";
                    ROCKSDB_INCLUDE_DIR = "${pkgs.rocksdb_8_11}/include";
                    CPPFLAGS = lib.optionals stdenv.isDarwin "-isystem ${lib.getDev pkgs.libcxx}/include/c++/v1";
                    LDFLAGS = lib.optionals stdenv.isDarwin "-L${lib.getLib pkgs.libcxx}/lib";
                    OPENSSL_NO_VENDOR = 1;
                  };
                  cargoArtifacts = craneLib.buildDepsOnly (commonArgs);
                in
                craneLib.buildPackage (commonArgs // {
                  inherit cargoArtifacts;
                  postInstall = ''
                    WRAPPED_PROG="$out/bin/.cargo-build-sbf-wrapped"
                    mv $out/bin/cargo-build-sbf $out/bin/.cargo-build-sbf-wrapped
                    cat > $out/bin/cargo-build-sbf <<'WRAP_EOF'
                      #!/bin/sh
                      set -x
                      required_flags=( "--no-rustup-override" "--skip-tools-install" )
                      seen_flags=""
                      extraArgs=()
                      for arg in "$@"; do
                          for flag in "''${required_flags[@]}"; do
                              if [ "$arg" = "$flag" ]; then
                                  seen_flags="$seen_flags $flag"
                                  break
                              fi
                          done
                      done
                      for flag in "''${required_flags[@]}"; do
                          echo "$seen_flags" | grep -qw \"$flag\" || extraArgs+=("$flag")
                      done
                      echo "Original args: $@"
                      echo "Extra args to add: ''${extraArgs[@]}"
                      export SBF_SDK_PATH="${platform-tools}/bin/platform-tools-sdk/sbf"
                      export RUSTC="${platform-tools}/bin/platform-tools-sdk/sbf/dependencies/platform-tools/rust/bin/rustc"
                      exec -a "$0" WRAPPED_PROG "$@"
                    WRAP_EOF
                    sed -i "s|WRAPPED_PROG|$WRAPPED_PROG|g" $out/bin/cargo-build-sbf
                    chmod +x $out/bin/cargo-build-sbf
                  '';
                  passthru = { inherit versions mkPkg; };
                });
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
              mkPkg = { version ? "0.31.1" }:
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


          platform-tools =
            let
              versions = {
                "1.45".x86_64-linux.sha256 = "sha256-QGm7mOd3UnssYhPt8RSSRiS5LiddkXuDtWuakpak0Y0=";
                "1.45".aarch64-linux.sha256 = "sha256-UzOekFBdjtHJzzytmkQETd6Mrb+cdAsbZBA0kzc75Ws=";
                "1.45".x86_64-darwin.sha256 = "sha256-EE7nVJ+8a/snx4ea7U+zexU/vTMX16WoU5Kbv5t2vN8=";
                "1.45".aarch64-darwin.sha256 = "sha256-aJjYD4vhsLcBMAC8hXrecrMvyzbkas9VNF9nnNxtbiE=";
                # "1.52".x86_64-linux.sha256 = "";
                "1.52".aarch64-darwin.sha256 = "sha256-+seEpShbkN87ECsL7XeMF8oixqqLtO9aR2lmc+qssSY=";
              };
              mkPkg = { version ? "1.52" }:
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
                    "cargo-build-sbf"
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
          ownPkgs.anchor-cli
          pkgs.surfpool
        ] ++ (attrValues scripts);
      };
  };

in
{
  flake.flakeModules = flakeModules;
  imports = (attrValues flakeModules);
}
