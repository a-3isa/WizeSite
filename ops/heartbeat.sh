#!/usr/bin/env bash
# Host heartbeat (tasks.md T095), every 5 minutes from heartbeat.timer. Checks:
#   - disk use of /srv/wizesite below DISK_MAX_PCT (85 %)
#   - backup lag (ops/test/backup_lag_check.sh)
#   - API 5xx rate below 5 % over the last 5 minutes (GET /internal/stats, loopback only)
#   - the nightly reconciler ran in the last 26 h with no drift
# All pass: ping the Healthchecks.io check. Any fail: ping <url>/fail with the reasons, so the
# alert says what broke. Settings: /srv/wizesite/secrets/heartbeat.env (HEALTHCHECKS_URL=...).
set -uo pipefail

ROOT=/srv/wizesite
APP="$ROOT/app"
[[ -r "$ROOT/secrets/heartbeat.env" ]] && source "$ROOT/secrets/heartbeat.env"
DISK_MAX_PCT="${DISK_MAX_PCT:-85}"
API_CONTAINER="${API_CONTAINER:-wizesite-api-1}"
problems=()

# Disk.
used="$(df --output=pcent "$ROOT" | tail -1 | tr -dc '0-9')"
(( used < DISK_MAX_PCT )) || problems+=("disk ${used}% used (limit ${DISK_MAX_PCT}%)")

# Backups. HEARTBEAT_SKIP_BACKUPS=1 only until the backup repository is set up (ops/BACKUPS.md).
if [[ "${HEARTBEAT_SKIP_BACKUPS:-0}" != 1 ]]; then
  if ! lag="$(bash "$APP/ops/test/backup_lag_check.sh" 2>&1)"; then
    problems+=("backups: ${lag//$'\n'/; }")
  fi
fi

# API error rate.
stats="$(docker exec "$API_CONTAINER" node -e "fetch('http://127.0.0.1:8080/internal/stats').then(r=>r.text()).then(t=>console.log(t)).catch(()=>process.exit(1))" 2>/dev/null)"
if [[ -z "$stats" ]]; then
  problems+=("api: not answering")
else
  requests="$(grep -o '"requests":[0-9]*' <<<"$stats" | cut -d: -f2)"
  errors="$(grep -o '"errors5xx":[0-9]*' <<<"$stats" | cut -d: -f2)"
  # Need a few requests before a rate means anything.
  if (( ${requests:-0} >= 20 && ${errors:-0} * 100 >= ${requests:-0} * 5 )); then
    problems+=("api: ${errors}/${requests} requests failed with 5xx in 5 min")
  fi
fi

# Reconciler.
state="$ROOT/state/reconcile/reconcile.json"
if [[ ! -r "$state" ]]; then
  problems+=("reconciler: no result yet")
else
  finished="$(grep -o '"finishedAt": *"[^"]*"' "$state" | cut -d'"' -f4)"
  age=$(( $(date -u +%s) - $(date -u -d "${finished:-1970-01-01T00:00:00Z}" +%s) ))
  (( age <= 26 * 3600 )) || problems+=("reconciler: last run $((age / 3600)) h ago")
  grep -q '"drift": *\[\]' "$state" || problems+=("reconciler: drift found (see $state)")
fi

if (( ${#problems[@]} == 0 )); then
  [[ -n "${HEALTHCHECKS_URL:-}" ]] && curl -fsS -m 10 --retry 3 -o /dev/null "$HEALTHCHECKS_URL"
  exit 0
fi

report="$(printf '%s\n' "${problems[@]}")"
echo "$report" >&2
[[ -n "${HEALTHCHECKS_URL:-}" ]] && curl -fsS -m 10 --retry 3 -o /dev/null --data-raw "$report" "$HEALTHCHECKS_URL/fail"
exit 1
