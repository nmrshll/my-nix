# thisFlake:
{ l, ... }: with builtins; let
  flakeModules.cli-tools = {
    perSystem = { pkgs, ... }:
      let
        bin = l.mapAttrs (n: pkg: "${pkg}/bin/${n}") (scripts // { inherit (pkgs) tmux; });

        # debug-bash = ''
        #   local var_name="$1"
        #   if [ -n "${!var_name}" ]; then
        #       echo "DEBUG: $var_name='${!var_name}'"
        #   else
        #       echo "DEBUG: $var_name is not set or is empty"
        #   fi
        # '';

        bash.wd = "$(git rev-parse --show-toplevel)";
        scripts = with bash; l.mapAttrs pkgs.writeShellScriptBin {
          dotenv = ''
            if [ -f "${wd}/.env" ]; then
                source "${wd}/.env";
                case "$(uname -s)" in
                    Linux*)     export $(grep -v '^#' "${wd}/.env" | xargs) ;;
                    Darwin*)    vars="$(grep -v -e '^#' -e '^[[:space:]]*$' "${wd}/.env" | cut -d= -f1)"; [ -n "$vars" ] && export $vars; true ;;
                esac
            fi
          '';

          setdotenv = ''
            if [ -f "${wd}/.env" ] && [ ! -L "${wd}/.env" ]; then
              mkdir -p "${wd}/infra"; mv "${wd}/.env" "${wd}/infra/.env.bak.$(date +%Y%m%d%H%M%S)"
            fi
            case "$1" in
              "local"*)       ln -sf "${wd}/infra/local.env" "${wd}/.env" ;;
              "remote-dev"*)  ln -sf "${wd}/infra/remote-dev.env" "${wd}/.env" ;;
              "devnet"*)     ln -sf "${wd}/infra/devnet.env" "${wd}/.env" ;;
              "testnet"*)     ln -sf "${wd}/infra/testnet.env" "${wd}/.env" ;;
              "uat"*)         ln -sf "${wd}/infra/uat.env" "${wd}/.env" ;;
              "none"*)        rm "${wd}/.env" ;;

              *) echo "$1 is not a supported environment. Environments supported are [\"none\", \"local\", \"remote-dev\", \"uat\"]" >&2; exit 1
            esac
          '';

          env-switch = ''
            ROOT="$(git rev-parse --show-toplevel)"
            ENV_DIR="$ROOT/.envs"
            ENV_FILE="$ROOT/.env"

            backup_real_file() {
              if [ -f "$ENV_FILE" ] && [ ! -L "$ENV_FILE" ]; then
                mkdir -p "$ROOT/infra"
                mv "$ENV_FILE" "$ROOT/infra/.env.bak.$(date +%Y%m%d%H%M%S)"
              fi
            }

            current_env_name() {
              if [ -L "$ENV_FILE" ]; then
                basename "$(readlink "$ENV_FILE")" .env
              else
                echo "(none)"
              fi
            }

            case "''${1:-}" in
              --list|-l)
                [ ! -d "$ENV_DIR" ] && echo "No .envs/ directory." && exit 0
                echo "Available environments:"
                for f in "$ENV_DIR"/*.env; do
                  [ ! -f "$f" ] && continue
                  [ "$(basename "$f")" = "_shared.env" ] && continue
                  name="$(basename "$f" .env)"
                  marker="  "
                  [ -L "$ENV_FILE" ] && [ "$(readlink "$ENV_FILE")" = "$f" ] && marker="* "
                  echo "''${marker}$name"
                done
                ;;
              --get|-g)
                current_env_name
                ;;
              "")
                current_env_name
                ;;
              *)
                NAME="$1"
                TARGET="$ENV_DIR/$NAME.env"
                if [ ! -f "$TARGET" ]; then
                  echo "Error: .envs/$NAME.env does not exist" >&2
                  exit 1
                fi
                backup_real_file
                SHARED="$ENV_DIR/_shared.env"
                if [ -f "$SHARED" ]; then
                  tmp="$(mktemp)"
                  if grep -q '# --- shared ---' "$TARGET"; then
                    awk -v sf="$SHARED" '
                      /^# --- shared ---$/ { print; while((getline line < sf) > 0) print line; skip=1; next }
                      /^# --- end shared ---$/ { print; skip=0; next }
                      !skip
                    ' "$TARGET" > "$tmp"
                  else
                    { echo "# --- shared ---"; cat "$SHARED"; echo "# --- end shared ---"; cat "$TARGET"; } > "$tmp"
                  fi
                  mv "$tmp" "$TARGET"
                fi
                ln -sf "$TARGET" "$ENV_FILE"
                echo "Switched to $NAME"
                ;;
            esac
          '';
          env-shared = ''
            SHARED="$(git rev-parse --show-toplevel)/.envs/_shared.env"
            if [ ! -f "$SHARED" ]; then
              echo "No shared env found. Create .envs/_shared.env first."
              exit 1
            fi
            cat "$SHARED"
          '';




          # TMUX / ZELLIJ (TODO import)
          respawn_tmux = ''
            ${bin.tmux} kill-session -t session 2>/dev/null
            ${bin.tmux} new-session -d -s session
            ${bin.tmux} set-option -g remain-on-exit on
            ${bin.tmux} bind-key C-d kill-server # use Ctrl-b-d to kill all of tmux
          '';
          tmux_cmd = ''
            SESSION="$1"
            shift; CMD="$@"
            if ${bin.tmux} list-windows |grep $SESSION;
                then ${bin.tmux} split-window -h -t session:$SESSION ';' send-keys -t session:$SESSION "''${CMD}" ENTER ;
                else ${bin.tmux} new-window -n $SESSION ';' send-keys -t session:$SESSION "''${CMD}" ENTER;
            fi
          '';
          tmux_attach = ''${bin.tmux} attach'';
          mux = ''
            ${bin.respawn_tmux};
            while [[ $# -gt 1 ]]; do
              window_name="$1"; cmd="$2"; shift 2
              tmux_cmd "$window_name" "$cmd"
            done
            ${bin.tmux_attach}
          '';

          # NIX commands
          # bash_array = ''IFS=, read -ra new_arr <<< "$1"; echo "''${new_arr[*]}" '';
          nshow = ''set -x; nix flake show --impure --show-trace --refresh --no-eval-cache $NIX_OVERRIDES'';
          neval = ''set -x; nix eval .#"$1" --show-trace --refresh --no-eval-cache $NIX_OVERRIDES'';
          attrNames = ''nix eval .#"$1" --apply builtins.attrNames $NIX_OVERRIDES'';
          # callerPath = ''echo ${dbg self.outPath}'';
          # somePath = ''ls ${./.}'';
          nfresh = ''nix flake update . $NIX_OVERRIDES'';
          ndev = ''nix develop . --show-trace --impure "$${nixOverrides[@]}" '';
          nup = ''set -x; nix flake update --show-trace --refresh --no-eval-cache $NIX_OVERRIDES'';
          ncheck = ''set -x; nix flake check --impure --show-trace . $NIX_OVERRIDES'';
          nclean = ''rm -rf result/ '';
          # reload-nix = writeScriptBin "reload-nix" ''
          #   nix flake lock --update-input scriptUtils && direnv allow
          # '';
        };

      in
      {
        inherit bin;
        expose.packages = scripts;
        myDevShell.buildInputs = attrValues scripts;
        myDevShell.shellHooks.dotenv = ''. ${bin.dotenv}'';
      };
  };

in
{
  flake.flakeModules = flakeModules // { utils = flakeModules; essentials = flakeModules; };
  imports = (attrValues flakeModules);
}
