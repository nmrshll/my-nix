{ pkgs, lib, stdenv, fetchFromGitHub, cmake, ninja, pkg-config, python312
, qt6, toml11, eigen, libepoxy, libpng, freetype, fontconfig, harfbuzz
, opusfile, libopus, libogg, dejavu_fonts, makeFontsConf, makeWrapper }:
let
  python = python312.withPackages (ps: with ps; [
    mako pillow numpy lz4 pygments cython toml setuptools
  ]);
  nyan = pkgs.callPackage ./nyan.nix { };
  fonts = makeFontsConf { fontDirectories = [ dejavu_fonts ]; };
in
stdenv.mkDerivation rec {
  pname = "openage";
  version = "0.6.0";
  src = fetchFromGitHub {
    owner = "SFTtech";
    repo = "openage";
    tag = "v${version}";
    hash = "sha256-xGxHV93p3x9tf5S8115YzYnr2bcfa0a68HlCCB7Lm0g=";
  };
  nativeBuildInputs = [ cmake ninja pkg-config python makeWrapper qt6.wrapQtAppsHook ];
  buildInputs = [
    nyan python toml11 eigen libepoxy libpng freetype fontconfig harfbuzz
    opusfile libopus libogg qt6.qtbase qt6.qtdeclarative qt6.qtmultimedia
  ];
  cmakeFlags = [
    "-DPROJECT_VERSION=${version}"
    "-DVERSION_FULL_STRING=${version}"
    "-DPython3_EXECUTABLE=${python}/bin/python3"
    "-DCMAKE_PY_INSTALL_PREFIX=${placeholder "out"}/${python312.sitePackages}"
    "-DDOWNLOAD_NYAN=OFF"
    "-DDISABLE_SUBPROJECT_UPDATES=ON"
    "-DWANT_BACKTRACE=OFF"
    "-DWANT_INOTIFY=OFF"
  ];
  # The Qt hook only automatically wraps native binaries, not the Python script.
  dontWrapQtApps = true;
  postFixup = ''
    wrapProgram "$out/bin/openage" "''${qtWrapperArgs[@]}" \
      --prefix PYTHONPATH : "${python}/${python312.sitePackages}:$out/${python312.sitePackages}" \
      --set FONTCONFIG_FILE ${fonts}
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    # Source-tree imports can hide a broken installed launcher.
    cd "$(mktemp -d)"
    unset PYTHONPATH
    "$out/bin/openage" --help
    "$out/bin/openage" --version | tee version.txt
    grep -F "openage ${version}" version.txt
    "$out/bin/openage" convert --help
    runHook postInstallCheck
  '';
  meta = {
    description = "Experimental open-source Age of Empires engine recreation";
    homepage = "https://github.com/SFTtech/openage";
    license = lib.licenses.gpl3Plus;
    mainProgram = "openage";
    platforms = lib.platforms.unix;
  };
}
