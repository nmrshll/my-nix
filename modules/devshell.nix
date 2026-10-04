with builtins; let

  flakeModules.devShell = { ... }: {
    perSystem = { lib, pkgs, config, ... }: {
      options = {
        myDevShell = {
          buildInputs = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = (attrValues config.packages);
            description = "Packages to add to the dev shell environment.";
          };
          shellHooks = lib.mkOption {
            type = lib.types.lazyAttrsOf (lib.types.oneOf [ lib.types.lines lib.types.str ]);
            default = { };
            description = "Named lines to add to the shell hook script.";
          };
          env = lib.mkOption {
            type = lib.types.lazyAttrsOf (lib.types.oneOf [ lib.types.str lib.types.int lib.types.bool ]);
            default = { };
            description = "Environment variables to set in the dev shell.";
          };
          cleanups = lib.mkOption {
            type = lib.types.lazyAttrsOf (lib.types.oneOf [
              lib.types.str
              (lib.types.submodule {
                options = {
                  path = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    description = "Path to clean up.";
                  };
                  script = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    description = "Custom cleanup script.";
                  };
                  type = lib.mkOption {
                    type = lib.types.enum [ "symlink" "file" "dir" "script" ];
                    default = "script";
                    description = "Type of item: symlink, file, dir, or script.";
                  };
                };
              })
            ]);
            default = { };
            description = "AttrSet of paths/lines or { path|script, type } objects to clean up in devShell.";
          };
          scripts = lib.mkOption {
            type = lib.types.lazyAttrsOf (lib.types.oneOf [ lib.types.lines lib.types.str ]);
            default = { };
            description = "AttrSet of shell script lines to map to binaries via pkgs.writeShellScriptBin and include in devShell.";
          };
          overrides = lib.mkOption {
            type = lib.types.lazyAttrsOf (lib.types.anything);
            # Full stdenv when the consumer asked for the nixpkgs toolchain
            # (compiler + libcxx + SDK from one nixpkgs, coherently);
            # bare stdenvNoCC otherwise (see `toolchain` below).
            default =
              if config.myDevShell.toolchain == "nixpkgs" then { }
              else { stdenv = pkgs.stdenvNoCC; };
            description = "Overrides for the dev shell environment.";
          };
          toolchain = lib.mkOption {
            type = lib.types.enum [ "none" "nixpkgs" "xcode" ];
            default = "none";
            description = ''
              C toolchain for the dev shell. Nothing by default: consumers
              that compile C/C++ (directly or via `-sys` crates) must opt in.
              - "none": no C toolchain. CC/CXX, SDKROOT and nix compile flags
                are scrubbed so a C build fails fast instead of mixing
                half-configured toolchains.
              - "nixpkgs": full nixpkgs stdenv (matching compiler, libcxx
                and Apple SDK). A specific compiler version can still be set
                explicitly via `myDevShell.overrides`.
              - "xcode" (darwin): impure system Xcode (xcrun SDK, /usr/bin
                clang). Nix compile flags are scrubbed so Xcode is
                self-consistent. Xcode upgrades may break builds.
            '';
          };
        };
      };

      config =
        let
          genCleanupCmd = item:
            if isString item then ''
              if [ -L "${item}" ]; then unlink "${item}"
              elif [ -f "${item}" ]; then rm -f "${item}"
              elif [ -d "${item}" ]; then rm -rf "${item}"
              fi
            ''
            else if item.type == "script" || item.script != null then item.script
            else if item.type == "symlink" then '' [ -L "${item.path}" ] && unlink "${item.path}" ''
            else if item.type == "file" then '' [ -f "${item.path}" ] && rm -f "${item.path}" ''
            else if item.type == "dir" then '' [ -d "${item.path}" ] && rm -rf "${item.path}" ''
            else "";
          scriptsPkgSet = mapAttrs pkgs.writeShellScriptBin config.myDevShell.scripts;
        in
        lib.mkMerge [
        {
          myDevShell.scripts.cleanup = lib.concatMapStringsSep "\n" genCleanupCmd (attrValues config.myDevShell.cleanups);

          devShells.default = (pkgs.mkShell.override config.myDevShell.overrides {
            env = mapAttrs (_: v: if (isBool v) then (if v then "true" else "false") else toString v) config.myDevShell.env;
            buildInputs = config.myDevShell.buildInputs ++ (attrValues scriptsPkgSet);
            shellHook = concatStringsSep "\n" (attrValues config.myDevShell.shellHooks);
          });
        }
        # "none": scrub every C-toolchain variable nix may have leaked in via
        # buildInputs, so C builds fail fast with "compiler not found"
        # instead of mixing e.g. nix libcxx headers with an Xcode SDK.
        (lib.mkIf (config.myDevShell.toolchain == "none") {
          myDevShell.shellHooks.toolchain = ''
            unset CC CXX CC_FOR_TARGET CXX_FOR_TARGET
            unset NIX_CFLAGS_COMPILE NIX_CFLAGS_COMPILE_FOR_TARGET
            unset SDKROOT DEVELOPER_DIR
          '';
        })
        # "xcode": explicitly impure system toolchain. Scrub nix flags so
        # Xcode's clang + libc++ + SDK are self-consistent.
        (lib.mkIf (config.myDevShell.toolchain == "xcode") {
          myDevShell.shellHooks.toolchain = ''
            unset NIX_CFLAGS_COMPILE NIX_CFLAGS_COMPILE_FOR_TARGET
            export DEVELOPER_DIR="$(/usr/bin/xcode-select -p)"
            export SDKROOT="$(/usr/bin/xcrun --show-sdk-path)"
            export CC=/usr/bin/clang CXX=/usr/bin/clang++
          '';
        })
      ];
    };
  };

in
{
  flake.flakeModules = flakeModules // { utils = flakeModules; essentials = flakeModules; };
  imports = (attrValues flakeModules);
}
