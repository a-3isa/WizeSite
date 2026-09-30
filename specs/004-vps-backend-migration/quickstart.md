# Quickstart: VPS Backend — Develop, Verify, Cut Over

**Feature**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

## 1. Local development

```bash
cd server
cp .env.example .env               # FIREBASE_PROJECT_ID=wize-site, GOOGLE_APPLICATION_CREDENTIALS, FILES_SIGNING_KEY, OPENROUTER_*, REVENUECAT_WEBHOOK_SECRET
docker compose -f compose.dev.yml up -d   # postgres + powersync
npm ci && npm run migrate && npm run dev  # API on http://localhost:8080
npm test                                  # pure-logic + Postgres integration tests
```

Flutter against local backend:

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080 --dart-define=SYNC_URL=http://10.0.2.2:8081
flutter analyze 2>&1 | Select-Object -First 80
flutter test --reporter compact
```

## 2. Staging rehearsal (repeat until green — FR-013)

1. Provision a throwaway VPS (same size) and run `ops/bootstrap.sh` then `ops/deploy.sh staging`.
2. `npm run migrate:firestore -- --target=staging --report=out/report.json`
3. Report must show: every collection count equal, every per-project total equal, every attachment MD5 equal,
   `mismatches: 0`, flagged money precision issues: 0 (or each explained).
4. Install a staging build on a test device, sign in with the owner account, and walk the manual
   parity checklist (§4).
5. Restore drill: `ops/restore.sh --pitr "<timestamp>"` onto a second fresh VPS; confirm app works and
   data is at most 15 min old. Time it (SC-008: < 4 h).

## 3. Production cutover (single window, both users present)

| # | Step | Check |
|---|---|---|
| 1 | Both phones: Settings → Sync Status shows **0 pending** | screenshot |
| 2 | Deploy read-only `firestore.rules` + `storage.rules`; remove Cloud Functions | write attempt from old app fails |
| 3 | `npm run migrate:firestore -- --target=prod` | report `mismatches: 0` |
| 4 | Switch RevenueCat webhook URL | test event → 200, row in `webhook_events` |
| 5 | Install new build on both phones | still signed in; data visible; totals match report |
| 6 | Record one expense with photo offline → reconnect | appears once on other phone ≤ 5 s |
| 7 | Record `cutover_at` in `ops/CUTOVER.md` | rollback window starts |

Downtime budget: < 1 hour from step 2 to step 5 (SC-004). Announce the window to the second user at
least 24 hours ahead, and record `window_start`/`window_end` in `ops/CUTOVER.md`.

Rollback (only within 7 days): `npm run rollback:firestore -- --since="$cutover_at"`, re-deploy old rules
and functions, reinstall previous build.

Day 7: `ops/decommission-firebase-data.sh` (deletes Firestore data + Storage objects; leaves Auth,
Crashlytics, Remote Config, App Check).

## 4. Manual parity checklist (Constitution III — manual path)

- [ ] Create project with and without contract value; payment blocked on no-contract project
- [ ] Create/edit/archive expense, payment, worker entry; quota decrements/refunds
- [ ] Free tier at limit → same blocked message (EN + AR)
- [ ] Voice note → draft expense matched to project
- [ ] Attachment upload offline → reconnect → opens on second phone
- [ ] Airplane mode: browse all projects, totals, previously opened attachments
- [ ] First launch of new build offline → "connect to load your data" state
- [ ] Member role cannot see gated financial data
- [ ] Delete project cascade removes children and files
- [ ] Reports/export produce same totals as before migration
- [ ] Arabic text and non-ASCII file names intact
- [ ] A Remote Config flag changed in the Firebase console takes effect in the app (FR-008)
- [ ] A paid workspace keeps its entitlements and quota limits after migration (US1 scenario 4)

## 5. Operations

- Deploy: `ops/deploy.sh prod` (CI-built image tag). Health: `curl https://api.<domain>/healthz`.
- Logs: `journalctl -u docker -f` / `docker compose logs api --since 1h`.
- Backups: `pgbackrest info`, `restic snapshots`. Alerts via external uptime monitor + heartbeat.
