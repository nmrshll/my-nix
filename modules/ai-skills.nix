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
      normalizeFragment = name: value:
        let
          content = if builtins.isPath value then builtins.readFile value else value;
        in
        if builtins.match "[a-z0-9][a-z0-9_-]*" name == null then
          throw "aiSkills.agentsMd.fragments: invalid fragment name ${builtins.toJSON name}"
        else if !builtins.isString content || lib.strings.trim content == "" then
          throw "aiSkills.agentsMd.fragments.${name}: fragment must be non-empty text or a markdown file"
        else
          content;
    in
    {
      key = builtins.unsafeDiscardStringContext "${toString ./ai-skills.nix}#ai-skills";
      imports = [ (import ./devshell.nix).flake.flakeModules.devShell ];

      options.aiSkills = {
        enable = lib.mkEnableOption "copying declared AI skills into the consumer checkout" // {
          default = true;
        };
        agentsMd = {
          enable = lib.mkEnableOption "managing agents.md fragments in the consumer checkout" // {
            default = true;
          };
          file = lib.mkOption {
            type = lib.types.str;
            default = "AGENTS.md";
            example = lib.literalExpression "\"agents.md\"";
            description = ''
              Name of the agents file at the consumer checkout root. Must be a
              single file name without directories, e.g. "agents.md" for
              projects that use the lowercase spelling. Relative to the
              consumer's Git worktree root.
            '';
          };
          fragments = lib.mkOption {
            type = lib.types.attrsOf (lib.types.oneOf [ lib.types.lines lib.types.path ]);
            default = { };
            example = lib.literalExpression ''{ git-conventions = "## Git\n..."; }'';
            description = ''
              Named markdown fragments managed inside aiSkills.agentsMd.file.
              Each fragment is written between a pair of HTML-comment markers
              naming it (<!-- my-nix:agents-fragment:start NAME --> ...
              <!-- my-nix:agents-fragment:end NAME -->). On every dev-shell
              entry the hook replaces only the content between a fragment's
              markers, appends fragments it has not seen yet, and removes
              fragments that are no longer declared, leaving everything else
              in the file -- including anything written by hand -- untouched.
              A value is either markdown text or a path to a markdown file
              (tracked in Git, like skill sources). Keys use lowercase
              letters, digits, hyphens and underscores.
            '';
          };
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
            fragmentsFile = pkgs.writeText "agents-md-fragments.json"
              (builtins.toJSON (builtins.mapAttrs normalizeFragment cfg.agentsMd.fragments));
            agentsSync = if cfg.agentsMd.enable && cfg.agentsMd.fragments != { } then ''
              ${python}/bin/python3 ${./sync-agents-md.py} "$repo" ${fragmentsFile} ${lib.escapeShellArg cfg.agentsMd.file}
            '' else "";
            installer = pkgs.writeShellScript "install-ai-skills" ''
              set -euo pipefail
              export PATH=${lib.makeBinPath [ pkgs.git pkgs.coreutils ]}:$PATH
              repo=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
              # nix develop can also be called from another checkout.
              [ -f "$repo/flake.nix" ] || exit 0
              hash=$(sha256sum < "$repo/flake.nix")
              [ "''${hash%% *}" = "${flakeHash}" ] || exit 0

              ${agentsSync}
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
