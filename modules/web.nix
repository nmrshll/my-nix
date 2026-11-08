# thisFlake:
# JavaScript / TypeScript / web toolchain for repos with a JS workspace.
#
# Opt-in: import `inputs.my-nix.flakeModules.web` explicitly. This module does
# not register itself in the `utils`/`essentials` groups, so every consumer of
# those keeps its current shell (same pattern as `rust.nix`).
#
# It supplies one Node, one package manager, the environment Vite/Astro/Panda
# expect, and a set of `web-*` scripts. It does not replace a repo's own
# `dev`/`build`/zellij aliases: those encode project-specific ordering, while
# these scripts are the generic operations.
{ l, self, ... }:
with builtins; let
  flakeModules.web = { lib, ... }: {
    perSystem = { pkgs, lib, config, bash, ... }:
      let
        cfg = config.web;

        pm = cfg.packageManagerPackage;
        pmName = cfg.packageManager;

        installCmd = "${pm}/bin/${pmName} install${lib.optionalString cfg.frozenLockfile " --frozen-lockfile"}";

        # Recursive "run in every workspace package": each manager spells it
        # differently. Yarn 1 has no equivalent that tolerates missing scripts,
        # so it runs at the root and a workspace should delegate.
        # No `exec` here: `web-check` chains three of these, and `exec` would
        # replace the shell after the first, silently skipping typecheck+build.
        runAll = script:
          if pmName == "pnpm" then "${pm}/bin/pnpm -r --if-present run ${script}"
          else if pmName == "bun" then "${pm}/bin/bun run --filter '*' ${script}"
          else "${pm}/bin/yarn run ${script}";

        runAllExec = script: "exec ${runAll script}";

        # pnpm forwards through `--`; yarn 1 does not need it.
        devPortArgs = if pmName == "yarn" then "--port \"$port\"" else "-- --port \"$port\"";

        # ---- app discovery -------------------------------------------------
        # Explicit `web.apps` wins. Otherwise read the workspace file and
        # expand its top-level `dir/*` globs, so a new package appears without
        # editing the flake. Only trailing-`/*` globs are expanded; `!` ignores
        # and deeper globs are not supported.
        workspaceFile =
          let path = "${self.outPath}/pnpm-workspace.yaml";
          in if pathExists path then path else null;

        trim = value: lib.strings.trim value;

        stripQuotes = value:
          let
            unquoted =
              if hasPrefix "\"" value then removeSuffix "\"" (removePrefix "\"" value)
              else if hasPrefix "'" value then removeSuffix "'" (removePrefix "'" value)
              else value;
          in trim unquoted;

        parseWorkspaceLine = line:
          let m = match "[[:space:]]*-[[:space:]]*([^#]*)" line;
          in if m == null then null
          else
            let entry = stripQuotes (trim (head m));
            in if entry == "" then null else entry;

        expandEntry = entry:
          if hasSuffix "/*" entry then
            let
              prefix = removeSuffix "/*" entry;
              dir = "${self.outPath}/${prefix}";
            in
            if pathExists dir then
              map (name: "${prefix}/${name}")
                (filter
                  (name:
                    (readDir dir).${name} == "directory"
                    && pathExists "${dir}/${name}/package.json")
                  (attrNames (readDir dir)))
            else [ ]
          else [ entry ];

        discoveredDirs =
          if workspaceFile == null then [ ]
          else
            lib.unique (concatMap expandEntry
              (filter (entry: entry != null)
                (map parseWorkspaceLine (splitString "\n" (readFile workspaceFile)))));

        discoveredApps = listToAttrs (map
          (dir: {
            name = baseNameOf dir;
            value = { inherit dir; };
          })
          (filter (dir: dir != "." && dir != "") discoveredDirs));

        declaredApps = if cfg.apps == { } then discoveredApps else cfg.apps;
        appNames = attrNames declaredApps;

        # ---- deterministic ports -------------------------------------------
        # Derived from the repo's package.json name, which is stable across
        # commits and unique per repo (the flake's store path is not: it changes
        # with every commit), so a port survives a `git pull`.
        hexDigit = {
          "0" = 0; "1" = 1; "2" = 2; "3" = 3; "4" = 4; "5" = 5; "6" = 6; "7" = 7;
          "8" = 8; "9" = 9; "a" = 10; "b" = 11; "c" = 12; "d" = 13; "e" = 14; "f" = 15;
        };
        hashInt = value:
          let
            chars = lib.stringToCharacters (hashString "sha256" value);
            slice = genList (index: elemAt chars index) 6;
          in
          foldl' (acc: char: acc * 16 + (hexDigit.${char} or 0)) 0 slice;

        packageJsonName =
          let path = "${self.outPath}/package.json";
          in
          if pathExists path then
            let parsed = tryEval (fromJSON (readFile path));
            in if parsed.success && (parsed.value.name or null) != null
            then parsed.value.name
            else "unnamed"
          else "unnamed";

        identity = if cfg.portHashSeed != "" then cfg.portHashSeed else packageJsonName;

        # Chrome and Firefox refuse these, whatever the app does.
        blockedPorts = [
          2049 3659 4045 4190 5060 5061 6000 6566
          6665 6666 6667 6668 6669 6679 6697 10080
        ];
        # Ends at 49151, just below the ephemeral range, so an outbound
        # connection can never be holding a dev port.
        portPool =
          if cfg.portBase > 49151 then
            throw "web.portBase must leave room for the band below 49151"
          else
            lib.filter (p: !(builtins.elem p blockedPorts)) (lib.range cfg.portBase 49151);
        poolSize = builtins.length portPool;

        # Hash "<repo identity>/<app name>". The repo half keeps different repos
        # apart; the app half keeps one app's port still when another app is
        # added, renamed or removed, which an index-based scheme cannot.
        hashedSlot = name: lib.mod (hashInt "${identity}/${name}") poolSize;

        # Two names can hash to one slot, and a repo runs several apps at once,
        # so probe forward instead of handing out the same port twice.
        assignPorts = lib.lists.foldl'
          (acc: name:
            let
              start = hashedSlot name;
              pick = i:
                let candidate = builtins.elemAt portPool (lib.mod (start + i) poolSize);
                in if builtins.elem candidate acc.taken then pick (i + 1) else candidate;
              port = pick 0;
            in {
              taken = acc.taken ++ [ port ];
              ports = acc.ports // { ${name} = port; };
            })
          { taken = [ ]; ports = { }; }
          appNames;

        appPort = name: assignPorts.ports.${name};

        resolvedApps = mapAttrs
          (name: app: app // { port = if app.port != null then app.port else appPort name; })
          declaredApps;

        resolvedPorts = mapAttrs (_: app: app.port) resolvedApps;

        # `WEB_PORT_TASKSTREAM_WEB` for app `taskstream-web`.
        appEnvVar = name: "WEB_PORT_${lib.toUpper (lib.replaceStrings
          [ "-" "." "@" "/" "+" ] [ "_" "_" "_" "_" "_" ] name)}";

        appDirs = map (name: resolvedApps.${name}.dir) appNames;
        defaultApp = if appNames == [ ] then "." else head appNames;

        resolveCase = concatStringsSep "\n" (map
          (name: "${name}) app=${lib.escapeShellArg resolvedApps.${name}.dir}; port=${toString resolvedApps.${name}.port} ;;")
          appNames);

        scripts = mapAttrs (n: t: pkgs.writeShellScriptBin n t) {
          web-install = ''
            set -euo pipefail
            cd ${bash.wd}
            ${installCmd}
          '';

          web-codegen = ''
            set -euo pipefail
            cd ${bash.wd}
            ${runAllExec "codegen"}
          '';

          web-typecheck = ''
            set -euo pipefail
            cd ${bash.wd}
            ${runAllExec "typecheck"}
          '';

          web-build = ''
            set -euo pipefail
            cd ${bash.wd}
            ${runAllExec "build"}
          '';

          # codegen -> typecheck -> build: `tsc` cannot resolve the generated
          # `styled-system` imports before codegen has run.
          web-check = ''
            set -euo pipefail
            cd ${bash.wd}
            ${runAll "codegen"}
            ${runAll "typecheck"}
            ${runAll "build"}
          '';

          # Installs first: starting a server against stale node_modules is the
          # failure this saves. `--port` is forwarded because a stale server on
          # the expected port otherwise silently serves the previous build.
          web-dev = ''
            set -euo pipefail
            cd ${bash.wd}
            app="''${1:-${lib.escapeShellArg defaultApp}}"
            if [ $# -gt 0 ]; then shift; fi
            port=${toString cfg.portBase}
            case "$app" in
            ${resolveCase}
              *) [ -d "$app" ] || { echo "web-dev: no such app: $app" >&2; exit 1; } ;;
            esac
            ${installCmd}
            cd "$app"
            export WEB_DEV_PORT="$port"
            exec ${pm}/bin/${pmName} run dev ${devPortArgs} "$@"
          '';

          web-ports = ''
            set -euo pipefail
            cd ${bash.wd}
            ${concatStringsSep "\n" (map
              (name: ''printf '%-24s %-40s %s\n' ${lib.escapeShellArg name} ${lib.escapeShellArg resolvedApps.${name}.dir} ${toString resolvedApps.${name}.port}'')
              appNames)}
          '';

          # Astro records a running dev/preview in .astro/*.json and refuses to
          # start a second one; a stale preview is the worse case, because a
          # Playwright suite reuses it and tests the previous build.
          web-stop = ''
            set -euo pipefail
            cd ${bash.wd}
            for dir in ${lib.escapeShellArgs appDirs}; do
              [ -d "$dir" ] || continue
              bin="$dir/node_modules/.bin/astro"
              [ -x "$bin" ] || continue
              ( cd "$dir" && "$bin" dev stop >/dev/null 2>&1 || true )
              ( cd "$dir" && "$bin" preview stop >/dev/null 2>&1 || true )
            done
          '';
        };
      in
      {
        options.web = {
          nodePackage = lib.mkOption {
            type = lib.types.package;
            default = pkgs.nodejs_26;
            description = ''
              Node for every package-manager invocation. Defaults to the newest
              nixpkgs Node; a repo that must match an existing engine pin sets
              this explicitly.
            '';
          };
          packageManager = lib.mkOption {
            type = lib.types.enum [ "pnpm" "yarn" "bun" ];
            default = "pnpm";
            description = ''
              Package manager used by every script. `pnpm` runs workspace
              scripts recursively; `bun` uses `--filter '*'`; `yarn` runs at the
              root only.
            '';
          };
          packageManagerPackage = lib.mkOption {
            type = lib.types.package;
            default = {
              pnpm = pkgs.pnpm;
              yarn = pkgs.yarn;
              bun = pkgs.bun;
            }.${cfg.packageManager};
            description = ''
              Override the manager binary (another pnpm, a Yarn Berry build).
              Defaults to the nixpkgs package for `web.packageManager`, so the
              version comes from the flake rather than a runtime download.
            '';
          };
          frozenLockfile = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Add `--frozen-lockfile` to installs. Off while developing (adding
              a dependency rewrites the lockfile); turn it on in CI.
            '';
          };
          managePackageManagerVersions = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Let pnpm honour `packageManager` by downloading that exact
              version. Off so the shell uses the flake's pnpm and never fetches
              a second one.
            '';
          };
          skipPlaywrightBrowserDownload = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = ''
              Export `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD`. Every suite here uses
              `channel: 'chrome'`, so Playwright's own browser bundle is wasted
              disk.
            '';
          };
          extraPackages = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = [ ];
            description = "Extra toolchain packages for the dev shell.";
          };
          apps = lib.mkOption {
            type = lib.types.attrsOf (lib.types.submodule {
              options = {
                dir = lib.mkOption {
                  type = lib.types.str;
                  description = "Path, relative to the repository root.";
                };
                port = lib.mkOption {
                  type = lib.types.nullOr lib.types.port;
                  default = null;
                  description = ''
                    Dev-server port. Null means "use the hashed auto-port";
                    set it only to override.
                  '';
                };
              };
            });
            default = { };
            example = lib.literalExpression ''
              {
                docs = { dir = "apps/docs-web"; };
                app = { dir = "apps/taskstream-web"; port = 5180; };
              }
            '';
            description = ''
              Apps `web-dev`, `web-ports` and `web-stop` know about. Leave empty
              to discover them from `pnpm-workspace.yaml`.
            '';
          };
          appNames = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            readOnly = true;
            description = ''
              Apps found in this repo, sorted by name. Lets other Nix code (a
              shell hook, another module) enumerate them instead of repeating
              the list.
            '';
          };
          portHashSeed = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = ''
              Seed for the per-repo port hash. Empty uses the repo's
              package.json `name`; set it when the name is shared between forks.
            '';
          };
          ports = lib.mkOption {
            type = lib.types.attrsOf lib.types.port;
            readOnly = true;
            description = "Resolved port per app, after hashing and overrides.";
          };
          portBase = lib.mkOption {
            type = lib.types.port;
            default = 20000;
            description = ''
              First port the hash may pick. The band always ends at 49151, just
              below the ephemeral range; raise it to move every app out of
              another tool's ports, or set `web.apps.<name>.port` for one.
            '';
          };
        };

        config = {
          web.appNames = appNames;
          web.ports = resolvedPorts;

          myDevShell.buildInputs =
            [ cfg.nodePackage pm ]
            ++ cfg.extraPackages
            ++ attrValues scripts;

          myDevShell.env = {
            # Corepack would refuse a manager that differs from the
            # packageManager pin, then download one when it cannot.
            COREPACK_ENABLE_STRICT = "0";
          } // lib.optionalAttrs (pmName == "pnpm" && !cfg.managePackageManagerVersions) {
            NPM_CONFIG_MANAGE_PACKAGE_MANAGER_VERSIONS = "false";
          } // lib.optionalAttrs cfg.skipPlaywrightBrowserDownload {
            PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
          } // lib.listToAttrs (map
            (name: { name = appEnvVar name; value = toString resolvedPorts.${name}; })
            appNames) // {
            # Statically computed, so a server reads a sibling's port instead of
            # hardcoding it or parsing `web-ports` output.
            WEB_APP_PORTS = builtins.toJSON resolvedPorts;
          };

          expose.packages = scripts;
        };
      };
  };

in
{
  flake.flakeModules = flakeModules;
  imports = (attrValues flakeModules);
}
