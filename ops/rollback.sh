#!/usr/bin/env bash
# Rollback to Firebase within 7 days of cutover (ops/CUTOVER.md "Rollback", tasks.md T099).
#
#   bash ops/rollback.sh <cutover_at ISO> --dry-run   # counts only
#   bash ops/rollback.sh <cutover_at ISO> --apply     # write to Firestore and Storage
#
# Needs a Firebase service-account key that can WRITE Firestore and Storage at
# /srv/wizesite/secrets/firebase-rollback.json (the migration key is read-only). Create it only
# when a rollback is decided, and delete it afterwards.
set -euo pipefail

SINCE="${1:?usage: rollback.sh <cutover_at ISO> --dry-run|--apply}"
MODE="${2:---dry-run}"
ROOT=/srv/wizesite
API=$(docker ps --format '{{.Names}}' | grep -E '^wizesite-api' | head -1)
IMAGE=$(docker inspect --format '{{.Config.Image}}' "$API")
NETWORKS=$(docker inspect --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$API" | tr ' ' '\n')
NETWORK=$(echo "$NETWORKS" | grep internal | head -1)
EGRESS=$(echo "$NETWORKS" | grep edge | head -1)
POSTGRES_PASSWORD="$(grep -E '^POSTGRES_PASSWORD=' "$ROOT/.env" | head -1 | cut -d= -f2-)"

ARGS=("--since=$SINCE")
case "$MODE" in
  --dry-run) ARGS+=(--dry-run) ;;
  --apply)
    [[ -r "$ROOT/secrets/firebase-rollback.json" ]] || { echo "missing secrets/firebase-rollback.json" >&2; exit 2; } ;;
  *) echo "unknown mode $MODE" >&2; exit 2 ;;
esac

docker rm -f wizesite-rollback >/dev/null 2>&1 || true
docker create \
  --name wizesite-rollback \
  --network "$NETWORK" \
  --memory 512m \
  -e DATABASE_URL="postgres://wizesite:${POSTGRES_PASSWORD}@postgres:5432/wizesite" \
  -e FILES_ROOT=$ROOT/files \
  -e GOOGLE_APPLICATION_CREDENTIALS=/run/secrets/firebase-rollback.json \
  -v $ROOT/files:$ROOT/files:ro \
  -v $ROOT/secrets:/run/secrets:ro \
  "$IMAGE" node --enable-source-maps /app/dist/tools/rollback-to-firestore/index.js "${ARGS[@]}" >/dev/null
docker network connect "$EGRESS" wizesite-rollback
status=0
docker start -a wizesite-rollback || status=$?
docker rm -f wizesite-rollback >/dev/null
exit $status
