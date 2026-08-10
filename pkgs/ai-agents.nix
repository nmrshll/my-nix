with builtins; {
  config.perSystem = { pkgs, l, lib, system, ... }: {

    ownPkgs.pi-coding-agent =
      let
        versions."0.70.2" = { sha256 = "qqmJloTp3mWuZBGgpwoyoFyXx6QD8xhJEwCZb7xFabM="; npmDepsHash = "sha256-ImDvTC0Nm+IGYJuqjwUUfnOtA65uJvjlpP4h2Xt/2vE="; };
        versions."0.64.0" = { sha256 = "knCfmoTjq5RADkGRcX7AAxTBhW+2GL4pDtgvMH8pMoY="; npmDepsHash = "sha256-dzBmtAhm0X4TsKW9nwKVyhvYlMLphzNtKkDvubWQFPk="; };
        versions."0.58.3" = { sha256 = "3GrE60n+EY5G50iRrbH7R74e+LQIy1M9+huZTp0ZTns="; npmDepsHash = "sha256-EC5fXZTtBTRkYXLg5p4xWE/ghi2iw30XwnSqJs/PT8I="; };
        mkPkg = { version ? (l.latest versions), ... }:
          let
            vData = versions.${version};
            src = pkgs.fetchFromGitHub {
              owner = "badlogic";
              repo = "pi-mono";
              tag = "v${version}";
              sha256 = "${vData.sha256}";
            };
          in
          pkgs.buildNpmPackage (finalAttrs: {
            pname = "pi-coding-agent";
            inherit version src;
            npmDepsHash = vData.npmDepsHash;
            npmWorkspace = "packages/coding-agent";

            # Skip native module rebuild for unneeded workspaces (e.g. canvas from web-ui)
            npmRebuildFlags = [ "--ignore-scripts" ];
            nativeBuildInputs = [
              pkgs.typescript-go
              pkgs.makeBinaryWrapper
            ];

            # Build workspace dependencies in order, then the coding-agent.
            # We invoke tsgo directly for workspace deps to skip pi-ai's
            # generate-models script which requires network access
            # (models.generated.ts is committed to the repo).
            buildPhase = ''
              runHook preBuild

              tsgo -p packages/ai/tsconfig.build.json
              tsgo -p packages/tui/tsconfig.build.json
              tsgo -p packages/agent/tsconfig.build.json
              npm run build --workspace=packages/coding-agent

              runHook postBuild
            '';

            # npm workspace symlinks in the output point into packages/ which
            # doesn't exist there. Replace runtime deps with built content and
            # delete the rest.
            postInstall = ''
              local nm="$out/lib/node_modules/pi-monorepo/node_modules"

              # Replace workspace deps needed at runtime with real copies
              for ws in @mariozechner/pi-ai:packages/ai \
                        @mariozechner/pi-agent-core:packages/agent \
                        @mariozechner/pi-tui:packages/tui; do
                IFS=: read -r pkg src <<< "$ws"
                rm "$nm/$pkg"
                cp -r "$src" "$nm/$pkg"
              done

              # Delete remaining workspace symlinks
              find "$nm" -type l -lname '*/packages/*' -delete

              # Clean up now-dangling .bin symlinks
              find "$nm/.bin" -xtype l -delete
            '';
            postFixup = "wrapProgram $out/bin/pi --prefix PATH : ${lib.makeBinPath [ pkgs.ripgrep ]}";

            doInstallCheck = true;
            nativeInstallCheckInputs = [
              pkgs.writableTmpDirAsHomeHook
              pkgs.pkgs.versionCheckHook
            ];
            versionCheckKeepEnvironment = [ "HOME" ];
            versionCheckProgram = "${placeholder "out"}/bin/pi";
            versionCheckProgramArg = "--version";

            # passthru.updateScript = nix-update-script { };
            passthru = { inherit versions mkPkg src version; };

            meta = {
              description = "Coding agent CLI with read, bash, edit, write tools and session management";
              homepage = "https://shittycodingagent.ai/";
              downloadPage = "https://www.npmjs.com/package/@mariozechner/pi-coding-agent";
              changelog = "https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/CHANGELOG.md";
              mainProgram = "pi";
            };
          });
      in
      mkPkg { };

    ownPkgs.pi-acp =
      let
        versions."0.0.24" = { sha256 = "83wNlyOYLkCa6BH/Edal54ovXbAmP745qzSjD+9ZOIE="; npmDepsHash = "sha256-GNn4XTeFDrmWQeuLSjRlz4nwP5T76HCwBLnIDFPcJkg="; };
        mkPkg = { version ? (l.latest versions), ... }:
          let
            vData = versions.${version} or (throw "Unsupported system or version: ${system} / ${version}");
            src = pkgs.fetchFromGitHub {
              owner = "svkozak";
              repo = "pi-acp";
              rev = "v${version}";
              sha256 = "${vData.sha256}";
            };
          in
          pkgs.buildNpmPackage rec {
            pname = "pi-acp";
            inherit version src;
            npmDepsHash = vData.npmDepsHash;
            passthru = { inherit versions mkPkg src; };
            meta = {
              description = "ACP support for Pi coding agent";
              mainProgram = "pi-acp";
            };
          };
      in
      mkPkg { };

    ownPkgs.claw-code =
      let
        versions."0.1.0_20260410" = { sha256 = "TqTrehnOyj/yExzADQTESmPU44ccwsVJM6pBd/DBHKA="; rev = "8aa1fa2cc931007f537854b1b0f0b61fdc986a50"; };
        # versions."0.1.0" = { sha256 = "ngAd6WjyvVAKotPY0Tl9ea8DpQuSGkrclZdyiGpnyDo="; rev = "be561bfdeb92fce7011938e748ee20051460d6a4"; };

        mkPkg = { version ? (l.latest versions), ... }:
          let
            vData = versions.${version} or (throw "Unsupported system or version: ${system} / ${version}");
            src = pkgs.fetchFromGitHub {
              owner = "ultraworkers";
              repo = "claw-code";
              rev = vData.rev;
              sha256 = vData.sha256;
            };
          in
          pkgs.rustPlatform.buildRustPackage {
            pname = "claw";
            version = version;
            src = "${src}/rust";
            cargoLock.lockFile = "${src}/Cargo.lock";
            doCheck = false; # Some tests are network-based, which won't work in a nix derivation
            passthru = { inherit versions mkPkg src; };
          };
      in
      mkPkg { };

    ownPkgs.poolside-cli =
      let
        versions."1.0.11".sha256 = "yaOiCpCU8IxXYEoQvj2KVmbCruPVITSqJwigKe+GDfM=";
        versions."1.0.0".sha256 = "/nYYNu9hZ6SvoV8lCkfNo0YtqjPtJgrIutEndWYVgIg=";

        mkPkg = { version ? (l.latest versions), ... }:
          if pkgs.stdenv.hostPlatform.system != "aarch64-darwin" then null
          else
          let
            # Mapping Nix system strings to the script's naming convention
            os = if pkgs.stdenv.isDarwin then "darwin" else "linux";
            arch = if pkgs.stdenv.isAarch64 then "arm64" else "amd64";
            src = pkgs.fetchurl {
              url = "https://downloads.poolside.ai/pool/v${version}/pool-${os}-${arch}.tar.gz";
              sha256 = versions.${version}.sha256;
            };
          in
          pkgs.stdenv.mkDerivation {
            pname = "pool";
            inherit version src;
            # We don't need to build anything, just unpack and install
            sourceRoot = ".";
            installPhase = ''
              mkdir -p $out/bin
              # The script says the binary inside is named pool-os-arch
              cp pool-${os}-${arch} $out/bin/pool
              chmod +x $out/bin/pool
            '';
            passthru = {
              inherit versions mkPkg src;
              latest_version_url = "https://downloads.poolside.ai/pool/pool-latest-version.txt";
            };
            meta = {
              description = "Poolside AI CLI";
              homepage = "https://poolside.ai";
              license = pkgs.lib.licenses.unfree; # Matches the EULA requirement in the script
            };
          };
      in
      mkPkg { };

    # NOTE: Exists in unstable nixpkgs
    # ownPkgs.qwen-code =
    #   let
    #     versions."0.14.3" = { sha256 = "sha256-RtZlwZev8zv3yMn+cCQpGvyPq/gyA39N4Iq0qFBTERY="; };
    #
    #     mkPkg = { version ? (l.latest versions), ... }:
    #       let vData = versions.${version} or (throw "Unsupported system or version: ${system} / ${version}");
    #       in pkgs.buildNpmPackage (finalAttrs: {
    #         inherit (pkgs) npmConfigHook;
    #         pname = "qwen-code";
    #         inherit version;
    #
    #         src = pkgs.fetchFromGitHub {
    #           owner = "QwenLM";
    #           repo = "qwen-code";
    #           tag = "v${finalAttrs.version}";
    #           sha256 = vData.sha256;
    #         };
    #
    #         npmDeps = pkgs.fetchNpmDepsWithPackuments {
    #           inherit (finalAttrs) src;
    #           name = "${finalAttrs.pname}-${finalAttrs.version}-npm-deps";
    #           hash = "sha256-13YseUyf7l3XwdsE4cGlXRbpK0zeADC6sGniKoEgGzk=";
    #           fetcherVersion = 2;
    #         };
    #         makeCacheWritable = true;
    #
    #         nativeBuildInputs = [ pkgs.pkg-config pkgs.git ] ++ l.optionals pkgs.stdenv.hostPlatform.isDarwin [
    #           pkgs.clang_20 # Works around node-addon-api constant expression issue with clang 21+ (keytar)
    #           pkgs.own.darwinOpenptyHook # Fixes node-pty openpty/forkpty build issue
    #         ];
    #
    #         buildInputs = [ pkgs.ripgrep pkgs.glib pkgs.libsecret ];
    #
    #         buildPhase = ''
    #           runHook preBuild
    #
    #           npm run generate
    #           # The CLI esbuild bundle resolves imports against workspace dist/ output,
    #           # so build the workspaces it depends on first (subset of upstream's
    #           # scripts/build.js buildOrder; we skip webui/sdk/vscode/plugin-example
    #           # as the bundled CLI does not pull them in).
    #           for ws in \
    #             packages/web-templates \
    #             packages/channels/base \
    #             packages/channels/telegram \
    #             packages/channels/weixin \
    #             packages/channels/dingtalk
    #           do
    #             npm run build --workspace=$ws
    #           done
    #           npm run bundle
    #
    #           runHook postBuild
    #         '';
    #
    #         installPhase = ''
    #           runHook preInstall
    #
    #           mkdir -p $out/bin $out/share/qwen-code
    #           cp -r dist/* $out/share/qwen-code/
    #           # Install production dependencies only
    #           npm prune --production
    #           cp -r node_modules $out/share/qwen-code/
    #           # Remove broken symlinks that cause issues in Nix environment
    #           find $out/share/qwen-code/node_modules -type l -delete || true
    #           patchShebangs $out/share/qwen-code
    #           ln -s $out/share/qwen-code/cli.js $out/bin/qwen
    #
    #           runHook postInstall
    #         '';
    #
    #         doInstallCheck = true;
    #         nativeInstallCheckInputs = [ pkgs.versionCheckHook ];
    #
    #         passthru.category = "AI Coding Agents";
    #
    #         meta = {
    #           description = "Command-line AI workflow tool for Qwen3-Coder models";
    #           homepage = "https://github.com/QwenLM/qwen-code";
    #           changelog = "https://github.com/QwenLM/qwen-code/releases";
    #           mainProgram = "qwen";
    #         };
    #       });
    #   in
    #   mkPkg { };

    # ownPkgs.hermes =
    #   let
    #     versions."".sha256 = "";
    #     mkPkg = { version ? (l.latest versions), ... }:
    #       let vData = versions.${version};
    #       in python311Packages.buildPythonApplication rec {
    #         pname = "hermes-agent";
    #         version = "0.1.0"; # Adjust as actual software versions dictate
    #
    #         src = fetchFromGitHub {
    #           owner = "NousResearch";
    #           repo = "hermes-agent";
    #           rev = "main"; # Replace with a specific pinned commit hash or tag
    #           hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; # Provide valid sha256 hash
    #         };
    #
    #         format = "pyproject";
    #
    #         nativeBuildInputs = [
    #           makeWrapper
    #           python311Packages.setuptools
    #           python311Packages.wheel
    #         ];
    #
    #         # Hard dependencies required by the agent's system tool integrations
    #         propagatedBuildInputs = [
    #           nodejs_22
    #           ripgrep
    #           ffmpeg
    #         ];
    #
    #         # Post-install injection guarantees that Hermes' runtime tools will always
    #         # locate Node, ripgrep, and ffmpeg cleanly without contaminating the global profile.
    #         postInstall = ''
    #           wrapProgram $out/bin/hermes \
    #             --prefix PATH : ${lib.makeBinPath [ nodejs_22 ripgrep ffmpeg ]}
    #         '';
    #
    #         meta = with lib; {
    #           description = "An open source AI agent by Nous Research";
    #           homepage = "https://github.com/NousResearch/hermes-agent";
    #           license = licenses.mit; # Verify upstream LICENSE metadata
    #           maintainers = [ ];
    #           platforms = platforms.unix;
    #         };
    #       };
    #   in
    #   mkPkg { };

    ownPkgs.hermes-agent =
      let
        versions."v2026.5.16" = { sha256 = "sha256-d9qhrTy45Q5UsmjapqMHOVi9e+gR9zE8Nq9Z0wObLmc="; };
        mkPkg = { version ? (l.latest versions), ... }:
          if pkgs.stdenv.hostPlatform.system != "aarch64-darwin" then null
          else
          let
            vData = versions.${version};
            hermes-src = pkgs.fetchFromGitHub {
              owner = "NousResearch";
              repo = "hermes-agent";
              rev = version;
              sha256 = vData.sha256;
            };
            hermes-flake = (builtins.getFlake "${unsafeDiscardStringContext hermes-src.outPath}");
            hermes-pkgs = hermes-flake.packages.${system}; # available: default, configKeys, fix-lockfiles, tui, web
            hermes-agent = hermes-pkgs.default or (throw "Package not found for ${system}");
          in
          hermes-agent // { passthru = (hermes-agent.passthru or { }) // { inherit versions mkPkg; src = hermes-src; }; };
      in
      mkPkg { };

    ownPkgs.oh-my-pi =
      let
        versions."v16.2.2".sha256 = "sha256:1qjzp0qz0q1pyvqw6glya8phllamw9dq58b2gj1y8wrs5a04bsag";
        versions."v15.7.3".sha256 = "052vncf0iy55b5hyfa7axf6xqx6aqafv82xab9m4hh2p6bjrsg12";
        mkPkg = { version ? (l.latest versions), ... }:
          if pkgs.stdenv.hostPlatform.system != "aarch64-darwin" then null
          else
          let
            vData = versions.${version};

            # Binary installation method
            binaryPackage = pkgs.stdenv.mkDerivation rec {
              pname = "omp-binary";
              inherit version;
              platform =
                if pkgs.stdenv.hostPlatform.isLinux then "linux"
                else if pkgs.stdenv.hostPlatform.isDarwin then "darwin"
                else throw "Unsupported platform";
              arch =
                if pkgs.stdenv.hostPlatform.isx86_64 then "x64"
                else if pkgs.stdenv.hostPlatform.isAarch64 then "arm64"
                else throw "Unsupported architecture";
              binaryName = "omp-${platform}-${arch}";
              src = fetchurl {
                url = "https://github.com/can1357/oh-my-pi/releases/download/${version}/${binaryName}";
                sha256 = vData.sha256;
              };

              dontUnpack = true;
              installPhase = ''
                mkdir -p $out/bin
                cp $src $out/bin/omp
                chmod +x $out/bin/omp
              '';
              passthru = { inherit versions mkPkg src; };
              meta = {
                description = "OMP Coding Agent (prebuilt binary)";
                homepage = "https://github.com/can1357/oh-my-pi";
                platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
              };
            };

            # Source installation method (requires Bun)
            # sourcePackage = stdenv.mkDerivation rec {
            #   pname = "omp-source";
            #   inherit version; # Specify actual version or commit hash
            #   src = pkgs.fetchFromGitHub {
            #     owner = "can1357";
            #     repo = "oh-my-pi";
            #     rev = "main"; # or specific commit hash
            #     hash = vData.sha256;
            #   };
            #
            #   nativeBuildInputs = [ bun git git-lfs makeWrapper ];
            #
            #   buildPhase = ''
            #     # Pull LFS files if needed
            #     git lfs pull
            #
            #     # Install the coding-agent package globally using bun
            #     bun install
            #     cd packages/coding-agent
            #     bun install
            #   '';
            #
            #   installPhase = ''
            #     mkdir -p $out/bin
            #
            #     # Create wrapper script that runs the bun module
            #     makeWrapper ${bun}/bin/bun $out/bin/omp \
            #       --add-flags "run $src/packages/coding-agent/index.js" \
            #       --set-default BUN_INSTALL "$HOME/.bun"
            #   '';
            #
            #   meta = with lib; {
            #     description = "OMP Coding Agent (installed from source via Bun)";
            #     homepage = "https://github.com/can1357/oh-my-pi";
            #     platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
            #   };
            # };

          in
          # Choose default method (binary is simpler with no runtime dependencies)
          binaryPackage;
      in
      mkPkg { };

    ownPkgs.mimo-code =
      let
        versions."0.1.9".sha256 = "sha256-Vhx5oVeji5419jbNdVh99ryZWKOKrL1lhzMchfiLyr0=";
        versions."0.1.3".sha256 = "sha256-dmoXFbZo0YAcVOgMA0OhYxLSe1p/sHSeXIdjxzafIN0=";
        versions."0.1.0".sha256 = "sha256-BO9FQS03ZR0pSYNKPubX/GnFp5BTkC0mc2qQ75mTavs=";
        mkPkg = { version ? (l.latest versions), avx2 ? false, ... }:
          if pkgs.stdenv.hostPlatform.system != "aarch64-darwin" then null
          else
          let
            vData = versions.${version} or (throw "Unsupported system/version: ${system} / ${version}");
            os =
              if pkgs.stdenv.hostPlatform.isLinux then "linux"
              else if pkgs.stdenv.hostPlatform.isDarwin then "darwin"
              else if pkgs.stdenv.hostPlatform.isWindows then "windows"
              else throw "Unsupported OS: ${pkgs.stdenv.hostPlatform.system}";
            arch = { x86_64 = "x64"; aarch64 = "arm64"; }.${pkgs.stdenv.hostPlatform.parsed.cpu.name}
              or (throw "Unsupported architecture: ${pkgs.stdenv.hostPlatform.parsed.cpu.name}");
            baselineSuffix = if arch == "x86_64" && !avx2 then "-baseline" else "";
            muslSuffix = if pkgs.stdenv.hostPlatform.isMusl then "-musl" else "";
            target = "${os}-${arch}${baselineSuffix}${muslSuffix}";
            extension = if pkgs.stdenv.hostPlatform.isLinux then "tar.gz" else "zip";
            src = pkgs.fetchzip {
              url = "https://github.com/XiaomiMiMo/MiMo-Code/releases/download/v${version}/mimocode-${target}.${extension}";
              sha256 = vData.sha256;
              stripRoot = false;
            };
          in
          pkgs.stdenv.mkDerivation {
            pname = "mimocode";
            inherit version src;
            installPhase = ''
              runHook preInstall
              mkdir -p $out/bin
              install -Dm755 $src/mimo $out/bin/mimo
              runHook postInstall
            '';
            passthru = { inherit versions mkPkg src; };
            meta = {
              description = "MiMo Code – CLI tool from Xiaomi's coding assistant";
              homepage = "https://mimo.xiaomi.com/coder/docs";
              platforms = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];
              mainProgram = "mimo";
            };
          };
      in
      mkPkg { };

    # Freebuff is distributed on npm as the package `freebuff`, but the npm
    # tarball only contains a thin launcher (index.js / launcher.js) that
    # downloads the real compiled CLI binary on first run and self-updates
    # thereafter. The launcher fetches:
    #   https://codebuff.com/api/releases/download/${version}/${fileName}
    # where ${version} is the npm wrapper version and fileName is one of
    # PLATFORM_TARGETS in launcher.js, e.g. `freebuff-darwin-arm64.tar.gz`.
    # Instead of shipping the launcher (which breaks Nix's purity), we fetch
    # the actual compiled binary directly, pinned per platform.
    #   https://github.com/CodebuffAI/codebuff-community/releases/download/freebuff-v${version}/
    ownPkgs.freebuff =
      let
        versions."0.0.142" = {
          darwin-arm64 = "1fiw69wazlj0v9kx75scs7c6wc467lmra0dyz1205qxj6vl404wm";
          darwin-x64 = "1jh1yffmj3n43l3ihsxjx7k15337xar0k1cn31322qms7qsm6mjd";
          linux-x64 = "10hxjqqn0zsf44pcgihf8fc8w7xvl967aznswxcidggb6xv7kraa";
          linux-arm64 = "1cbhnigv4afghm7ncv9xlxa08mija4529blrcg484zaqyxyfz4lf";
        };
        mkPkg = { version ? (l.latest versions), ... }:
          let
            vData = versions.${version} or (throw "Unsupported version: ${version}");
            # launcher.js PLATFORM_TARGETS naming: <os>-<arch> with
            # darwin/linux/win32 for os and x64/arm64 for arch. On
            # x86_64-linux we always fetch the AVX2 build (linux-x64); the
            # launcher would fall back to linux-x64-baseline on CPUs without
            # AVX2 (see mimo-code's `avx2` param if baseline support is needed).
            target = {
              aarch64-darwin = "darwin-arm64";
              x86_64-darwin = "darwin-x64";
              x86_64-linux = "linux-x64";
              aarch64-linux = "linux-arm64";
            }.${pkgs.stdenv.hostPlatform.system} or (throw "Unsupported system: ${pkgs.stdenv.hostPlatform.system}");
            sha256 = vData.${target} or (throw "No hash for ${target} in version ${version}");
            src = pkgs.fetchurl {
              url = "https://codebuff.com/api/releases/download/${version}/freebuff-${target}.tar.gz";
              inherit sha256;
            };
          in
          pkgs.stdenv.mkDerivation {
            pname = "freebuff";
            inherit version src;
            # The tarball unpacks to the freebuff binary + a tree-sitter.wasm
            # sidecar (used at runtime for code parsing), both at the top level
            # (no enclosing directory), so unpackPhase can't auto-detect a
            # sourceRoot.
            sourceRoot = ".";

            # freebuff creates ~/.config on startup, so give the check a
            # writable HOME (mirrors pi-coding-agent).
            doInstallCheck = true;
            nativeInstallCheckInputs = [
              pkgs.writableTmpDirAsHomeHook
              pkgs.pkgs.versionCheckHook
            ];
            versionCheckKeepEnvironment = [ "HOME" ];
            versionCheckProgram = "${placeholder "out"}/bin/freebuff";
            versionCheckProgramArg = "--version";

            installPhase = ''
              runHook preInstall
              mkdir -p $out/bin
              install -Dm755 freebuff $out/bin/freebuff
              install -Dm644 tree-sitter.wasm $out/bin/tree-sitter.wasm
              runHook postInstall
            '';
            passthru = { inherit versions mkPkg src; };
            meta = {
              description = "The world's strongest free coding agent";
              homepage = "https://codebuff.com";
              changelog = "https://github.com/CodebuffAI/codebuff-community/releases";
              downloadPage = "https://www.npmjs.com/package/freebuff";
              license = pkgs.lib.licenses.mit;
              mainProgram = "freebuff";
              platforms = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];
            };
          };
      in
      mkPkg { };

  };
}
