# Production cutover: Firebase → VPS (tasks.md T102–T105)

Domain: `api.buildozer.dpdns.org`, `sync.buildozer.dpdns.org` (Cloudflare Tunnel to the VPS).
Firebase keeps Auth, Crashlytics, Remote Config and App Check.

Commands marked **VPS** run as root on the VPS (`./scripts/ssh-run.ps1 "<command>"` from the PC).
Commands marked **PC** run in the repo on your PC with the Firebase CLI signed in to `wize-site`.

## Record

| Field | Value |
|---|---|
| Announced to the second user (≥ 24 h before) | |
| `window_start` (UTC) | |
| `window_end` (UTC) | |
| `cutover_at` (UTC, step 7) | |
| Over 1 hour? Cause | |

Downtime budget: **< 1 hour** from step 2 to step 5 (SC-004).

## Before the window (day before)

- [ ] Rehearsals #1 and #2 recorded green in `specs/004-vps-backend-migration/rehearsals.md` (T103).
- [ ] Backups configured and fresh (`ops/BACKUPS.md`; `bash /srv/wizesite/app/ops/test/backup_lag_check.sh` exits 0), heartbeat and uptime monitor active (`ops/MONITORING.md`).
- [ ] New app build ready for both phones (Codemagic, `API_BASE_URL`/`SYNC_URL` set) but **not installed**.
- [ ] Latest server deployed: **VPS** `bash /srv/wizesite/app/ops/deploy.sh --build`; **PC** `DOMAIN=buildozer.dpdns.org VPS_IP=185.97.144.179 bash ops/test/deploy_smoke.sh`.
- [ ] Dry run of the migration: **VPS** `bash /srv/wizesite/app/ops/migrate.sh prod --dry-run` → `mismatches: 0`.
- [ ] Message the second user: time of the window, "keep the app open and online until I say so, then update".

## In the window

1. **Both phones: nothing pending.** Settings → Sync Status shows **0 pending** on both phones. Screenshot both.
   - [ ] done, `window_start` recorded

2. **Freeze Firebase.**
   - **PC** `firebase deploy --config firebase.readonly.json --only firestore:rules,storage`
   - **PC** `firebase functions:list` and delete every listed function:
     `firebase functions:delete <name> [<name> ...] --region us-central1 --force`
     (they stay in `functions/` for a rollback until T108).
   - Check: on a phone still on the old build, try to add an expense → it fails (stays pending).
   - [ ] done

3. **Final migration** into the VPS (replaces the staging contents).
   - **VPS** `bash /srv/wizesite/app/ops/migrate.sh prod --reload`
   - Check: exits 0, report `/srv/wizesite/state/migration/report-prod.json` shows `mismatches: 0`, all
     attachment MD5s equal, precision flags 0 (or each explained here: ____).
   - [ ] done

4. **RevenueCat webhook.** In the RevenueCat dashboard change the webhook URL from the Cloud Function
   to `https://api.buildozer.dpdns.org/v1/webhooks/revenuecat` (same Authorization value as
   `REVENUECAT_WEBHOOK_SECRET` in `/srv/wizesite/.env`). Send a test event.
   - Check: **VPS** `docker exec -u postgres wizesite-postgres-1 psql -U wizesite -d wizesite -c "select id, received_at from webhook_events order by received_at desc limit 3"` shows it.
   - [ ] done

5. **Install the new build on both phones.**
   - Check: still signed in; projects and totals visible and equal to the report; Remote Config flag
     and paid entitlements behave as before.
   - [ ] done, `window_end` recorded

6. **Offline test.** Phone A: airplane mode, add an expense with a photo, reconnect.
   - Check: it appears exactly once on phone B within 5 s, photo opens on both.
   - [ ] done

7. **Start the rollback window.** Record `cutover_at` above (UTC, now). From here every change on the
   VPS can be copied back to Firebase for 7 days.
   - [ ] done

## Seven-day watch (T105)

Each day, note issues below.

- [ ] Reconciler: `cat /srv/wizesite/state/reconcile/reconcile.json` → `"drift": []`
- [ ] Backup lag: `bash /srv/wizesite/app/ops/test/backup_lag_check.sh` exits 0
- [ ] Error rate: no heartbeat alert; `docker compose logs api --since 24h | grep -c '"statusCode":5'`

| Day | Date | Reconciler | Backups | Errors | Notes |
|---|---|---|---|---|---|
| 1 | | | | | |
| 2 | | | | | |
| 3 | | | | | |
| 4 | | | | | |
| 5 | | | | | |
| 6 | | | | | |
| 7 | | | | | |

## Rollback (only for a critical defect, only within 7 days)

1. Phones: stop using the app; Sync Status 0 pending if possible.
2. Create a Firebase service-account key that can write Firestore and Storage, put it at
   `/srv/wizesite/secrets/firebase-rollback.json` (mode 0600).
3. **PC** redeploy the old backend: `git checkout main -- firestore.rules storage.rules functions`
   (if changed) then `firebase deploy --only firestore:rules,storage,functions`.
4. **VPS** `bash /srv/wizesite/app/ops/rollback.sh "<cutover_at>" --dry-run`, check the counts, then
   `bash /srv/wizesite/app/ops/rollback.sh "<cutover_at>" --apply`.
5. Switch the RevenueCat webhook back to the Cloud Function URL.
6. Reinstall the previous app build on both phones.
7. Delete `/srv/wizesite/secrets/firebase-rollback.json` and the key in the Firebase console.

## Day 7

If the watch is clean: decommission the Firebase data (US4, T106–T108): verify first with the APIs
disabled, then `ops/decommission-firebase-data.sh`, then remove the Firebase data code from the repo.
