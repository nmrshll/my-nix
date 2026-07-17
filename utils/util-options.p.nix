with builtins; let

  # Let any module add overlays or extra packages / pkgs.lib.X to the pkgs perSystem arg.
  flakeModules.pkgsArg = { self, ... }: {
    perSystem = { config, l, system, ... }:
      let overlayType = l.mkOptionType { name = "nixpkgs-overlay"; description = "nixpkgs overlay"; check = l.isFunction; merge = l.mergeOneOption; };
      in {
        options.pkgs.extraPkgs = l.mkOption { type = l.types.nestedAttrs l.types.package; default = { }; };
        options.pkgs.overlays = l.mkOption { type = l.types.listOf overlayType; default = [ ]; };
        options.pkgs.nixpkgsConfig = l.mkOption { type = l.types.unspecified; default = { }; };
        # let any module add to pkgs.lib.X perSystem arg
        options.pkgs.extraLib = l.mkOption { type = l.types.nestedAttrs l.types.unspecified; default = { }; };
        options.pkgs.extraBin = l.mkOption { type = l.types.nestedAttrs l.types.str; default = { }; };

        config.pkgs.overlays = [
          (final: prev: { lib = l.deepMergeSetList [ (prev.lib or { }) config.pkgs.extraLib ]; })
          (final: prev: { bin = l.deepMergeSetList [ (prev.bin or { }) config.pkgs.extraBin ]; })
          (final: prev: { extraPkgs = l.deepMergeSetList [ (prev.extraPkgs or { }) config.pkgs.extraPkgs ]; })
        ]; /* TODO: here we could cycle through extraPkgs and gen 1 overlay per key */

        config.pkgs.nixpkgsConfig.allowUnfree = true;
        # config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "terraform" ];

        # inject into perSystem pkgs
        config._module.args.pkgs = import self.inputs.nixpkgs {
          inherit system;
          overlays = config.pkgs.overlays;
          config = config.pkgs.nixpkgsConfig;
        };
      };
  };

  # # WHY: if a flakeModule adds to "packages" output directly, then consumers of the module will also get "packages" polluted.
  # # This module lets flakeModules add packages to expose as outputs of this flake, but not consumer flakes.
  # TODO local/exposed version of all outputs
  flakeModules.exposePkgs = { self, ... }: {
    config.perSystem = { l, ... }: {
      options.expose.packages = l.mkOption { type = l.types.nestedAttrs l.types.package; default = { }; };
    };
  };

  flakeModules.bin = { lib, flake-parts-lib, ... }: flake-parts-lib.mkTransposedPerSystemModule {
    name = "bin";
    option = lib.mkOption { type = lib.types.lazyAttrsOf lib.types.str; /* default = { }; */ };
    file = ./util-options.nix;
  };
  # flakeModules.perSystemLib = { lib, flake-parts-lib, ... }: flake-parts-lib.mkTransposedPerSystemModule {
  #   name = "lib";
  #   option = lib.mkOption { type = lib.types.lazyAttrsOf lib.types.unspecified; /* default = { }; */ };
  #   file = ./util-options.nix;
  # };
  # flakeModules.bin = { lib, ... }: {
  #   perSystem = { ... }: {
  #     options.bin = lib.mkOption { type = lib.types.attrsOf lib.types.str; default = { }; };
  #     # config.bin = config.bin;
  #   };
  # };

  # This exposes ownPkgs in flake outputs AND as a perSystem module argument (collected from pkgs/ )
  flakeModules.ownPkgs = part@{ config, l, ... }: {
    options.pkgDefs = l.mkOption { type = l.types.unspecified; default = { }; };
    # TODO: use findNixFilesRec
    imports = [
      ../pkgs/cli-pkgs.nix
      ../pkgs/editor-pkgs.nix
      ../pkgs/gui-pkgs.nix
      ../pkgs/libs-pkgs.nix
      ../pkgs/service-pkgs.nix
    ];

    config.perSystem = { pkgs, l, system, /*inputs',*/ /*lib,*/ ... }: with builtins; let
      # # TODO figure out env-based overrides
      # mkExtraInput = overridePath: defaultSrc:
      #   if overridePath != "" && pathExists overridePath
      #   then (getFlake overridePath)
      #   else getFlake defaultSrc;

      # extraInputs =
      #   let tools = mkExtraInput (getEnv "NIX_OVERRIDE_INPUT_TOOLS") "https://gitlab.com/nmrshll/tools.git";
      #   in {
      #     # TODO use PAT in URL/env for private repos
      #     tools = getFlake ("path:/Users/me/src/me/tools");
      #   };

      # collect packages indexed by name & version
      ownPkgDefs = foldl' (a: b: deepSeq b (a // b)) { } (map
        (pkgName:
          let
            pkgDef = getAttr pkgName config.pkgDefs;
            versionedPkgs = listToAttrs (map
              (version: {
                name = "${pkgName}_${version}";
                value = { pkgs, lib, ... }: (pkgDef.mkPkg { inherit pkgs lib l version; });
              })
              (attrNames pkgDef.versions.${system} or { }));
            defaultPkg =
              if pkgDef ? versions.${system} || !(pkgDef?versions)
              then { ${pkgName} = { pkgs, lib, ... }: (pkgDef.mkPkg { inherit pkgs lib l; }); }
              else { };
          in
          versionedPkgs // defaultPkg
        )
        (attrNames config.pkgDefs));

      # ownPkgs = l.filterAttrs (n: v: v != null) (
      #   (l.mapAttrs (name: mkPkg: pkgs.callPackage mkPkg { }) ownPkgDefs)
      # );
      mkOwnPkgs = { pkgs, lib, ... }: l.filterAttrs (n: v: v != null) (
        (l.mapAttrs (name: mkPkg: pkgs.callPackage mkPkg { }) ownPkgDefs)
      );
      thisFlakeInputs = part.config.flakeInputsOf.my-nix;

    in
    {
      pkgs.overlays = [
        # (final: prev: { own = (prev.own or { }) // { tools = (l.dbg3 inputs.tools.packages).${system} or { }; }; })
        (final: prev: { own.tools = thisFlakeInputs.tools.packages.${system}; })
        (final: prev: { own = (prev.own or { }) // { my-nix = mkOwnPkgs { pkgs = final; lib = prev.lib; }; }; })
      ];
      expose.packages.own = {
        tools = thisFlakeInputs.tools.packages.${system};
        my-nix = mkOwnPkgs { pkgs = pkgs; lib = l; };
      };
    };
  };

  flakeModules.ownPkgs2 = part@{ l, ... }: {
    imports = [
      ../pkgs/new-structure.nix
    ];
    config.perSystem = perSys@{ pkgs, config, l, system, ... }: {
      options.ownPkgs = l.mkOption { type = l.types.attrsOf l.types.unspecified; default = { }; };
      config.pkgs.overlays = [
        (final: prev: { own = (prev.own or { }) // perSys.config.ownPkgs; })
      ];
      config.expose.packages.own = perSys.config.ownPkgs;
    };
  };

  # let any module extend the flakeModule/perSystem lib arg
  flakeModules.extraLib = { config, lib, /*flake-parts-lib, inputs,*/ ... }: {
    # imports = [
    #   # TODO does this let other modules set flake.lib.${system} ??
    #   (flake-parts-lib.mkTransposedPerSystemModule {
    #     name = "lib";
    #     option = lib.mkOption { type = lib.types.lazyAttrsOf lib.types.unspecified; default = { }; };
    #     file = ./util-options.nix;
    #   })
    # ];


    # TODO nestedAttrs
    options.extraLib = lib.mkOption {
      type = lib.types.anything // {
        merge = loc: defs:
          let
            values = lib.getValues defs;
            baseLib = (import ./lib.p.nix { inherit lib; }).extraLib;
          in
          baseLib.deepMergeSetList ([ lib ] ++ values);
      };
      default = { };
    };
    config = {
      # TODO find a way to merge with global libs, preferably with a namespace
      # Use the merged option value directly to avoid manual merging logic here
      _module.args.l = config.extraLib;
    };

    # TODO expose extraLib in flake outputs under lib
    # options.flake.lib = lib.mkOption { type = lib.types.lazyAttrsOf lib.types.str; default = { }; };
    # lib = config.lib;

    config.perSystem = { config, lib, ... }: {
      # _module.args.lib = lib // config.lib;
      options.extraLib = lib.mkOption {
        type = lib.types.anything // {
          merge = loc: defs:
            let
              values = lib.getValues defs;
              baseLib = (import ./lib.p.nix { inherit lib; }).extraLib;
            in
            baseLib.deepMergeSetList ([ lib ] ++ values);
        };
        default = { };
      };
      config = {
        _module.args.l = config.extraLib;
      };
      # config.bin = config.bin;
    };
  };

  flakeModules.moduleTypes = { l, ... }: {
    options.flakeModules = l.mkOption { type = l.types.lazyAttrsOf l.types.unspecified; default = { }; };
    options.flake.flakeModules = l.mkOption { type = l.types.lazyAttrsOf l.types.unspecified; default = { }; };
    # config.flake.flakeModules = (l.deepMergeSetList [
    #   config.flakeModules
    #   # { utils.all.imports = attrValues config.flakeModules.utils; }
    # ]);
  };

in
{
  flake.flakeModules = flakeModules // { utils = flakeModules; essentials = flakeModules; };
  imports = (attrValues flakeModules);
}
