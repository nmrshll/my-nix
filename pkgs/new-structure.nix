with builtins; {
  config.perSystem = { pkgs, l, ... }: {
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
        mkPkg = { version ? (l.latest versions), ... }:
          let
            npmTarball = pkgs.fetchurl {
              url = "https://registry.npmjs.org/omniroute/-/omniroute-${version}.tgz";
              hash = versions.${version}.npmDistHash;
            };
          in
          pkgs.buildNpmPackage rec {
            pname = "omniroute";
            inherit version;
            npmDepsHash = versions.${version}.npmDepsHash;

            # Runtime: Node 24 (NODE_MODULE_VERSION 137). omniroute's engines
            # allow '>=22 <23 || >=24 <27'; build and run on nodejs_24 so
            # node-gyp-rebuilt native modules (e.g. better-sqlite3 12.x on
            # 3.8.48, a V8-ABI module) match the runtime ABI 137. (On 3.8.49,
            # better-sqlite3 13.x is N-API and version-independent.)
            nodejs = pkgs.nodejs_24;

            src = pkgs.fetchFromGitHub {
              owner = "diegosouzapw";
              repo = "OmniRoute";
              rev = "v${version}";
              sha256 = versions.${version}.sha256;
            };

            nativeBuildInputs = with pkgs; [
              python3
              pkg-config
              nodejs_24
              makeWrapper
            ];

            buildInputs = with pkgs; [
              glib
              nss
              libsecret
            ];

            npmFlags = [ "--ignore-scripts" ];

            # Skip the heavy Next.js build (next build needs Google Fonts fetch
            # which fails in Nix sandbox). We inject the prebuilt dist/ from
            # the npm tarball in installPhase instead.
            dontNpmBuild = true;

            installPhase = ''
              runHook preInstall

              # Compile native modules from source using node-gyp directly.
              # npm rebuild / prebuild-install may fetch a CI binary compiled
              # against a different V8 than runtime Node 24 — force source
              # compilation so the binary matches the Nix-built Node.js.
              (cd node_modules/better-sqlite3 && node ../.bin/node-gyp rebuild 2>&1)
              (cd node_modules/wreq-js && node ../.bin/node-gyp rebuild 2>&1) || true

              # Inject prebuilt dist/ from npm tarball — this avoids running
              # the Next.js build (next/font/google fetches fail in sandbox)
              tar xzf ${npmTarball} --strip=1 -C . package/dist/

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
              # the node-gyp build compiled above (against
              # ${pkgs.nodejs_24.version}). This matters for V8-ABI versions
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
                makeWrapper ${pkgs.nodejs_24}/bin/node \
                  $out/bin/$bin \
                  --add-flags "$out/lib/node_modules/omniroute/bin/$bin.mjs" \
                  --set NODE_PATH "$out/lib/node_modules" \
                  --prefix PATH : ${pkgs.nodejs_24}/bin
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

  };
}
