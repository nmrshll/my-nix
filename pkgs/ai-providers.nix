# AI infrastructure & inference engines: packages that run, serve, or route AI,
# plus AI-powered tools (as opposed to ai-agents.nix, which holds AI coding agents).
with builtins; {
  config.perSystem = { pkgs, l, lib, system, ... }: {

    ownPkgs.cactus =
      let
        versions."2.0.1".sha256 = "sha256-rZvgjWa5Qqss9qxVi3LR8pQykPxh9MylllFFiYpSd5o=";
        mkPkg = { version ? (l.latest versions), ... }:
          let
            pythonEnv = pkgs.python3.withPackages (ps: with ps; [
              numpy
              torch
              transformers
              scipy
              pillow
              huggingface-hub
              fastapi
              uvicorn
              python-multipart
              httpx
              setuptools
              wheel
            ]);
            src = pkgs.fetchFromGitHub {
              owner = "cactus-compute";
              repo = "cactus";
              rev = "v${version}";
              sha256 = versions.${version}.sha256;
            };
          in
          pkgs.stdenv.mkDerivation {
            pname = "cactus";
            inherit version src;

            nativeBuildInputs = [ pythonEnv pkgs.python3.pkgs.pip ];

            buildPhase = ''
              runHook preBuild
              cd python
              pip install . --no-deps --no-build-isolation --prefix=$out
              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall
              mkdir -p $out/bin
              cat > $out/bin/cactus <<WRAPPER
              #!${pkgs.stdenv.shell}
              export PYTHONPATH="$out/lib/python${pkgs.python3.pythonVersion}/site-packages:${pythonEnv}/${pkgs.python3.sitePackages}:\$PYTHONPATH"
              exec ${pythonEnv}/bin/python3 -c "from cactus.cli import main; main()" "\$@"
              WRAPPER
              chmod +x $out/bin/cactus
              runHook postInstall
            '';

            meta = {
              description = "Tiny AI for tiny devices - A hybrid edge-cloud AI engine";
              homepage = "https://github.com/cactus-compute/cactus";
              platforms = l.platforms.unix;
            };
            passthru = { inherit versions mkPkg src; };
          };
      in
      mkPkg { };


    ownPkgs.omniroute =
      let
        versions."3.8.48" = {
          sha256 = "sha256-lqw0M0mHqsMWWvz7X+3sO+FbaVmJ9bL9FBgB5HxsUBI=";
          npmDepsHash = "sha256-pVq6fpF0d1FeJmZm4rGcV0wjpoFcDmlhY254Muo00qI=";
          npmDistHash = "sha256-sJXyyGId+zdaSRDtYkMOhz7abuuRm1ZU1AeyHFk4MlU=";
        };
        versions."3.8.49" = {
          sha256 = "sha256-nRLziV4NWPoa0ev57DV7jmAvLpL/1MP1EMZO2/drrTU=";
          npmDepsHash = "sha256-R0u93MLUUWC8xFgq4S0Aj/7wg4pygTKwxP/eWkWMgCw=";
          npmDistHash = "sha256-fcGsAxOdv1ZSwt24eHJu97lyRATKBw8rYeFvGTRhxYs=";
        };
        versions."3.8.50" = {
          sha256 = "sha256-Cjtt2jv/65tkz23QdDkj53iX3X54U4PgNXJ0OYD/eLI=";
          npmDepsHash = "sha256-nFa72z6Xwbbbgb0ub0b5XeeYkiSZalpFhQL5qn7PJV4=";
          rev = "release/v3.8.50";
        };
        mkPkg = { version ? (l.latest versions), ... }:
          let
            vInfo = versions.${version};
            hasDistTarball = vInfo ? npmDistHash;
            npmTarball = if hasDistTarball then pkgs.fetchurl {
              url = "https://registry.npmjs.org/omniroute/-/omniroute-${version}.tgz";
              hash = vInfo.npmDistHash;
            } else null;
          in
          pkgs.buildNpmPackage rec {
            pname = "omniroute";
            inherit version;
            npmDepsHash = vInfo.npmDepsHash;
            # Dist-tarball versions (3.8.48/3.8.49) use the default fetcher v1
            # (their npmDepsHash was computed with it); source builds without a
            # dist tarball (3.8.50) need v2 for packument caching. Passing null
            # breaks nixpkgs 26.05's buildNpmPackage, which sets
            # NIX_NPM_FETCHER_VERSION unconditionally.
            npmDepsFetcherVersion = if hasDistTarball then 1 else 2;

            # Runtime: Node 24 (NODE_MODULE_VERSION 137). omniroute's engines
            # allow '>=22 <23 || >=24 <27'; build and run on nodejs_24 so
            # node-gyp-rebuilt native modules (e.g. better-sqlite3 12.x on
            # 3.8.48, a V8-ABI module) match the runtime ABI 137. (On 3.8.49,
            # better-sqlite3 13.x is N-API and version-independent.)
            nodejs = pkgs.nodejs_24;

            src = pkgs.fetchFromGitHub {
              owner = "diegosouzapw";
              repo = "OmniRoute";
              rev = vInfo.rev or "v${version}";
              sha256 = vInfo.sha256;
            };

            nativeBuildInputs = [
              pkgs.python3
              pkgs.pkg-config
              pkgs.makeWrapper
            ];

            buildInputs = with pkgs; [
              glib
              nss
              libsecret
            ];

            npmFlags = [ "--ignore-scripts" ];

            # When a dist tarball is available (npmDistHash present), skip
            # the heavy Next.js build and inject the prebuilt dist/ from the
            # tarball in installPhase.  When no tarball exists yet (new version
            # not published to npm), build from source with Google Fonts
            # download disabled (they fail in the Nix sandbox).
            dontNpmBuild = hasDistTarball;

            preBuild = pkgs.lib.optionalString (!hasDistTarball) ''
              export NEXT_FONT_GOOGLE_DOWNLOADS_DISABLED=1
            '';

            installPhase = ''
              runHook preInstall

              # Compile native modules from source using node-gyp directly.
              # npm rebuild / prebuild-install may fetch a CI binary compiled
              # against a different V8 than runtime Node 24 — force source
              # compilation so the binary matches the Nix-built Node.js.
              (cd node_modules/better-sqlite3 && node ../.bin/node-gyp rebuild 2>&1)
              (cd node_modules/wreq-js && node ../.bin/node-gyp rebuild 2>&1) || true

              ${if hasDistTarball then ''
              # Inject prebuilt dist/ from npm tarball — this avoids running
              # the Next.js build (next/font/google fetches fail in sandbox)
              tar xzf ${npmTarball} --strip=1 -C . package/dist/
              '' else ''
              # Source build: next build produced .build/next/standalone
              cp -r .build/next/standalone dist
              ''}

              # Replace stub modules in dist/node_modules/ with full copies
              # from root node_modules/. The Next.js standalone bundles only
              # a subset; packages like ioredis, undici, etc. end up as
              # stubs (package.json only). Syncing all stubs avoids runtime
              # ERR_MODULE_NOT_FOUND from dynamic imports (MCP, etc.).
              for mod in $(cd "$PWD/dist/node_modules" && find . -maxdepth 1 -mindepth 1 -type d -exec basename {} \; && find . -maxdepth 2 -mindepth 2 -path './@*/*' -type d 2>/dev/null | sed 's|^\./||'); do
                rootDir="$PWD/node_modules/$mod"
                distDir="$PWD/dist/node_modules/$mod"
                if [ -d "$rootDir" ] && [ -d "$distDir" ]; then
                  distFiles=$(find "$distDir" -maxdepth 1 -type f 2>/dev/null | wc -l)
                  if [ "$distFiles" -le 1 ]; then
                    echo "[nix] Syncing stub module: $mod"
                    rm -rf "$distDir"
                    cp -r "$rootDir" "$distDir"
                  fi
                fi
              done

              # Safeguard: make sure the dist copy of better-sqlite3 carries
              # the node-gyp build compiled above (against ${nodejs.version}).
              # This matters for V8-ABI versions
              # (better-sqlite3 12.x on 3.8.48), where the tarball's prebuilt
              # could target a different ABI; on 3.8.49 (13.x, N-API) the
              # copy is a no-op.
              if [ -d dist/node_modules/better-sqlite3 ]; then
                rm -rf dist/node_modules/better-sqlite3/build
                cp -r node_modules/better-sqlite3/build dist/node_modules/better-sqlite3/build
              fi

              # Copy the package to $out
              mkdir -p $out/lib/node_modules/omniroute
              cp -r . $out/lib/node_modules/omniroute/

              # Create bin wrappers
              mkdir -p $out/bin
              for bin in omniroute omniroute-reset-password; do
                makeWrapper ${nodejs}/bin/node \
                  $out/bin/$bin \
                  --add-flags "$out/lib/node_modules/omniroute/bin/$bin.mjs" \
                  --set NODE_PATH "$out/lib/node_modules" \
                  --prefix PATH : ${nodejs}/bin
              done

              runHook postInstall
            '';

            passthru = { inherit versions mkPkg; };

            meta = with pkgs.lib; {
              description = "Unified AI router with 160+ providers, RTK+Caveman compression, auto fallback, MCP/A2A";
              homepage = "https://github.com/diegosouzapw/OmniRoute";
              license = licenses.mit;
              mainProgram = "omniroute";
              platforms = platforms.unix;
            };
          };
      in
      mkPkg { };

    ownPkgs.omlx =
      let
        versions."0.2.24-macos15-sequoia" = { sha256 = "07g4wqydlczcqhx7ahvdrsp1ygxnm8dqmqlifvq2xx071p3d11iz"; number = "0.2.24"; };
        # versions."0.3.0rc1-macos15-sequoia" = { sha256 = "1q1lndzayf7j7h658gigg3107hh8qbkvwwiibqazywgxjjggfrc6"; number = "0.3.0rc1"; };
        mkPkg = { version ? (l.latest versions), ... }:
          if pkgs.stdenv.hostPlatform.system != "aarch64-darwin" then null
          else
            let
              versionInfo = versions.${version};
              url = "https://github.com/jundot/omlx/releases/download/v${versionInfo.number}/oMLX-${version}.dmg";
              src = pkgs.fetchurl { inherit url; sha256 = versionInfo.sha256; };
              dotApp = pkgs.lib.darwin.installDmg {
                inherit url;
                inherit version;
                sha256 = versionInfo.sha256;
                appname = "oMLX";
                meta = { description = "Local AI inference for Apple MLX."; homepage = "https://github.com/jundot/omlx"; };
              };
            in
            (pkgs.symlinkJoin {
              name = "omlx-${version}";
              paths = [ dotApp ];
              nativeBuildInputs = [ pkgs.makeWrapper ];
              postBuild = ''
                mkdir -p $out/bin

                # Define the path to the actual binary inside the app bundle
                APP_BIN="$out/Applications/oMLX.app/Contents/MacOS/omlx-cli"

                # Create a wrapper instead of a symlink.
                # This prefixes the PATH with the location of python3 and the app's internal MacOS folder
                # so that the script can find 'python3' and its sibling files.
                makeWrapper "$APP_BIN" "$out/bin/omlx" \
                  --prefix PATH : "${lib.makeBinPath [ pkgs.python3 ]}:$(dirname "$APP_BIN")"
              '';
            }) // { passthru = { inherit versions mkPkg src; }; };
      in
      mkPkg { };

    ownPkgs.handy =
      let
        versions."0.9.4".aarch64-darwin.sha256 = "sha256:0xi4wxszpb6scpcadns2fxhhxr405i9v2pi5nsnc6kg4zm6fry5v";
        versions."0.8.2".aarch64-darwin.sha256 = "1a2156h5sfnr5mydps7b6r701nqzkpmhb8m1wpizdppchy563vnp";
        versions."0.7.11".aarch64-darwin.sha256 = "0ill0rsmvxy81yhgdp4wk39nvb60r2qhcv12fywb1z5ppab4d1za";
        versions."0.7.9".aarch64-darwin.sha256 = "0hsrklmphdd14za0d7n1c96xbw9g3n6bfg1jn7jvjwysh17affbv";
        versions."0.6.5".aarch64-darwin.sha256 = "1vmrbj35cjrxlqq8d2a12chhmg41z2fb3dvp51dm3hg795sr8rwb";
        versions."0.6.4" = {
          x86_64-linux.sha256 = "tItYRJL0e5mQMRufWBh8zcqJPDkbLf98jW9yjB50Z4Q=";
          x86_64-darwin.sha256 = "yTRNaH/P5nMKT2oYk9b9oRH8s6PAi30Vtfw9TgE7WnE=";
          aarch64-darwin.sha256 = "9trjwzQIqM5Okvnj2GAlBxKajyBiM0HbNmw4JukUsF4=";
        };
        mkPkg = { version ? (l.latest (l.filterAttrs (name: v: v ? "${system}") versions)), ... }:
          let
            arch = elemAt (split "-" system) 0;
            url =
              if pkgs.stdenv.isDarwin then "https://github.com/cjpais/Handy/releases/download/v${version}/Handy_${arch}.app.tar.gz"
              else "https://github.com/cjpais/Handy/releases/download/v${version}/Handy_${version}_amd64.deb";
            src = fetchurl {
              inherit url; sha256 = versions.${version}.${system}.sha256;
            };
            pname = "handy";

          in
          pkgs.stdenv.mkDerivation {
            inherit pname version src;

            nativeBuildInputs =
              pkgs.lib.optionals pkgs.stdenv.isLinux [
                pkgs.autoPatchelfHook
                pkgs.dpkg
                pkgs.copyDesktopItems
              ]
              ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
                pkgs.makeWrapper
              ];

            buildInputs = pkgs.lib.optionals pkgs.stdenv.isLinux [
              pkgs.gcc-unwrapped.lib
              pkgs.alsa-lib
              pkgs.cairo
              pkgs.gdk-pixbuf
              pkgs.glib
              pkgs.gtk3
              pkgs.libsoup_3
              pkgs.openssl
              pkgs.vulkan-loader
              pkgs.webkitgtk_4_1
            ];

            runtimeDependencies = pkgs.lib.optionals pkgs.stdenv.isLinux [
              pkgs.stdenv.cc.cc.lib
              pkgs.libayatana-appindicator
            ];

            desktopItems = pkgs.lib.optionals pkgs.stdenv.isLinux [
              (pkgs.makeDesktopItem {
                name = "handy";
                desktopName = "Handy";
                comment = "Fast and accurate local transcription app";
                exec = "handy";
                icon = "handy";
                categories = [ "Audio" "AudioVideo" "Utility" ];
                startupNotify = true;
              })
            ];

            unpackPhase =
              if pkgs.stdenv.isLinux then ''
                runHook preUnpack
                dpkg -x $src .
                runHook postUnpack
              ''
              else ''
                runHook preUnpack
                mkdir -p ./unpacked
                tar -xzf $src -C ./unpacked
                runHook postUnpack
              '';
            installPhase =
              if pkgs.stdenv.isLinux then ''
                runHook preInstall
                # Install the binary
                install -Dm755 usr/bin/handy $out/bin/handy
                # Install resources
                mkdir -p $out/lib/Handy/resources
                cp -r usr/lib/Handy/resources/* $out/lib/Handy/resources/
                # Install icons
                mkdir -p $out/share/icons/hicolor
                if [ -d usr/share/icons/hicolor ]; then
                  cp -r usr/share/icons/hicolor/* $out/share/icons/hicolor/
                fi
                runHook postInstall
              ''
              else ''
                runHook preInstall
                mkdir -p $out/Applications
                cp -r ./unpacked/Handy.app $out/Applications/
                # Create a wrapper script in bin
                mkdir -p $out/bin
                makeWrapper $out/Applications/Handy.app/Contents/MacOS/Handy $out/bin/handy
                runHook postInstall
              '';

            passthru = { inherit versions mkPkg src; };

            meta = with pkgs.lib; {
              description = "Fast and accurate local transcription app using AI models";
              homepage = "https://handy.computer/";
              changelog = "https://github.com/cjpais/Handy/releases/tag/v${version}";
              sourceProvenance = with sourceTypes; [ binaryNativeCode ];
              maintainers = [ ];
              platforms = [ "x86_64-linux" "x86_64-darwin" "aarch64-darwin" ];
              mainProgram = "handy";
            };
          };
      in
      mkPkg { };

    # TODO use python314Packages.mlx-lm -> dep unzip is broken
    # TODO below beautifulsoup is also broken
    # ownPkgs.mlx-lm =
    #   let
    #     versions."0.31.1".sha256 = "5KGXLpzGEmyay6HvEM8qOe5zUmFRo1VbZKzOQvfr7Sk=";
    #     versions."0.31.0".sha256 = "1YZt2HtHyhP4h3WOcSytbN0sN2x58OYAmQtoxisNt1o=";
    #     mkPkg = { version ? (l.latest versions), ... }:
    #       let
    #         versionInfo = versions.${version};
    #         pyPkgs = pkgs.python314Packages;
    #       in
    #       pyPkgs.buildPythonApplication rec {
    #         pname = "mlx-lm";
    #         inherit version;
    #         pyproject = true;
    #
    #         src = pkgs.fetchFromGitHub {
    #           owner = "ml-explore";
    #           repo = "mlx-lm";
    #           tag = "v${version}";
    #           hash = "sha256-${versionInfo.sha256}";
    #         };
    #
    #         build-system = [ pyPkgs.setuptools ];
    #         dependencies = [
    #           pyPkgs.mlx
    #           pyPkgs.transformers
    #           pyPkgs.protobuf
    #           pyPkgs.jinja2
    #         ];
    #         pythonRelaxDeps = [ "transformers" ];
    #         doCheck = false; # Tests require additional dependencies
    #
    #         meta = {
    #           description = "LLM access to models using MLX";
    #           homepage = "https://github.com/ml-explore/mlx-lm";
    #           # license = lib.licenses.mit;
    #           # maintainers = with lib.maintainers; [ jwiegley ];
    #         };
    #       };
    #   in
    #   mkPkg { };

    # TEMP BROKEN
    # ownPkgs.anemll =
    #   let
    #     versions."0.3.5".sha256 = "";
    #     mkPkg = { version ? (l.latest versions), ... }:
    #       pkgs.python3.pkgs.buildPythonApplication rec {
    #         pname = "anemll";
    #         version = "0.3.5";
    #         pyproject = true;
    #         nativeBuildInputs = with pkgs.python3.pkgs; [ setuptools ];
    #
    #         src = pkgs.fetchFromGitHub {
    #           owner = "Anemll";
    #           repo = "Anemll";
    #           rev = "refs/tags/v${version}";
    #           hash = "sha256-${versions.${version}.sha256}";
    #         };
    #
    #         propagatedBuildInputs = with pkgs.python3.pkgs; [ coremltools numpy tqdm transformers torch scikit-learn sentencepiece psutil ];
    #         nativeCheckInputs = with pkgs.python3.pkgs; [ pytest pytest-cov ];
    #         meta = {
    #           description = "Open-source pipeline for accelerating LLMs on Apple Neural Engine (ANE)";
    #           homepage = "https://anemll.com";
    #           documentation = "https://anemll.com/docs";
    #           license = lib.licenses.mit;
    #           maintainers = [ ];
    #           platforms = lib.platforms.darwin; # macOS only (requires Apple Neural Engine)
    #           broken = !pkgs.stdenv.isDarwin;
    #         };
    #       };
    #   in
    #   mkPkg { };

  };
}
