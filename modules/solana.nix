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
            spl-token =
              let
                versions."5.6.1" = { sha256 = "sha256-7gOP19SESZMnfLPZfOP588TUstc01SRedn7uO7zrd4U="; cargoHash = "sha256-kbpIyV4GFhebrZzVodnAxiJhgHnwb06JzGcRZCjchq0="; };
                mkPkg = { version ? "5.6.1" }:
                  let v = versions.${version};
                  in pkgs.rustPlatform.buildRustPackage {
                    pname = "spl-token4";
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

            # solana-cli = { version ? "2.2.3" }:
            #   let
            #     src = srcs.agave { inherit version; };
            #     solanaPkgs = [ "agave-install" "agave-install-init" "agave-ledger-tool" "agave-validator" "agave-watchtower" "cargo-test-sbf" "rbpf-cli" "solana" "solana-bench-tps" "solana-faucet" "solana-gossip" "solana-keygen" "solana-log-analyzer" "solana-net-shaper" "solana-dos" "solana-stake-accounts" "solana-test-validator" "solana-tokens" "solana-genesis" ];
            #     commonArgs = {
            #       pname = "solana-cli";
            #       inherit src version;
            #       strictDeps = true;
            #       cargoExtraArgs = lib.concatMapStringsSep " " (n: "--bin=${n}") solanaPkgs;
            #       doCheck = false;
            #       nativeBuildInputs = [ pkgs.protobuf pkgs.pkg-config pkgs.clang ];
            #       buildInputs = [
            #         pkgs.openssl
            #         pkgs.rustPlatform.bindgenHook
            #         pkgs.makeWrapper
            #       ]
            #       ++ lib.optionals stdenv.isLinux [ pkgs.udev ]
            #       ++ lib.optionals stdenv.isDarwin [ pkgs.libcxx ];
            #       PROTOC = "${pkgs.protobuf}/bin/protoc";
            #       CXXFLAGS = "-std=c++11";
            #       OPENSSL_NO_VENDOR = 1;
            #       ROCKSDB_LIB_DIR = "${pkgs.rocksdb_8_11}/lib";
            #       ROCKSDB_INCLUDE_DIR = "${pkgs.rocksdb_8_11}/include";

            #       # PROTOC = "${pkgs.protobuf}/bin/protoc";
            #       LIBUSB_NO_VENDOR = 1;
            #       CC = "${pkgs.llvmPackages.clang}/bin/clang";
            #       CXX = "${pkgs.llvmPackages.clang}/bin/clang++";
            #       # CXXFLAGS = "-std=c++11";
            #       NIX_CFLAGS_COMPILE = "-isystem ${pkgs.llvmPackages.libcxx.dev}/include/c++/v1";
            #     };
            #     cargoArtifacts = craneLib.buildDepsOnly (commonArgs // { dummySrc = src; });
            #   in
            #   craneLib.buildPackage (commonArgs // {
            #     inherit cargoArtifacts;
            #     postInstall = ''
            #       mkdir -p $out/bin/platform-tools-sdk/sbf
            #       cp -a ./platform-tools-sdk/sbf/* $out/bin/platform-tools-sdk/sbf/
            #     '';
            #   });

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


            # cli2 =
            #   { stdenv
            #   , fetchFromGitHub
            #   , fetchurl
            #   , lib
            #   , rustPlatform
            #   , udev
            #   , protobuf
            #   , installShellFiles
            #   , pkg-config
            #   , openssl
            #   , nix-update-script
            #   , versionCheckHook
            #   , clang
            #   , libclang
            #   , rocksdb
            #   , # Taken from https://github.com/solana-labs/solana/blob/master/scripts/cargo-install-all.sh#L84
            #     solanaPkgs ? [
            #       "cargo-build-sbf"
            #       "cargo-test-sbf"
            #       "solana"
            #       "solana-bench-tps"
            #       "solana-faucet"
            #       "solana-gossip"
            #       "agave-install"
            #       "solana-keygen"
            #       "agave-ledger-tool"
            #       "solana-net-shaper"
            #       "agave-validator"
            #       "solana-test-validator"
            #     ]
            #     ++ [
            #       # XXX: Ensure `solana-genesis` is built LAST!
            #       # See https://github.com/solana-labs/solana/issues/5826
            #       "solana-genesis"
            #     ]
            #   ,
            #   }:
            #   let
            #     version = "3.0.12";
            #     hash = "sha256-Zubu7cTSJrJFSuguCo3msdas/QshFpo1+T6DVQyqrhY=";

            #     # Platform tools configuration
            #     platformToolsVersion = "v1.52";
            #     platformToolsSrc =
            #       if stdenv.hostPlatform.isDarwin && stdenv.hostPlatform.isAarch64 then
            #         fetchurl
            #           {
            #             url = "https://github.com/anza-xyz/platform-tools/releases/download/${platformToolsVersion}/platform-tools-osx-aarch64.tar.bz2";
            #             sha256 = "sha256-Fyffsx6DPOd30B5wy0s869JrN2vwnYBSfwJFfUz2/QA="; # Run: nix-prefetch-url --type sha256 <url>
            #           }
            #       else if stdenv.hostPlatform.isLinux && stdenv.hostPlatform.isx86_64 then
            #         fetchurl
            #           {
            #             url = "https://github.com/anza-xyz/platform-tools/releases/download/${platformToolsVersion}/platform-tools-linux-x86_64.tar.bz2";
            #             sha256 = "sha256-izhh6T2vCF7BK2XE+sN02b7EWHo94Whx2msIqwwdkH4"; # Run: nix-prefetch-url --type sha256 <url>
            #           }
            #       else null;
            #   in
            #   rustPlatform.buildRustPackage rec {
            #     pname = "solana-cli";
            #     inherit version;

            #     src = fetchFromGitHub {
            #       owner = "anza-xyz";
            #       repo = "agave";
            #       tag = "v${version}";
            #       inherit hash;
            #     };

            #     cargoHash = "sha256-qnZbFkyzE2hdy/ynZQZmCs5kCeTUMci9f/pVKID/mRQ=";

            #     strictDeps = true;
            #     cargoBuildFlags = map (n: "--bin=${n}") solanaPkgs;
            #     RUSTFLAGS = "-Amismatched_lifetime_syntaxes -Adead_code -Aunused-parens";
            #     LIBCLANG_PATH = "${libclang.lib}/lib";

            #     # Even tho the tests work, a shit ton of them try to connect to a local RPC
            #     # or access internet in other ways, eventually failing due to Nix sandbox.
            #     # Maybe we could restrict the check to the tests that don't require an RPC,
            #     # but judging by the quantity of tests, that seems like a lengthty work and
            #     # I'm not in the mood ((ΦωΦ))
            #     doCheck = false;

            #     nativeBuildInputs = [
            #       installShellFiles
            #       protobuf
            #       pkg-config
            #     ];
            #     buildInputs = [
            #       openssl
            #       clang
            #       libclang
            #       rustPlatform.bindgenHook
            #     ]
            #     ++ lib.optionals stdenv.hostPlatform.isLinux [ udev ];

            #     doInstallCheck = true;

            #     nativeInstallCheckInputs = [ versionCheckHook ];
            #     versionCheckProgram = "${placeholder "out"}/bin/solana";
            #     versionCheckProgramArg = "--version";

            #     postInstall = lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
            #       installShellCompletion --cmd solana \
            #         --bash <($out/bin/solana completion --shell bash) \
            #         --fish <($out/bin/solana completion --shell fish)

            #       mkdir -p $out/bin/platform-tools-sdk
            #       cp -r ./platform-tools-sdk/sbf $out/bin/platform-tools-sdk

            #       mkdir -p $out/bin/deps
            #       find . -name libsolana_program.dylib -exec cp {} $out/bin/deps \;
            #       find . -name libsolana_program.rlib -exec cp {} $out/bin/deps \;
            #     '' + lib.optionalString (platformToolsSrc != null) ''
            #       # Unpack platform-tools into sbf directory
            #       mkdir -p $out/bin/platform-tools-sdk/sbf/dependencies
            #       mkdir -p $out/bin/platform-tools-sdk/sbf/dependencies/platform-tools
            #       tar -xjf ${platformToolsSrc} -C $out/bin/platform-tools-sdk/sbf/dependencies/platform-tools --strip-components=1

            #       # Remove broken symlinks
            #       find $out/bin/platform-tools-sdk/sbf/dependencies/platform-tools -type l ! -exec test -e {} \; -delete
            #     '';

            #     # Used by build.rs in the rocksdb-sys crate. If we don't set these, it would
            #     # try to build RocksDB from source.
            #     ROCKSDB_LIB_DIR = "${rocksdb}/lib";

            #     # Require this on darwin otherwise the compiler starts rambling about missing
            #     # cmath functions
            #     CPPFLAGS = lib.optionals stdenv.hostPlatform.isDarwin "-isystem ${lib.getInclude stdenv.cc.libcxx}/include/c++/v1";
            #     LDFLAGS = lib.optionals stdenv.hostPlatform.isDarwin "-L${lib.getLib stdenv.cc.libcxx}/lib";

            #     # If set, always finds OpenSSL in the system, even if the vendored feature is enabled.
            #     OPENSSL_NO_VENDOR = 1;

            #     meta = with lib; {
            #       description = "Web-Scale Blockchain for fast, secure, scalable, decentralized apps and marketplaces";
            #       homepage = "https://solana.com";
            #       license = licenses.asl20;
            #       maintainers = with maintainers; [
            #         netfox
            #         happysalada
            #         aikooo7
            #         JacoMalan1
            #       ];
            #       platforms = platforms.unix;
            #     };

            #     passthru.updateScript = nix-update-script { };
            #   };

            cli3 =
              let
                versions."3.0.12" = {
                  hash = "sha256-Zubu7cTSJrJFSuguCo3msdas/QshFpo1+T6DVQyqrhY=";
                  cargoHash = "sha256-qnZbFkyzE2hdy/ynZQZmCs5kCeTUMci9f/pVKID/mRQ=";
                  platformToolsVersion = "v1.52";
                  platformToolsHash = {
                    aarch64-darwin = "sha256-Fyffsx6DPOd30B5wy0s869JrN2vwnYBSfwJFfUz2/QA=";
                    x86_64-linux = "sha256-izhh6T2vCF7BK2XE+sN02b7EWHo94Whx2msIqwwdkH4";
                  };
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

                    sysStr = mapSystemStr.${pkgs.stdenv.hostPlatform.system} or null;
                    platformToolsSrc =
                      if sysStr != null then
                        (pkgs.fetchurl {
                          url = "https://github.com/anza-xyz/platform-tools/releases/download/${v.platformToolsVersion}/platform-tools-${sysStr}.tar.bz2";
                          sha256 = v.platformToolsHash.${pkgs.stdenv.hostPlatform.system};
                        }) else null;
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
                    RUSTFLAGS = "-Amismatched_lifetime_syntaxes -Adead_code -Aunused-parens";
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
                      tar -xjf ${platformToolsSrc} -C $out/bin/platform-tools-sdk/sbf/dependencies/platform-tools --strip-components=1
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
          pkgs.overlays = [ (import part.config.flakeInputsOf.my-nix.rust-overlay) ];

          packages = {
            inherit (ownPkgs) spl-token-3 spl-token2 spl-token4 cli3;
            solana-platform-tools = callPackage ownPkgs.solana-platform-tools { };
            solana-cli = callPackage ownPkgs.solana-cli { };
            anchor-cli = callPackage ownPkgs.anchor-cli { };
            # spl-token = callPackage ownPkgs.spl-token { };
            cargo-build-sbf = callPackage ownPkgs.cargo-build-sbf { };
          };

          myDevShell.env = env;
          myDevShell.buildInputs = buildInputs ++ [
            ownPkgs.spl-token
            # (callPackage ownPkgs.solana-cli { })
            ownPkgs.cli3
            (callPackage ownPkgs.anchor-cli { })
            (callPackage ownPkgs.cargo-build-sbf { })
          ] ++ (attrValues scripts);
        };
    };

in
{
  flake.flakeModules = flakeModules;
  imports = (attrValues flakeModules);
}
