# Tasks: Migrate Backend Data & Logic from Firebase to Self-Hosted VPS

**Input**: Design documents from `/specs/004-vps-backend-migration/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md),
[data-model.md](./data-model.md), [contracts/](./contracts/), [quickstart.md](./quickstart.md)

**Tests**: INCLUDED. Constitution 2.0.0 Principle III requires automated tests for accounting,
offline, permission and attachment changes. Every one of those areas is touched here.

**Organization**: Grouped by user story from spec.md. US1 = migrated data readable in the new app
(read parity). US2 = all day-to-day writes on the new backend. US3 = operations. US4 = Firebase data
decommission. Production cutover is a separate cross-cutting phase between US3 and US4.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: US1–US4 from spec.md
- Paths are relative to the repo root: `server/` (new API), `ops/` (new VPS ops), `lib/` + `test/`
  (Flutter), `functions/` (frozen reference; must keep deploying unchanged until cutover)

## Global rules for every task

- Do **not** modify `functions/`, `firestore.rules` or `storage.rules` before Phase 6. They are live
  production and also the parity reference.
- Preserve RPC payloads, results and error codes exactly (contracts/rpc-api.md).
- Money is `NUMERIC(14,2)` on the server and `double` on the client; never round silently.
- Arabic/English: any new user-facing string goes into both `_en` and `_ar` maps in
  `lib/app/localization/app_localizations.dart`. Never rely on English fallback.
- Non-ASCII files: never round-trip them through PowerShell `Get-Content`/`Set-Content`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Scaffold the new server and ops projects without touching the running app.

- [X] T001 Create `server/` Node 22 TypeScript project: `server/package.json` (type module; scripts `build`, `dev`, `test`, `test:integration`, `migrate`, `migrate:firestore`, `rollback:firestore`, `reconcile`; deps fastify, postgres, node-pg-migrate, firebase-admin, @fastify/multipart, @fastify/rate-limit; dev deps typescript, @types/node), `server/tsconfig.json` (strict, outDir `dist`), `server/.gitignore`
- [X] T002 [P] Create `server/.env.example` listing every variable with comments: `DATABASE_URL`, `FIREBASE_PROJECT_ID=wize-site`, `GOOGLE_APPLICATION_CREDENTIALS`, `FILES_ROOT=/srv/wizesite/files`, `FILES_SIGNING_KEY`, `OPENROUTER_API_KEY`, `OPENROUTER_MODEL`, `OPENROUTER_TRANSCRIPTION_MODEL`, `REVENUECAT_WEBHOOK_SECRET`, `PUBLIC_API_URL`, `LOG_LEVEL`. Values copied from `functions/.env.example`, with no real secrets
- [X] T003 [P] Copy `functions/eslint.config.mjs` to `server/eslint.config.mjs` and add a `lint` script in `server/package.json`
- [X] T004 [P] Create `server/compose.dev.yml` (postgres:17 with `wal_level=logical`, PowerSync service image ≥1.3.8 using Postgres bucket storage in a separate database, ports 5432/8081) and `server/compose.test.yml` (ephemeral Postgres + PowerSync for integration tests)
- [X] T005 [P] Create `server/Dockerfile` (multi-stage node:22-slim build → runtime, non-root user, `HEALTHCHECK` on `/healthz`)
- [X] T006 [P] Create `server/compose.yml` for production: services `caddy`, `api`, `postgres`, `powersync`, with memory limits per research R13 (postgres 900M, powersync 600M, api 256M, caddy 64M); postgres not published on a host port; volumes under `/srv/wizesite/{pgdata,files,caddy}`; `restart: unless-stopped` on every service so the stack comes back after an unexpected reboot
- [X] T007 [P] Create `ops/Caddyfile` with `api.{$DOMAIN}` → api:8080 and `sync.{$DOMAIN}` → powersync:8080, automatic TLS, gzip, security headers
- [X] T008 [P] Create `ops/bootstrap.sh`: ufw allow 22/80/443 only, SSH key-only, install Docker + compose plugin, 2 GB swapfile, journald `SystemMaxRetentionSec=14d`, create `/srv/wizesite/{pgdata,files,caddy,backups}` with 0700, and a `wizesite` deploy user
- [X] T009 [P] Add a `server` workflow to `codemagic.yaml`: `npm ci`, `npm run lint`, `npm test`, integration tests with `compose.test.yml`, then build and push the image tagged with the git SHA to GHCR
- [X] T010 [P] Secret hygiene (FR-024): add `.gitignore` entries for `server/.env`, `**/*service-account*.json`, `ops/**/*.env`, `ops/restic/*.key`, `ops/pgbackrest/*.key`, `out/`; add a `gitleaks detect` step (fail on findings) to the `server` workflow in `codemagic.yaml`; add `.gitleaks.toml` allowlisting `android/app/google-services.json` and `lib/firebase_options.dart` (public client config, not secrets)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Baseline, a de-risking spike, the schema, and the API/sync/client skeletons that every story needs.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete. T012 is a go/no-go gate.

- [X] T011 Run the baseline: `flutter analyze 2>&1 | Select-Object -First 80`, `flutter test --reporter compact`, `npm --prefix functions test`. Fix **every** failure until all three suites are green (constitution III: failing tests MUST be resolved before broad feature expansion); Phase 2 stays blocked until then. Record the initial failures and their fixes in `specs/004-vps-backend-migration/baseline.md` as a record only
- [ ] T012 **SPIKE (go/no-go)**: on a throwaway 4 GB VPS run `ops/bootstrap.sh`, deploy Caddy + Postgres + PowerSync with `sync-staging.<domain>`, configure `client_auth.jwks_uri` = Firebase securetoken JWKS and audience `wize-site`, sync a `spike_items` table bucketed by `workspace_id` into a minimal Flutter harness in `tool/spike_powersync/`. Record in `specs/004-vps-backend-migration/spike-results.md`: Firebase ID token accepted (Y/N), cross-workspace leak (must be 0 rows), p95 propagation over 50 writes (must be ≤ 5 s), RAM used by each container. If any check fails, stop and revisit research R3 _2026-10-01: real Firebase token accepted (owner's staging sign-in synced the production data); the sync tests cover workspace isolation. Still open: p95 propagation over 50 writes between two phones._
- [X] T013 [P] Copy pure modules with their tests from `functions/src/` into `server/src/domain/`: `money.ts`, `idempotency.ts`, `revenuecat_status.ts`, `account_deletion.ts`, `storage_lifecycle.ts`, `worker_accounting_summary_initializer.ts`, `entity_last_used_backfill.ts`, and `voice/**` (services, types, utils, `voice_parser.test.ts`). Replace any `firebase-admin`/`firebase-functions` imports with interfaces satisfied later by `server/src/db` — *Done 2026-09-30: `idempotency.ts` not copied (Firestore-transaction bound; rewritten for Postgres in T022). `worker_accounting_summary_initializer.ts` and `entity_last_used_backfill.ts` not copied (one-off Firestore backfills; superseded by in-transaction recompute and the migrator). Voice App Check test dropped (enforced by the RPC auth layer, T019/T021). Added `src/domain/errors.ts` (`RpcError`, HttpsError-compatible); transcription reads audio via an injected `AudioReader`.*
- [X] T014 [P] Extract the pure accounting functions from `functions/src/index.ts` into `server/src/domain/accounting.ts`, unchanged: `classifyProjectRisk`, `shallowEqualDerivedState`, `workerEntryTotalCost`, `normalizeWorkerStatus`, `workerAccountingAmounts`, `buildWorkerAccountingSummaryPayload`, `hasRelevantProjectFieldsChanged`, `hasRelevantExpenseFieldsChanged`, `hasRelevantPaymentFieldsChanged`, `hasRelevantWorkerEntryFieldsChanged`, `hasRelevantWorkerAccountingFieldsChanged`, `buildAccountingSummaryPayloads`, `buildWorkspaceMetricsPayload`. Copy `project_risk_classification.test.ts` and `project_recompute_trigger.test.ts` (pure parts) to `server/test/unit/` — *Done 2026-09-30: 39 declarations extracted verbatim (targets + their helpers) into an 840-line pure module; only the 3 emulator-free builder tests were portable from `project_recompute_trigger.test.ts` (the other 41 need Firestore and are covered by the T057 parity harness).*
- [X] T015 Create `server/migrations/001_identity.sql`: `workspaces`, `memberships`, `user_profiles`, `subscriptions`, `usage_counters`, `idempotency_keys`, `webhook_events`, per data-model.md. Copy the role enum values exactly from `firestore.rules`
- [X] T016 Create `server/migrations/002_accounting.sql`: `projects`, `expenses`, `payments`, `workers`, `worker_entries`, `worker_accounting_records`, `contractor_accounting_records`, `equipment_accounting_records`, `transport_provider_accounting_records`, `entities`, `attachments`, `notifications`, `drafts`, `reports`, `report_exports`. Include CHECK constraints from `server/src/domain/money.ts` lists, `legacy jsonb`, `UNIQUE (workspace_id, client_mutation_id)`, and exact columns copied from each Dart model in `lib/features/*/domain/`
- [X] T017 Create `server/migrations/003_derived_and_sync.sql`: `project_metrics` (incl. `risk_level`, `computed_at`, `source_version`), `workspace_metrics`, `project_summaries`, `weekly_summaries`, `entity_summaries`, `category_summaries`, `worker_accounting_summaries` (one table per Firestore collection, per data-model.md); indexes derived only from real query sites (grep `orderBy|where|limit` in `lib/`); `CREATE PUBLICATION powersync FOR TABLE ...` covering every synced table in contracts/sync-rules.md
- [X] T018 [P] Create `server/src/db/pool.ts` (postgres.js pool from `DATABASE_URL`) and `server/src/db/tx.ts` (`withTransaction(fn)` with serialization-failure retry ×3)
- [X] T019 [P] Write failing tests `server/test/integration/auth.test.ts`: missing token → 401 `unauthenticated`; invalid App Check → 401; valid token with no membership in the target workspace → 403 `permission-denied`; role matrix cases. Use Firebase Auth emulator tokens or a stubbed verifier behind an interface
- [X] T020 [P] Write failing tests `server/test/integration/rpc_envelope.test.ts`: `{data}` → `{result}`; each error code → HTTP status per contracts/rpc-api.md; body > 1 MB → 413; rate limit → 429 `resource-exhausted` with `retryAfterSeconds`; replaying the same `X-Idempotency-Key` returns the stored response without a second write
- [X] T021 Implement `server/src/auth/verify.ts` (firebase-admin `verifyIdToken` + `appCheck().verifyToken`) and `server/src/auth/roles.ts` (role → allowed-function matrix copied from `functions/src/index.ts` checks and `firestore.rules`) so T019 passes
- [X] T022 Implement `server/src/app.ts` (Fastify, JSON logs, `/healthz` checking db + PowerSync reachability), `server/src/rpc/router.ts` (`POST /v1/rpc/:name` → registry, envelope, error mapping, 1 MB limit, per-uid rate limit 60/min burst 120) and `server/src/rpc/idempotency.ts` (store the response in `idempotency_keys` inside the same transaction) so T020 passes
- [X] T023 Create `server/powersync/powersync.yaml` per contracts/sync-rules.md, with the split already resolved in contracts/sync-rules.md (every table whose `firestore.rules` read uses `canAccessAccounting` goes to `workspace_financial`, including `attachments`; roles `owner`, `admin`, `accountingApproved`). Re-verify the split against `firestore.rules` before writing
- [X] T024 [P] Write `server/test/sync/sync_rules.test.ts` against `compose.test.yml`: a non-member receives 0 rows; a `member` role receives 0 rows from gated financial tables; removing a membership drops that workspace's rows on the next sync; deletes propagate
- [X] T025 Add `powersync` to `pubspec.yaml`. Create `lib/core/config/backend_config.dart` (`API_BASE_URL`, `SYNC_URL` from `--dart-define`), `lib/core/sync/schema.dart` (local tables mirroring data-model.md column names), `lib/core/sync/powersync_db.dart` (one DB file per Firebase uid, Riverpod provider) and `lib/core/sync/firebase_connector.dart` (`fetchCredentials` returns the Firebase ID token, refreshed on expiry; `uploadData` is a no-op because writes go through the offline queue)
- [X] T026 [P] Create `lib/core/pagination/local_page.dart`, a keyset-pagination helper over SQLite with the same public API as `lib/core/pagination/firestore_page.dart`, plus `test/core/pagination/local_page_test.dart`
- [X] T027 [P] Create the test helper `test/helpers/local_db.dart`: an in-memory PowerSync/SQLite database with `schema.dart` plus fixture loaders. This replaces `fake_cloud_firestore` for repository tests
- [X] T028 [P] Write failing test `test/core/services/callable_client_test.dart`: the HTTP envelope maps to the same `CallableClientException(code, message)` for every error code in contracts/rpc-api.md; a 401 triggers a token refresh and one retry; `Authorization` and `X-Firebase-AppCheck` headers are sent
- [X] T029 Rewrite the transport in `lib/core/services/callable_client.dart`: POST `$API_BASE_URL/v1/rpc/{functionName}` with `Authorization: Bearer <idToken>`, `X-Firebase-AppCheck`, and `X-Idempotency-Key`. Map the error envelope to the existing `CallableClientException`. Keep the public `call<T>()` signature and the telemetry. Remove `FirebaseFunctions` and `httpFunctionName` usage. Update `lib/core/utils/firebase_functions_error_message.dart` for the new codes, so T028 passes. Moved here from US2 because US1's staging build must already call the new API (`ensureUserWorkspaceBootstrap`, `getAttachmentDownloadUrl`). Staging builds only; production stays on Firebase until the cutover phase

**Checkpoint**: Spike green, schema migrates, the API rejects unauthorized calls, the sync rules are proven, the client can open a local DB, and `CallableClient` talks to the new API. User stories can start.

---

## Phase 3: User Story 1 — Existing users keep working without losing anything (Priority: P1) 🎯 MVP

**Goal**: Migrate all production data and files to Postgres/VPS with a verification report, and make the app show every migrated record, total and attachment identically, read-only and offline-capable.

**Independent Test**: Run the migrator against a staging copy (report `mismatches: 0`). Install a staging build signed in as the owner. Every project, total, balance, risk indicator and attachment equals the pre-migration snapshot, including in airplane mode after the first sync.

### Tests for User Story 1 ⚠️ (write first, must fail)

- [X] T030 [P] [US1] `server/test/migration/transform.test.ts`: Firestore fixture docs → rows. Cover `Timestamp` → timestamptz with microsecond exactness; a money value with >2 decimals is flagged, not rounded; embedded `attachments[]` is normalized to the `attachments` table; unknown fields go to `legacy`; uids missing from Auth are skipped (FR-014); Arabic text and non-ASCII paths are unchanged
- [X] T031 [P] [US1] `server/test/migration/verify.test.ts`: the report detects a count mismatch, a per-project total mismatch, and an MD5 mismatch, each giving a non-zero exit
- [X] T032 [P] [US1] `server/test/unit/recompute.test.ts`: recomputing `project_metrics`/summaries from rows equals the output of the `functions/` builders for the same fixture (parity for derived data)
- [X] T033 [P] [US1] `test/features/read_parity_test.dart`: first, while the old repositories still exist, load a fixture into `fake_cloud_firestore`, run the old repositories and write their model output as golden JSON to `test/fixtures/read_parity/*.json`; then assert that the new repositories over `test/helpers/local_db.dart` (same fixture) match those goldens. Cover projects, expenses, payments, workers, worker entries, entities, the 4 accounting record types, summaries and notifications

### Implementation for User Story 1 — server & migration

- [X] T034 [US1] Implement `server/src/recompute/project.ts`, `workspace.ts`, `worker.ts`: build derived rows (`project_metrics`, the four `*_summaries` tables with the same ids `buildAccountingSummaryPayloads` produces today, `workspace_metrics`, `worker_accounting_summaries`) from base rows using `server/src/domain/accounting.ts`, and write only when changed (`shallowEqualDerivedState`). Export `recomputeProject(tx, projectId)` and `recomputeWorkspace(tx, workspaceId)` so T032 passes — *Done: implemented as `server/src/recompute/{rows,project,persist}.ts` (pure core + persistence); notification side effects of recomputeProjectSummary move to the mutating RPCs (US2).*
- [X] T035 [US1] Implement `server/tools/migrate-from-firestore/export.ts`: firebase-admin export of every collection in data-model.md to NDJSON under `out/export/<timestamp>/`, and a listing of every Storage object under `receipts/`, `attachments/`, `voice-expenses/`, `profile-photos/` with its MD5
- [X] T036 [US1] Implement `server/tools/migrate-from-firestore/transform.ts`: per-collection mappers per the data-model.md mapping table, so T030 passes
- [X] T037 [US1] Implement `server/tools/migrate-from-firestore/load.ts` (one transaction per collection group, FK order: identity → projects → children → attachments; derived tables through T034 recompute, not copied) and `files.ts` (download each object to `$FILES_ROOT/<same path>`, verify MD5, mode 0600)
- [X] T038 [US1] Implement `server/tools/migrate-from-firestore/verify.ts` and CLI `index.ts` (`npm run migrate:firestore -- --target=<env> --report=out/report.json`): counts per collection; per-project totals from raw source rows vs migrated rows vs migrated summaries; attachment count + MD5; money-precision flags; exit code 1 on any mismatch, so T031 passes
- [X] T039 [P] [US1] Implement RPCs `ensureUserWorkspaceBootstrap` and `setActiveWorkspace` in `server/src/rpc/workspace.ts`, ported from `functions/src/index.ts` (`bootstrapWorkspaceForUser`, `setActiveWorkspaceForUser`), with integration tests in `server/test/integration/workspace_bootstrap.test.ts`
- [X] T040 [P] [US1] Implement `getAttachmentDownloadUrl` RPC and `GET /v1/files/signed/*` in `server/src/files/download.ts` per contracts/files-api.md (membership check, HMAC with 15-min TTL, RFC 5987 filename). Add tests in `server/test/integration/files_download.test.ts` (expired → 403, other workspace → 403, Arabic filename header)

### Implementation for User Story 1 — client read path

- [X] T041 [P] [US1] Make models row-compatible: in `lib/core/models/accounting_summary.dart`, `lib/core/models/attachment.dart` and `lib/features/{contractors,equipment,transport,workers}/domain/*_record.dart`, `lib/features/notifications/domain/notification_item.dart`, `lib/features/projects/domain/project.dart`, `expense.dart`, `payment.dart`, `worker_models.dart`, add `fromRow(Map)` that accepts ISO-8601 strings and REAL numbers. Keep the existing fallbacks for old records (Principle II). Remove `Timestamp` imports — *Done via `lib/core/sync/local_row.dart` (`localRowToMap`): local rows are mapped back to the Firestore document shape, so the existing `fromMap` constructors work unchanged; no model edits were needed.*
- [X] T042 [P] [US1] Port reads in `lib/features/projects/data/project_repository.dart`, `lib/features/projects/presentation/screens/projects_screen.dart` and `archived_projects_screen.dart` to local SQLite watch queries plus `local_page.dart`. Join `project_metrics` for the derived totals
- [X] T043 [P] [US1] Port reads in `lib/features/expenses/data/expense_repository.dart`, `expense_summary_providers.dart` and `lib/features/expenses/presentation/screens/expenses_screen.dart`, preserving filters in `expense_filter.dart`
- [X] T044 [P] [US1] Port reads in `lib/features/payments/data/payment_repository.dart` and `lib/features/payments/presentation/screens/payments_screen.dart`, preserving `payment_filter.dart`
- [X] T045 [P] [US1] Port reads in `lib/features/workers/data/worker_repository.dart`, `worker_accounting_repository.dart` and `lib/features/workers/presentation/screens/workers_screen.dart`
- [X] T046 [P] [US1] Port reads in `lib/features/entities/data/entity_repository.dart` and `lib/features/entities/presentation/screens/resource_directory_screen.dart`
- [X] T047 [P] [US1] Port reads in `lib/features/{contractors,equipment,transport}/data/*_accounting_repository.dart`, `lib/features/common/presentation/screens/domain_accounting_records_screen.dart` and the read side of `domain_accounting_save_adapter.dart`
- [X] T048 [P] [US1] Port `lib/features/dashboard/data/dashboard_providers.dart`, `lib/features/activity/data/activity_providers.dart` and `lib/core/providers/accounting_access_provider.dart`
- [X] T049 [P] [US1] Port `lib/features/reports/data/entity_aggregation_providers.dart`, `report_project_selector_provider.dart`, `reports_providers.dart` and `lib/features/reports/services/report_export_data_builder.dart`, keeping explicit date/filter bounds (Principle V)
- [X] T050 [P] [US1] Port reads in `lib/features/settings/data/user_settings_repository.dart`, `lib/features/settings/presentation/screens/workspace_settings_screen.dart` and `lib/core/providers/workspace_provider.dart`
- [X] T051 [P] [US1] Replace `lib/features/subscription/data/firebase_subscription_repository.dart` and `firebase_usage_quota_repository.dart` with `local_subscription_repository.dart` and `local_usage_quota_repository.dart` that read the synced `subscriptions`/`usage_counters`. Update the providers that use them. _Done via DocSource: both repositories read through `docSourceProvider` (`.withSource`), so no separate `local_*` files were needed._
- [X] T052 [P] [US1] Port reads in `lib/features/notifications/data/notification_repository.dart` and `notification_providers.dart`
- [X] T053 [US1] Port the read side of `lib/core/services/session_restore_service.dart` (membership/active workspace lookup) to the local DB
- [X] T054 [US1] Add `lib/core/sync/sync_gate.dart`: before the first complete sync for this uid, show a "connect to load your data" state instead of an empty workspace (spec edge case), with new `_en` and `_ar` keys in `lib/app/localization/app_localizations.dart`. Add a widget test in `test/core/sync/sync_gate_test.dart`
- [X] T055 [US1] Point attachment viewing at the `getAttachmentDownloadUrl` RPC through `CallableClient` (transport swap is in T029). Ensure opened attachments are cached on the device for offline viewing (reuse the existing image cache if present, otherwise add `lib/core/services/attachment_cache_service.dart`), with a test
- [X] T056 [US1] Run the US1 checkpoint on staging: `npm run migrate:firestore -- --target=staging` (report green), install a staging build (`--dart-define` staging URLs), then compare against a pre-migration snapshot and record the results in `specs/004-vps-backend-migration/staging-us1.md`

**Checkpoint**: US1 is independently demonstrable. Migrated data is complete and verified, and a read-only app shows it online and offline.

---

## Phase 4: User Story 2 — Day-to-day recording works exactly as before (Priority: P1)

**Goal**: Every write (create/edit/archive, quotas, refunds, cascade delete, voice, uploads, webhook) runs on the new API. Derived totals update in the same transaction, the offline queue replays idempotently, and teammates see changes within 5 s.

**Independent Test**: The quickstart §4 manual checklist passes on staging, and the parity harness shows identical derived rows between `functions/` (emulator) and the new API for the scripted scenario.

### Tests for User Story 2 ⚠️ (write first, must fail)

- [X] T057 [P] [US2] Parity harness `server/test/parity/scenario.ts` + `parity.test.ts`: a scripted scenario (create workspace/project with and without contract value, expenses with attachments, payments, worker entries, archive with refund, update, cascade delete) runs against the Firebase emulators (`functions/` + Firestore + Storage + Auth, configured in a harness-only `server/test/parity/firebase.parity.json` with its own ports; the production `firebase.json` is not changed) and the new API. Assert equal results, equal usage counters and equal derived rows _Done: Cloud Functions run in-process on the Firestore + Storage emulators (callables via `.run`, the project trigger once at the end); 11/11 pass, incl. a sanity check that both sides hold the data. Run: `firebase emulators:exec --config server/test/parity/firebase.parity.json --only "firestore,storage" --project demo-wizesite "cd server && npm run test:parity"`. **Found a live Firebase bug:** `archiveExpenseWithQuotaRefund` and `archivePaymentWithQuotaRefund` (and `archiveWorkerEntryWithQuotaRefund`, same code) update the record, then read the usage counter in the same transaction, which Firestore rejects, so those archives always fail in production. The new API does them correctly; the harness applies their intent on the Firebase side and pins the bug._
- [X] T058 [P] [US2] `server/test/integration/projects.test.ts`: quota enforcement on create; update; archive/unarchive; `deleteProjectCascade` removes children, attachments rows and files, and refunds counters
- [X] T059 [P] [US2] `server/test/integration/expenses.test.ts` and `payments.test.ts`: create with quota, `resource-exhausted` at the limit (same message), update, archive with refund; a payment on a project with null `contract_value` → `failed-precondition`; recompute happens in the same transaction (no stale read after 200). _Done in `expenses_payments.test.ts`. The limit error stays `failed-precondition` / `LIMIT_REACHED` with today's details (not `resource-exhausted`): that is what the app shows as the plan-limit message, while it maps `resource-exhausted` to "service unavailable"._
- [X] T060 [P] [US2] `server/test/integration/workers.test.ts`: `createWorker`, `updateWorker`, `archiveWorker`, worker entry create/update/archive with refund, and the worker accounting summary. _Worker accounting summaries are driven by the accounting records (Firebase trigger on `worker_accounting_records`), so they are covered with the record upserts in T063/T074, not by worker entries._
- [X] T061 [P] [US2] `server/test/integration/workspace_members.test.ts`: `createWorkspace`, `completeInitialWorkspaceSetup`, `inviteMemberByEmail`, `inviteMemberWithQuota`, `updateWorkspaceMemberRole`, `removeWorkspaceMember`, `checkLimit`, role denials
- [X] T062 [P] [US2] `server/test/integration/user_account.test.ts`: `updateUserProfile`, `updateUserSettings`, `deleteOwnAccount` (Postgres rows + files removed, Firebase `deleteUser` called through a mocked admin, idempotent on retry)
- [X] T063 [P] [US2] `server/test/integration/direct_write_rpcs.test.ts`: `upsertEntity`, `archiveEntity`, `deleteEntity`, `touchEntityLastUsed`, the three accounting-record upserts, `markNotificationsRead`, `restoreMembership`. Each enforces the same conditions `firestore.rules` enforces today for those paths
- [X] T064 [P] [US2] `server/test/integration/files_upload.test.ts`: content-type and size limits copied verbatim from `storage.rules` (`validAttachmentUpload`, `validVoiceUpload`, `validProfilePhotoUpload`); the path is always `{kind}/{callerUid}/…`; idempotent re-upload
- [X] T065 [P] [US2] `server/test/integration/voice.test.ts` (OpenRouter mocked): audio upload → `processVoiceExpense` → draft is matched to a project exactly as `functions/src/voice` does today; the 120 s timeout is respected
- [X] T066 [P] [US2] `server/test/integration/revenuecat_webhook.test.ts`: every case in contracts/webhooks.md, including dedupe on `event_id`
- [X] T067 [P] [US2] `test/core/services/offline_action_queue_idempotency_test.dart`: on replay, `X-Idempotency-Key` equals the offline action id, and a replayed action produces exactly one server record (against a mocked HTTP server)

### Implementation for User Story 2 — server

- [X] T068 [P] [US2] Implement `server/src/rpc/projects.ts`: `createProjectWithQuota`, `updateProject`, `archiveProject`, `unarchiveProject`, `deleteProjectCascade`, ported from `functions/src/index.ts` (`createProjectWithQuotaForUser`, `updateProjectForUser`, `archiveProjectForUser`, `unarchiveProjectForUser`), each calling `recomputeProject`/`recomputeWorkspace` in the same transaction
- [X] T069 [P] [US2] Implement `server/src/rpc/expenses.ts`: `createExpenseWithQuota`, `updateExpense`, `archiveExpenseWithQuotaRefund`, with in-transaction recompute
- [X] T070 [P] [US2] Implement `server/src/rpc/payments.ts`: `createPaymentWithQuota`, `updatePayment`, `archivePaymentWithQuotaRefund`, including the no-contract-value invariant from feature 003
- [X] T071 [P] [US2] Implement `server/src/rpc/workers.ts`: `createWorker`, `updateWorker`, `archiveWorker`, `createWorkerEntryWithQuota`, `updateWorkerEntry`, `archiveWorkerEntryWithQuotaRefund`, with worker summary recompute
- [X] T072 [P] [US2] Extend `server/src/rpc/workspace.ts` with `createWorkspace`, `completeInitialWorkspaceSetup`, `updateWorkspaceMemberRole`, `removeWorkspaceMember`, `inviteMemberByEmail`, `inviteMemberWithQuota`, `checkLimit` _Implemented in `server/src/rpc/members.ts` (kept apart from the bootstrap code in `workspace.ts`)._
- [X] T073 [P] [US2] Implement `server/src/rpc/user.ts`: `updateUserProfile`, `updateUserSettings`, `deleteOwnAccount` (ported from `server/src/domain/account_deletion.ts`; deletes rows + files, then `admin.auth().deleteUser`) _Firebase is called through an injected `AuthAdmin`; deleteUser runs before commit, so a Firebase failure deletes nothing. Deploy prerequisite: the API's service account needs **Firebase Authentication Admin** (the migration key is read-only)._
- [X] T074 [P] [US2] Implement the new RPCs in `server/src/rpc/entities.ts`, `accounting_records.ts`, `notifications.ts` and `session.ts` per the contracts/rpc-api.md "New" table _Also `upsertWorkerAccountingRecord` (missing from the contract table). Where the rules blocked app behaviour the RPCs follow the app; see contracts/rpc-api.md._
- [X] T075 [P] [US2] Implement `POST /v1/files` in `server/src/files/upload.ts` per contracts/files-api.md (multipart, limits, sha256, `attachments` row when linked) _No `attachments` row is written: records keep embedding their attachments (data-model.md), and nothing reads that table._
- [X] T076 [P] [US2] Implement `processVoiceExpense` in `server/src/rpc/voice.ts` using `server/src/domain/voice/**`, reading audio from `$FILES_ROOT` _Marked mutating so a retried call returns the first result instead of paying for a second transcription. Transcription model default restored to Firebase's `openai/gpt-audio-mini`._
- [X] T077 [P] [US2] Implement `POST /v1/webhooks/revenuecat` in `server/src/webhooks/revenuecat.ts` (constant-time secret compare, dedupe, subscription + usage counter update)
- [X] T078 [US2] Implement the nightly reconciler `server/src/recompute/reconcile.ts` (`npm run reconcile`: recompute every project, log and count drift, non-zero exit on drift) and schedule it nightly at 02:00 through a `reconciler` cron sidecar service in `server/compose.yml` (supercronic running `npm run reconcile`), writing its last result to `/srv/wizesite/state/reconcile.json`. No dependency on US3; T095 only reads that file _The `reconciler` service runs the same image with a built-in daily loop (`--daily`, 02:00 UTC) instead of supercronic, so no extra binary ships. Drift = the money totals only; date-relative fields change daily by design._
- [X] T079 [US2] Register every function from contracts/rpc-api.md in `server/src/rpc/registry.ts`. Add a static test `server/test/unit/registry.test.ts` asserting that the registry contains every callable exported by `functions/src/index.ts` (except the `*Http` twins and triggers) plus the new RPCs _`processVoiceExpense` is listed in the test's PENDING map until T076 lands; the test fails if it is registered and still listed._

### Implementation for User Story 2 — client

- [X] T080 [US2] Thread the offline action id as the idempotency key: `lib/core/services/offline_action_queue.dart` and `offline_queue_coordinator.dart` pass `action.id` to `CallableClient`. Add queue action types for the new RPCs (entities, accounting records, notifications). Keep `pending_id_remap.dart` and `sync_error_classifier.dart` behavior unchanged; extend `test/core/services/` queue tests _Progress: every call in `WorkspaceMutationService._applyQueuedAction` now passes `idempotencyKey: action.id` (T067 proves a replay after a lost response creates one record). Still open: queue action types for the new RPCs, done together with T082._
- [X] T081 [US2] Rewrite `lib/core/services/storage_upload_service.dart` to `POST /v1/files` (multipart, same kinds), returning `storagePath`. Update `lib/core/services/pending_attachment_service.dart` and `lib/features/settings/data/profile_repository.dart` (profile photo) accordingly _Progress: attachments and voice audio upload through `POST /v1/files` in self-hosted builds (`StorageUploadService` + `SelfHostedRpcTransport.uploadFile`, pending uploads keyed by their record id; Firebase builds unchanged). Profile photos (owner's decision): uploaded as kind `profile-photos` and shown from a public avatar route, `GET /v1/public/profile-photos/{uid}/{uuid}.jpg|png` (only those paths; random names; immutable caching)._
- [X] T082 [P] [US2] Replace direct Firestore writes with RPC calls through `CallableClient` or the offline queue in `lib/features/entities/data/entity_repository.dart`, `lib/features/{contractors,equipment,transport}/data/*_accounting_repository.dart`, `lib/features/common/presentation/controllers/domain_accounting_save_adapter.dart`, `lib/features/notifications/data/notification_repository.dart`, `lib/features/settings/data/user_settings_repository.dart` and `lib/core/services/session_restore_service.dart` _Done for self-hosted builds (Firebase builds unchanged): writes are queued as new action types and replayed to the RPCs with the action id as key. Known gap: offline, a new contact or accounting record is returned to the screen that saved it but appears in lists only after it syncs (no optimistic overlay for these types yet)._
- [X] T083 [P] [US2] Route the voice screens `lib/features/voice_expense/presentation/screens/voice_processing_screen.dart` and `voice_review_screen.dart` through `CallableClient` (`processVoiceExpense`) and the new upload service. Remove direct Functions/HTTP URL usage _The voice flow already went through `CallableClient` and the upload service; the fix was the client timeout (30 s default vs. 120 s on the server, now 130 s for this call) and a stable key per recording (`voice:<storagePath>`)._
- [X] T084 [US2] Remove Firebase data dependencies: in `pubspec.yaml` drop `cloud_firestore`, `firebase_storage`, `cloud_functions`, `fake_cloud_firestore` and the `packages/cloud_firestore` dependency override; delete `packages/cloud_firestore/` and `lib/core/pagination/firestore_page.dart`; clean `lib/core/providers/firebase_providers.dart` and `lib/core/services/firebase_initializer.dart` (keep Auth, App Check, Crashlytics, Remote Config); remove the Firestore/Storage keys in `lib/core/utils/app_error_messages.dart`. `flutter analyze` must be clean. Run only after T033's goldens are committed _Done: every repository and provider reads the local replica (`docSourceProvider` is always `LocalDocSource`) and writes through queued RPCs; `CallableClient` is RPC-only and `StorageUploadService`/profile photos use `POST /v1/files`. `FirestorePage` is now `RecordPage` (`lib/core/pagination/record_page.dart`). `BackendConfig` defaults to `api.`/`sync.buildozer.dpdns.org`, overridable with the defines. The expense quick summary still read Firestore directly; it now reads `project_summaries` locally._
- [X] T085 [US2] Migrate the 42 test files that use `fake_cloud_firestore`/`cloud_firestore` under `test/` to `test/helpers/local_db.dart` or mocked `CallableClient`. Delete `test/firestore_rules_coverage_test.dart` (superseded by T024 and T063). In `test/features/read_parity_test.dart` delete the `fake_cloud_firestore` golden-capture half; the committed goldens in `test/fixtures/read_parity/` stay and keep asserting the new repositories. `flutter test --reporter compact` must be green _Done: provider tests use `test/helpers/memory_doc_source.dart` (in-memory, works under fake async) or `test/helpers/local_fixture_store.dart` (real local database, Firestore-style `collection().doc().set()` seeding); repository tests run the Local* repositories. One expectation changed: equal-date project ordering follows the sort direction on id, as real Firestore does (the fake ordered ids ascending). 723 tests green._
- [ ] T086 [US2] Run the US2 checkpoint on staging: the quickstart §4 manual checklist on two devices (EN + AR), including the Remote Config flag and paid-entitlement items and an offline expense with a photo that appears once on the other device within 5 s. Record in `specs/004-vps-backend-migration/staging-us2.md`
- [ ] T087 [US2] Latency check (SC-005, plan p95 RPC < 500 ms): `server/test/perf/rpc_latency.ts` runs 200 mixed calls (`createExpenseWithQuota`, `updatePayment`, `getAttachmentDownloadUrl`, plus local list opens) against staging over a throttled mobile-like connection; assert server p95 < 500 ms and end-to-end p95 < 2 s. Record in `specs/004-vps-backend-migration/staging-us2.md`

**Checkpoint**: The app runs fully on the VPS backend in staging, with behavior identical to production today.

---

## Phase 5: User Story 3 — Owner can operate the backend on their own server (Priority: P2)

**Goal**: Reproducible deploy, PITR backups with ≤ 15 min RPO, a tested restore < 4 h, and alerting on downtime, errors and disk.

**Independent Test**: On a fresh VPS, deploy from the repo, write data, run backups, destroy the server, restore on another fresh VPS to a point in time, and confirm the app works with data at most 15 minutes old. Alerts fire when the API is stopped.

### Tests for User Story 3 ⚠️

- [X] T088 [P] [US3] `ops/test/deploy_smoke.sh`: after `ops/deploy.sh`, `/healthz` returns 200 over HTTPS with a valid certificate for `api.` and `sync.`, and port 5432 is closed from outside _Run against staging from outside: api/sync 200 with valid certificates, 5432 closed on the public address._
- [X] T089 [P] [US3] `ops/test/backup_lag_check.sh`: fails if the newest archived WAL is older than 15 min or the newest restic snapshot is older than 15 min _Database lag from `pg_stat_archiver` (an idle database with nothing unarchived is not lag); files from the newest restic snapshot._

### Implementation for User Story 3

- [X] T090 [US3] Implement `ops/deploy.sh <env> <image-tag>`: pull the image, `npm run migrate` in a one-off container, `docker compose up -d`, poll `/healthz` for 60 s, and automatically roll back to the previous tag stored in `/srv/wizesite/.last_tag` on failure _`ops/deploy.sh --build | <image-ref>` (the VPS has one environment): builds/pulls, migrates in a one-off container, starts the stack, polls `/healthz` for 60 s, rolls back to the image in `/srv/wizesite/state/last_image` on failure._
- [X] T091 [US3] Configure Postgres WAL archiving in `server/compose.yml` (`archive_mode=on`, `archive_timeout=60`, `archive_command` = pgbackrest) and add `ops/pgbackrest/pgbackrest.conf` (S3-compatible repo on B2/R2, repo encryption, `repo1-retention-full-type=time`, 30 days) _Postgres image = postgres:17 + pgBackRest (`server/docker/postgres.Dockerfile`). Archiving is gated by `PG_ARCHIVE_MODE` (default off) so WAL cannot pile up before the repository exists; repository settings and passphrase come from `PGBACKREST_*` in `/srv/wizesite/.env`. Verified locally end to end (stanza, archive, full backup, point-in-time restore). Setup steps: `ops/BACKUPS.md`._
- [X] T092 [P] [US3] Add `ops/systemd/pgbackrest-full.{service,timer}` (daily 03:00) and `pgbackrest-diff.{service,timer}` (every 6 h)
- [X] T093 [P] [US3] Add `ops/restic/restic.env.example` and `ops/systemd/restic-files.{service,timer}` (every 10 min, `$FILES_ROOT` → B2/R2), `restic-check.{service,timer}` (daily) and `restic-forget.{service,timer}` (`--keep-within 30d --prune`, weekly) _restic runs from its official image through `ops/restic/restic.sh`, so nothing is installed on the host._
- [X] T094 [US3] Implement `ops/restore.sh [--pitr <timestamp>]`: bootstrap, pgbackrest restore to the target time, restic restore of files, deploy, health check. Print elapsed time and the timestamp of the newest restored record
- [X] T095 [US3] Implement `ops/heartbeat.sh` + `ops/systemd/heartbeat.{service,timer}` (every 5 min): check disk < 85 %, backup lag (T089), API 5xx rate < 5 % over 5 min (read from an API `GET /internal/stats` bound to localhost only; add it in `server/src/app.ts`), and the reconciler result. On success ping the Healthchecks.io URL; on failure ping `/fail` with the reason _`GET /internal/stats` (`server/src/stats.ts`, loopback only, unit-tested) gives the 5-minute 5xx rate._
- [X] T096 [P] [US3] Write `ops/MONITORING.md`: external uptime monitor on `https://api.<domain>/healthz` every 1 min, alert after 3 failures via email + Telegram; Healthchecks.io heartbeat setup; how to read logs (`docker compose logs api --since 1h`)
- [ ] T097 [US3] Execute a restore drill: deploy staging, write marked records, wait for backups, destroy the VPS, run `ops/restore.sh --pitr` on a fresh VPS. Record the elapsed time (< 4 h, SC-008) and data age (≤ 15 min, FR-019) in `ops/drills/<date>-restore.md`
- [ ] T098 [US3] Execute an alert drill: stop the api container on staging and confirm the alert arrives within 5 min; fill disk to 86 % with a temp file and confirm the heartbeat alert. Record in `ops/drills/<date>-alerts.md`

**Checkpoint**: The operator can deploy, back up, restore and monitor without Firebase consoles.

---

## Phase 6: Production Cutover (cross-cutting: completes FR-013, FR-015–FR-017; requires US1–US3)

**Purpose**: One coordinated switch for both users, with the 7-day rollback window.

- [ ] T099 Implement `server/tools/rollback-to-firestore/index.ts` (`npm run rollback:firestore -- --since=<cutover_at>`): export rows with `updated_at > since` plus deletions (from the `deleted_rows` table in data-model.md, created in `server/migrations/004_tombstones.sql` with AFTER DELETE triggers on every base table) back to Firestore following the data-model.md "Reverse mapping (rollback)" section, and copy new files to Storage. Test it against staging in `server/test/migration/rollback.test.ts`
- [ ] T100 [P] Create `firestore.readonly.rules` and `storage.readonly.rules` (deny all writes, keep reads for the rollback window) and a `firebase.readonly.json` target that deploys them
- [X] T101 [P] Add production and staging `--dart-define` values (`API_BASE_URL`, `SYNC_URL`) to the build workflows in `codemagic.yaml` _All three app builds pass `API_BASE_URL`/`SYNC_URL` from the Codemagic environment, defaulting to `api.`/`sync.buildozer.dpdns.org` (also the app's built-in default)._
- [ ] T102 Write `ops/CUTOVER.md` from quickstart §3, with exact commands, the owner's domain, checkboxes, a `cutover_at` field, a downtime budget of < 1 hour (SC-004) with `window_start`/`window_end` timestamps to fill in, and a step to announce the window to the second user at least 24 hours ahead
- [ ] T103 Full staging rehearsal #1 and #2 of `ops/CUTOVER.md` against a fresh staging copy (FR-013). Both runs must finish with report `mismatches: 0` and a green checklist. Record in `specs/004-vps-backend-migration/rehearsals.md`
- [ ] T104 Production cutover: execute `ops/CUTOVER.md` steps 1–7 (both phones at 0 pending → read-only rules + remove Cloud Functions → final migration report green → switch the RevenueCat webhook URL → install the new build on both phones → offline expense test → record `cutover_at`). Fill in `window_start`/`window_end`; if the window passes 1 hour, note the cause in `ops/CUTOVER.md`
- [ ] T105 Seven-day watch: daily check of the reconciler result, backup lag and error rate; note any issue in `ops/CUTOVER.md`. Invoke the rollback tool only on a critical defect

---

## Phase 7: User Story 4 — Firebase data services are decommissioned (Priority: P3)

**Goal**: After the 7-day window, Firestore, Storage and Cloud Functions hold nothing and are turned off. The Firebase project remains for Auth, App Check, Crashlytics and Remote Config.

**Independent Test**: With the Firestore, Storage and Functions APIs disabled for the project, every flow in the quickstart §4 checklist still works, and the Firestore/Storage consoles show no data.

- [ ] T106 [US4] Verify first: on staging (or with production APIs disabled for 1 hour), disable the Firestore, Storage and Cloud Functions APIs and run the quickstart §4 checklist. Record in `specs/004-vps-backend-migration/decommission-check.md`
- [ ] T107 [US4] Implement and run `ops/decommission-firebase-data.sh`: recursive delete of all Firestore collections via firebase-admin batch, delete all Storage objects, delete all deployed Cloud Functions. Print the counts before and after (must be 0)
- [ ] T108 [US4] Remove Firebase data code from the repo: delete `functions/`, `firestore.rules`, `firestore.readonly.rules`, `storage.rules`, `storage.readonly.rules`, `firestore.indexes.json`, `firebase.readonly.json`; strip the `functions`, `firestore`, `storage` and `emulators` sections from `firebase.json` (keep the `flutter` section); drop the parity harness's `functions/` dependency (keep the recorded fixtures as golden files in `server/test/parity/golden/`)

---

## Phase 8: Polish & Cross-Cutting Concerns

- [ ] T109 [P] Rewrite the backend sections of `README.md` (stack, voice flow now `POST /v1/files` + `processVoiceExpense` RPC, setup via `server/` and `ops/`) and remove the Firebase Functions setup
- [ ] T110 [P] Update `docs/SECURITY.md` for the new threat surface: VPS hardening, secrets location, signed file URLs, sync rules, backup encryption
- [ ] T111 [P] Refresh the knowledge graph to include `server/`: `graphify lib server --update`, then `graphify export obsidian`
- [ ] T112 Final gate (constitution workflow): `flutter analyze`, `flutter test --reporter compact`, `npm --prefix server test` and the integration suites. Report any failures or skipped environment-dependent checks in `specs/004-vps-backend-migration/final-verification.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (1)** → **Foundational (2)**. T012 (spike) is a hard gate for everything after Phase 2.
- **US1 (3)** needs Phase 2.
- **US2 (4)** needs Phase 2 and T034 (recompute) + T041 (models) from US1. Its client tasks need the US1 read path (T042–T053) finished, because T084 removes Firestore.
- **US3 (5)** needs only Phase 1 + the Phase 2 compose/schema, so it can run in parallel with US1/US2.
- **Cutover (6)** needs US1 + US2 + US3 complete.
- **US4 (7)** needs cutover + 7 days.
- **Polish (8)** after US4 (T109/T110 can start after cutover).

### User Story Dependencies

- **US1**: independent after Phase 2 (MVP: verified migration + read parity).
- **US2**: builds on the US1 models, recompute and read path, but is testable on its own through the parity harness and integration tests.
- **US3**: independent of US1/US2.
- **US4**: depends on the production cutover.

### Within Each User Story

- Tests are written first and must fail before implementation.
- Server: domain/recompute → RPC modules → registry.
- Client: models → repositories → services → dependency removal (T084 last).

### Parallel Opportunities

- Phase 1: T002–T010 all [P].
- Phase 2: T013/T014, T018/T019/T020, T024/T026/T027/T028 in parallel once T015–T017 exist; T029 after T028.
- US1: all test tasks T030–T033 in parallel; the client read ports T042–T052 are separate feature folders, all [P].
- US2: tests T057–T067 in parallel; server RPC modules T068–T077 in parallel (separate files); client T082/T083 in parallel.
- US3 can proceed in parallel with US1/US2.

## Parallel Example: User Story 1

```text
# Tests first, together:
T030 transform.test.ts   T031 verify.test.ts   T032 recompute.test.ts   T033 read_parity_test.dart

# Client read ports, together (one per feature folder):
T042 projects  T043 expenses  T044 payments  T045 workers  T046 entities
T047 domain accounting  T048 dashboard/activity  T049 reports  T050 settings
T051 subscription  T052 notifications
```

## Parallel Example: User Story 2

```text
T068 projects.ts  T069 expenses.ts  T070 payments.ts  T071 workers.ts  T072 workspace.ts
T073 user.ts  T074 entities/accounting_records/notifications/session  T075 upload  T076 voice  T077 webhook
```

## Implementation Strategy

### MVP First (User Story 1)

1. Phases 1–2, including the spike go/no-go (T012).
2. Phase 3: the migrator with a green report on staging, plus the read-only app on migrated data.
3. **Stop and validate**: T056. This proves nothing is lost before any write path is built.

### Incremental Delivery

1. US1 → proves data fidelity.
2. US2 → full parity on staging (T086).
3. US3 → recoverable, monitored server (drills T097/T098).
4. Cutover (T103 twice → T104) → 7-day watch.
5. US4 → decommission → Polish.

### Production safety

Production keeps running on Firebase, untouched, until T104. Every task before T104 runs against
staging only.

## Notes

- 112 tasks. Where [P] tasks touch shared registries (`registry.ts`, `app_localizations.dart`), merge those edits sequentially.
- Commit after each task or logical group, and never commit secrets (`.env`, service account JSON, restic/pgbackrest keys).
- Update this file's checkboxes as tasks complete.
