#!/usr/bin/env bash
# restic for the WizeSite files (tasks.md T093), run from the official image so nothing is
# installed on the host. Credentials: /srv/wizesite/secrets/restic.env (restic.env.example).
#
#   restic.sh backup        # back up /srv/wizesite/files (every 10 min, restic-files.timer)
#   restic.sh check         # verify the repository structure (daily, restic-check.timer)
#   restic.sh forget        # keep 30 days, prune (weekly, restic-forget.timer)
#   restic.sh init          # once, to create the repository
#   restic.sh <any restic args>   # e.g. snapshots --latest 1, restore latest --target /restore
set -euo pipefail

ROOT=/srv/wizesite
ENV_FILE="$ROOT/secrets/restic.env"
IMAGE="${RESTIC_IMAGE:-restic/restic:0.17.3}"
[[ -r "$ENV_FILE" ]] || { echo "missing $ENV_FILE (see ops/restic/restic.env.example)" >&2; exit 2; }

run() {
  docker run --rm --env-file "$ENV_FILE" \
    -v "$ROOT/files:/srv/wizesite/files:ro" \
    -v "$ROOT/restic-cache:/root/.cache/restic" \
    -v "${RESTORE_TARGET:-$ROOT/restore}:/restore" \
    --hostname wizesite "$IMAGE" "$@"
}

install -d -m 700 "$ROOT/restic-cache"
case "${1:-}" in
  backup) run backup --quiet --tag files /srv/wizesite/files ;;
  check) run check ;;
  forget) run forget --tag files --keep-within 30d --prune ;;
  "") echo "usage: restic.sh backup|check|forget|init|<restic args>" >&2; exit 2 ;;
  *) run "$@" ;;
esac
