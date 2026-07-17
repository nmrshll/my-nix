{
  config.perSystem = { pkgs, l, ... }: {
    ownPkgs.cactus =
      let
        versions."2.0.1".sha256 = "sha256-UV5aquH0YqCpex9LDrDdmZmdebhUXKqqsM6X/d2vJIs=";
        mkPkg = { version ? l.latest versions, ... }: pkgs.stdenv.mkDerivation rec {
          pname = "cactus";
          inherit version;

          src = pkgs.fetchFromGitHub {
            owner = "cactus-compute";
            repo = "cactus";
            rev = "v${version}";
            sha256 = versions.${version}.sha256;
          };

          nativeBuildInputs = with pkgs; [ cmake python3 ];

          buildInputs = with pkgs; [ python3 libcurl ]
            ++ l.optionals stdenv.isDarwin (with darwin.apple_sdk.frameworks; [ CoreFoundation CoreServices ]);

          # The 'setup' script creates a Python venv. We replicate its essential logic.
          # The Cactus build uses a custom Python script ('python/build.py') that acts as the build system.
          buildPhase = ''
            runHook preBuild

            # The build script expects certain environment variables
            export CACTUS_SOURCE_DIR="$PWD"
            export BUILD_DIR="$PWD/build"

            # Run the Python build script to compile the core libraries and the Python bindings.
            # We explicitly build the 'python' target as per the instructions.
            python3 python/build.py --python

            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall

            mkdir -p $out/bin
            mkdir -p $out/lib
            mkdir -p $out/share/cactus

            # Install the main 'cactus' Python CLI script.
            # The entry point is typically the 'cactus' script generated in the build or source root.
            # We'll install the main python module and create a wrapper.
            cp -r python/cactus $out/lib/
            cp -r build/lib.*/cactus* $out/lib/ # Find the compiled shared libraries

            # Create a wrapper script that sets up PYTHONPATH and runs the CLI.
            # This mimics the behavior of 'source ./setup' which activates a venv.
            cat > $out/bin/cactus <<EOF
            #!${pkgs.stdenv.shell}
            export PYTHONPATH="$out/lib:\$PYTHONPATH"
            export CACTUS_INSTALL_DIR="$out/share/cactus"
            exec ${pkgs.python3}/bin/python3 -m cactus.cli "\$@"
            EOF
            chmod +x $out/bin/cactus

            # Install any necessary model conversion or utility scripts if they exist
            cp -r scripts $out/share/cactus/ 2>/dev/null || true

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
