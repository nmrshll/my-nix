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


          # zmux = ''
          #   #!/usr/bin/env bash
          #   # Usage: zellij-multi "command1" "command2" ...

          #   set -e

          #   if [ $# -eq 0 ]; then
          #       echo "Usage: $0 <command> [command...]"
          #       exit 1
          #   fi

          #   # Clean up temporary files on exit
          #   cleanup() {
          #       rm -f "$config_file" "$layout_file"
          #   }
          #   trap cleanup EXIT

          #   config_file=$(mktemp)
          #   layout_file=$(mktemp)

          #   # Write minimal config to suppress startup tips
          #   cat > "$config_file" <<EOF
          #   show_startup_tips false
          #   show_release_notes false
          #   EOF

          #   # Start building the layout
          #   cat > "$layout_file" <<EOF
          #   layout {
          #       default_tab_template {
          #           pane size=20 position="left" borderless=true {
          #               plugin location="zellij:tab-bar" {
          #                   position "left"
          #               }
          #           }
          #           children
          #       }
          #   EOF

          #   # Escape a string for use inside a KDL double‑quoted string
          #   escape_kdl() {
          #       local str="$1"
          #       str="$${str//\\/\\\\}"   # escape backslashes
          #       str="$${str//\"/\\\"}"   # escape double quotes
          #       printf "%s" "$str"
          #   }

          #   # Generate one tab per command
          #   tab_index=1
          #   for cmd in "$@"; do
          #       escaped_cmd=$(escape_kdl "$cmd")
          #       # Use a short version of the command as the tab name
          #       tab_name="$${cmd:0:20}"
          #       # Remove any quotes that might break KDL
          #       tab_name="$${tab_name//\"/}"
          #       # If the command is empty, use a generic name
          #       [ -z "$tab_name" ] && tab_name="cmd$tab_index"

          #       cat >> "$layout_file" <<EOF
          #       tab name="$tab_name" {
          #           pane command="$${SHELL}" args "-c" "$escaped_cmd"
          #   }
          #   EOF
          #   ((tab_index++))
          #   done

          #   echo "}" >> "$layout_file"

          #   # Launch Zellij with the generated config and layout
          #   zellij --config "$config_file" --new-session-with-layout "$layout_file"
          # '';
          rip = ''
            case "''${1:-}" in
              --name|-n)
                NAME="$2"
                if [ -z "$${NAME}" ]; then printf "Missing name\n Usage: rip <name>\n"; exit 1; fi
                pkill -9 -f "$NAME"
                ;;
              --port|-p)
                PORT="$2"
                if [ -z "$${PORT}" ]; then printf "Missing port\n Usage: rip --port <port>\n"; exit 1; fi
                kill -9 $(lsof -t -i :"$PORT")
                ;;
              *)
                NAME="$1"
                if [ -z "$${NAME}" ]; then printf "Missing name\n Usage: rip <name>\n"; exit 1; fi
                pkill -9 -f "$NAME"
                printf "Running       ps auxww | grep $NAME \n"
                ps auxww | grep "$NAME" | grep -v grep | grep -v "rip $NAME"
                ;;
            esac
          '';

          pstree2 = ''
            pid=$1; while [ $pid -gt 1 ]; do ps -p $pid -o pid=,ppid=,comm= | awk '{print "  " prev $0; prev="  "}'; pid=$(ps -p $pid -o ppid=); done
          '';
          # pstree = ''${pkgs.pstree}/bin/pstree "$@" '';
          run-net = ''set -x; surfpool start '';

          dev = ''rip surfpool; ${mkZmux [
              { name = "surfpool"; command = "${bin.run-net}"; }
              { name = "dev"; command = "npm run dev"; }
              { name = "logs"; command = "tail -f logs/app.log"; }
              { command = "watch src/"; } # name auto-derived from command
            ]}
            ps auxww | grep "[s]urfpool"
            ${pkgs.pstree}/bin/pstree $(pgrep surfpool)
          '';
          hassurf = ''ps auxww | grep "[s]urf" '';

          long = ''for i in {1..1000000}; do
              echo "Processing number $i"
              # Simulate heavy work
              sleep 0.1
          done'';
          start = ''
            set -x
            ${pkgs.own.my-nix.oxmgr}/bin/oxmgr start "${bin.long}" --name "$(${bin.oxns})-long-loop" --namespace "$(${bin.oxns})"
            ${pkgs.own.my-nix.oxmgr}/bin/oxmgr logs "long-loop" -f
          '';
          stop = ''
            set -x
            ${pkgs.own.my-nix.oxmgr}/bin/oxmgr stop "long-loop"
          '';
          oxns = ''printf "${wd}" | md5sum | cut -c1-8'';
        };



        mkZmux = commandSet:
          let
            # escape = str: builtins.replaceStrings [ "\\" "\"" ] [ "\\\\" "\\\"" ] str;
            # pane size=20 borderless=true {
            #   plugin location="zellij:tab-bar" {
            #     position "left"
            #   }
            # }
            # layout {
            #   default_tab_template {
            #     pane split_direction="Vertical" {
            #         pane size="15%" {
            #             plugin location="zellij:tab-bar" {
            #               position "left"
            #             }
            #         }
            #         children
            #     }
            #   }
            #   ${l.concatStringsSep "\n" (l.imap0 (i: cmd: ''
            #     tab name="${l.strings.substring 0 20 cmd}" {
            #       pane command="${mkCmd cmd}"
            #     }
            #   '') commands)}
            # }
            # pidfile = "/tmp/zellij-dev-pids";
            mkCmd = cmd: "${(pkgs.writeShellScriptBin "cmd" ''
              echo $$ >> ${pidfile}
              exec ${cmd}
            '')}/bin/cmd";
            # keybindsCfg = ''
            #   keybinds {
            #       shared {
            #           // Toggle selectability (for resizing the pane)
            #           bind "Alt s" {
            #               MessagePlugin "file:${verticalTabsPlugin}" {
            #                   name "toggle_selectable"
            #               }
            #           }
            #       }
            #   }
            # '';
            verticalTabsPlugin = pkgs.fetchurl {
              url = "https://github.com/cfal/zellij-vertical-tabs/releases/download/v0.1.0/zellij-vertical-tabs.wasm";
              sha256 = "sha256-UxCRtWqzvAAIvRTeGfcZheOrhYURDuAh747kE1ViAqI=";
            };
            layoutContent = ''
              keybinds {
                  shared {
                      // Toggle selectability (for resizing the pane)
                      bind "Alt s" {
                          MessagePlugin "file:${verticalTabsPlugin}" {
                              name "toggle_selectable"
                          }
                      }
                  }
                  shared_except "locked" {
                    bind "Alt up" { GoToPreviousTab; }
                    bind "Alt down" { GoToNextTab; }
                  }
              }
              layout {
                default_tab_template {
                  pane split_direction="vertical" {
                      pane size=18 borderless=true {
                          plugin location="file:${verticalTabsPlugin}" {
                              // Colorful style with custom indicators
                              format "#[fg=muted]{index} #[fg=none]{name}"
                              format_active "#[fg=accent]▶ {index} {name} #[fg=success]{indicators}"
                              indicator_active "●"
                              indicator_fullscreen "□"
                              indicator_sync "⇄"
                              max_name_length 14
                          }
                      }
                      children
                  }
                  pane size=1 borderless=true {
                      plugin location="zellij:status-bar"
                  }
                }
                ${l.concatStringsSep "\n" (map (entry: ''
                  tab name="${entry.name or (l.strings.substring 0 20 entry.command)}" {
                    pane name="${entry.name or (l.strings.substring 0 20 entry.command)}" command="${mkCmd entry.command}" {
                    }
                  }
                '') commandSet)}
              }
            '';
            # close_on_exit true
            layout = pkgs.writeText "layout.kdl" layoutContent;
            config = pkgs.writeText "config.kdl" ''
              show_startup_tips false
              show_release_notes false
              on_force_close "quit"
            '';
          in
          ''
            set -x
            ${mkGrantPermissions verticalTabsPlugin}
            ${pkgs.zellij}/bin/zellij --version
            ${pkgs.zellij}/bin/zellij --config ${config} --new-session-with-layout ${layout}
          '';

        mkGrantPermissions = wasm_path: ''
          WASM="$1"
          PERMS_FILE="$HOME/Library/Caches/org.Zellij-Contributors.Zellij/permissions.kdl"
          if [ -z "${wasm_path}" ]; then echo "No .wasm at path: ${wasm_path}" >&2 ; exit 1 ; fi
          mkdir -p "$(dirname "$PERMS_FILE")"
          if grep -qF "${wasm_path}" "$PERMS_FILE" 2>/dev/null; then
            echo "Permissions already granted for ${wasm_path}"
          else
            cat >> "$PERMS_FILE" <<EOF
          "${wasm_path}" {
              ChangeApplicationState
              ReadApplicationState
          }
          EOF
            echo "Granted permissions for ${wasm_path}"
          fi
        '';

        # zellij-vertical-tabs = pkgs.stdenv.mkDerivation {
        #   pname = "zellij-vertical-tabs";
        #   version = "0.1.0";
        #   src = pkgs.fetchurl {
        #     url = "https://github.com/cfal/zellij-vertical-tabs/releases/download/v0.1.0/zellij-vertical-tabs.wasm";
        #     sha256 = "sha256-UxChtVqzvACF0U3h+XcZheOrhYURDuAh745ENTVSIqI=";
        #   };
        #   dontUnpack = true;
        #   installPhase = ''
        #     mkdir -p $out
        #     cp $src $out/zellij-vertical-tabs.wasm
        #   '';
        # };

        devDeps = [
          pkgs.own.my-nix.oxmgr
          pkgs.pstree
        ];

      in
      {
        config.extraLib = { inherit mkZmux; };
        config.bin = bin;
        config.expose.packages = scripts;
        config.myDevShell.buildInputs = devDeps ++ (attrValues scripts);
        config.myDevShell.shellHooks.dotenv = ''. ${bin.dotenv}'';
      };
  };

in
{
  flake.flakeModules = flakeModules // { utils = flakeModules; essentials = flakeModules; };
  imports = (attrValues flakeModules);
}
