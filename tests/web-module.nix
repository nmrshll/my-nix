{ lib, flake-parts }:
let
  my = builtins.getFlake (toString ./..);

  eval = modules: (flake-parts.lib.evalFlakeModule {
    inputs.self.outPath = ../.;
    inputs.self.inputs.nixpkgs = my.inputs.nixpkgs;
  } {
    # `web` is opt-in by import, exactly as a consumer would add it.
    imports = builtins.attrValues my.flakeModuleGroups.essentials ++ [ my.flakeModules.web ] ++ modules;
    systems = [ "aarch64-darwin" ];
  }).config;

  configured = eval [{
    perSystem.web.apps = {
      docs = { dir = "apps/docs-web"; };
      showcase = { dir = "demos/design-system-showcase"; };
      pinned = { dir = "apps/pinned"; port = 5199; };
    };
  }];

  bunny = eval [{
    perSystem.web = {
      packageManager = "bun";
      apps.docs.dir = "apps/docs-web";
    };
  }];

  # Same repo, one more app: per-app hashing must leave the existing ports alone.
  extra = eval [{
    perSystem.web.apps = {
      docs = { dir = "apps/docs-web"; };
      showcase = { dir = "demos/design-system-showcase"; };
      pinned = { dir = "apps/pinned"; port = 5199; };
      later = { dir = "apps/later"; };
    };
  }];

  system = configured.allSystems.aarch64-darwin;
  extraSystem = extra.allSystems.aarch64-darwin;
  bunSystem = bunny.allSystems.aarch64-darwin;

  scripts = system.expose.packages;
  scriptNames = builtins.attrNames scripts;
  env = system.myDevShell.env;
  # `pinned` carries an explicit port, so band checks only cover the hashed ones.
  autoPorts = builtins.attrValues (builtins.removeAttrs system.web.ports [ "pinned" ]);

  readScript = set: name: builtins.readFile "${set.${name}}/bin/${name}";
  devScript = readScript scripts "web-dev";
  checkScript = readScript scripts "web-check";
  bunCodegenScript = readScript bunSystem.expose.packages "web-codegen";

  checks = {
    scripts-installed = builtins.all (n: builtins.elem n scriptNames)
      [ "web-install" "web-codegen" "web-typecheck" "web-build" "web-check" "web-dev" "web-ports" "web-stop" ];

    node-is-26 = lib.hasPrefix "nodejs-26" (system.web.nodePackage.name or "");
    manager-defaults-to-pnpm = system.web.packageManager == "pnpm";

    ports-in-band = builtins.all (p: p >= 20000 && p <= 49151) autoPorts;
    ports-not-browser-blocked = builtins.all
      (p: !(builtins.elem p [ 2049 3659 4045 4190 5060 5061 6000 6566 6665 6666 6667 6668 6669 6679 6697 10080 ]))
      autoPorts;
    # The point of hashing the app name instead of its index.
    ports-stable-when-app-added = extraSystem.web.ports.docs == system.web.ports.docs
      && extraSystem.web.ports.showcase == system.web.ports.showcase;
    ports-hash-app-name = system.web.ports.docs != system.web.ports.showcase;
    app-names-listed = system.web.appNames == [ "docs" "pinned" "showcase" ];
    app-port-env = env.WEB_PORT_DOCS == toString system.web.ports.docs;
    app-ports-json = builtins.fromJSON env.WEB_APP_PORTS == system.web.ports;
    ports-distinct =
      builtins.length autoPorts == builtins.length (lib.unique autoPorts);
    explicit-port-wins = system.web.apps.pinned.port == 5199;
    explicit-port-in-table = system.web.ports.pinned == 5199;

    corepack-relaxed = env.COREPACK_ENABLE_STRICT == "0";
    pnpm-version-management-off = env.NPM_CONFIG_MANAGE_PACKAGE_MANAGER_VERSIONS == "false";
    playwright-skips-download = env.PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD == "1";

    # The manager enum changes the generated commands.
    bun-uses-filter = lib.hasInfix "bun run --filter" bunCodegenScript;
    bun-drops-pnpm-env = !(bunSystem.myDevShell.env ? NPM_CONFIG_MANAGE_PACKAGE_MANAGER_VERSIONS);
    bun-script-exists = bunSystem.expose.packages ? web-dev;

    # `web-check` must reach all three steps: an early `exec` would drop the rest.
    check-runs-codegen = lib.hasInfix "run codegen" checkScript;
    check-runs-typecheck = lib.hasInfix "run typecheck" checkScript;
    check-runs-build = lib.hasInfix "run build" checkScript;
    check-has-no-early-exec = !(lib.hasInfix "exec " checkScript);

    # web-dev installs before starting and forwards the hashed port.
    dev-installs = lib.hasInfix "install" devScript;
    dev-forwards-port = lib.hasInfix "--port" devScript;
    dev-exports-port = lib.hasInfix "WEB_DEV_PORT" devScript;
    # Each app arm must carry its own port: matching by name again after
    # rewriting `app` to a path silently left the port empty.
    dev-arm-has-port = lib.hasInfix
      "docs) app=apps/docs-web; port=${toString system.web.ports.docs}" devScript;
    dev-fallback-port = lib.hasInfix "port=${toString system.web.portBase}" devScript;
    dev-wd-not-quoted = !(lib.hasInfix "cd '$(git rev-parse --show-toplevel)'" devScript);
  };
in
lib.mapAttrs (name: passed: assert lib.assertMsg passed "web module check failed: ${name}"; passed) checks
