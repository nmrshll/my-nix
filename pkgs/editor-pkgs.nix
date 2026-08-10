{
  config.perSystem = { pkgs, ... }: {

    ownPkgs.openspec =
      let
        versions."0.16.0".sha256 = "eBZvgjjEzhoO1Gt4B3lsgOvJ98uGq7gaqdXQ40i0SqY=";
        versions."0.15.0".sha256 = "Wb0m2ZRmOXNj6DOK9cyGYzFLNTQjLO+czDxzIHfADnY=";
        mkPkg = { version ? "0.16.0", ... }:
          let
            src = pkgs.fetchFromGitHub {
              owner = "Fission-AI";
              repo = "OpenSpec";
              rev = "v${version}";
              sha256 = versions.${version}.sha256;
            };
            pname = "openspec";
          in
          pkgs.buildNpmPackage rec {
            inherit version src pname;

            pnpmDeps = pkgs.pnpm.fetchDeps {
              inherit pname version src;
              fetcherVersion = 2;
              hash = "sha256-qqIdSF41gv4EDxEKP0sfpW1xW+3SMES9oGf2ru1lUnE=";
            };
            npmConfigHook = pkgs.pnpm.configHook;
            npmDeps = pnpmDeps;
            dontNpmPrune = true; # hangs forever on both Linux/darwin

            passthru = { inherit versions mkPkg src; };

            meta = with pkgs.lib; {
              description = "Spec-driven development framework for AI coding assistants";
              homepage = "https://github.com/Fission-AI/OpenSpec";
              license = licenses.mit;
              mainProgram = "openspec";
              platforms = platforms.all;
            };
          };
      in
      mkPkg { };

    # NOW PART OF NIXPKGS
    #  gemini-cli = { pkgs, lib, version ? "0.1.7", ... }:
    #     let
    #       versionDeps = {
    #         early-access = { hash = "sha256-KNnfo5hntQjvc377A39+QBemeJjMVDRnNuGY/93n3zc="; npmDepsHash = "sha256-/IAEcbER5cr6/9BFZYuV2j1jgA75eeFxaLXdh1T3bMA="; };
    #         "0.1.7" = { hash = "sha256-DAenod/w9BydYdYsOnuLj7kCQRcTnZ81tf4MhLUug6c="; npmDepsHash = "sha256-otogkSsKJ5j1BY00y4SRhL9pm7CK9nmzVisvGCDIMlU="; };
    #         "0.1.5" = { hash = "sha256-JgiK+8CtMrH5i4ohe+ipyYKogQCmUv5HTZgoKRNdnak="; npmDepsHash = "sha256-yoUAOo8OwUWG0gyI5AdwfRFzSZvSCd3HYzzpJRvdbiM="; };
    #       }.${version};
    #     in
    #     pkgs.buildNpmPackage {
    #       name = "gemini-cli";
    #       src = pkgs.fetchFromGitHub {
    #         owner = "google-gemini";
    #         repo = "gemini-cli";
    #         tag = if lib.hasPrefix "0." version then "v${version}" else "${version}";
    #         hash = versionDeps.hash;
    #       };
    #       npmDepsHash = versionDeps.npmDepsHash;
    #
    #       nativeBuildInputs = [ pkgs.typescript ];
    #       fixupPhase = ''
    #         runHook preFixup
    #         find $out -type l -exec test ! -e {} \; -delete
    #         runHook postFixup
    #       '';
    #       # nativeInstallCheckInputs = [
    #       #   versionCheckHook
    #       # ];
    #       doInstallCheck = true;
    #       versionCheckProgram = "${placeholder "out"}/bin/gemini";
    #       versionCheckProgramArg = "--version";
    #       meta = {
    #         description = "Open-source AI agent that brings the power of Gemini directly into your terminal";
    #         homepage = "https://github.com/google-gemini/gemini-cli";
    #         changelog = "https://github.com/google-gemini/gemini-cli/releases/tag/v${version}";
    #         license = lib.licenses.asl20;
    #         maintainers = with lib.maintainers; [
    #           ryota2357
    #         ];
    #         mainProgram = "gemini";
    #       };
    #     };

    ownPkgs.warp =
      let
        versions."0.2025.07.02.08.36.stable_02".sha256 = "sha256:06ys4d5p9fw0v0033ckxlnmlxpmkrydzm7c53bipvah1i9i5nxk1";
        versions."0.2025.06.25.08.12.stable_01".sha256 = "sha256:09n9frfds1a71zkbhydiv87ckb4frlai2c9qmp0zrx313x8i5y7g";
        mkPkg = { version ? "0.2025.07.02.08.36.stable_02", ... }:
          if pkgs.stdenv.hostPlatform.system != "aarch64-darwin" then null
          else
          let
            url = pkgs.lib.forSystem {
              aarch64-darwin = "https://releases.warp.dev/stable/v${version}/Warp.dmg";
            };
            sha256 = versions.${version}.sha256;
            src = pkgs.fetchurl { inherit url sha256; };
          in
          pkgs.lib.darwin.installDmg {
            inherit url version;
            sha256 = versions.${version}.sha256;
            appname = "Warp";
            meta = { description = "The Agentic Development Environment (it's actually a terminal)"; homepage = "https://warp.dev/"; };
            passthru = { inherit versions mkPkg src; };
          };
      in
      mkPkg { };

    ownPkgs.windsurf =
      let
        versions."1.2.4".sha256 = "sha256:1h05cvvk7qjsnws2y48aajabzgafhi0nmmk840f2x7cmjvqlfq1j";
        mkPkg = { version ? "1.2.4", ... }:
          if pkgs.stdenv.hostPlatform.system == "aarch64-darwin" then
            let
              url = pkgs.lib.forSystem {
                aarch64-darwin = "https://windsurf-stable.codeiumdata.com/darwin-arm64-dmg/stable/7f3de2bfc56b2f76334027e4d55dd26daa003035/Windsurf-darwin-arm64-${version}.dmg";
              };
              sha256 = versions.${version}.sha256;
              src = pkgs.fetchurl { inherit url sha256; };
            in
            pkgs.lib.darwin.installDmg {
              inherit url version;
              sha256 = versions.${version}.sha256;
              appname = "Windsurf";
              meta = { description = "Windsurf is an AI code editor."; homepage = "https://codeium.com/windsurf"; };
              passthru = { inherit versions mkPkg src; };
            }
          else null;
      in
      mkPkg { };

    ownPkgs.aide =
      let
        versions."1.96.4.25031".sha256 = "sha256:0xkllb9a7wp5wyadppsblskdwa87qrab8f6ymkfkbypd0fkl6x4q";
        mkPkg = { version ? "1.96.4.25031", ... }:
          if pkgs.stdenv.hostPlatform.system == "aarch64-darwin" then
            let
              url = pkgs.lib.forSystem {
                aarch64-darwin = "https://github.com/codestoryai/binaries/releases/download/${version}/Aide.arm64.${version}.dmg";
              };
              sha256 = versions.${version}.sha256;
              src = pkgs.fetchurl { inherit url sha256; };
            in
            pkgs.lib.darwin.installDmg {
              inherit url version;
              sha256 = versions.${version}.sha256;
              appname = "Aide";
              meta = {
                description = "Aide is an open-source AI code editor (fork of VSCode).";
                homepage = "https://aide.dev/";
              };
              passthru = { inherit versions mkPkg src; };
            }
          else null;
      in
      mkPkg { };

  };
}
