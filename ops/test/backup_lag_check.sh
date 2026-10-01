#!/usr/bin/env bash
# Backup lag check (tasks.md T089, FR-019: at most 15 minutes of data at risk). Exit 0 when both
# backups are fresh, 1 with the reason on stderr otherwise. Used by ops/heartbeat.sh.
#
# Database: the newest archived WAL segment is at most MAX_LAG_MIN old, or nothing was written
#   since it (an idle database produces no WAL, so an old segment is not lag).
# Files: the newest restic snapshot is at most MAX_LAG_MIN old.
set -uo pipefail

MAX_LAG_MIN="${MAX_LAG_MIN:-15}"
PG_CONTAINER="${PG_CONTAINER:-wizesite-postgres-1}"
RESTIC="${RESTIC:-/srv/wizesite/app/ops/restic/restic.sh}"
failed=0

wal="$(docker exec -u postgres "$PG_CONTAINER" psql -U wizesite -d wizesite -AtF '|' -c "
  SELECT current_setting('archive_mode'),
         coalesce(extract(epoch FROM now() - last_archived_time)::int, -1),
         coalesce(last_archived_wal, ''),
         pg_walfile_name(pg_current_wal_lsn()),
         failed_count
  FROM pg_stat_archiver" 2>&1)" || { echo "database: cannot query archiver status: $wal" >&2; failed=1; wal=""; }

if [[ -n "$wal" ]]; then
  IFS='|' read -r mode age last current failures <<<"$wal"
  if [[ "$mode" != "on" ]]; then
    echo "database: WAL archiving is off (PG_ARCHIVE_MODE)" >&2; failed=1
  elif [[ "$age" -lt 0 ]]; then
    echo "database: no WAL segment archived yet" >&2; failed=1
  elif [[ "$current" != "$last" && "$age" -gt $((MAX_LAG_MIN * 60)) ]]; then
    echo "database: newest archived WAL is $((age / 60)) min old (failed attempts: $failures)" >&2; failed=1
  fi
fi

snap="$(bash "$RESTIC" snapshots --tag files --latest 1 --json 2>&1)" || { echo "files: cannot list restic snapshots: ${snap:0:200}" >&2; failed=1; snap=""; }
if [[ -n "$snap" ]]; then
  newest="$(grep -o '"time":"[^"]*"' <<<"$snap" | tail -1 | cut -d'"' -f4)"
  if [[ -z "$newest" ]]; then
    echo "files: no restic snapshot yet" >&2; failed=1
  else
    age=$(( $(date -u +%s) - $(date -u -d "$newest" +%s) ))
    if (( age > MAX_LAG_MIN * 60 )); then
      echo "files: newest restic snapshot is $((age / 60)) min old" >&2; failed=1
    fi
  fi
fi

exit "$failed"
