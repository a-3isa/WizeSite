# Monitoring (tasks.md T095, T096)

Two independent signals. Either one alerts you within 5 minutes.

## 1. External uptime monitor (is the API reachable from the internet?)

Use any free uptime service (UptimeRobot, Better Stack, Healthchecks' HTTP checks):

- URL: `https://api.buildozer.dpdns.org/healthz` (200 and `"status":"ok"` when the database and
  sync service are up; 503 otherwise).
- Interval: 1 minute. Alert after **3 consecutive failures**.
- Alert channels: email **and** Telegram (most services have a Telegram integration; otherwise
  add a Telegram bot as a webhook).
- Optional second monitor: `https://sync.buildozer.dpdns.org/probes/liveness`.

This catches: VPS down, Docker down, Cloudflare Tunnel broken, API crash loop, database down.

## 2. Heartbeat from the VPS (is everything healthy inside?)

`ops/heartbeat.sh`, every 5 minutes from `heartbeat.timer`, checks:

| Check | Fails when |
|-------|-----------|
| Disk | `/srv/wizesite` filesystem ≥ 85 % used |
| Backups | newest archived WAL or restic snapshot older than 15 min (`ops/test/backup_lag_check.sh`) |
| API errors | ≥ 5 % of requests answered 5xx in the last 5 min (with at least 20 requests), from `GET /internal/stats` (loopback only, not public) |
| Reconciler | no run in 26 h, or money drift found (`/srv/wizesite/state/reconcile/reconcile.json`) |

Setup with [Healthchecks.io](https://healthchecks.io) (free):

1. Create a check: period 5 min, grace 5 min. Add the email and Telegram integrations.
2. Put its ping URL in `/srv/wizesite/secrets/heartbeat.env` (mode 0600):
   ```
   HEALTHCHECKS_URL=https://hc-ping.com/<uuid>
   # Until backups are configured (ops/BACKUPS.md):
   # HEARTBEAT_SKIP_BACKUPS=1
   ```
3. Enable the timer (see ops/BACKUPS.md step 6) and run it once by hand:
   `bash /srv/wizesite/app/ops/heartbeat.sh; echo $?`.

On success the check is pinged; on failure `/fail` is pinged with the reasons as the body, so the
alert says what broke. If the VPS dies, the pings stop and Healthchecks alerts after the grace
period.

## Reading logs

```
cd /srv/wizesite/app/server
docker compose logs api --since 1h          # API requests and errors
docker compose logs powersync --since 1h    # sync service
docker compose logs reconciler --since 24h  # nightly reconciler
journalctl -u heartbeat.service --since -1h # heartbeat results
journalctl -u restic-files.service -n 20    # file backups
docker exec -u postgres wizesite-postgres-1 pgbackrest --stanza=wizesite info   # database backups
```

## Drill (T098)

Stop the API (`docker stop wizesite-api-1`): the uptime monitor alerts within ~3 min and the
heartbeat reports `api: not answering`. Fill the disk past 85 % with a temporary file
(`fallocate -l <size> /srv/wizesite/drill.tmp`, remove afterwards): the heartbeat alerts. Record
both in `ops/drills/<date>-alerts.md`.
