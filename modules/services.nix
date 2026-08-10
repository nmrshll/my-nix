# thisFlake:
with builtins; let
  flakeModules.services = { ... }: {
    perSystem = { pkgs, ... }:
      with builtins; let

        bin = mapAttrs (n: pkg: "${pkg}/bin/${n}") scripts;

        wdname = "$(basename ${wd})";
        wd = "$(git rev-parse --show-toplevel)";
        scripts = mapAttrs (n: t: pkgs.writeShellScriptBin n t) {
          sql-migrate-and-export = ''deps; await_postgres $POSTGRES_PORT; sqlx migrate run; cargo sqlx prepare; '';
          # await_postgres_up = writeScriptBin "await_postgres_up" ''#!/usr/bin/env bash
          #   PORT="''${1:-''${POSTGRES_PORT:-5432}}"
          #   while ! test "`echo -ne "\x00\x00\x00\x17\x00\x03\x00\x00user\x00username\x00\x00" | nc -w 3 0.0.0.0 $PORT 2>/dev/null | head -c1`" = R; do echo "waiting on postgres (port $PORT)..."; sleep 0.3; done;
          # '';
          await_postgres = ''#!/usr/bin/env bash
              PORT="''${1:-''${POSTGRES_PORT:-5432}}"
              # while ! test "`echo -ne "\x00\x00\x00\x17\x00\x03\x00\x00user\x00username\x00\x00" | nc -w 3 0.0.0.0 $PORT 2>/dev/null | head -c1`" = R; do echo "waiting on postgres (port $PORT)..."; sleep 0.3; done;

              # TEST STRING NOT EMPTY i.e. while not contains "accepting"
              while ! [ -n "`${pkgs.postgresql_15}/bin/pg_isready -h 0.0.0.0 -p $PORT | grep "accepting"`" ]; do
                echo "waiting on postgres (port $PORT)..."; sleep 0.3;
              done
            '';
          await_postgres_migrated = ''#!/usr/bin/env bash
              await_postgres
              while test ! "sqlx migrate info | grep -q 'pending'"; do
                echo "waiting on postgres migrations..."; sleep 0.3;
              done
            '';
          await_server = ''
            if [ -n "$1" ] || [ -n "$SERVER_ORIGIN" ]; then
              SERVER_ORIGIN="''${1:-$SERVER_ORIGIN}"
            else
              echo "Error: neither argument $1 nor SERVER_ORIGIN set" >&2
              return 1
            fi

            while [[ ! `curl "$SERVER_ORIGIN/health" 2>/dev/null` =~ "ok" ]]; do echo "waiting on server ($SERVER_ORIGIN)..."; sleep 0.3; done
          '';

          # DOCKER / CONTAINERS
          down = ''#!/usr/bin/env bash
              docker-compose -f infra/docker-compose.yml down
              docker network ls --filter "type=custom" --filter="name=`${wdname}`" -q | xargs -r docker network rm
              docker ps --filter="name=`${wdname}`" -aq | xargs -r docker rm -f -v
            '';
          logs = ''
            docker-compose -f infra/docker-compose.yml logs -f "$1"
          '';
          docker-build = ''nix build .#docker; docker load < result;'';

        };
      in
      {
        inherit bin;
        expose.packages = scripts;
      };
  };

in
{
  flake.flakeModules = flakeModules;
  imports = (attrValues flakeModules);
}
