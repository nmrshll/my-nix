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
        launcher = pkgs.writeShellApplication {
          name = "brave-settings-launch";
          text = builtins.readFile ./brave-settings-launch.sh;
        };
        runner = pkgs.writeShellApplication {
          name = "brave-settings-sync";
          runtimeInputs = [ pkgs.nodejs ];
          text = ''exec ${helper}/bin/brave-settings "$@"'';
          derivationArgs.passthru = {
            tests.lifecycle = pkgs.runCommand "brave-settings-launch-test" {
              nativeBuildInputs = [ pkgs.python3 ];
            } ''
              python3 ${./test-brave-settings-launch.py} ${launcher}/bin/brave-settings-launch
              touch "$out"
            '';
            wrapBrave = { brave, stateDir, dataDir }:
            brave.overrideAttrs (old: {
              nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];
              postInstall = (old.postInstall or "") + ''
                program="$out/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"
                real="$out/Applications/Brave Browser.app/Contents/MacOS/.Brave Browser-settings-wrapped"
                mv "$program" "$real"
                makeWrapper ${launcher}/bin/brave-settings-launch "$program" \
                  --set BRAVE_SETTINGS_SYNC ${runner}/bin/brave-settings-sync \
                  --set BRAVE_SETTINGS_STATE_DIR ${pkgs.lib.escapeShellArg stateDir} \
                  --set BRAVE_SETTINGS_DATA_DIR ${pkgs.lib.escapeShellArg dataDir} \
                  --set BRAVE_SETTINGS_BROWSER "$real"
              '';
            });
          };
        };
      in runner;
  };
}
