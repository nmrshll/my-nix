with builtins; let
  flakeModules.solana = part@{ self, config, pkgs, inputs, ... }:
    let
      crane = part.config.flakeInputsOf.my-nix.crane;
    in
    {
      perSystem = { pkgs, config, lib, system, ... }:
        let
          craneLib = crane.mkLib pkgs;
          inherit (pkgs) stdenv callPackage;

          srcs = {
            agave = { version }:
              let
                sha256 = {
                  "2.3.0" = "sha256-JrK8U0yYq2IS2luC1nbSM0nOC0XZLYKgtv7GBEPtCns=";
                  "2.2.3" = "sha256-nRCamrwzoPX0cAEcP6p0t0t9Q41RjM6okupOPkJH5lQ=";
                }.${version};
              in
              pkgs.fetchFromGitHub { inherit sha256; owner = "anza-xyz"; repo = "agave"; rev = "v${version}"; fetchSubmodules = true; };

            solana-platform-tools =
              let
                mapSystemStr = { x86_64-linux = "linux-x86_64"; aarch64-linux = "linux-aarch64"; x86_64-darwin = "osx-x86_64"; aarch64-darwin = "osx-aarch64"; x86_64-windows = "windows-x86_64"; };
                perVersionHash = {
                  x86_64-linux."1.45" = "sha256-QGm7mOd3UnssYhPt8RSSRiS5LiddkXuDtWuakpak0Y0=";
                  aarch64-linux."1.45" = "sha256-UzOekFBdjtHJzzytmkQETd6Mrb+cdAsbZBA0kzc75Ws=";
                  x86_64-darwin."1.45" = "sha256-EE7nVJ+8a/snx4ea7U+zexU/vTMX16WoU5Kbv5t2vN8=";
                  aarch64-darwin."1.45" = "sha256-aJjYD4vhsLcBMAC8hXrecrMvyzbkas9VNF9nnNxtbiE=";
                  x86_64-windows."1.45" = "sha256-7D7NN2tClnQ/UAwKUZEZqNVQxcKWguU3Fs1pgsC5CIk=";
                }.${system};
              in
              mapAttrs (version: hash: { sysStr = mapSystemStr.${system}; inherit hash version; }) perVersionHash;
          };

          ownPkgs = {
            spl-token = { version ? "5.1.0" }:
              let
                pname = "spl-token";
                srcHash = "sha256-XqQgTbiiLKHSTInxdRh1SYgtwxcyr9Q9XJPx9+tDRwc=";
                cargoHash = "sha256-e07bJvN0+Hhd8qzhr91Ft8JjzIdkxNNkaRofj01oM2c=";
              in
              pkgs.rustPlatform.buildRustPackage {
                src = pkgs.fetchFromGitHub {
                  owner = "solana-program";
                  repo = "token-2022";
                  rev = "cli@v${version}";
                  hash = srcHash;
                };
                useFetchCargoVendor = true;
                inherit pname version cargoHash;
                nativeBuildInputs = [ pkgs.pkg-config pkgs.protobuf pkgs.rustPlatform.bindgenHook ];
                buildInputs = [
                  pkgs.openssl
                  pkgs.rocksdb_8_11
                  pkgs.snappy
                ] ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.udev ];
                doCheck = false;
                PROTOC = "${pkgs.protobuf}/bin/protoc";
                ROCKSDB_LIB_DIR = "${pkgs.rocksdb_8_11}/lib";
                SNAPPY_LIB_DIR = "${pkgs.snappy}/lib";
                OPENSSL_NO_VENDOR = 1;
                OPENSSL_STATIC = 1;
              };

            solana-platform-tools = { version ? "1.45" }:
              let
                source = srcs.solana-platform-tools.${version};
                agaveSrc = srcs.agave { version = "2.2.3"; };
              in
              stdenv.mkDerivation {
                inherit version;
                pname = "solana-platform-tools";
                src = pkgs.fetchzip {
                  url = "https://github.com/anza-xyz/platform-tools/releases/download/v${version}/platform-tools-${source.sysStr}.tar.bz2";
                  hash = source.hash;
                  stripRoot = false;
                };
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
              };

            cargo-build-sbf = { version ? "2.3.0" }:
              let
                platform-tools = callPackage ownPkgs.solana-platform-tools { };
                srcPatched = stdenv.mkDerivation {
                  name = "cargo-build-sbf-patched";
                  src = srcs.agave { inherit version; };
                  phases = [ "unpackPhase" "patchPhase" "installPhase" ];
                  patches = [ ../pkgs/cargo-build-sbf-main.patch ];
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
                  nativeBuildInputs = [ pkgs.protobuf pkgs.pkg-config ];
                  buildInputs = [
                    pkgs.openssl
                    pkgs.rustPlatform.bindgenHook
                    pkgs.makeWrapper
                  ]
                  ++ lib.optionals stdenv.isLinux [ pkgs.udev ]
                  ++ lib.optionals stdenv.isDarwin [ pkgs.libcxx ];
                  NIX_OUTPATH_USED_AS_RANDOM_SEED = "aaaaaaaaaa";
                  ROCKSDB_LIB_DIR = "${pkgs.rocksdb_8_11}/lib";
                  ROCKSDB_INCLUDE_DIR = "${pkgs.rocksdb_8_11}/include";
                  CPPFLAGS = lib.optionals stdenv.isDarwin "-isystem ${lib.getDev pkgs.libcxx}/include/c++/v1";
                  LDFLAGS = lib.optionals stdenv.isDarwin "-L${lib.getLib pkgs.libcxx}/lib";
                  OPENSSL_NO_VENDOR = 1;
                };
                cargoArtifacts = craneLib.buildDepsOnly (commonArgs // { dummySrc = srcPatched; });
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
              });

            solana-cli = { version ? "2.2.3" }:
              let
                src = srcs.agave { inherit version; };
                solanaPkgs = [ "agave-install" "agave-install-init" "agave-ledger-tool" "agave-validator" "agave-watchtower" "cargo-test-sbf" "rbpf-cli" "solana" "solana-bench-tps" "solana-faucet" "solana-gossip" "solana-keygen" "solana-log-analyzer" "solana-net-shaper" "solana-dos" "solana-stake-accounts" "solana-test-validator" "solana-tokens" "solana-genesis" ];
                commonArgs = {
                  pname = "solana-cli";
                  inherit src version;
                  strictDeps = true;
                  cargoExtraArgs = lib.concatMapStringsSep " " (n: "--bin=${n}") solanaPkgs;
                  doCheck = false;
                  nativeBuildInputs = [ pkgs.protobuf pkgs.pkg-config ];
                  buildInputs = [
                    pkgs.openssl
                    pkgs.rustPlatform.bindgenHook
                    pkgs.makeWrapper
                  ]
                  ++ lib.optionals stdenv.isLinux [ pkgs.udev ]
                  ++ lib.optionals stdenv.isDarwin [ pkgs.libcxx ];
                  NIX_OUTPATH_USED_AS_RANDOM_SEED = "aaaaaaaaaa";
                  ROCKSDB_LIB_DIR = "${pkgs.rocksdb_8_11}/lib";
                  ROCKSDB_INCLUDE_DIR = "${pkgs.rocksdb_8_11}/include";
                  CPPFLAGS = lib.optionals stdenv.isDarwin "-isystem ${lib.getDev pkgs.libcxx}/include/c++/v1";
                  LDFLAGS = lib.optionals stdenv.isDarwin "-L${lib.getLib pkgs.libcxx}/lib";
                  OPENSSL_NO_VENDOR = 1;
                };
                cargoArtifacts = craneLib.buildDepsOnly (commonArgs // { dummySrc = src; });
              in
              craneLib.buildPackage (commonArgs // {
                inherit cargoArtifacts;
                postInstall = ''
                  mkdir -p $out/bin/platform-tools-sdk/sbf
                  cp -a ./platform-tools-sdk/sbf/* $out/bin/platform-tools-sdk/sbf/
                '';
              });

            anchor-cli = { version ? "0.31.1" }:
              let
                pname = "anchor-cli";
                versionsDeps."0.31.1" = {
                  hash = "sha256-c+UybdZCFL40TNvxn0PHR1ch7VPhhJFDSIScetRpS3o=";
                  rust-nightly = pkgs.rust-bin.nightly."2025-04-21".minimal;
                  rust = pkgs.rust-bin.stable."1.85.0".default;
                  platform-tools = callPackage ownPkgs.solana-platform-tools { version = "1.45"; };
                  patches = [ (pkgs.fetchurl { url = "https://raw.githubusercontent.com/arijoon/solana-nix/87bea8cac979d14c758c24d2b9178c44a6e95b39/patches/anchor-cli/0.31.1.patch"; sha256 = "sha256:0w07q4cszg54pf5511qxy9fmj1ywqbmqszjl1hsb56dq3xrpax87"; }) ];
                };
                versionDeps = versionsDeps.${version};
                anchorCraneLib = (crane.mkLib pkgs).overrideToolchain versionDeps.rust;
                originalSrc = pkgs.fetchFromGitHub {
                  owner = "coral-xyz";
                  repo = "anchor";
                  rev = "v${version}";
                  hash = versionDeps.hash;
                };
                src = stdenv.mkDerivation {
                  name = "anchor-cli-patched";
                  src = originalSrc;
                  phases = [ "unpackPhase" "patchPhase" "installPhase" ];
                  patches = versionDeps.patches;
                  installPhase = ''
                    runHook preInstall
                    mkdir -p $out
                    cp -r ./* $out/
                    runHook postInstall
                  '';
                };
                commonArgs = {
                  inherit pname version src;
                  strictDeps = true;
                  doCheck = false;
                  nativeBuildInputs = [ pkgs.protobuf pkgs.pkg-config pkgs.makeWrapper ];
                  buildInputs = [ ]
                    ++ lib.optionals stdenv.isLinux [ pkgs.udev ]
                    ++ lib.optional stdenv.isDarwin [ ];
                };
              in
              anchorCraneLib.buildPackage (commonArgs // {
                postInstall =
                  let
                    cargo-nightly = pkgs.runCommand "cargo-nightly"
                      { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
                      mkdir -p $out/bin
                      ln -s ${versionDeps.rust-nightly}/bin/cargo $out/bin/cargo
                      wrapProgram $out/bin/cargo \
                        --prefix PATH : "${versionDeps.rust-nightly}/bin"
                    '';
                  in
                  ''
                    rust=${versionDeps.platform-tools}/bin/platform-tools-sdk/sbf/dependencies/platform-tools/rust/bin
                    wrapProgram $out/bin/anchor \
                      --prefix PATH : "$rust" ${if versionDeps ? rust-nightly then "--set RUST_NIGHTLY_BIN \"${cargo-nightly}/bin\"" else ""}
                  '';
                cargoExtraArgs = "-p ${pname}";
                meta = { mainProgram = "anchor"; description = "Anchor cli"; };
              });
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

          packages = {
            solana-platform-tools = callPackage ownPkgs.solana-platform-tools { };
            solana-cli = callPackage ownPkgs.solana-cli { };
            anchor-cli = callPackage ownPkgs.anchor-cli { };
            spl-token = callPackage ownPkgs.spl-token { };
            cargo-build-sbf = callPackage ownPkgs.cargo-build-sbf { };
          };

        in
        {
          pkgs.overlays = [ (import part.config.flakeInputsOf.my-nix.rust-overlay) ];

          inherit packages;

          myDevShell.buildInputs = buildInputs ++ (attrValues packages) ++ (attrValues scripts);
          myDevShell.env = env;
        };
    };

in
{
  flake.flakeModules = flakeModules;
  imports = (attrValues flakeModules);
}
