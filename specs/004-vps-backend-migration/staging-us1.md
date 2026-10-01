# US1 staging checkpoint (T056)

Staging stack: `api.buildozer.dpdns.org` / `sync.buildozer.dpdns.org` (shared Hostinger VPS, Cloudflare
Tunnel). Firebase remains production; this run is read-only against it.

## 1. Migration run — 2026-10-01 — PASS

Command (one-off container from the deployed API image, internal + edge networks, 512 MB cap):
`node dist/tools/migrate-from-firestore/index.js --target=staging --reset`
Report: `/srv/wizesite/state/migration/report-staging.json` (on the server, mode 700; the Firestore
snapshot used for the run sits next to it under `out/export/`).

Result: **OK — 0 mismatches**, 11 projects verified (totals recomputed from migrated rows = totals
from source records = stored `project_metrics`), 48 attachment files copied with matching MD5.

| Collection | Source | Skipped | Loaded |
|---|---:|---:|---:|
| users | 34 | 11 | 23 |
| workspaces | 41 | 11 | 30 |
| memberships | 43 | 12 | 31 |
| usage_counters | 7 | 4 | 3 |
| projects | 14 | 3 | 11 |
| workers | 7 | 2 | 5 |
| entities | 2 | 0 | 2 |
| expenses | 45 | 27 | 18 |
| payments | 27 | 19 | 8 |
| worker_entries | 11 | 8 | 3 |
| notifications | 2 | 0 | 2 |

Skipped = data of Firebase Auth accounts that no longer exist (and workspaces they owned), plus the
duplicates below. Collections not listed were empty.

### Findings fixed during the run

| Finding | Fix | Commit |
|---|---|---|
| `completion_percentage` holds arbitrary doubles (e.g. 32.807…), rejected by `NUMERIC(5,2)` | Column is `DOUBLE PRECISION` (not money), migration 004 | fc789b2 |
| Two owner memberships per (workspace, user) in 2 workspaces (canonical id + legacy random id, same role) | Merge; keep canonical id; conflicting roles block the load | f7eceeb |
| Blank `clientMutationId` collides on the `(workspace_id, client_mutation_id)` key | Blank loads as NULL; different records sharing an id block the load | a10b1d4 |
| One expense (50,000 EGP, 25 Jun, project ODxe9XiyW82ojGcS7hXK) stored twice by an offline retry | Keep earliest save `fHkEtJ2HFZoW735660Aa`, drop `jGF0A1NJ0BuOm3lLvWET` (owner's decision: fix in migration, not Firestore) | 1a03d91 |
| Explicit `null` in NOT NULL columns with defaults (e.g. `expenses.source`) | Loader applies the column default | 3d76ecb |
| `/srv/wizesite/files` root-owned; API image runs non-root | `deploy.sh` chowns it to the image's `app` user | 5c6dc64 |
| Server app tree was missing `tools/migrate-from-firestore`; `git archive` emitted CRLF | Deploy from `git -c core.autocrlf=false archive HEAD server ops` | — |

### Expected warnings (4)

- Project ODxe9XiyW82ojGcS7hXK: Firebase's stored metrics include the duplicate expense
  (totalExpenses 100,000 vs 50,000 from records; netProfit 100,000 vs 150,000). The recomputed value
  is used. The live Firebase app keeps showing the inflated figure until cutover.
- The dropped duplicate expense and the merged duplicate membership.

## 2. App check against staging — PASS (owner, 2026-10-01)

Run the app on the Android emulator (same app id as production, so not on the phone), signed in as
the owner, with `--dart-define=API_BASE_URL=https://api.buildozer.dpdns.org
--dart-define=SYNC_URL=https://sync.buildozer.dpdns.org`. Staging is **read-only** for US1: do not
add or edit records in this build.

- [x] Sign-in works and the "loading your data" gate clears (real Firebase token accepted by
      PowerSync — also closes the T012 token check)
- [x] Projects list and totals match the production app (except ODxe9XiyW82ojGcS7hXK: −50,000 EGP
      expenses, by design)
- [x] Expenses, payments, workers, worker entries, contacts match per project
- [x] Dashboard and reports match
- [x] An attachment opens; after turning networking off, it opens again from the device cache
- [x] With networking off after the first sync, the app still shows all data

Owner confirmed all items on 2026-10-01 (emulator, signed in with the production account).
