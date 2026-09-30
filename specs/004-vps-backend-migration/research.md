# Research: Migrate Backend Data & Logic from Firebase to Self-Hosted VPS

**Feature**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md) | **Date**: 2026-09-30

Each entry: **Decision / Rationale / Alternatives considered**. All Technical Context unknowns are
resolved here.

## Baseline: what exists today (measured 2026-09-30)

| Surface | Current state | Migration consequence |
|---|---|---|
| Client Firestore use | 38 `lib/` files import `cloud_firestore`; 45 `.snapshots()` listeners; 48 `.get()` reads; 71 `orderBy/limit/startAfter` query sites | Every read path must be re-pointed to a local database |
| Client direct writes | ~13 direct writes bypass functions (entities, contractor/equipment/transport accounting records, notifications read-flag, user settings, membership in session restore) guarded only by `firestore.rules` | Must move behind server endpoints; no direct DB writes from client |
| Server logic | `functions/src/index.ts` 5,384 lines, 38 callables, 9 HTTP twins, 5 `onDocumentWritten` recompute triggers, RevenueCat webhook, voice pipeline (OpenRouter) | Business logic ported; Firestore data-access layer rewritten |
| Server write mechanics | 8 `runTransaction`, 81 `FieldValue.*` uses (increment, serverTimestamp, …) | Map to SQL transactions and column arithmetic |
| Authorization | `firestore.rules` 518 lines, 28 collections; `storage.rules` 4 path families | Re-expressed as API authorization + sync rules |
| Indexes | 58 composite Firestore indexes | Replaced by Postgres indexes on server, SQLite indexes on client |
| Offline | Firestore on-device cache (reads) + Hive `OfflineActionQueue` (writes, retries, id remap) replayed via `CallableClient` | Hive queue kept; read cache replaced |
| Client chokepoint | `lib/core/services/callable_client.dart` wraps every callable with auth + App Check refresh + telemetry | Single swap point for transport |
| Storage | `receipts/`, `attachments/`, `voice-expenses/`, `profile-photos/` keyed by `{userId}` | Files move to VPS disk; paths preserved as keys |
| Forked package | `packages/cloud_firestore` path override (6.6.0) | Removed with Firestore |

## R1. Server data store

**Decision**: PostgreSQL 17, single instance on the VPS.

**Rationale**: Financial data with multi-row invariants (quota counters + record + summaries
changed together) needs real ACID transactions and constraints (FKs, CHECK on money, UNIQUE on
idempotency keys). Postgres gives point-in-time recovery via WAL archiving, which is how the 15-min
RPO (FR-019) is met cheaply. It is also the only store PowerSync (R3) can replicate from with
Postgres bucket storage, so one database engine serves both roles. Memory footprint tunable to
~768 MB within the 4 GB budget.

**Alternatives considered**:
- *SQLite (e.g. PocketBase)*: tiny, but PITR is weaker (Litestream is a separate moving part),
  no native logical replication for a sync engine, and single-writer limits concurrent webhook +
  API writes.
- *MongoDB (closest to Firestore's document model)*: easier data port, but weaker multi-document
  integrity story for accounting, higher RAM, and PowerSync would then need Mongo for bucket
  storage too — two heavy engines on 4 GB.
- *Self-hosted Supabase*: bundles Postgres + realtime + storage, but ~10 containers realistically
  need >4 GB, its auth is unused (sign-in stays on Firebase), and it still has no offline read
  cache for Flutter.

## R2. Server runtime & API shape

**Decision**: Node.js 22 + TypeScript (same as today) with Fastify, `postgres` (postgres.js) driver,
SQL migrations via `node-pg-migrate`. Expose an **RPC-over-HTTPS** API that mirrors the existing
callables one-to-one: `POST /v1/rpc/{functionName}` with the same request payload and response
shape, and errors carrying the same `HttpsError`-style codes.

**Rationale**: The 5.4k lines of business logic (`classifyProjectRisk`, `buildAccountingSummaryPayloads`,
`workerAccountingAmounts`, money helpers, idempotency, voice parser, RevenueCat status mapping) are
largely pure functions and port unchanged; only the Firestore access layer is rewritten. Keeping
the callable contract means the client change is confined to `CallableClient` and the offline
queue replays the same payloads — preserving Constitution I and IV. Existing `node --test` suites
for pure logic keep running as-is.

**Alternatives considered**:
- *REST resource redesign*: cleaner URLs, but touches every client call site and the offline
  queue payload format for no user value.
- *Go/Rust rewrite*: lower RAM, but discards tested logic — violates "preserve behavior".
- *GraphQL*: no benefit for a fixed first-party client.

## R3. Offline read parity & real-time updates (FR-005, FR-006, SC-006)

**Decision**: **PowerSync Open Edition (self-hosted)** with Postgres as its bucket storage, and the
`powersync` Flutter SDK (local SQLite on device). Writes do **not** go through PowerSync's CRUD
upload path; they continue through the existing Hive `OfflineActionQueue` → RPC API. PowerSync is
used as a read-replication + live-update channel only.

**Rationale**: Clarification Q5 requires full offline browsing parity with Firestore's cache.
Building a correct incremental sync protocol (checkpoints, deletes, per-user scoping, resumable
streams) is the riskiest bespoke work in the whole migration; PowerSync provides exactly this,
self-hostable, with Postgres bucket storage (service image ≥1.3.8) so no MongoDB is needed.
It validates Firebase ID tokens directly via Firebase's public JWKS, so no token exchange service
is required. Real-time propagation (SC-006, 5 s) comes from Postgres logical replication streamed
to clients. Keeping writes in the existing queue preserves the tested retry, id-remap and
error-classification behavior.

**Alternatives considered**:
- *Custom sync (Drift + `updated_at` cursor pulls + WebSocket "changed" pings)*: full control and
  no extra service, but delete propagation, per-workspace scoping and consistency across related
  tables must all be hand-built and tested; estimated 2–3× the client effort.
- *ElectricSQL*: read-path sync for Postgres, but no first-class Flutter SDK.
- *Online-only reads with HTTP cache*: rejected by clarification Q5.

**Risks & mitigations**: PowerSync Open Edition is source-available (FSL), fine for own use.
Resource budget ~512–768 MB. A spike task (Phase 0 of tasks) must prove: Firebase JWT accepted,
workspace-scoped sync rule works, 5 s propagation on the target VPS.

## R4. Keeping Firebase Auth & App Check (FR-009, FR-010)

**Decision**: The API verifies every request with `firebase-admin`:
`auth().verifyIdToken(idToken, checkRevoked=false)` from `Authorization: Bearer`, and
`appCheck().verifyToken()` from the `X-Firebase-AppCheck` header. PowerSync validates the same ID
token via JWKS `https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com`,
audience `wize-site`. User identity = Firebase `uid`, unchanged.

**Rationale**: Both are Firebase-hosted verification services that work from any server with a
service account; nothing about sign-in or device attestation changes for the client, and
`CallableClient` already fetches both tokens. The same service account supports `auth().deleteUser`
for account deletion (FR-014).

**Alternatives considered**: own JWT issuance after exchanging the Firebase token — an extra hop
and key management for no gain.

## R5. Attachment storage (FR-001, FR-011)

**Decision**: Files on the VPS filesystem under `/srv/wizesite/files/{original-storage-path}`,
written and read only through the API. Uploads: `POST /v1/files` (multipart) with the same
content-type and size limits as `storage.rules`. Downloads: existing `getAttachmentDownloadUrl`
RPC returns a short-lived (15 min) HMAC-signed URL served by the API. Original Storage object paths
are preserved as keys so record metadata needs no rewrite.

**Rationale**: Two users; volume is small. Filesystem + signed URLs is the smallest-footprint
option and mirrors today's semantics (download URL obtained through a callable).

**Alternatives considered**:
- *MinIO*: S3 API, but another ~300 MB service, and its community edition has been feature-reduced.
- *Garage / SeaweedFS*: viable S3-compatible stores, unnecessary at this scale.
- *External object storage (R2/B2) as primary*: removes disk risk but adds a third-party data
  dependency the owner wants to avoid; used for backups only (R7).

## R6. Replacing `onDocumentWritten` recompute triggers (FR-003)

**Decision**: Recompute derived rows (project_metrics, accounting summaries, worker accounting
summaries, workspace_metrics, risk classification) **synchronously inside the same SQL transaction**
as the mutating RPC, using the ported pure builders. A nightly reconciliation job recomputes all
projects and logs any drift.

**Rationale**: All writes now pass through the API (R2/R3), so there is no "write happened
elsewhere" case that needs a trigger. Same-transaction recompute removes today's eventual
consistency window and the trigger retry/loop hazards (`writeIfChanged`, `shallowEqualDerivedState`
stay useful to avoid no-op updates flooding sync). Per-project recompute over two users' data is
milliseconds.

**Alternatives considered**: Postgres triggers in PL/pgSQL (duplicates tested TS logic in another
language); outbox + worker queue (async again, more parts).

## R7. Backups & restore (FR-019, FR-020, SC-008)

**Decision**:
- Postgres: **pgBackRest** with WAL archiving (`archive_timeout = 60s`) to an S3-compatible bucket
  off the VPS (Backblaze B2 or Cloudflare R2), daily full/diff backups, 30-day retention → PITR to
  any point in 30 days, worst-case loss ≈ 1 min (well within 15 min).
- Files: **restic** to the same off-site bucket every 10 minutes (systemd timer) plus daily
  `restic check`; 30-day retention via `forget --keep-within 30d`.
- Restore drill scripted (`ops/restore.sh`) and executed on a throwaway VPS before cutover.

**Rationale**: pgBackRest is the standard PITR tool and very light. Restic is deduplicated and
encrypted client-side, so the off-site provider never sees plaintext financial documents.

**Alternatives considered**: WAL-G (equally good; pgBackRest chosen for built-in retention and
verify); nightly `pg_dump` only (fails 15-min RPO); provider VPS snapshots (same failure domain).

## R8. Deployment & TLS (FR-018, FR-022)

**Decision**: Docker Compose on the VPS: `caddy`, `api`, `postgres`, `powersync`. Caddy terminates
TLS with automatic Let's Encrypt certificates for `api.<domain>` and `sync.<domain>` (clarification
Q4). Images built by CI, deployed by `ops/deploy.sh` (pull + `docker compose up -d` + migration
run + health check); secrets in `/srv/wizesite/.env` (root-only), never in repo. Firewall: only
22 (key-only SSH), 80, 443 open; Postgres not exposed.

**Rationale**: Reproducible from repo, no manual server edits, fits the owner's single-server
operator model.

**Alternatives considered**: Kubernetes/k3s (overkill, RAM); bare systemd services (less
reproducible); Nginx + certbot (more config than Caddy).

## R9. Monitoring & alerting (FR-021)

**Decision**: External uptime check (free tier of Healthchecks.io/UptimeRobot) on
`https://api.<domain>/healthz` every 1 min, alert after 3 consecutive failures, delivered by
email + Telegram. On-box cron pushes a heartbeat that fails if disk > 85%, backup lag > 15 min,
or API 5xx rate > 5% over 5 min. API logs as JSON to journald with 14-day retention.

**Rationale**: An external probe is required to detect "server down" — an on-box monitor dies with
the server. Zero extra containers on the 4 GB box.

**Alternatives considered**: Uptime Kuma / Prometheus + Grafana on the same VPS (RAM, and blind
when the VPS is down).

## R10. Data migration mechanics (FR-010–FR-014, SC-001)

**Decision**: A one-shot TypeScript migrator (`server/tools/migrate-from-firestore`) using
`firebase-admin`:
1. Export every collection in scope to NDJSON (+ Storage objects with MD5 from metadata).
2. Transform to relational rows: Firestore doc IDs kept as primary keys (TEXT); `Timestamp` → `timestamptz` UTC;
   money kept in the same unit/representation as `money.ts`; unknown fields preserved in a
   `legacy jsonb` column (Constitution II — no silent loss).
3. Skip data for uids that no longer exist in Firebase Auth (FR-014).
4. Load in one transaction per collection group; upload files; verify MD5.
5. **Verification report**: per-collection counts, per-project totals recomputed from raw source
   rows vs. from migrated rows vs. migrated summary rows, attachment count + checksum; any mismatch
   → non-zero exit.
Runs repeatedly against staging (FR-013).

**Rationale**: Preserving IDs means attachment paths, offline-queue references and deep links keep
working; recomputing totals from raw rows on both sides catches both transform bugs and
pre-existing summary drift.

## R11. Cutover & 7-day rollback (FR-015, FR-016, FR-017)

**Decision**:
1. Both users sync (Sync Status screen shows 0 pending) and stop using the app.
2. Deploy `firestore.rules`/`storage.rules` set to deny all writes; disable Cloud Functions
   (delete triggers/callables deployment) → old backend read-only (FR-017).
3. Final migration + verification report green.
4. Both users install the new build (points to `api.`/`sync.<domain>`), sign in state preserved.
5. Days 0–7: `tools/rollback-to-firestore` can export rows with `updated_at > cutover_at` (and
   tombstones) back into Firestore and re-enable rules/functions.
6. Day 7: delete Firestore data + Storage objects; disable Firestore/Storage/Functions APIs.

## R12. Testing strategy (Constitution III)

**Decision**:
- Server pure-logic tests: existing `node --test` suites ported as-is.
- Server integration tests: real Postgres via Docker (`docker compose -f compose.test.yml`), one
  test file per RPC group covering quota, refund, cascade delete, recompute parity, authorization
  per role, idempotent replay.
- **Parity harness**: run the same scripted scenario against the old functions (emulator) and new
  API, compare resulting derived rows.
- Firestore rules tests → replaced by API authorization tests + PowerSync sync-rule tests
  (a user never receives another workspace's rows).
- Flutter: repositories get an in-memory PowerSync/SQLite test DB replacing `fake_cloud_firestore`;
  widget tests unchanged where they mock repositories.

## R13. RAM budget (4 GB / 2 vCPU)

| Component | Budget |
|---|---|
| Postgres (shared_buffers 512 MB) | ~900 MB |
| PowerSync service | ~600 MB |
| API (Node) | ~250 MB |
| Caddy | ~50 MB |
| pgBackRest/restic bursts | ~200 MB |
| OS + page cache headroom | ~1.9 GB |

Swap 2 GB as safety net. Fits with margin.
