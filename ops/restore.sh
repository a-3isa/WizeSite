#!/usr/bin/env bash
# Disaster recovery (tasks.md T094, SC-008 < 4 h, FR-019 <= 15 min of data lost). Run as root on a
# fresh VPS after ops/prepare-host.sh (or bootstrap.sh), with the app copied to
# /srv/wizesite/app and these restored from your password manager:
#   /srv/wizesite/.env                     (incl. PGBACKREST_* and PG_ARCHIVE_MODE=on)
#   /srv/wizesite/secrets/restic.env
#   /srv/wizesite/secrets/firebase-auth-admin.json
#
#   bash ops/restore.sh                     # latest state
#   bash ops/restore.sh --pitr "2026-10-01 09:30:00+00"   # point in time
#
# Steps: database from pgBackRest (base backup + WAL replay) -> files from restic -> deploy ->
# health check. Prints the elapsed time and the newest restored record's timestamp.
set -euo pipefail

ROOT=/srv/wizesite
APP="$ROOT/app"
PITR=""
if [[ "${1:-}" == "--pitr" ]]; then PITR="${2:?--pitr needs a timestamp}"; fi
started=$(date -u +%s)
cd "$APP/server"
dc() { docker compose -f compose.yml --env-file "$ROOT/.env" "$@"; }

echo "==> stopping services that use the database"
dc stop api powersync reconciler 2>/dev/null || true
dc stop postgres 2>/dev/null || true

echo "==> building the postgres image"
dc build postgres

if [[ -n "$(ls -A "$ROOT/pgdata" 2>/dev/null)" ]]; then
  mv "$ROOT/pgdata" "$ROOT/pgdata.before-restore.$(date -u +%Y%m%dT%H%M%SZ)"
fi
install -d -m 700 "$ROOT/pgdata"
PG_IDS="$(docker run --rm --entrypoint sh wizesite-postgres:17 -c 'echo "$(id -u postgres):$(id -g postgres)"')"
chown "$PG_IDS" "$ROOT/pgdata"
install -d -m 750 -o "${PG_IDS%%:*}" -g "${PG_IDS##*:}" "$ROOT/pgbackrest"

echo "==> restoring the database${PITR:+ to $PITR}"
restore_args=(--stanza=wizesite --delta)
if [[ -n "$PITR" ]]; then
  restore_args+=(--type=time "--target=$PITR" --target-action=promote)
fi
dc run --rm --no-deps -u postgres --entrypoint pgbackrest postgres "${restore_args[@]}" restore

echo "==> restoring files"
install -d -m 755 "$ROOT/files"
rm -rf "$ROOT/restore"
RESTORE_TARGET="$ROOT/restore" bash "$APP/ops/restic/restic.sh" restore latest --tag files --target /restore
cp -a "$ROOT/restore/srv/wizesite/files/." "$ROOT/files/"
rm -rf "$ROOT/restore"

echo "==> deploying"
bash "$APP/ops/deploy.sh" --build

newest="$(dc exec -T postgres psql -U wizesite -d wizesite -At -c "
  SELECT max(t) FROM (
    SELECT max(updated_at) AS t FROM expenses UNION ALL
    SELECT max(updated_at) FROM payments UNION ALL
    SELECT max(updated_at) FROM worker_entries UNION ALL
    SELECT max(updated_at) FROM projects) s")"
elapsed=$(( $(date -u +%s) - started ))
echo "==> restore finished in $((elapsed / 3600))h $((elapsed % 3600 / 60))m $((elapsed % 60))s"
echo "==> newest restored record: ${newest:-none}"
