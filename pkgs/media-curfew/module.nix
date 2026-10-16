{ ... }: {
  perSystem = { pkgs, ... }: {
    ownPkgs.media-curfew = { }:
      if !pkgs.stdenv.hostPlatform.isDarwin then null else
      pkgs.swiftPackages.stdenv.mkDerivation {
        pname = "media-curfew";
        version = "1";
        src = ./.;
        nativeBuildInputs = [ pkgs.swiftPackages.swift ];
        buildPhase = ''
          runHook preBuild
          swiftc -O -framework AppKit Policy.swift Processes.swift main.swift -o media-curfew
          runHook postBuild
        '';
        doCheck = true;
        checkPhase = ''
          runHook preCheck
          swiftc -framework AppKit Policy.swift Processes.swift Tests.swift -o curfew-tests
          ./curfew-tests
          runHook postCheck
        '';
        installPhase = ''
          runHook preInstall
          mkdir -p "$out/Applications/Media Curfew.app/Contents/MacOS" "$out/bin"
          install -m755 media-curfew "$out/Applications/Media Curfew.app/Contents/MacOS/media-curfew"
          cp Info.plist "$out/Applications/Media Curfew.app/Contents/Info.plist"
          ln -s "../Applications/Media Curfew.app/Contents/MacOS/media-curfew" "$out/bin/media-curfew"
          runHook postInstall
        '';
        meta = {
          description = "Block mpv and VLC from 22:00 to 05:00 local time";
          platforms = pkgs.lib.platforms.darwin;
          mainProgram = "media-curfew";
        };
      };
  };
}
