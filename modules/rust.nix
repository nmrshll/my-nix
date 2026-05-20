# thisFlake:
with builtins; let
  flakeModules.rust = part@{ self, config, pkgs, inputs, ... }: {
    perSystem = { pkgs, config, l, lib, ... }:
      with builtins; let
        bin = mapAttrs (n: pkg: "${pkg}/bin/${n}") (scripts // { inherit (pkgs); });

        defaultRust = pkgs.rust-bin.stable.latest.default.override {
          extensions = [ "rust-src" "rust-analyzer" ];
          targets = [ ];
        };
        rustToolchain = config.rust.toolchain or defaultRust;
        craneLib = (part.config.flakeInputsOf.my-nix.crane.mkLib pkgs).overrideToolchain (p: rustToolchain);

        buildInputs = config.rust.buildInputs ++ [
          rustToolchain
        ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
          # pkgs.apple-sdk_26
          # pkgs.libiconv
        ];
        devInputs = with pkgs; [
          cargo-nextest
        ];

        src = craneLib.cleanCargoSource self.outPath;
        relPath = p: (/. + builtins.unsafeDiscardStringContext "${self.outPath + "${p}"}");
        commonArgs = {
          inherit src buildInputs;
          inherit (config.rust) nativeBuildInputs; /* strictDeps = true; */
          env = config.rust.buildEnv;
          # dontUseCmakeConfigure = true;  # for apple metal ?
        };
        cargoArtifacts = craneLib.buildDepsOnly commonArgs;
        perCrateArgs = path:
          let
            crateToml = fromTOML (readFile (self.outPath + "/${path}/Cargo.toml"));
            rootToml =
              if pathExists (self.outPath + "/Cargo.toml")
              then fromTOML (readFile (self.outPath + "/Cargo.toml"))
              else { };
            resolvedVersion =
              if builtins.isAttrs crateToml.package.version && crateToml.package.version ? workspace && crateToml.package.version.workspace == true
              then rootToml.workspace.package.version or "0.1.0" # Fallback if missing in root
              else crateToml.package.version;
          in
          rec {
            inherit cargoArtifacts buildInputs;
            inherit (config.rust) nativeBuildInputs;
            pname = crateToml.package.name;
            version = resolvedVersion;
            cargoExtraArgs = "-p ${pname}";
            src = lib.fileset.toSource {
              root = (/. + builtins.unsafeDiscardStringContext self.outPath);
              fileset = lib.fileset.unions [
                (craneLib.fileset.commonCargoSources (relPath "/${path}"))
                (relPath "/Cargo.toml")
                (relPath "/Cargo.lock")
              ];
            };
            doCheck = false; # we disable tests since we'll run them all via cargo-nextest
            env = config.rust.buildEnv;
            # dontUseCmakeConfigure = true;  # for apple metal ?
          };
        buildCrate = path: craneLib.buildPackage (perCrateArgs path);


        workspaceMembers =
          if pathExists (self.outPath + "/Cargo.toml") then (fromTOML (readFile (self.outPath + "/Cargo.toml"))).workspace.members or [ ]
          else [ ];
        expandWsMember = member:
          if lib.hasSuffix "/*" member then
            let
              baseDir = lib.removeSuffix "/*" member;
              subDirs = lib.filterAttrs (name: type: type == "directory") (readDir (self.outPath + "/${baseDir}"));
            in
            map (name: "${baseDir}/${name}") (attrNames subDirs)
          else
            [ member ];

        validCratePaths = filter (crate: pathExists (relPath "/${crate}/Cargo.toml")) (concatLists (map expandWsMember workspaceMembers));
        crates = listToAttrs (map (path: { name = baseNameOf path; value = buildCrate path; }) validCratePaths);

        tests = lib.optionalAttrs (pathExists (self.outPath + "/Cargo.toml")) {
          clippy = craneLib.cargoClippy (commonArgs // {
            inherit cargoArtifacts;
            cargoClippyExtraArgs = "--all-targets -- --deny warnings";
          });
        };


        wd = "$(git rev-parse --show-toplevel)";
        scripts = lib.mapAttrs (n: t: pkgs.writeShellScriptBin n t) {
          fix-fmt = ''
            cargo fmt --all --
            cargo clippy --fix
          '';
          check = ''
            cargo fmt --all -- --check
            cargo clippy -- -D warnings
          '';

          rfmt = ''set -x
        	if [ -f "${wd}/rustfmt.toml" ];
        		then rustfmt --config-file="${wd}/rustfmt.toml" "$@"
        		else rustfmt "$@"
        	fi
        '';
          cargo-newbin = ''if [ "$1" = "newbin" ]; then shift; fi; cargo new --bin "$1" --vcs none'';
          cargo-newlib = ''if [ "$1" = "newlib" ]; then shift; fi; cargo new --lib "$1" --vcs none'';
          # cwadd = ''${pkgs.own.tools.cargo-wadd}/bin/cargo-wadd $@'';
          cadd = ''cargo add $(packages) $@'';

          build = ''nix build . --show-trace '';
          # run = ''cargo run $(packages) $@ '';
          run = ''cargo run $@ '';
          prun = ''cargo run -p "''${@:-$CURRENT_CRATE}" '';
          pbuild = ''cargo build -p "''${@:-$CURRENT_CRATE}" '';
          # utest = ''cargo nextest run --workspace --nocapture -- $SINGLE_TEST '';
          utest = ''set -x; cargo nextest run $(packages) --nocapture "$@" -- $SINGLE_TEST '';
          packages = ''if [ -n "$CURRENT_CRATE" ]; then echo "-p $CURRENT_CRATE"; else echo "--workspace"; fi '';
          ptest = ''package="$1"; shift; cargo nextest run -p "$package" --nocapture "$@" -- "$SINGLE_TEST" '';
          # penv = ''printf "%s\n" "${toJSON config.devShells.default.shellHook}" '';
          de = ''printf "%s\n" "${pkgs.pkg-config}" '';
        };

        env = {
          RUST_BACKTRACE = "full";
        };

      in
      {
        # User input options
        options.rust.targets = l.mkOption { type = l.types.listOf l.types.str; default = [ ]; };
        options.rust.extensions = l.mkOption { type = l.types.listOf l.types.str; default = [ ]; };
        options.rust.toolchain = l.mkOption { type = l.types.package; default = defaultRust; };
        options.rust.buildInputs = l.mkOption { type = l.types.listOf l.types.package; default = [ ]; };
        options.rust.nativeBuildInputs = l.mkOption { type = l.types.listOf l.types.package; default = [ ]; };
        options.rust.buildEnv = l.mkOption { type = l.types.attrsOf l.types.str; default = { }; };
        # Internal options
        options.rust.crates = l.mkOption { type = l.types.nestedAttrs l.types.package; default = { }; readOnly = true; };

        config = {
          inherit bin;
          rust.crates = crates;
          checks = tests;
          # legacyPackages = { inherit crates; };
          # packages = l.mapAttrs' (name: value: { name = "crate-${name}"; inherit value; }) crates;

          packages = crates; # expose caller's crates in caller outputs

          expose.packages = scripts // { customRust = defaultRust; };
          pkgs.overlays = [ (import part.config.flakeInputsOf.my-nix.rust-overlay) ];

          myDevShell.buildInputs = buildInputs ++ devInputs ++ (attrValues scripts);
          myDevShell.env = env;
          # myDevShell.shellHooks.de = ''
          #   comm -13 <(echo "$nativeBuildInputs" | tr ' ' '\n' | sort) <(echo "$PATH" | tr ':' '\n' | sort) | grep "/nix/store"
          # '';
          extraLib = { inherit craneLib; customRust = { inherit buildCrate; }; };

          vscode.settings = {
            "rust-analyzer.server.extraEnv" = {
              CARGO = "${config.rust.toolchain}/bin/cargo";
              RUSTC = "${config.rust.toolchain}/bin/rustc";
              RUSTFMT = "${config.rust.toolchain}/bin/rustfmt";
              # SQLX_OFFLINE = 1;
              # RUSTFLAGS = env.RUST_BACKTRACE; # Assuming RUSTFLAGS refers to the RUST_BACKTRACE from the env block
            } // config.rust.buildEnv;
            "rust-analyzer.server.path" = "${config.rust.toolchain}/bin/rust-analyzer";
            "rust-analyzer.runnables.command" = "${config.rust.toolchain}/bin/cargo";
            "rust-analyzer.runnables.extraEnv" = {
              CARGO = "${config.rust.toolchain}/bin/cargo";
              RUSTC = "${config.rust.toolchain}/bin/rustc";
              RUSTFMT = "${config.rust.toolchain}/bin/rustfmt";
              # SQLX_OFFLINE = 1;
              # RUSTFLAGS = env.RUST_BACKTRACE; # Assuming RUSTFLAGS refers to the RUST_BACKTRACE from the env block
            } // config.rust.buildEnv;
          };
        };
      };
  };

in
{
  flake.flakeModules = flakeModules;
  imports = (attrValues flakeModules);
}
