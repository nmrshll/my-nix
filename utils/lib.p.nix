{ ctx ? { user = "me"; }, lib, ... }: with builtins; let

  mkLib = { lib }: rec {
    dbgJSON = o: (trace (toJSON o) o);
    dbgAttrs = o: (trace (attrNames o) o);

    dbg2 = o: (lib.traceSeqN 2 o) o;
    dbg3 = o: (lib.traceSeqN 3 o) o;
    dbg4 = o: (lib.traceSeqN 4 o) o;
    dbg5 = o: (lib.traceSeqN 5 o) o;

    # SETS & LISTS
    # TODO use mapAttrs ??
    mapKeys = f: obj: listToAttrs (map
      (key: {
        name = f key;
        value = obj.${key};
      })
      (attrNames obj));
    prefixKeys = prefix: obj: mapKeys (k: "${prefix}_${k}") obj;

    deepMergeSetList = listOfAttrs:
      lib.zipAttrsWith
        (name: values:
          if lib.all lib.isAttrs values then deepMergeSetList values
          else if lib.all lib.isList values then lib.concatLists values
          else lib.last values
        )
        listOfAttrs;

    # remap keys and values at the same time. f: (k, v) -> (k', v'): mapAttrsToList then mergeRecursive
    mapKvKv = f: obj: deepMergeSetList (lib.mapAttrsToList f obj);

    attrsForEach = obj: f: deepMergeSetList (attrValues (lib.mapAttrs (k: v: f k v) obj));

    # STRINGS
    slugify = str: lib.toLower (replaceStrings [ " " ] [ "-" ] str);

    # FILES
    # findNixFilesRec = dir: lib.flatten (lib.mapAttrsToList
    #   (name: type:
    #     let path = "${toString dir}/${name}"; in
    #     if type == "directory" then findNixFilesRec path  # Recursively call if it's a directory
    #     else if type == "regular" && lib.hasSuffix ".nix" name then [ path ]  # Collect the path if it's a .nix file
    #     else [ ]  # Ignore everything else
    #   )
    #   (builtins.readDir dir));

    # filter is a function of (path) -> bool
    findFilesRec = filter: dir: lib.flatten (lib.mapAttrsToList
      (name: type:
        let path = "${toString dir}/${name}"; in
        if type == "directory" then findFilesRec filter path
        else if filter path then [ path ]
        else [ ]
      )
      (builtins.readDir dir));
    findFlakePartFilesRec = findFilesRec (lib.hasSuffix ".p.nix");
    findNixFilesRec = findFilesRec (lib.hasSuffix ".nix");


    # PACKAGES
    flatMapPkgs = set:
      let
        f = p: s: builtins.foldl' (a: b: a // b) { } (builtins.attrValues (builtins.mapAttrs
          (k: v:
            if builtins.isAttrs v && !(v ? type && v.type == "derivation") then f "${p}${k}." v
            else { "${p}${k}" = v; }
          )
          s));
      in
      f "" set;
    flatListPkgs = set: attrValues (flatMapPkgs set);
    mapBins = mapAttrs (name: pkg: "${pkg}/bin/${name}");

    # MODULES
    hm_2_OS = v:
      if typeOf v == "list" then { imports = (map hm_2_OS v); }
      else if typeOf v == "lambda" then { home-manager.users.me = v; }
      else throw "Invalid argument to hm_2_OS: ${toString v}";

    types = lib.types // {
      nestedAttrs = type: lib.types.lazyAttrsOf (lib.types.oneOf [
        type
        (types.nestedAttrs type)
      ]);
    };

    constOpt = v: lib.mkOption { type = lib.types.unspecified; readOnly = true; default = v; };
  };

  # TODO should all lib go in here ???? legacy nixpkgs way vs new way ???
  mkPkgsLib = { lib, pkgs ? null, system ? pkgs.hostPlatform.system, ... }: {
    throwSystem = throw "Unsupported system: ${system}";
    forSystem = perSystemAttrs: perSystemAttrs.${system} or throwSystem;

    mkScripts = mapAttrs (name: script: pkgs.writeShellScriptBin name script);
    mapBins = mapAttrs (name: pkg: "${pkg}/bin/${name}");
  };


  flakeModules.myLib = { lib, ... }: {
    config.extraLib = mkLib { lib = lib; };
    config.perSystem = { pkgs, system, lib, ... }: {
      extraLib = mkLib { lib = lib; };
      pkgs.extraLib = mkPkgsLib { inherit pkgs system; lib = lib; };
    };

    # usual shape of lib: fn({finalPkgs,lib}) -> {attrs}
    options.flake.lib = lib.mkOption { type = lib.types.unspecified; default = { }; };
    # config.flake.lib = final: mkPkgsLib { lib = final.lib; pkgs = final; };
    config.flake.lib = mkLib { lib = lib; };
  };


in
{
  extraLib = mkLib { lib = lib; };
  flake.flakeModules = flakeModules // { utils = flakeModules; essentials = flakeModules; };
  imports = (attrValues flakeModules);
}
