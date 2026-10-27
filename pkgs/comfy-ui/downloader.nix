{ writeShellApplication, python3, curl, lib }:
(writeShellApplication {
  name = "comfyui-models";
  text = ''
    exec ${lib.getExe python3} ${./download-models.py} --curl ${lib.getExe curl} "$@"
  '';
}).overrideAttrs (old: {
  passthru = (old.passthru or { }) // { models = import ./model-manifest.nix; };
})
