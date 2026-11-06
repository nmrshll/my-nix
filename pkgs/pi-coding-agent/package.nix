{
  bundle,
  fd,
  fetchFromGitHub,
  fetchurl,
  lib,
  makeWrapper,
  nodejs_22,
  ripgrep,
  sourceHash,
  stdenvNoCC,
  version,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "pi-coding-agent";
  inherit version;

  src = fetchurl {
    url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-${bundle.target}.tar.gz";
    inherit (bundle) hash;
  };
  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/libexec/pi" "$out/bin"
    cp -R . "$out/libexec/pi/"
    wrapProgram "$out/libexec/pi/pi" \
      --prefix PATH : ${lib.makeBinPath [ fd ripgrep ]} \
      --suffix PATH : ${lib.makeBinPath [ nodejs_22 ]}
    ln -s ../libexec/pi/pi "$out/bin/pi"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export PI_CODING_AGENT_DIR="$TMPDIR/pi-agent"
    test "$("$out/bin/pi" --version)" = "${version}"
    runHook postInstallCheck
  '';

  passthru = {
    assetPath = "libexec/pi";
    source = fetchFromGitHub {
      owner = "earendil-works";
      repo = "pi";
      tag = "v${finalAttrs.version}";
      hash = sourceHash;
    };
  };

  meta = {
    description = "Extensible AI coding agent CLI";
    homepage = "https://pi.dev/";
    changelog = "https://github.com/earendil-works/pi/releases/tag/v${version}";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "pi";
    platforms = [ "aarch64-darwin" "x86_64-darwin" ];
  };
})
