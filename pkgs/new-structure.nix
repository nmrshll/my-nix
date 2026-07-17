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
            passthru = { inherit versions mkPkg; };
          };
      in
      mkPkg { };
  };
}
