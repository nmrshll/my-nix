{
  pkgDefs.openspec = rec {
    versions = {
      aarch64-darwin."0.16.0".sha256 = "eBZvgjjEzhoO1Gt4B3lsgOvJ98uGq7gaqdXQ40i0SqY=";
      aarch64-darwin."0.15.0".sha256 = "Wb0m2ZRmOXNj6DOK9cyGYzFLNTQjLO+czDxzIHfADnY=";
    };
    mkPkg = { pkgs, version ? "0.16.0", system ? pkgs.stdenv.hostPlatform.system, ... }: pkgs.buildNpmPackage rec {
      inherit version;
      pname = "openspec";

      src = pkgs.fetchFromGitHub {
        owner = "Fission-AI";
        repo = "OpenSpec";
        rev = "v${version}";
        sha256 = versions.${system}.${version}.sha256;
      };
      pnpmDeps = pkgs.pnpm.fetchDeps {
        inherit pname version src;
        fetcherVersion = 2;
        hash = "sha256-qqIdSF41gv4EDxEKP0sfpW1xW+3SMES9oGf2ru1lUnE=";
      };
      npmConfigHook = pkgs.pnpm.configHook;
      npmDeps = pnpmDeps;
      dontNpmPrune = true; # hangs forever on both Linux/darwin

      meta = with pkgs.lib; {
        description = "Spec-driven development framework for AI coding assistants";
        homepage = "https://github.com/Fission-AI/OpenSpec";
        license = licenses.mit;
        mainProgram = "openspec";
        platforms = platforms.all;
      };
    };
  };

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

  pkgDefs.warp = rec {
    versions = {
      aarch64-darwin."0.2025.07.02.08.36.stable_02".sha256 = "sha256:06ys4d5p9fw0v0033ckxlnmlxpmkrydzm7c53bipvah1i9i5nxk1";
      aarch64-darwin."0.2025.06.25.08.12.stable_01".sha256 = "sha256:09n9frfds1a71zkbhydiv87ckb4frlai2c9qmp0zrx313x8i5y7g";
    };
    mkPkg = { pkgs, l, version ? "0.2025.07.02.08.36.stable_02", system ? pkgs.stdenv.hostPlatform.system, ... }:
      let
        url = pkgs.lib.forSystem {
          aarch64-darwin = "https://releases.warp.dev/stable/v${version}/Warp.dmg";
        };
      in
      pkgs.lib.darwin.installDmg {
        inherit url version;
        sha256 = versions.${system}.${version}.sha256;
        appname = "Warp";
        meta = { description = "The Agentic Development Environment (it's actually a terminal)"; homepage = "https://warp.dev/"; };
      };
  };

  pkgDefs.windsurf = rec {
    versions = {
      aarch64-darwin."1.2.4".sha256 = "sha256:1h05cvvk7qjsnws2y48aajabzgafhi0nmmk840f2x7cmjvqlfq1j";
      x86_64-linux."1.2.4".sha256 = "sha256:0pqy587d1kmdzz6jax2n56vz6av5jplmr3g3knasylw5sz202a06";
    };
    mkPkg = { pkgs, l, version ? "1.2.4", system ? pkgs.stdenv.hostPlatform.system, ... }:
      # let
      #   # url = pkgs.lib.forSystem {
      #   #   aarch64-darwin = "https://windsurf-stable.codeiumdata.com/darwin-arm64-dmg/stable/7f3de2bfc56b2f76334027e4d55dd26daa003035/Windsurf-darwin-arm64-${version}.dmg";
      #   #   # x86_64-linux = "https://windsurf-stable.codeiumdata.com/linux-x64/stable/${hash}/Windsurf-linux-x64-${version}.tar.gz"
      #   # };
      #   # src = pkgs.lib.forSystem {
      #   #   aarch64-darwin = { inherit url; sha = "sha256:1h05cvvk7qjsnws2y48aajabzgafhi0nmmk840f2x7cmjvqlfq1j"; };
      #   #   x86_64-linux = { inherit url; sha = "sha256:0pqy587d1kmdzz6jax2n56vz6av5jplmr3g3knasylw5sz202a06"; };
      #   # };
      # in
      if pkgs.stdenv.hostPlatform.system == "aarch64-darwin" then
        (pkgs.lib.darwin.installDmg {
          url = pkgs.lib.forSystem {
            aarch64-darwin = "https://windsurf-stable.codeiumdata.com/darwin-arm64-dmg/stable/7f3de2bfc56b2f76334027e4d55dd26daa003035/Windsurf-darwin-arm64-${version}.dmg";
            # x86_64-linux = "https://windsurf-stable.codeiumdata.com/linux-x64/stable/${hash}/Windsurf-linux-x64-${version}.tar.gz"
          };
          inherit version;
          sha256 = versions.${system}.${version}.sha256;
          appname = "Windsurf";
          meta = { description = "Windsurf is an AI code editor."; homepage = "https://codeium.com/windsurf"; };
        }) else null;
  };

  pkgDefs.aide = rec {
    versions = {
      aarch64-darwin."1.96.4.25031".sha256 = "sha256:0xkllb9a7wp5wyadppsblskdwa87qrab8f6ymkfkbypd0fkl6x4q";
      x86_64-linux."1.96.4.25031".sha256 = "sha256:0pqy587d1kmdzz6jax2n56vz6av5jplmr3g3knasylw5sz202a06";
    };
    mkPkg = { pkgs, l, version ? "1.96.4.25031", system ? pkgs.stdenv.hostPlatform.system, ... }:
      let
        url = pkgs.lib.forSystem {
          aarch64-darwin = "https://github.com/codestoryai/binaries/releases/download/${version}/Aide.arm64.${version}.dmg";
          # x86_64-linux = "https://windsurf-stable.codeiumdata.com/linux-x64/stable/${hash}/Windsurf-linux-x64-${version}.tar.gz"
        };
        # src = pkgs.lib.forSystem
        #   {
        #     aarch64-darwin = { inherit url; sha = "sha256:0xkllb9a7wp5wyadppsblskdwa87qrab8f6ymkfkbypd0fkl6x4q"; };
        #     x86_64-linux = { inherit url; sha = "sha256:0pqy587d1kmdzz6jax2n56vz6av5jplmr3g3knasylw5sz202a06"; };
        #   };
      in
      if pkgs.stdenv.hostPlatform.system == "aarch64-darwin" then
        (pkgs.lib.darwin.installDmg {
          inherit url version;
          sha256 = versions.${system}.${version}.sha256;
          appname = "Aide";
          meta = {
            description = "Aide is an open-source AI code editor (fork of VSCode).";
            homepage = "https://aide.dev/";
          };
        }) else null;
  };

}
