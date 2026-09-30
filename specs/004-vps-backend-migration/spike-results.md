# Spike Results (T012) — PowerSync go/no-go

**Status**: ⏳ PARTIAL. Local checks pass; the checks that need the real VPS, a real Firebase token and a
real phone are still open.

## Verified locally (2026-09-30, Docker Desktop, Postgres 17 + PowerSync service `latest`)

| Check | Result | Evidence |
|---|---|---|
| PowerSync service starts with Postgres bucket storage (no MongoDB) | ✅ | `server/compose.test.yml`; logs "Service started", "Replicating" |
| Sync rules load | ✅ after fix | `IN (...)` lists are rejected in parameter queries: one equality query per role |
| Workspace scoping / no cross-workspace leak | ✅ 0 rows | `server/test/sync/sync_rules.test.ts` (8 tests) |
| Financial rows hidden from plain members; visible to owner/admin/accountingApproved/workspace owner | ✅ | same suite |
| Membership removal and deletes propagate | ✅ | same suite |
| JWT auth via configured keys (HS256 test key) | ✅ | same suite; production config uses the Firebase JWKS URL instead |
| Local replication lag (write → visible on a fresh sync) | ✅ ~0.6 s | same suite timings |
| Flutter SDK (`powersync` 2.4.0) opens a DB with the generated schema, incl. Arabic text | ✅ | `test/helpers/local_db_test.dart`, `test/core/pagination/local_page_test.dart` |

### Findings to carry forward

- Postgres 17 logical replication does **not** publish generated columns, so tables keyed by something other
  than `id` alias their key in the sync rules (`SELECT uid AS id, ...`).
- A sync-rules version that fails to load is persisted and replayed; recover with a clean redeploy.

## Staging deployment (2026-09-30)

| Check | Result |
|---|---|
| Stack deployed on the owner's VPS (`/srv/wizesite`, compose project `wizesite`) via `ops/deploy.sh --build` | ✅ |
| Migrations 001–003 applied; PowerSync replicating all 26 published tables | ✅ |
| `/healthz` → `{"status":"ok","db":"ok","sync":"ok"}` | ✅ |
| Memory at idle: powersync 94 MB, api 32 MB, postgres 64 MB (caps 512/192/640 MB) | ✅ well under budget |
| No host ports published; existing services on the shared box untouched | ✅ |
| Public route `api.`/`sync.buildozer.dpdns.org` via Cloudflare Tunnel | ✅ HTTPS 200 on `/healthz` and `/probes/liveness`, valid certificates; unauthenticated API and sync calls → 401 |

Host differs from the plan's assumption: shared box, **1 vCPU**, no swap, existing Traefik on 80/443 → routing
through Cloudflare Tunnel instead of Caddy; memory caps lowered (see `server/compose.yml`).

## Still open (needs the public route and a real phone)

| Check | Pass criterion |
|---|---|
| Real Firebase ID token accepted via `jwks_uri` + audience `wize-site` | 200 on `/sync/stream` |
| p95 propagation over 50 writes, API → second phone | ≤ 5 s |
| RAM per container on the 4 GB box under light load | Within research R13 budget |
| Offline: write through the Hive queue, reconnect, row returns via sync | Exactly one row |

**Go/no-go decision**: pending the open checks. If the real-token check fails, the fallback is a token-exchange
endpoint on the API that mints a sync JWT (research R3/R4); if propagation or RAM fails, revisit research R3.
