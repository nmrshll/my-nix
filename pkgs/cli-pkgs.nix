with builtins; {

  pkgDefs.atlassian-cli = rec {
    versions = {
      aarch64-darwin."1.2.5-stable".sha256 = "sha256:1xij39cv16af7cs5pwyg3fb56kdmf2kvvrg0hizs4m0cly3pv00a";
    };
    mkPkg = { pkgs, version ? "1.2.5-stable", system ? pkgs.stdenv.hostPlatform.system, ... }:
      let
        sysShort = { aarch64-darwin = "darwin"; x86_64-linux = "linux"; }.${pkgs.stdenv.hostPlatform.system};
        sysLong = { aarch64-darwin = "darwin_arm64"; x86_64-linux = "linux-x64"; }.${pkgs.stdenv.hostPlatform.system};
      in
      pkgs.stdenv.mkDerivation {
        inherit version;
        pname = "atlassian-cli";
        src = fetchTarball {
          url = "https://acli.atlassian.com/${sysShort}/${version}/acli_${version}_${sysLong}.tar.gz";
          sha256 = versions.${system}.${version}.sha256;
        };
        installPhase = ''
          mkdir -p $out/bin
          cp -r $src/acli $out/bin/acli
        '';
        meta = { description = "Atlassian CLI"; homepage = "https://acli.atlassian.com/"; };
      };
  };

  pkgDefs.leveldb-viewer = rec {
    versions = {
      aarch64-darwin."master".sha256 = "DLP4gVoC9Nb/0iIjkNG1mwCIAfxH1KPbrDm/ueE3fFk=";
    };
    mkPkg = { pkgs, version ? "master", system ? pkgs.stdenv.hostPlatform.system, ... }:
      pkgs.buildGoModule {
        pname = "leveldb-viewer";
        inherit version;

        vendorHash = "sha256-2I5oxQo9bINJ+BjGO4FHOkRx1W2O315rx6MUGRZh3xo=";

        src = pkgs.fetchFromGitHub {
          owner = "arkantos1482";
          repo = "leveldb-viewer";
          rev = version;
          sha256 = versions.${system}.${version}.sha256;
        };
      };
  };


  pkgDefs.pi-coding-agent = rec {
    versions = {
      aarch64-darwin."0.58.3" = { sha256 = "3GrE60n+EY5G50iRrbH7R74e+LQIy1M9+huZTp0ZTns="; npmDepsHash = "sha256-EC5fXZTtBTRkYXLg5p4xWE/ghi2iw30XwnSqJs/PT8I="; };
    };
    mkPkg = { pkgs, lib, version ? "0.58.3", system ? pkgs.stdenv.hostPlatform.system, ... }: pkgs.buildNpmPackage (finalAttrs: {
      pname = "pi-coding-agent";
      # version = "0.58.3";
      inherit version;

      src = pkgs.fetchFromGitHub {
        owner = "badlogic";
        repo = "pi-mono";
        tag = "v${finalAttrs.version}";
        hash = "sha256-${versions.${system}.${version}.sha256}";
      };

      # npmDepsHash = "sha256-EC5fXZTtBTRkYXLg5p4xWE/ghi2iw30XwnSqJs/PT8I=";
      npmDepsHash = versions.${system}.${version}.npmDepsHash;

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
        pkgs.versionCheckHook
      ];
      versionCheckKeepEnvironment = [ "HOME" ];
      versionCheckProgram = "${placeholder "out"}/bin/pi";
      versionCheckProgramArg = "--version";

      passthru.updateScript = nix-update-script { };

      meta = {
        description = "Coding agent CLI with read, bash, edit, write tools and session management";
        homepage = "https://shittycodingagent.ai/";
        downloadPage = "https://www.npmjs.com/package/@mariozechner/pi-coding-agent";
        changelog = "https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/CHANGELOG.md";
        # license = lib.licenses.mit;
        # maintainers = with lib.maintainers; [ munksgaard ];
        mainProgram = "pi";
      };
    });
  };

  # TODO package https://github.com/ErfanY/krust

}
