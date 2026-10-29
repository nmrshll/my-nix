{ lib, stdenv, fetchFromGitHub, cmake, ninja, flex }:
stdenv.mkDerivation {
  pname = "openage-nyan";
  version = "0.3";
  src = fetchFromGitHub {
    owner = "SFTtech";
    repo = "nyan";
    tag = "v0.3";
    hash = "sha256-bjz4aSS5RO+QuLd7kyblTPNcuQFhYK7sW1csNXHL4Qs=";
  };
  nativeBuildInputs = [ cmake ninja flex ];
  cmakeFlags = [ "-DDOXYGEN_ENABLE=OFF" "-DREGISTER_USERPACKAGE=OFF" ];
  meta = {
    description = "Data description language used by openage";
    homepage = "https://github.com/SFTtech/nyan";
    license = lib.licenses.lgpl3Plus;
    platforms = lib.platforms.unix;
  };
}
