#!/usr/bin/env bash
# Minimal, non-invasive host preparation for a server that ALREADY runs other services
# (e.g. a shared box with Traefik). Unlike bootstrap.sh it does not touch the firewall,
# SSH settings, swap or installed packages. Idempotent.
#
#   sudo bash ops/prepare-host.sh
#
# Creates /srv/wizesite/* and, on first run only, /srv/wizesite/.env with freshly generated
# secrets. Secrets are generated here, on the server, and never printed.
set -euo pipefail

ROOT=/srv/wizesite

command -v docker >/dev/null || { echo "docker is required" >&2; exit 1; }
docker compose version >/dev/null || { echo "docker compose plugin is required" >&2; exit 1; }

install -d -m 700 "$ROOT"
for d in files state app; do install -d -m 755 "$ROOT/$d"; done
install -d -m 700 "$ROOT/secrets"
install -d -m 700 "$ROOT/pgdata"
chown 999:999 "$ROOT/pgdata" # postgres container uid

if [[ ! -f "$ROOT/.env" ]]; then
  umask 077
  {
    echo "POSTGRES_PASSWORD=$(openssl rand -hex 24)"
    echo "FILES_SIGNING_KEY=$(openssl rand -hex 32)"
    echo "FIREBASE_PROJECT_ID=wize-site"
    echo "PUBLIC_API_URL=https://api.invalid"
    echo "LOG_LEVEL=info"
    echo "# Public routes: set to true with API_HOST/SYNC_HOST once DNS points here."
    echo "TRAEFIK_ENABLE=false"
    echo "API_HOST="
    echo "SYNC_HOST="
  } > "$ROOT/.env"
  echo "created $ROOT/.env"
else
  echo "$ROOT/.env already exists (left unchanged)"
fi

stat -c '%a %U %n' "$ROOT/.env"
ls -ld "$ROOT" "$ROOT"/*
