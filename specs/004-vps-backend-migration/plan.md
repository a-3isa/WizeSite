# Implementation Plan: Migrate Backend Data & Logic from Firebase to Self-Hosted VPS

**Branch**: `004-vps-backend-migration` | **Date**: 2026-09-30 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/004-vps-backend-migration/spec.md`

## Summary

Move WizeSite's database, attachment files and all server logic from Firebase (Firestore, Storage,
Cloud Functions) to the owner's 4 GB / 2 vCPU VPS. Firebase Auth, App Check, Crashlytics and Remote
Config stay. Two live users, whose data is migrated with a verification report, one coordinated
cutover, and a 7-day read-only rollback window.

Technical approach, in four parts:

1. **Same contract, new transport.** A Node 22/TypeScript API (Fastify + PostgreSQL 17) exposes every
   existing callable as `POST /v1/rpc/{name}`. Payloads, results and error codes are unchanged. Pure
   business logic is ported from `functions/src` without changes. Only the Firestore access layer is
   rewritten as SQL. On the client, only `CallableClient` changes, and the Hive offline queue keeps
   replaying the same payloads.
2. **Offline reads via PowerSync.** A self-hosted PowerSync Open Edition service replicates each
   user's workspaces from Postgres into a local SQLite database on the device. This replaces Firestore's
   offline cache and live listeners, giving full offline browsing (clarification Q5) and ≤ 5 s live
   updates. It authenticates with the existing Firebase ID token through Firebase's public JWKS, so no
   token exchange is needed.
3. **All writes go through the API.** About 13 direct client Firestore writes become new RPCs. The 5
   Firestore triggers become in-transaction recomputes of derived summaries, which removes today's
   eventual-consistency window.
4. **Operator-grade single server.** Docker Compose (Caddy/API/Postgres/PowerSync) with automatic
   TLS on `api.`/`sync.<domain>`. pgBackRest WAL archiving plus restic take off-site backups (RPO about
   1 min, well within the 15 min target), with a scripted and rehearsed restore, external uptime
   alerting, and a migrator that emits a verification report.

The riskiest parts are (a) replacing 45 live Firestore listeners and 48 one-shot reads across 38
client files with local SQLite queries, and (b) proving that migrated money totals are identical. Both
are gated by a spike and a staging rehearsal before cutover.

## Technical Context

**Language/Version**: Dart 3 / Flutter (client, unchanged toolchain); TypeScript on Node.js 22 (server, same as today's functions)

**Primary Dependencies**: Server: Fastify, postgres.js, node-pg-migrate, firebase-admin (Auth + App Check verification, Auth user deletion, migration export only), OpenRouter (voice, unchanged). Sync: PowerSync Open Edition service (self-hosted, Postgres bucket storage). Client: `powersync` Flutter SDK, `http`; keep `firebase_core`, `firebase_auth`, `firebase_app_check`, `firebase_crashlytics`, `firebase_remote_config`, `google_sign_in`, `hive`, RevenueCat; **remove** `cloud_firestore` (+ `packages/cloud_firestore` fork), `firebase_storage`, `cloud_functions`, `fake_cloud_firestore`

**Storage**: PostgreSQL 17 on VPS (source of truth); VPS filesystem `/srv/wizesite/files` for attachments; device SQLite (PowerSync) + Hive (offline queue, pending attachments); off-site S3-compatible bucket (B2/R2) for encrypted backups only

**Testing**: `node --test` (ported pure-logic suites) + Postgres integration tests via Docker; parity harness comparing old functions (emulator) and new API outputs; PowerSync sync-rule tests; `flutter test` with in-memory PowerSync DB replacing `fake_cloud_firestore`; manual parity checklist in [quickstart.md](./quickstart.md)

**Target Platform**: Server: single Linux VPS, 4 GB RAM / 2 vCPU, Docker Compose. Client: Android + iOS

**Project Type**: Mobile app + self-hosted API/sync backend

**Performance Goals**: p95 RPC < 500 ms server-side (SC-005: user actions < 2 s end-to-end); cross-device propagation ≤ 5 s p95 (SC-006); full restore < 4 h (SC-008)

**Constraints**: RAM budget fits 4 GB (research R13); RPO ≤ 15 min (FR-019); availability ≥ 99.5 % (SC-009); no client-side direct DB writes; Arabic/RTL and non-ASCII filenames preserved; Firebase Auth uid remains the identity key

**Scale/Scope**: 2 users, 1–2 workspaces, small data volume. Code scope: 38 client files importing Firestore, 45 listeners, 48 reads, ~13 direct writes; 38 callables + webhook + 5 triggers + voice pipeline in a 5,384-line `functions/src/index.ts`; 28 Firestore collections; 58 composite indexes; 518 lines of rules

**Unknowns**: None. All resolved in [research.md](./research.md). One validation spike is required before the rest of the build (PowerSync + Firebase JWT + workspace bucket + 5 s propagation on the target VPS).

## Constitution Check

*GATE: evaluated before Phase 0 and re-evaluated after Phase 1 design.*

Evaluated against **constitution 2.0.0** (amended 2026-09-30 for this feature; the 1.0.0 wording
named Firebase services and is superseded).

| Principle / Constraint | Status | How the plan complies |
|---|---|---|
| **I. Preserve Existing Product Behavior** (backend replacement allowed when spec-required + proven by parity/regression tests; contracts preserved) | ✅ | Spec 004 requires the replacement. RPC payloads, results and error codes unchanged; offline queue, id-remap and UI behavior unchanged; business logic ported; parity harness proves equivalence. |
| **II. Accounting Correctness & Traceability** (incl. migration verification report) | ✅ | NUMERIC money, CHECK constraints, same-transaction recompute, nightly reconciler, `legacy jsonb`; migrator report with `mismatches: 0` required. |
| **III. Test-Backed Change Discipline** | ✅ | Ported pure-logic tests; Postgres integration, authorization, sync-rule and parity tests; manual checklist in quickstart. Baseline tests green before the port. |
| **IV. Offline, Security & Recovery First** (incl. role gating in synced data, off-site backups, tested restore) | ✅ | Hive queue + `X-Idempotency-Key` + `clientMutationId`; role gating in API **and** `workspace_financial` sync bucket; pgBackRest PITR + restic off-site; restore drill before cutover; 7-day rollback. |
| **V. Scalable Data Access** (incl. on-device queries, workspace-scoped sync) | ✅ | Screens paginate local SQLite queries; sync buckets scoped to active memberships. Revisit date-windowed buckets if a workspace exceeds ~100k rows. |
| Constraint: metadata-only records; file store or pending storage holds files | ✅ | `attachments` table metadata only; files on VPS disk; Hive pending storage unchanged. |
| Constraint: backend-enforced integrity, client not sole enforcer | ✅ | All writes via API; Postgres constraints; sync rules. |
| Constraint: indexes only for implemented queries (server + device) | ✅ | Postgres/SQLite indexes derived from actual query sites. |
| Constraint: reproducible self-hosted deploy; secrets out of repo/bundle | ✅ | `ops/deploy.sh` + Compose from repo; secrets in root-only `.env` on VPS. |
| Workflow gate: `flutter analyze`, `flutter test`, backend tests | ✅ | In quickstart and every delivery slice. |

**Gate result: PASS.** No violations.

**Post-design re-check (after Phase 1)**: data model, contracts and quickstart introduce no violations;
the role split in `sync-rules.md` satisfies Principle IV's synced-data clause. PASS.

## Project Structure

### Documentation (this feature)

```text
specs/004-vps-backend-migration/
├── plan.md              # This file
├── research.md          # Phase 0: decisions R1–R13
├── data-model.md        # Phase 1: Postgres schema + Firestore mapping
├── quickstart.md        # Phase 1: dev, staging rehearsal, cutover, manual parity checklist
├── contracts/
│   ├── rpc-api.md       # RPC envelope, auth, idempotency, function catalogue
│   ├── files-api.md     # Upload / signed download (replaces Storage)
│   ├── sync-rules.md    # PowerSync auth + buckets + role gating
│   └── webhooks.md      # RevenueCat
├── checklists/requirements.md
└── tasks.md             # Phase 2 (/speckit-tasks)
```

### Source Code (repository root)

```text
server/                          # NEW — replaces functions/ after cutover
├── src/
│   ├── app.ts                   # Fastify bootstrap, /healthz
│   ├── auth/                    # Firebase ID token + App Check verification, role guard
│   ├── rpc/                     # one module per callable group; router maps /v1/rpc/:name
│   ├── domain/                  # PORTED pure logic from functions/src (money, risk, summaries, voice parser, revenuecat_status, idempotency)
│   ├── db/                      # postgres.js pool, repositories, transaction helper
│   ├── recompute/               # in-transaction derived-state builders + nightly reconciler
│   ├── files/                   # upload, signed URLs, storage-path policy
│   └── webhooks/revenuecat.ts
├── migrations/                  # node-pg-migrate SQL migrations
├── tools/
│   ├── migrate-from-firestore/  # export → transform → load → verify report
│   └── rollback-to-firestore/   # 7-day window reverse sync
├── test/                        # unit (ported), integration (Postgres), parity, sync-rules
├── powersync/powersync.yaml     # sync rules (contracts/sync-rules.md)
├── Dockerfile
├── compose.yml / compose.dev.yml / compose.test.yml
└── package.json

ops/                             # NEW — VPS operations
├── bootstrap.sh                 # firewall, docker, swap, users, dirs
├── deploy.sh                    # pull image, migrate, up -d, health check
├── Caddyfile                    # api.<domain>, sync.<domain>, auto-TLS
├── pgbackrest.conf, restic.env.example, backup timers (systemd)
├── restore.sh
├── heartbeat.sh                 # disk / backup-lag / 5xx → external monitor
├── decommission-firebase-data.sh
└── CUTOVER.md                   # runbook + cutover_at record

lib/                             # EXISTING Flutter app — modified
├── core/services/callable_client.dart        # transport swap → RPC API (single chokepoint)
├── core/services/storage_upload_service.dart # → POST /v1/files
├── core/providers/firebase_providers.dart    # drop Firestore/Storage/Functions providers
├── core/sync/                                # NEW: PowerSync db, schema, connector (Firebase token)
└── features/*/data/*_repository.dart          # Firestore queries → local SQLite queries; direct writes → RPC

functions/                       # EXISTING — frozen; kept for the parity harness until day 7, then deleted
firestore.rules, storage.rules   # EXISTING — replaced by deny-all at cutover; deleted at decommission
packages/cloud_firestore/        # EXISTING fork — deleted
```

**Structure Decision**: a new top-level `server/` holds the API, migrations, sync config and migration
tools, and `ops/` holds VPS operations. `functions/src` pure modules are **copied** into
`server/src/domain` with their tests (`functions/` must keep deploying unchanged until cutover and
serves as the parity reference); `functions/` is deleted at decommission. The Flutter app keeps its feature-folder
layout; only data-layer files and core services change.

## Delivery slices (for `/speckit-tasks`)

| # | Slice | Maps to | Exit gate |
|---|---|---|---|
| 0 | Green baseline tests (constitution 2.0.0 ratified 2026-09-30) | Gate | All current tests pass |
| 1 | **Spike**: VPS + Caddy + Postgres + PowerSync, Firebase JWT accepted, one table synced to a test app, ≤ 5 s propagation | R3 risk | Measured on target VPS |
| 2 | Schema + migrator + verification report against staging copy | US1, FR-010–014 | `mismatches: 0` |
| 3 | API: auth, RPC router, port all callables + new RPCs + in-tx recompute + files + webhook | US2, FR-002–009 | Parity harness green; integration tests green |
| 4 | Client: PowerSync layer, repositories to SQLite, CallableClient/Storage swap, remove Firestore | US2, FR-005/006 | `flutter analyze` clean; `flutter test` green; manual checklist |
| 5 | Ops: backups, restore drill, monitoring, deploy script | US3, FR-018–022 | Restore < 4 h; RPO ≤ 15 min proven |
| 6 | Staging rehearsal end-to-end | FR-013 | Checklist green twice |
| 7 | Production cutover + 7-day watch + rollback tool ready | FR-015–017 | Report green; both phones live |
| 8 | Decommission Firebase data services | US4 | Firestore/Storage empty; Functions deleted |

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Extra service (PowerSync) on the VPS | Full offline read parity + live updates (Q5, FR-005/006) | Custom delta sync would take about 2–3× the client effort and carries more correctness risk; online-only reads were rejected in Q5 |
| New `server/` project alongside `functions/` during transition | Parity harness needs both until cutover | In-place rewrite loses the reference implementation needed to prove equivalence |
