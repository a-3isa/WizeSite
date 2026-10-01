#!/usr/bin/env bash
# Firestore -> Postgres migration on the VPS (quickstart §2-3, ops/CUTOVER.md step 3).
#
#   bash ops/migrate.sh <target> --dry-run   # report only, nothing loaded
#   bash ops/migrate.sh <target> --load      # load into an empty database
#   bash ops/migrate.sh <target> --reload    # replace the database contents (TRUNCATE + load)
#
# Runs the tool from the deployed API image in a one-off container: the internal network reaches
# Postgres, the edge network reaches Firebase. Read-only against Firebase
# (/srv/wizesite/secrets/firebase-service-account.json). Report:
# /srv/wizesite/state/migration/report-<target>.json; exit 1 on any mismatch.
set -euo pipefail

TARGET="${1:?usage: migrate.sh <target> --dry-run|--load|--reload}"
MODE="${2:---dry-run}"
ROOT=/srv/wizesite
OUT=$ROOT/state/migration
API=$(docker ps --format '{{.Names}}' | grep -E '^wizesite-api' | head -1)
IMAGE=$(docker inspect --format '{{.Config.Image}}' "$API")
NETWORKS=$(docker inspect --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$API" | tr ' ' '\n')
NETWORK=$(echo "$NETWORKS" | grep internal | head -1)
EGRESS=$(echo "$NETWORKS" | grep edge | head -1)
APP_UID=$(docker exec "$API" id -u)

install -d -m 700 -o "$APP_UID" -g "$APP_UID" "$OUT"

POSTGRES_PASSWORD="$(grep -E '^POSTGRES_PASSWORD=' "$ROOT/.env" | head -1 | cut -d= -f2-)"
FIREBASE_PROJECT_ID="$(grep -E '^FIREBASE_PROJECT_ID=' "$ROOT/.env" | head -1 | cut -d= -f2- || true)"

ARGS=("--target=$TARGET" "--report=$OUT/report-$TARGET.json")
case "$MODE" in
  --dry-run) ARGS+=(--dry-run) ;;
  --load) ;;
  --reload) ARGS+=(--reset) ;;
  *) echo "unknown mode $MODE" >&2; exit 2 ;;
esac

echo "image=$IMAGE target=$TARGET mode=$MODE"
free -m | awk 'NR==2{print "host memory: used " $3 " MB, available " $7 " MB"}'

docker rm -f wizesite-migrate >/dev/null 2>&1 || true
docker create \
  --name wizesite-migrate \
  --network "$NETWORK" \
  --memory 512m \
  --workdir "$OUT" \
  -e DATABASE_URL="postgres://wizesite:${POSTGRES_PASSWORD}@postgres:5432/wizesite" \
  -e FILES_ROOT=$ROOT/files \
  -e GOOGLE_APPLICATION_CREDENTIALS=/run/secrets/firebase-service-account.json \
  -e FIREBASE_PROJECT_ID="${FIREBASE_PROJECT_ID:-wize-site}" \
  -v $ROOT/files:$ROOT/files \
  -v $ROOT/state:$ROOT/state \
  -v $ROOT/secrets:/run/secrets:ro \
  "$IMAGE" node --enable-source-maps /app/dist/tools/migrate-from-firestore/index.js "${ARGS[@]}" >/dev/null
docker network connect "$EGRESS" wizesite-migrate
status=0
docker start -a wizesite-migrate || status=$?
docker rm -f wizesite-migrate >/dev/null
exit $status
