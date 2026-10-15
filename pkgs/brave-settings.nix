{ ... }: {
  config.perSystem = { pkgs, system, ... }: {
    ownPkgs.brave-settings-runner = { }:
      let
        # This helper is actively developed in the user's existing tools checkout,
        # like nix-home's local Nexo extension. getFlake uses committed Git source.
        tools = builtins.getFlake "git+file:///Users/me/src/me/tools";
        crate = "${tools}/crates/brave-settings";
        crateManifest = builtins.fromTOML (builtins.readFile "${crate}/Cargo.toml");
        workspaceManifest = builtins.fromTOML (builtins.readFile "${tools}/Cargo.toml");
        manifest = (pkgs.formats.toml { }).generate "Cargo.toml" (crateManifest // {
          workspace = { };
          dependencies = pkgs.lib.mapAttrs (name: dependency:
            if builtins.isAttrs dependency && (dependency.workspace or false)
            then workspaceManifest.workspace.dependencies.${name}
            else dependency
          ) crateManifest.dependencies;
        });
        # Build this crate alone: the tools workspace includes unrelated media
        # clients and their dependencies. Keep these versions aligned with its lock.
        source = pkgs.runCommand "brave-settings-source" { } ''
          mkdir -p "$out"
          cp -r ${crate}/src "$out/src"
          cp ${manifest} "$out/Cargo.toml"
          cp ${./brave-settings.lock} "$out/Cargo.lock"
        '';
        helper = pkgs.rustPlatform.buildRustPackage {
          pname = "brave-settings";
          version = crateManifest.package.version;
          src = source;
          cargoLock.lockFile = ./brave-settings.lock;
          nativeCheckInputs = [ pkgs.nodejs ];
          doCheck = true;
        };
        runner = pkgs.writeShellApplication {
          name = "brave-settings-sync";
          runtimeInputs = [ pkgs.nodejs ];
          text = ''exec ${helper}/bin/brave-settings "$@"'';
          derivationArgs.passthru.wrapBrave = { brave, stateDir, dataDir }:
            brave.overrideAttrs (old: {
              nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];
              postInstall = (old.postInstall or "") + ''
                wrapProgram "$out/Applications/Brave Browser.app/Contents/MacOS/Brave Browser" \
                  --run ${pkgs.lib.escapeShellArg ''${runner}/bin/brave-settings-sync apply-pending --state-dir ${pkgs.lib.escapeShellArg stateDir} --brave-data-dir ${pkgs.lib.escapeShellArg dataDir} || echo 'Brave extension updates remain queued; see brave-settings.log' >&2''}
              '';
            });
        };
      in runner;
  };
}
