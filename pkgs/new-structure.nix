with builtins; {
  config.perSystem = { pkgs, l, ... }: {
    ownPkgs.cactus =
      let
        versions."2.0.1".sha256 = "sha256-UV5aquH0YqCpex9LDrDdmZmdebhUXKqqsM6X/d2vJIs=";
        mkPkg = { version ? (l.latest versions), ... }:
          let
            # Python environment with all required packages
            pythonEnv = pkgs.python3.withPackages (ps: with ps; [
              # Core dependencies from requirements.txt
              numpy
              torch
              transformers
              # Add other packages as needed
            ]);

            # Find Python site-packages directory
            sitePackages = "${pythonEnv}/${pkgs.python3.sitePackages}";
          in
          pkgs.stdenv.mkDerivation {
            pname = "cactus";
            inherit version;

            src = pkgs.fetchFromGitHub {
              owner = "cactus-compute";
              repo = "cactus";
              rev = "v${version}";
              sha256 = versions.${version}.sha256;
            };

            nativeBuildInputs = [ pkgs.cmake pkgs.python3 pkgs.git ];

            buildInputs = [ pythonEnv ];
            # ++ lib.optionals stdenv.isDarwin (with darwin.apple_sdk.frameworks; [ CoreFoundation CoreServices ]);

            # Configure git hooks (mimics Step 1 of setup)
            patchPhase = ''
              runHook prePatch
              # Setup git hooks path (but in Nix build, git isn't initialized)
              # We'll skip this since it's for development, not package building
              runHook postPatch
            '';

            buildPhase = ''
              runHook preBuild

              # Step 2 & 3 of setup: we skip venv creation since we use Nix's Python
              # but we need to set up PYTHONPATH for the build
              export PYTHONPATH="$PWD/python:${sitePackages}:$PYTHONPATH"

              # Step 4: Install cactus CLI as an editable package
              # Instead of pip install -e, we'll copy the source and create a proper wrapper
              mkdir -p $out/lib/python
              cp -r python/cactus $out/lib/python/

              # Build the C++ components (cactus build --python equivalent)
              python3 python/build.py --python

              # The build script outputs to build/ directory
              # We need to copy the shared libraries too
              if [ -d build ]; then
                cp -r build/lib*/*.so $out/lib/ 2>/dev/null || true
                cp -r build/lib*/*.dylib $out/lib/ 2>/dev/null || true
              fi

              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall
              mkdir -p $out/bin
              mkdir -p $out/lib/python
              # Create a wrapper script that mimics the functionality
              # of the installed CLI after "pip install -e"
              cat > $out/bin/cactus <<EOF
              #!${pkgs.stdenv.shell}
              export PYTHONPATH="$out/lib/python:${sitePackages}:\$PYTHONPATH"
              export CACTUS_SOURCE_DIR="$out/share/cactus"
              export CACTUS_ROOT="$out"
              exec ${pythonEnv}/bin/python3 -m cactus.cli "\$@"
              EOF
              chmod +x $out/bin/cactus

              # Copy any required data files
              mkdir -p $out/share/cactus
              cp -r scripts $out/share/cactus/ 2>/dev/null || true
              cp -r weights $out/share/cactus/ 2>/dev/null || true
              runHook postInstall
            '';

            meta = {
              description = "Tiny AI for tiny devices - A hybrid edge-cloud AI engine";
              homepage = "https://github.com/cactus-compute/cactus";
              platforms = l.platforms.unix;
            };
            passthru = { inherit versions mkPkg; };
          };
      in
      mkPkg { };


  };
}
