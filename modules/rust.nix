# thisFlake:
with builtins; let
  flakeModules.rust = part@{ self, ... }: {
    perSystem = { pkgs, config, l, lib, ... }:
      with builtins; let
        bin = mapAttrs (n: pkg: "${pkg}/bin/${n}") (scripts // { /* inherit (pkgs); */ });

        defaultRust = pkgs.rust-bin.stable.latest.default.override {
          extensions = [ "rust-src" "rust-analyzer" ];
          targets = [ ];
        };
        rustToolchain = config.rust.toolchain or defaultRust;
        craneLib = (part.config.flakeInputsOf.my-nix.crane.mkLib pkgs).overrideToolchain (p: rustToolchain);

        buildInputs = config.rust.buildInputs ++ [
          rustToolchain
        ] ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
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
        # crane's dependency-only build replaces every crate it finds under the
        # source with a dummy stub. That is wrong for `[patch]` path crates that
        # live in the repo but are linked against by *other* dependencies (the
        # stub then has none of the real API). These crane escape hatches are
        # threaded into `buildDepsOnly` only, so a consumer can hand in a
        # pre-built `dummySrc`, append to the dummy generation with
        # `extraDummyScript` (e.g. restore the real sources of its patch
        # crates), or replace the whole vendor dir with `cargoVendorDir`.
        depsArgs = commonArgs
          // lib.optionalAttrs (config.rust.dummySrc != null) { inherit (config.rust) dummySrc; }
          // lib.optionalAttrs (config.rust.extraDummyScript != "") { inherit (config.rust) extraDummyScript; }
          // lib.optionalAttrs (config.rust.cargoVendorDir != null) { inherit (config.rust) cargoVendorDir; };
        cargoArtifacts = craneLib.buildDepsOnly depsArgs;
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
            # Other workspace member dirs (e.g. libs/* shared libs): cargo still
            # resolves every glob in the root workspace manifest, so each member
            # base dir must exist in the narrowed source (cargo ≥1.99 hard-errors
            # on unmatched globs). The crate's own parent dir is already covered
            # above, so only the *other* member dirs are added here.
            memberBase = m: if lib.hasSuffix "/*" m then lib.removeSuffix "/*" m else m;
            extraMemberDirs = lib.unique (filter
              (d: d != "" && d != dirOf path && pathExists (self.outPath + "/${d}"))
              (map memberBase (rootToml.workspace.members or [ ])));
          in
          rec {
            inherit cargoArtifacts buildInputs;
            inherit (config.rust) nativeBuildInputs;
            pname = crateToml.package.name;
            version = resolvedVersion;
            cargoExtraArgs = "-p ${pname}";
            src = lib.fileset.toSource {
              root = (/. + builtins.unsafeDiscardStringContext self.outPath);
              fileset = lib.fileset.unions ([
                (craneLib.fileset.commonCargoSources (relPath "/${path}"))
                (relPath "/Cargo.toml")
                (relPath "/Cargo.lock")
              ] ++ map (d: craneLib.fileset.commonCargoSources (relPath "/${d}")) extraMemberDirs);
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
        scripts = mapAttrs pkgs.writeShellScriptBin {
          fix-fmt = ''
            cargo fmt --all --
            cargo clippy --fix
          '';
          rcheck = ''
            cargo fmt --all -- --check
            cargo clippy -- -D warnings
          '';
          rfix = ''cargo clippy --workspace && cargo fmt --all'';

          rfmt = ''set -x
           	if [ -f "${wd}/rustfmt.toml" ];
            		then rustfmt --config-file="${wd}/rustfmt.toml" "$@"
            		else rustfmt "$@"
           	fi
          '';
          cargo-newbin = ''if [ "$1" = "newbin" ]; then shift; fi; cargo new --bin "$1" --vcs none'';
          cargo-newlib = ''if [ "$1" = "newlib" ]; then shift; fi; cargo new --lib "$1" --vcs none'';
          # cwadd = ''${pkgs.own.tools.cargo-wadd}/bin/cargo-wadd $@'';
          cadd = ''cargo add $(__cargo-package-args) $@'';

          # run = ''cargo run $(__cargo-package-args) $@ '';
          run = ''cargo run $@ '';
          prun = ''cargo run -p "''${@:-$CURRENT_PKG}" '';
          pbuild = ''cargo build -p "''${@:-$CURRENT_PKG}" '';
          # utest = ''cargo nextest run --workspace --nocapture -- $SINGLE_TEST '';
          rutest = ''
            if [ "$1" == "--all" ]; then export ALL_PKGS=true; fi
            set -x; cargo nextest run $(__cargo-package-args) $(test_filter_args) --nocapture "$@" -- $SINGLE_TEST '';
          test_filter_args = '' [[ -n "$TEST_FILTER" ]] && printf "%s" "--filter-expr $TEST_FILTER" '';
          __cargo-package-args = ''
            if [ -n "''${ALL_PKGS+x}" ]; then echo "--workspace"; exit 0; fi
            if [ -n "$CURRENT_PKG" ]; then echo "-p $CURRENT_PKG"; else echo "--workspace"; fi
          '';
          # rptest = ''package="$1"; shift; cargo nextest run -p "$package" --nocapture "$@" -- "$SINGLE_TEST" '';
          # penv = ''printf "%s\n" "${toJSON config.devShells.default.shellHook}" '';
          # de = ''printf "%s\n" "${pkgs.pkg-config}" '';
          workspace-members = ''cargo metadata --format-version=1 | jq -r '.workspace_members[] | split("#")[0] | split("/")[-1]' '';

          pcheck = ''cargo check -p "''${@:-$CURRENT_PKG}" '';
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
        options.rust.buildEnv = l.mkOption { type = l.types.attrsOf (lib.types.oneOf [ lib.types.str lib.types.int lib.types.bool ]); default = { }; };
        # Escape hatches for crane's dependency-only build; see `depsArgs` above.
        options.rust.dummySrc = l.mkOption { type = l.types.nullOr l.types.package; default = null; };
        options.rust.extraDummyScript = l.mkOption { type = l.types.str; default = ""; };
        options.rust.cargoVendorDir = l.mkOption { type = l.types.nullOr l.types.package; default = null; };
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
          # Importing the rust module is itself the opt-in to a C toolchain:
          # Rust builds almost always need cc available (build scripts,
          # linking). mkDefault so an explicit consumer setting still wins.
          myDevShell.toolchain = l.mkDefault "nixpkgs";
          # Default only: a consumer flake setting its own RUST_BACKTRACE
          # (e.g. `myDevShell.env.RUST_BACKTRACE = 1`) wins, since mkDefault
          # loses to a plain definition instead of conflicting with it.
          myDevShell.env = lib.mapAttrs (_: lib.mkDefault) env;
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
