# thisFlake:
with builtins; let
  flakeModules.git = { config, pkgs, ... }: {
    perSystem = { config, pkgs, lib, ... }:
      with builtins; let
        # l = lib // builtins;
        # sh_use_dbg = ''dbg_var() {  local var_name="$1";  if [ -n "''${!var_name}" ]; then  echo "$var_name=''${!var_name}";  else echo "DBG_VAR: $var_name is not set or is empty"; fi  }'';

        wd = "$(git rev-parse --show-toplevel)";
        scripts = mapAttrs (n: t: pkgs.writeShellScriptBin n t) {
          remote-name = ''
            NB_REMOTES="$(git -C "${wd}" remote | wc -l | tr -d '[:space:]')"
            if [ $NB_REMOTES -eq 1 ]; then
              CURRENT_REMOTE="$(git -C "${wd}" remote | tr -d '[:space:]')";
            else
              >&2 echo "[ERROR]: no unique origin remote"; exit 1
            fi
            dbg_var CURRENT_REMOTE
          '';
          autorebase = ''set -euxo pipefail
              # This script will automatically rebase your branch onto main, by doing:
              #  - backup your current branch
              #  - pull latest changes on main
              #  - squash all of your branch into one commit
              #  - rebase your branch on top of the latest main
              # If you have conflicts after running it:
              #  - for each file, fix conflicts, git-stage the file
              #  - run `git rebase --continue`
              #  - Now, your branch should have one more commit than main

              SQUASH=''${SQUASH-false}
              RESET_TARGET=''${RESET_TARGET-false}

              REMOTE_NAME="$(remote-name)"
              if ! git fetch "$REMOTE_NAME" ; then
                  >&2 echo "[ERROR]: Failed to fetch from remote '$REMOTE_NAME'";
                  exit 1
              fi
              MAIN_REMOTE_BRANCH=$(git -C "${wd}" symbolic-ref refs/remotes/''${REMOTE_NAME}/HEAD | sed "s@^refs/remotes/''${REMOTE_NAME}/@@")
              WORK_BRANCH=$(git rev-parse --abbrev-ref HEAD)

              TARGET_BRANCH=''${TARGET_BRANCH-$MAIN_REMOTE_BRANCH}
              if [ -z "$TARGET_BRANCH" ] || [ "$TARGET_BRANCH" == "null" ]; then echo "TARGET_BRANCH can't be empty"; exit 1; fi

              # echo "SQUASH: $SQUASH" "WORK_BRANCH: $WORK_BRANCH" "TARGET_BRANCH: $TARGET_BRANCH"
              # exit 1

              # check we're not on main or TARGET_BRANCH
              if [[ "''${WORK_BRANCH}" =~ "''${MAIN_REMOTE_BRANCH}" ]]; then echo "[ERROR] Branch can't be main branch" && exit 1; fi
              if [[ "''${WORK_BRANCH}" =~ "''${TARGET_BRANCH}" ]]; then echo "[ERROR] Branch can't be $TARGET_BRANCH" && exit 1; fi
              # check everything committed
              if [ -n "$(git status --porcelain)" ]; then
                  echo "[ERROR] There are uncommitted changes in working tree. Commit, then run this script again"
                  exit 1
              fi

              # backup work branch
              BACKUP_BRANCH="''${WORK_BRANCH}_backup_$(date +%y%m%d%H%M)"
              git checkout -b "''${BACKUP_BRANCH}"

              # update target branch
              git fetch $REMOTE_NAME
              git checkout "''${TARGET_BRANCH}"
              if [ "$RESET_TARGET" == "true" ];then
                git reset --hard "$REMOTE_NAME/$TARGET_BRANCH"
              else
                git pull
              fi
              git checkout "''${WORK_BRANCH}"

              # squash all changes of my branch
              if [ "$SQUASH" == "true" ];then
                TITLE_OF_FIRST_COMMIT_REBASED=$(git log --format=%B $(git merge-base $TARGET_BRANCH $WORK_BRANCH)..$WORK_BRANCH | tr -s '\n' | tail -n 1)
                LAST_COMMON_COMMIT=$(git merge-base ''${WORK_BRANCH} ''${TARGET_BRANCH})
                git reset --soft ''${LAST_COMMON_COMMIT}
                git commit --all -m "$TITLE_OF_FIRST_COMMIT_REBASED"
              fi

              git rebase "''${TARGET_BRANCH}"
            '';
          gupdate = ''set -x
              REPO_PATH=$(git rev-parse --show-toplevel)
              REMOTE_NAME=$(
                NB_REMOTES=$(git -C "$REPO_PATH" remote | wc -l | tr -d '[:space:]')
                if [ $NB_REMOTES -eq 1 ]; then
                  CURRENT_REMOTE=$(git -C "$REPO_PATH" remote | tr -d '[:space:]'); echo $CURRENT_REMOTE
                else
                  >&2 echo "[ERROR]: no unique origin remote"; exit 1
                fi;
              );
              if ! git fetch "$REMOTE_NAME" ; then
                  >&2 echo "[ERROR]: Failed to fetch from remote '$REMOTE_NAME'";
                  exit 1
              fi
              MAIN_REMOTE_BRANCH=$(git -C "$REPO_PATH" symbolic-ref refs/remotes/''${REMOTE_NAME}/HEAD | sed "s@^refs/remotes/''${REMOTE_NAME}/@@")
              WORK_BRANCH=$(git rev-parse --abbrev-ref HEAD)


              echo "$REMOTE_NAME $MAIN_REMOTE_BRANCH $WORK_BRANCH"

              # check we're not on main
              if [[ "''${WORK_BRANCH}" =~ "''${MAIN_REMOTE_BRANCH}" ]]; then echo "[ERROR] Branch can't be main branch" && exit 1; fi
              # check everything committed
              if [ -n "$(git status --porcelain)" ]; then
                  echo "[ERROR] There are uncommitted changes in working tree. Commit, then run this script again"
                  exit 1
              fi

              # backup work branch
              BACKUP_BRANCH="''${WORK_BRANCH}_backup_$(date +%y%m%d%H%M)"
              git checkout -b "''${BACKUP_BRANCH}"
              git checkout "''${WORK_BRANCH}"

              git fetch "$REMOTE_NAME"
              git merge --no-edit "$REMOTE_NAME/$MAIN_REMOTE_BRANCH" || exit 1
            '';

          git-unsee = ''
            # git add --intent-to-add "$@"
            git update-index --assume-unchanged "$@"
          '';
        };

      in
      {
        expose.packages = scripts;
      };
  };

in
{
  flake.flakeModules = flakeModules // { utils = flakeModules; essentials = flakeModules; };
  imports = (attrValues flakeModules);
}
