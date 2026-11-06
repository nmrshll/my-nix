let
  flakeModules.ai-skills = { config, lib, self, ... }:
    let
      cfg = config.aiSkills;
      skillDirectory = lib.types.addCheck lib.types.path
        (source: builtins.pathExists (source + "/SKILL.md"));
      copyCommands = lib.mapAttrsToList
        (name: source:
          if builtins.match "[a-z0-9][a-z0-9_-]*" name == null then
            throw "aiSkills.skills: invalid skill directory name ${builtins.toJSON name}"
          else
            "install_skill ${lib.escapeShellArg name} ${lib.escapeShellArg "${source}"}")
        cfg.skills;
    in
    {
      key = builtins.unsafeDiscardStringContext "${toString ./ai-skills.nix}#ai-skills";
      imports = [ (import ./devshell.nix).flake.flakeModules.devShell ];

      options.aiSkills = {
        enable = lib.mkEnableOption "copying declared AI skills into the consumer checkout" // {
          default = true;
        };
        skills = lib.mkOption {
          type = lib.types.attrsOf skillDirectory;
          default = { };
          example = lib.literalExpression "{ review = ./skills/review; }";
          description = ''
            Skill directories contributed by this flake or its modules. Each
            directory must contain SKILL.md. Keys are destination names under
            .agents/skills and use lowercase letters, digits, hyphens and underscores.
          '';
        };
      };

      config = {
        aiSkills.skills.feature-spec = ../skills/feature-spec;
        perSystem = { pkgs, ... }:
          let
            flakeHash = builtins.hashFile "sha256" (self.outPath + "/flake.nix");
            python = pkgs.python3.withPackages (ps: [ ps.pyyaml ps.tomlkit ]);
            skillSources = lib.escapeShellArgs (map (source: "${source}") (builtins.attrValues cfg.skills));
            installer = pkgs.writeShellScript "install-ai-skills" ''
              set -euo pipefail
              export PATH=${lib.makeBinPath [ pkgs.git pkgs.coreutils ]}:$PATH
              repo=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
              # nix develop can also be called from another checkout.
              [ -f "$repo/flake.nix" ] || exit 0
              hash=$(sha256sum < "$repo/flake.nix")
              [ "''${hash%% *}" = "${flakeHash}" ] || exit 0

              skills_dir="$repo/.agents/skills"
              if [ -L "$repo/.agents" ] || [ -L "$skills_dir" ]; then
                echo "ai-skills: skipping symlinked skills directory: $skills_dir" >&2
                exit 0
              fi
              mkdir -p -- "$skills_dir"
              duplicates=$(${python}/bin/python3 ${./sync-codex-skills.py} --identical-sources ${skillSources})

              install_skill() (
                dest="$skills_dir/$1"
                if [ -e "$dest" ] || [ -L "$dest" ]; then
                  exit 0
                fi
                if [[ $'\n'"$duplicates"$'\n' == *$'\n'"$2"$'\n'* ]]; then
                  exit 0
                fi
                staging=$(mktemp -d -- "$skills_dir/.$1.XXXXXX")
                trap 'rm -rf -- "$staging"' EXIT
                cp -R -- "$2/." "$staging/"
                chmod -R u+w -- "$staging"
                mv -T --no-clobber -- "$staging" "$dest"
              )

              ${lib.concatStringsSep "\n" copyCommands}
              exec ${python}/bin/python3 ${./sync-codex-skills.py} "$repo" "$@"
            '';
          in
          lib.mkIf cfg.enable {
            myDevShell.shellHooks.ai-skills = ''
              ${installer} || echo "ai-skills: could not sync skills" >&2
            '';
            myDevShell.scripts = {
              sync-ai-skills = "exec ${installer}";
              codex-local-skills = ''exec ${installer} --codex "$@"'';
            };
          };
      };
    };
in
{
  flake.flakeModules = flakeModules;
  imports = builtins.attrValues flakeModules;
}
