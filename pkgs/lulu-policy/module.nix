{ ... }: {
  perSystem = { pkgs, ... }: {
    ownPkgs.lulu-policy = { }: pkgs.stdenvNoCC.mkDerivation {
      pname = "lulu-policy";
      version = "1";
      src = ./.;
      nativeBuildInputs = [ pkgs.makeWrapper ];
      doCheck = true;
      checkPhase = ''
        PYTHONDONTWRITEBYTECODE=1 ${pkgs.python3}/bin/python3 -m unittest -v test_policy.py
      '';
      installPhase = ''
        mkdir -p $out/libexec $out/bin
        cp policy.py $out/libexec/lulu-policy.py
        makeWrapper ${pkgs.python3}/bin/python3 $out/bin/lulu-policy \
          --add-flags $out/libexec/lulu-policy.py
      '';
      meta = {
        description = "Apply a declarative LuLu 4.2 profile while its extension is stopped";
        platforms = pkgs.lib.platforms.darwin;
        mainProgram = "lulu-policy";
      };
    };
  };
}
