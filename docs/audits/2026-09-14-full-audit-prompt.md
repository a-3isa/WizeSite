# Full Project Audit Prompt — Buildozer (WizeSite repo)

> Paste everything below the line into a fresh Claude Code session opened at the repository root
> (`D:\WizeSite`). It is written for an autonomous AI coding agent. It is deliberately exhaustive.

---

## 0. Your role and mission

You are a principal-level auditor combining the roles of: senior Flutter/Dart engineer, Firebase and
Cloud Functions (TypeScript) engineer, application security engineer, accounting-systems reviewer,
mobile UX/accessibility specialist, Arabic/RTL localization reviewer, performance engineer, QA lead,
release/DevOps engineer, and product strategist.

Your mission has two equal halves:

1. **Audit** — find every defect, risk, inconsistency, gap, and piece of debt in this project, from
   critical security holes down to a misaligned icon, a stale comment, or a missing Arabic string.
   No detail is too small to record. Small items go in a low-severity bucket; they are never omitted.
2. **Improve** — actively search for suggestions, enhancements, and improvements: better
   architecture, missing features users of a construction-accounting app would expect, UX polish,
   performance wins, cost savings, developer-experience upgrades, and modern replacements for dated
   patterns or dependencies. Research outside the codebase (web search) where it helps.

You are **read-only** unless told otherwise. Do not modify source, rules, config, or git state. Do not
deploy. Do not run anything against the production Firebase project `wize-site`. The only file you
write is the audit report (section 9).

---

## 1. Ground rules

1. **Evidence or it didn't happen.** Every finding cites `path:line` (or a command + its output).
   Mark each finding `CONFIRMED` (you verified it in code/tests/output) or `SUSPECTED` (plausible,
   not proven — say what would prove it).
2. **Trust nothing written before today.** Prior audits, specs, READMEs, commit messages, comments,
   and the "leads" in section 7 of this prompt are hypotheses. Re-verify against the current code.
3. **Navigate efficiently.** A knowledge graph exists in `graphify-out/` (`GRAPH_REPORT.md`,
   `graph.json`) covering `lib/` and `functions/` only — not `packages/`, `test/`, or native code.
   Use it (via the `graphify` skill) to find god nodes, communities, and call paths before grepping.
   It was generated 2026-08-06, so confirm anything it says against current files.
4. **Context hygiene.** Read large files in chunks of ≤200 lines. Never read `pubspec.lock`,
   `package-lock.json`, `*.g.dart`, `*.freezed.dart`, `functions/node_modules/**`, `build/**`,
   `.dart_tool/**`, the Pub cache, or binaries. Cap command output (`| Select-Object -First 80`,
   `--reporter compact`, `git log --oneline -20`). Summarize long outputs; don't paste them.
5. **Encoding hazard.** Never round-trip non-ASCII files (especially
   `lib/app/localization/app_localizations.dart`, which holds Arabic) through PowerShell
   `Get-Content`/`Set-Content`. Use the Read tool to inspect them.
6. **Secrets.** If you see a secret value, never print it in the report. Report the file, the key
   name, and whether it is tracked in git or present in history.
7. **Parallelize.** You may split the audit across subagents by domain (section 5), but each
   subagent must follow these same rules and return findings in the section 9 template. Merge and
   de-duplicate before writing the report.
8. **Be specific about fixes.** Every finding carries a concrete recommended fix (what to change,
   where, and how to verify), an effort estimate (S ≤ 2h, M ≤ 1d, L ≤ 1wk, XL > 1wk), and a risk-of-fix
   note.

---

## 2. Project context (verify, then build on it)

**Product.** Buildozer — a mobile-first, field-ready construction operations and accounting app for
contractors (Egypt/MENA focus; EGP currency appears in docs). Bilingual English/Arabic with RTL.
Offline use with intermittent connectivity is a core requirement.

**Naming is inconsistent — note where it matters:** repo folder `WizeSite`; Firebase project
`wize-site`; Dart package `buildtrack_app`; constitution title "BuildTrack"; app/bundle name
"Buildozer"; bundle/application id `com.ahmed.buildozer`; functions package `buildtrack-functions`.

**Client stack.** Flutter (Dart SDK `^3.10.8`), Riverpod 3, go_router 17, intl, google_fonts,
Firebase (core, auth, Firestore, Functions, Storage, Messaging, Crashlytics, App Check), Hive for
local persistence (`app_prefs`, `offline_actions`, `pending_attachments` boxes), RevenueCat
(`purchases_flutter`, `purchases_ui_flutter`), `pdf` + `printing`, `fl_chart`, `record` +
`audioplayers` (voice), `image_picker`, `file_picker` (beta), `flutter_contacts`,
`permission_handler`, `connectivity_plus`, `google_sign_in`, `url_launcher`, `package_info_plus`.
`cloud_firestore` is pinned to `6.6.0` **and** overridden with a local fork at
`packages/cloud_firestore` (see `scripts/patch_cloud_firestore.ps1`).

**Backend.** Cloud Functions v2, Node 22, TypeScript 6, firebase-admin 13, firebase-functions 7.
Almost everything lives in one ~4,550-line `functions/src/index.ts`; voice pipeline in
`functions/src/voice/`; helpers `http_app_check.ts`, `http_cors.ts`; one-off scripts
`entity_last_used_backfill.ts`, `worker_accounting_summary_initializer.ts`. Global options:
`region: us-central1`, `maxInstances: 10`. Secrets: `OPENROUTER_API_KEY`, `OPENROUTER_MODEL`,
`OPENROUTER_TRANSCRIPTION_MODEL`, `REVENUECAT_WEBHOOK_SECRET`.

Exported functions (verify the list is complete):
- Callables: `checkLimit`, `createProjectWithQuota`, `updateProject`, `archiveProject`,
  `unarchiveProject`, `createExpenseWithQuota`, `createPaymentWithQuota`,
  `createWorkerEntryWithQuota`, `archiveExpenseWithQuotaRefund`, `archivePaymentWithQuotaRefund`,
  `archiveWorkerEntryWithQuotaRefund`, `updateExpense`, `updatePayment`, `createWorker`,
  `updateWorker`, `archiveWorker`, `updateWorkerEntry`, `deleteProjectCascade`,
  `updateUserProfile`, `updateUserSettings`, `ensureUserWorkspaceBootstrap`, `setActiveWorkspace`,
  `completeInitialWorkspaceSetup`, `createWorkspace`, `updateWorkspaceMemberRole`,
  `removeWorkspaceMember`, `inviteMemberByEmail`, `inviteMemberWithQuota`, `processVoiceExpense`.
- HTTP twins (CORS + App Check verified manually): `createProjectWithQuotaHttp`,
  `createExpenseWithQuotaHttp`, `createPaymentWithQuotaHttp`, `createWorkerEntryWithQuotaHttp`,
  `archiveExpenseWithQuotaRefundHttp`, `archivePaymentWithQuotaRefundHttp`,
  `archiveWorkerEntryWithQuotaRefundHttp`, `processVoiceExpenseHttp`.
- Webhook: `revenuecatWebhook`.
- Firestore triggers: `onExpenseWriteRecompute`, `onPaymentWriteRecompute`,
  `onWorkerEntryWriteRecompute`, `onWorkerAccountingWriteRecompute`, `onProjectWriteRecompute`.

**Firestore collections** (from `firestore.rules`): `users`, `workspaces`, `memberships`,
`projects`, `expenses`, `payments`, `worker_entries`, `worker_accounting_records`,
`contractor_accounting_records`, `equipment_accounting_records`,
`transport_provider_accounting_records`, `workers`, `entities`, `subscriptions`, `usage_counters`,
`notifications`, `workspace_metrics`, `project_metrics`, `worker_accounting_summaries`,
`attachments`, `reports`, `report_exports`, `project_summaries`, `weekly_summaries`,
`entity_summaries`, `category_summaries`, `drafts`. Indexes in `firestore.indexes.json`.

**Storage paths** (`storage.rules`): `voice-expenses/{userId}/…`, `receipts/{userId}/…`,
`attachments/{userId}/…`, `profile-photos/{userId}/…`; 10 MB cap; MIME allowlists; default deny.

**Client layout.** Feature-first: `lib/features/<feature>/{domain,data,presentation}` for
`activity, auth, common, contractors, dashboard, entities, equipment, expenses, notifications,
payments, projects, reports, settings, subscription, transport, voice_expense, workers`. Shared
code in `lib/core/{cache,constants,models,navigation,pagination,prefetch,providers,services,utils,
widgets,widgets/ds}`; app shell in `lib/app/{app.dart,router.dart,theme/,localization/}`.
~205 Dart files in `lib/`, ~141 in `test/`, one `integration_test/app_full_feature_smoke_test.dart`.

Largest client files (prime suspects for complexity/rebuild/perf issues):
`app_localizations.dart` (~89 KB), `report_pdf_exporter.dart` (~56 KB), `reports_screen.dart`,
`expenses_screen.dart`, `dashboard_screen.dart`, `dashboard_providers.dart`,
`reports_providers.dart`, `payments_screen.dart`, `add_expense_screen.dart`, `settings_screen.dart`,
`project_repository.dart`, `workspace_mutation_service.dart`, `projects_screen.dart`,
`create_project_screen.dart`, `add_payment_screen.dart` (all 27–52 KB).

**Localization.** Hand-rolled `_en` / `_ar` maps in `app_localizations.dart`, with a silent English
fallback. Tests: `test/localization/localization_coverage_test.dart`.

**Governance.** `.specify/memory/constitution.md` v1.0.0 — five principles: (I) preserve existing
behaviour, (II) accounting correctness and traceability, (III) test-backed change, (IV) offline,
security and recovery first, (V) scalable data access; plus product constraints (attachment metadata
only in Firestore, backend-enforced integrity, indexes only for real queries). Grade the code against
every principle. Spec-kit feature folders: `specs/001-complete-accounting-scope`,
`specs/001-review-improvement-pack`, `specs/003-optional-project-budget` (current branch; a `002`
design-system branch exists but has no spec folder here).

**Build and release.** Android: `android/app/build.gradle.kts` (auto versionCode from git commit
count, release signing via `key.properties` or Codemagic `CM_KEYSTORE_PATH`, minify + shrink on,
`allowBackup=false`). iOS via `codemagic.yaml` (workflows `ios_release_artifact`, `ios_testflight`,
Xcode 26.4, Mac mini M2, dSYM upload). Store assets in `store/play/`. Release checker
`tool/release_audit.dart`. Demo seeding `scripts/seed_demo_account.js`.

**Prior audit material to diff against** (find what is fixed, still open, or regressed):
`docs/audits/2026-05-17-full-platform-audit.md`, `docs/audits/2026-05-17-release-gate-checklist.md`,
`BUILDOZER_UI_UX_AUDIT.md`, `Buildozer_—_Full_Project_Review_&_Improvement_Recommendations.md`,
`UX_Reconstruction_Proposal.md`, `specs/001-review-improvement-pack/review-findings.md`,
`docs/expenses_plan_gap_audit.md`, `docs/superpowers/plans/2026-07-24-buildozer-ui-ux-audit.md`.

---

## 3. Phase 0 — Baseline (run first, record results verbatim-summarized)

Run these, capture pass/fail counts and the first meaningful errors. If a command cannot run
(missing SDK, emulator, credentials), record it as a finding about reproducibility, not a silent skip.

```text
git status --short ; git log --oneline -20 ; git branch -a
flutter --version
flutter pub get
flutter analyze 2>&1 | Select-Object -First 80
flutter test --reporter compact 2>&1 | Select-Object -Last 50
flutter test --coverage --reporter compact   (then summarize coverage/lcov.info per feature folder)
flutter pub outdated
dart run tool/release_audit.dart
cd functions ; npm ci ; npm run build ; npm test ; npm audit --omit=dev ; npm outdated
firebase emulators:exec --only firestore,storage "npm --prefix functions test"   (if emulators available)
```

Also record: Flutter/Dart/Node versions actually installed vs. those declared; number of analyzer
issues by severity; number of skipped tests; tests that pass only because they are skipped or
mocked into meaninglessness.

---

## 4. Audit method

For each domain in section 5: (a) map the relevant files, (b) read the critical paths end to end,
(c) check against the checklist, (d) try to construct a concrete failure scenario for each suspicion
(inputs/state → wrong output, crash, leak, or bad UX), (e) record findings with the section 9 template.

Trace at least these end-to-end flows across UI → provider → repository/queue → callable → rules →
trigger → metrics → UI refresh:
1. Sign up → verify email → initial workspace setup → first project.
2. Create project with and without a Contract Value (spec 003), then edit/clear it.
3. Add expense (manual, with attachment, offline, then reconnect).
4. Add expense by voice (record → upload → `processVoiceExpense` → review → confirm).
5. Add payment (including picking a project with no contract value).
6. Add worker, record worker entries/attendance, worker accounting.
7. Contractor / equipment / transport-provider accounting records.
8. Archive and unarchive expense/payment/worker entry with quota refund; `deleteProjectCascade`.
9. Invite member, change role, remove member; switch workspace; confirm access revocation.
10. Hit a plan limit → limit reached screen → purchase via RevenueCat → webhook → entitlement.
11. Generate a report, export PDF and charts, share/print.
12. Notifications: creation, delivery (FCM), read state.
13. App kill mid-sync, reinstall, sign out/in with pending queue items.

---

## 5. Audit domains and checklists

### A. Secrets, credentials, and repository security
- Service account key `wize-site-firebase-adminsdk-*.json` sits at repo root. It is gitignored now —
  check **full history** (`git log --all --full-history -- <file>`) and all branches/remotes for it
  and for `.env`, `functions/.env.*`, `android/key.properties`, `*.jks`. If ever committed, it is a
  CRITICAL finding: rotate the key, purge history.
- Grep the whole tree (excluding node_modules/build) for API keys, tokens, private keys, webhook
  secrets, passwords, `sk-`, `AIza`, `-----BEGIN`. Distinguish public Firebase config (acceptable)
  from true secrets.
- `functions/.env.example` lists `OPENAI_API_KEY` though the code uses OpenRouter — stale or live?
- Are secrets accessed only through `defineSecret` and bound to the functions that need them?
- Is `google-services.json` / `GoogleService-Info.plist` modification in the working tree intended?
- Check `.gitignore` completeness and stray tracked junk (see section 7).

### B. Firestore security rules (`firestore.rules`)
- For every collection: who can read, create, update, delete? Is anything writable directly by the
  client that should only be written by a callable (money, metrics, summaries, usage counters,
  subscriptions, memberships, roles)?
- Workspace isolation: can a user read/write another workspace's documents by guessing IDs? Can a
  removed member still read? Can a member escalate their own role or membership?
- `canAccessAccounting` / accounting roles: are financial collections (payments, summaries,
  metrics, reports, report_exports, accounting records) restricted to owner/admin/accounting roles
  as the constitution requires? Can a field worker role read totals through a side collection
  (`project_metrics`, `workspace_metrics`, `weekly_summaries`, `category_summaries`, notifications)?
- Validation functions (`validProjectUpdate`, `validExpenseUpdate`, `validPaymentUpdate`,
  `validWorker*`, `validAccountingRecord`, `validDomainAccountingRecord`): type checks, numeric
  ranges (negative, zero, NaN, huge values), string lengths, immutable fields (`createdBy`,
  `workspaceId`, `projectId`, `createdAt`), `request.time` timestamps, `diff().affectedKeys()`
  allowlists.
- Spec 003: `contractValue` must be null or positive; `0` must not be storable as a "real" value.
- List queries: do rules allow unbounded `list` operations that would let a client enumerate data?
- Rules cost: number of `get()`/`exists()` calls per request (10-call limit, billing).
- Are `drafts`, `attachments`, `reports`, `report_exports` rules consistent with how the client uses
  them? Any collection used by code but missing from rules, or in rules but unused?
- Test coverage: `functions/src/firestore_rules.test.ts` and `test/firestore_rules_coverage_test.dart`
  — list every rule branch with no test.

### C. Storage security rules (`storage.rules`)
- Paths are keyed by `{userId}` and only the owner can read. In a shared workspace, how do teammates
  view receipts/attachments uploaded by someone else? If via long-lived download-token URLs stored
  in Firestore, those URLs are bearer secrets — assess leakage (logs, PDFs, shares) and revocation
  when a member is removed.
- MIME allowlist vs. what the client actually uploads (`attachment_file_types.dart`,
  `attachment_validation_service.dart`); content-type spoofing; `zip` allowed — justified?
- Voice uploads: README says `.m4a`; rules allow `audio/(wav|mpeg|aac|webm|mp4)` — confirm the
  recorder's actual content type matches.
- Orphaned files: are files deleted when an expense/project is archived or cascaded-deleted?
- Size cap 10 MB: enforced client-side too, with a friendly message?

### D. Cloud Functions (`functions/src/**`)
- **AuthN/AuthZ on every callable**: `request.auth` checked; workspace membership and role checked
  server-side for every read/write; IDs from the client never trusted for ownership.
- **App Check**: HTTP twins call `verifyHttpAppCheck`, but do the `onCall` functions set
  `enforceAppCheck: true` (or equivalent)? If not, callables are reachable without attestation.
  Assess whether the HTTP twins are still needed at all, or are a duplicated attack surface.
- **CORS** (`http_cors.ts`): allowed origins, credentials, preflight handling.
- **Input validation**: every field type-checked, bounded, normalized; currency and decimal
  handling; dates/timezones; string sanitization; payload size.
- **Transactions and idempotency**: quota consume/refund inside the same transaction as the write?
  Retries from the offline queue with the same client ID — duplicate records or double quota?
  Archive-with-refund called twice?
- **Triggers** (`on*WriteRecompute`): recursion/loops (trigger writes a doc that re-triggers),
  at-least-once delivery (non-idempotent increments), out-of-order events, full recompute cost on
  large projects, `onProjectWriteRecompute` firing on metric writes.
- **Risk classification** and `recomputeProjectMetrics` with null contract (spec 003 research R6):
  both arms suppressed? The two different `remainingBalance` formulas kept separate (R7)?
- **`deleteProjectCascade`**: batch limits (500), partial failure, storage cleanup, authorization,
  quota refunds, metrics cleanup, undo/soft-delete.
- **Membership functions**: removing the last owner, owner removing themselves, inviting an existing
  member, email case sensitivity, invite spam/abuse, enumeration of registered emails.
- **`revenuecatWebhook`**: secret compared in constant time? Replay protection? Event types
  handled (renewal, cancellation, expiration, billing issue, refund, transfer, product change)?
  Mapping app user ID → workspace. Idempotency on duplicate events. Sandbox vs production events.
- **Voice pipeline** (`functions/src/voice/`): storage path ownership verified before download;
  file size/duration limits; prompt injection via transcript into the LLM parser; LLM output
  validated against a schema before being returned; model fallback, timeouts (120 s, 1 GiB — right
  sized?), cost per call, rate limiting per user, PII in logs.
- **Global options**: `maxInstances: 10` applies to everything including the webhook and triggers —
  risk of throttling/dropped events under load? Per-function `concurrency`, `memory`,
  `minInstances` for cold-start-sensitive callables.
- **Code structure**: 4,550-line `index.ts` — propose a module split (projects, expenses, payments,
  workers, workspaces, subscription, triggers, shared validation). Duplicated logic between callable
  and HTTP twins.
- **Error handling and logging**: `HttpsError` codes meaningful to the client; no stack traces or
  internal IDs leaked; structured logging; `logging_static.test.ts` intent satisfied.
- **Tooling**: `"lint": "echo \"No lint configured\""` — no ESLint. Strict `tsconfig`? Compiled
  `functions/lib/` is tracked in git (≈56 files) — intended?
- Node 22 / firebase-functions 7 / TypeScript 6 compatibility and deprecations.

### E. Accounting correctness (highest business risk)
- Money representation: `double` in Dart and `number` in TS — floating-point rounding in totals,
  summaries, PDFs, and comparisons. Recommend integer minor units or a decimal type if warranted,
  with a migration path.
- Currency: single-currency assumption? Formatting via `intl` per locale (Arabic-Indic digits?),
  rounding mode consistency between client, functions, and PDF.
- Every derived figure (project budget used, profit/loss, margin, remaining balance, cash collected,
  outstanding payments, worker cost, category totals, weekly summaries, entity aggregations):
  find **every** place it is computed (client providers, `project_metrics_merger.dart`,
  `dashboard_providers.dart`, `reports_providers.dart`, `report_export_data_builder.dart`,
  functions recompute). Are they consistent? Any double counting of archived records, worker
  entries vs. expenses, or payments across projects?
- Archived records excluded everywhere they should be, included where they should be (audit trail).
- Old documents missing newer fields load with deterministic fallbacks (constitution II) —
  especially the `?? 0` anti-pattern flagged by spec 003.
- Spec 003 invariant: a project without a Contract Value can never hold payments — enforced in
  callables, mirrored in the client, and surfaced to the user when a queued offline action is
  rejected. Walk `specs/003-optional-project-budget/tasks.md` and mark each task done/not done
  against the code.
- Date boundaries: timezone of "today", week start (Saturday in Egypt?), month rollover, DST,
  report date filters inclusive/exclusive.
- Audit trail: who changed an amount and when? Is edit history kept? Recommend if absent.

### F. Offline queue and sync
- `offline_action_queue.dart`, `offline_queue_coordinator.dart`, `pending_attachment_service.dart`,
  `sync_error_classifier.dart`, `workspace_mutation_service.dart`, `sync_status_screen.dart`.
- Ordering and dependencies (create project offline → add expense to it offline → sync).
- Idempotency keys; retry/backoff; poison messages that retry forever; permanent vs. transient error
  classification; user visibility of failures and a way to fix or discard.
- Optimistic placeholders reconciled with server results; flicker; stale cache after sync.
- Workspace switch or sign-out with pending items — are they lost, leaked to the next user, or
  replayed under the wrong workspace?
- Hive boxes are **unencrypted** and hold financial actions and pending attachments. Assess risk on
  rooted/shared devices; recommend `HiveAesCipher` with a key in secure storage if warranted.
- Firestore offline persistence settings and cache size; interaction with the Hive queue (two
  offline systems — any conflict or double write?).
- Connectivity detection correctness (`connectivity_plus` reports network, not internet).

### G. Auth, session, workspaces, and roles
- `auth_session.dart`, `session_restore_service.dart`, `email_auth_service.dart`,
  `google_auth_service.dart`, splash/login/verify-email/forgot-password/onboarding screens, router
  redirects in `lib/app/router.dart`.
- Redirect loops (a splash/login loop was fixed in `78fbe92` — confirm no remaining path), deep
  links into protected routes, back-button escapes after sign-out.
- Unverified email access; Google sign-in edge cases; account deletion (required by Apple and
  Google Play policies — does it exist?); password reset UX.
- Role model enforcement in the UI matches rules and functions (no screen shows figures the backend
  would deny, and vice versa). `accounting_access_service.dart` / provider correctness.
- Riverpod providers that cache user/workspace data — cleared on sign-out and workspace switch?

### H. Subscription, quota, and monetization
- `subscription/**`, `entitlement_guard_service.dart`, `revenuecat_purchase_coordinator.dart`,
  `firebase_usage_quota_repository.dart`, `usage_card.dart`, plans/manage/limit/success screens.
- Source of truth for entitlement (RevenueCat vs. Firestore `subscriptions`) and race conditions
  after purchase; restore purchases; downgrade behaviour when over quota; usage period key rollover
  timezone.
- Client-side limit checks can be bypassed — confirm server enforcement for every quota-bearing
  action including invites.
- Store compliance: price display, trial terms, cancellation info, links to terms/privacy.
- `REVENUECAT_SETUP.md` accuracy.

### I. Voice expense feature (client side)
- `voice_recorder_service.dart`, `microphone_permission_service.dart`, `voice_capture_controller.dart`,
  record/processing/review screens, `voice_expense_repository.dart`.
- Permission denied/permanently denied flows on Android and iOS; interruption (call, backgrounding);
  max duration; file cleanup after success/failure; offline behaviour (queue or block with message);
  Arabic speech accuracy and dialect handling; review screen lets the user correct every field.

### J. Flutter architecture, state, and code quality
- Layering violations (presentation importing Firestore directly, domain depending on Flutter).
- Riverpod usage: provider scoping, `autoDispose` where appropriate, `ref.watch` in callbacks,
  `ref.read` in build, listeners that leak, providers recreated per rebuild, family keys with
  unstable equality, error/loading states handled via `app_async_state.dart` / `async_content.dart`
  consistently.
- `freezed_annotation` and `json_annotation` are dependencies, but there are **zero** generated
  files and no `build_runner`/`freezed`/`json_serializable` dev dependencies — dead dependencies or
  abandoned approach? Hand-written `fromMap` parsing robustness instead.
- Very large files (section 2) — propose splits into widgets/controllers; duplicated code across the
  four domain accounting features (contractors, equipment, transport, workers) and the `common`
  domain accounting screen — is the abstraction complete?
- `analysis_options.yaml` uses only `flutter_lints` defaults — recommend stricter rules
  (`strict-casts`, `strict-inference`, `strict-raw-types`, `unawaited_futures`,
  `avoid_dynamic_calls`, `prefer_const_constructors`, `always_use_package_imports`,
  `use_build_context_synchronously`, etc.) and estimate the fallout.
- ~167 `TODO`/`FIXME`/`HACK` markers across `lib/` and `functions/src/` — triage them into the report.
- `print`/`debugPrint` usage (~11) — leaking data in release logs?
- `BuildContext` used across async gaps; `mounted` checks; controllers/streams/timers disposed.
- `main.dart`: Crashlytics `log` called before `setCrashlyticsCollectionEnabled`; every
  `PlatformDispatcher` error recorded as `fatal: true`; `ensureInitialized` inside the guarded zone;
  Hive boxes opened in `main` and again in services — confirm no zone-mismatch warnings and that
  startup failures (Firebase init error, no network) show a recoverable UI rather than a blank screen.
- The forked `packages/cloud_firestore` override: why it exists, what it patches, how far behind
  upstream it is, and the exit plan.

### K. UI, UX, and design system
- Design system under `lib/core/widgets/ds/` and `lib/app/theme/{app_theme.dart,build_tokens.dart}`:
  are screens using tokens, or hard-coded colors, paddings, radii, font sizes? List every hard-coded
  value outside the theme.
- Light and dark mode on every screen (`dark_mode_smoke_test.dart` coverage); contrast ratios.
- Empty, loading, error, offline, and permission-denied states on every screen; skeletons vs.
  spinners; no blank async loading (`test/static/no_blank_async_loading_test.dart`).
- Forms: validation messages, numeric keyboards, thousand separators, decimal input in Arabic
  locale, preventing double-submit, preserving input on error, unsaved-changes guard.
- Navigation: bottom nav shell, back behaviour, deep links, predictable titles, FAB placement.
- Small screens (≤360 dp width), large text scale (200%), tablets, landscape, notches/safe areas.
- Consistency of icons, terminology ("expense" vs "cost", "payment" vs "receipt"), capitalization,
  date and number formats across screens and PDFs.
- Re-check each item in `BUILDOZER_UI_UX_AUDIT.md` and `UX_Reconstruction_Proposal.md`: done, partly
  done, or not done.

### L. Localization and RTL
- Every key present in both `_en` and `_ar`; no silent English fallback visible in Arabic UI; no
  hard-coded user-facing strings in widgets, snackbars, dialogs, validators, PDFs, notifications,
  Cloud Function error messages, or push payloads.
- Plurals, gender, and interpolation handled correctly in Arabic (the hand-rolled maps likely lack
  ICU plural rules). Consider migrating to `gen-l10n` ARB files — assess effort and benefit.
- RTL: `EdgeInsetsDirectional`, `AlignmentDirectional`, directional icons (arrows, chevrons),
  `TextDirection` for mixed Arabic/Latin/number strings, charts and PDFs in RTL, onboarding paging
  direction (fixed in `63a015b` — confirm).
- Native: iOS `CFBundleLocalizations` and localized `InfoPlist.strings` for permission prompts;
  Android `res/values-ar`; store listing in Arabic.
- Fonts: Google Fonts fetched at runtime — offline first launch shows fallback? Bundle the fonts?

### M. Accessibility
- Semantics labels on icon buttons, charts, stat tiles, progress bars, money rows; touch targets
  ≥48 dp; focus order; screen reader announcement of errors and sync results; not conveying meaning
  by color alone (profit/loss red/green); reduced-motion respect for the counter/progress animations
  added in `7af5603`; text scaling without overflow. Check `accessibility_rtl_test.dart` coverage.

### N. Performance
- Cold start work in `main` and `FirebaseInitializer`; eager preloading (`core/prefetch`,
  `app_prefetcher`) — does it load more than the first screen needs?
- Firestore reads per screen open; listeners left open; unbounded queries (constitution V);
  pagination correctness (`core/pagination`); dashboard "All-Projects overview derived live"
  (`9de29e0`) — read cost at 100 projects / 10k expenses.
- Widget rebuild scope; `const` constructors; heavy work in `build`; list virtualization; image
  decoding size for receipts; PDF generation on the main isolate (`report_pdf_exporter.dart`) —
  move to `compute`/isolate?
- App size: unused dependencies, fonts, assets, split-per-ABI, deferred components.
- Cloud Functions cold starts and cost; trigger fan-out; recompute cost.

### O. Data model, indexes, and migrations
- Every query in client and functions has a matching index; every index is used (constitution rule).
- Denormalized fields (`projectName` on expenses, etc.) kept in sync on rename?
- Document size growth, hot documents (metrics/counters updated on every write — contention),
  write rate limits per document (1/s sustained).
- Backfill/migration scripts: idempotent, resumable, dry-run mode, documented.
- Backup and restore strategy (Firestore PITR/exports) — exists? documented?

### P. Reports and exports
- `reports/**`: correctness of every figure vs. the source records; date range bounds; project vs.
  workspace scope (`report_scope.dart`); PDF Arabic shaping and RTL, font embedding, pagination of
  long tables, page numbers, currency formatting, generation time on low-end devices; chart exports;
  share/print on Android and iOS; access restricted to accounting roles.

### Q. Notifications
- FCM token registration/refresh/removal on sign-out; Android 13+ `POST_NOTIFICATIONS` runtime
  permission (not seen in the manifest — verify); iOS `UIBackgroundModes` `remote-notification` and
  APNs setup (not seen in `Info.plist` — verify); notification tap deep-links; localization of
  notification text; in-app notification list pagination and read state.

### R. Testing
- Map test coverage per feature and per risk axis (accounting, offline, permissions, attachments,
  exports). Identify untested critical paths.
- Test quality: assertions that actually check behaviour; over-mocking; flaky time-dependent tests
  (use of `fake_async`); golden tests absent?
- Cloud Functions tests: which run without emulators, which require them, and whether CI runs them.
- Integration test `app_full_feature_smoke_test.dart`: is it runnable and run anywhere?
- Static guard tests in `test/static/` and `functions/src/*_static.test.ts` — still meaningful?
- Recommend missing tests with exact file names and cases.

### S. Build, release, CI/CD, and native configuration
- `codemagic.yaml` hard-codes `--build-name=1.0.0` while `pubspec.yaml` is `1.0.9+1` — which version
  ships? Is there an Android workflow at all? Do any workflows run `flutter test` or `npm test`
  (only `flutter analyze` was seen)? No GitHub Actions — recommend a PR gate.
- `rm -rf Pods Podfile.lock` + `pod install --repo-update` on every build: slow and non-reproducible.
- Android: auto versionCode from git commit count (breaks on shallow clones/squashes?), R8/proguard
  rules for Firebase, RevenueCat, Hive, pdf; `minSdk`/`targetSdk` meet current Play requirements;
  exported components; network security config; permissions justified (`RECORD_AUDIO`,
  `READ_CONTACTS` — Play declaration needed).
- iOS: privacy manifest (`PrivacyInfo.xcprivacy`) with required-reason APIs; usage descriptions
  specific and localized; App Tracking not required? Minimum iOS version; Swift Package Manager
  disabled in pubspec — reason?
- Firebase deploy config split (`firebase.json` vs `firebase.deploy.json`) — why, and are they in
  sync?
- Crashlytics symbol upload for Android (obfuscation mapping) as well as iOS dSYMs.
- Unused platform folders (`linux/`, `macos/`, `windows/`, `web/`) — ship or delete?

### T. Dependencies
- `flutter pub outdated` and `npm outdated`: majors behind, discontinued packages, security
  advisories (`npm audit`). `file_picker: ^12.0.0-beta.7` is a beta in production.
  `hive`/`hive_flutter` 2.x maintenance status (consider `hive_ce` or alternatives). `http` still
  needed? `purchases_ui_flutter` used? Licenses compatible with a commercial app.

### U. Repository hygiene and documentation
- Tracked junk files at repo root: `0`, `const`, `Gradle`, `onSelect(index)`,
  `store/play/$(node` (and untracked `'project_1')`, `_error`, `flutter_01.log`,
  `firestore-debug.log`) — accidental shell redirections. Also tracked large binaries
  (`Buildozer Design System.zip`) and design scratch files (`UX_Mockups.html`, two
  `implementation_plan_*ui*.md` files).
- Root-level scattered docs: propose a `docs/` structure and an index.
- `AGENTS.md` points to `specs/001-review-improvement-pack/plan.md` while `CLAUDE.md` points to
  `specs/003-optional-project-budget/plan.md` — agent instructions disagree.
- README accuracy (setup steps, deploy command, env vars, architecture). Missing: CONTRIBUTING,
  architecture diagram, runbook, incident response, data retention policy, changelog.
- Commit hygiene: several recent commit messages are raw `git status` dumps (`b607c69`, `dfd60b5`,
  `bca0ffc`, `25ceb78`). Recommend Conventional Commits enforcement.
- Branch state: stale branches (`001-*`, `002-*`) merged or abandoned?

### V. Observability and operations
- Crashlytics: non-fatal logging of handled errors, custom keys (workspace, screen), user ID
  (privacy-safe); `app_telemetry.dart` — what is tracked, is there any product analytics?
- Functions: structured logs, alerting on error rate, budget alerts, quota dashboards.
- Feature flags / remote config for kill switches (voice AI, purchases) — absent? recommend.
- Forced-update mechanism for breaking backend changes (`package_info_plus` present — used?).

### W. Privacy, legal, and store compliance
- Data collected (contacts, audio, photos, financial records, email) vs. privacy policy and store
  data-safety forms; contacts uploaded or used locally only; audio retention and deletion; sending
  audio/transcripts to OpenRouter/third-party models disclosed to users and in the policy.
- In-app account deletion and data export; workspace data ownership when owner leaves.
- Egypt/MENA data protection considerations (e.g., Egypt PDPL) and GDPR if EU users.
- `store/play/LISTING.md` claims match actual features.

---

## 6. Enhancement, suggestion, and improvement search (mandatory, not optional)

Spend real effort here. For each idea give: user/business value, evidence it matters (code gap,
competitor precedent, user-flow friction you observed), effort, dependencies, risks, and a priority
(Now / Next / Later).

1. **Product features** — research (use WebSearch) what leading construction management and
   contractor accounting apps offer (e.g., Procore, Buildertrend, CoConstruct, Fieldwire, Raken,
   QuickBooks for contractors, and apps popular in Egypt/Gulf markets). Compare against Buildozer and
   list missing capabilities that fit a mobile-first, offline, Arabic-first product. Candidate areas
   to evaluate (don't assume — justify): client invoicing and payment schedules/milestones, change
   orders, quotations/BOQ, purchase orders, supplier credit and dues, cheques and post-dated cheque
   tracking, petty cash/custody per site engineer, material inventory per site, daily site logs with
   photos and weather, worker attendance via QR/geo, payroll/advances, subcontractor retention,
   VAT/tax handling, multi-currency, budget vs. actual by category, cash-flow forecasting, alerts for
   overspend, WhatsApp sharing of statements/reports (very common in MENA), receipt OCR,
   approvals workflow, client portal/read-only share links, audit log, data export to Excel.
2. **UX improvements** — friction points you found in the traced flows; faster data entry (recent
   values, templates, duplicates, quick add from dashboard, widgets, voice improvements); onboarding
   and first-run value; progressive disclosure for field workers vs. accountants.
3. **Architecture and code** — module boundaries, splitting `index.ts`, shared validation schemas
   between client and functions, money type, repository interfaces for testability, code generation
   for models, ARB-based localization, removing HTTP twins.
4. **Performance and cost** — read/write reductions, aggregation strategies, caching, function
   sizing, image compression before upload, bundle size.
5. **Security hardening** — App Check enforcement, encrypted local storage, least-privilege rules,
   rate limiting, abuse protection on invites and voice AI, secret rotation policy.
6. **Quality and delivery** — CI pipeline on PRs (analyze, test, functions test, rules test with
   emulators, coverage threshold), pre-commit hooks, stricter lints, golden tests, staging Firebase
   project, release checklist automation, Dependabot/Renovate.
7. **Observability and growth** — analytics events for activation/retention funnels, in-app
   feedback, NPS, crash-free-users target, remote config, A/B testing of paywall.
8. **Modernization** — newer Flutter/Dart language features (records, patterns, sealed classes for
   state), Riverpod code generation/`Notifier` patterns, replacing dated or beta packages.
9. **Quick wins** — a separate list of items that each take under two hours and give visible value.

---

## 7. Pre-identified leads (verify each; do not copy into the report unverified)

These were noticed while preparing this prompt. Confirm, refute, or refine each one.

1. Service-account JSON and `.env` files exist on disk at the repo root (gitignored) — check history.
2. `functions/src` `onCall` functions show no `enforceAppCheck`; only HTTP twins verify App Check.
3. Hive boxes `offline_actions` and `pending_attachments` are opened without an encryption cipher.
4. Storage rules are per-uploader (`owner(userId)`), which conflicts with shared-workspace viewing
   unless download URLs are shared.
5. `maxInstances: 10` is global, including `revenuecatWebhook` and all Firestore triggers.
6. `functions` has no linter; `functions/lib/` build output is committed.
7. `freezed_annotation` / `json_annotation` declared, no generated code, no generator dev deps.
8. `file_picker` on a beta version.
9. Local fork override of `cloud_firestore` in `packages/`.
10. Codemagic `--build-name=1.0.0` vs pubspec `1.0.9+1`; no test steps observed in CI.
11. `AGENTS.md` and `CLAUDE.md` reference different active plans.
12. Tracked junk files at root (`0`, `const`, `Gradle`, `onSelect(index)`, `store/play/$(node`).
13. `functions/.env.example` mentions `OPENAI_API_KEY` though voice uses OpenRouter.
14. Android manifest lacks `POST_NOTIFICATIONS`; iOS `Info.plist` lacks `UIBackgroundModes` and
    `CFBundleLocalizations` — despite FCM and Arabic support.
15. `analysis_options.yaml` uses default lints only; ~167 TODO/FIXME/HACK markers.
16. `main.dart` logs to Crashlytics before setting collection state and marks all uncaught
    `PlatformDispatcher` errors fatal.
17. Six 40–90 KB Dart files and a 4,550-line functions file concentrate risk.
18. Money is `double`/`number` end to end.
19. Several recent commits have `git status` output as their message.
20. `google-services.json` and `pubspec.yaml` have uncommitted modifications on this branch.

---

## 8. Severity scale

| Severity | Meaning | Examples |
|---|---|---|
| **P0 – Critical** | Exploitable security hole, data loss/corruption, wrong money shown as correct, leaked secret, store rejection, crash on a core flow | Cross-workspace read, committed private key, double-charged quota, payments hidden |
| **P1 – High** | Serious bug or risk on a common path; compliance gap; broken offline recovery | Queued action retries forever silently, missing account deletion, role bypass in UI |
| **P2 – Medium** | Bug on an edge path, significant UX/perf/maintainability issue | Unbounded query at scale, missing Arabic strings on a screen, 50 KB widget file |
| **P3 – Low** | Polish, consistency, hygiene, minor debt | Hard-coded padding, stale comment, junk file, typo, icon misalignment |
| **Idea** | Enhancement or suggestion (section 6) | New feature, refactor proposal, tooling upgrade |

---

## 9. Output — the report

Write one Markdown file: `docs/audits/2026-09-14-full-audit-report.md` (adjust the date to the day
you run). Structure:

1. **Executive summary** (≤ 1 page): overall health score per domain (A–W, 0–10 with one-line
   justification), top 10 risks, top 10 improvements, release-readiness verdict (ship / ship with
   fixes / do not ship) with reasons.
2. **Baseline results** from section 3 (versions, analyzer counts, test counts, coverage, npm audit,
   outdated majors, commands that could not run and why).
3. **Constitution compliance** — each of the five principles and the product constraints:
   PASS / PARTIAL / FAIL with evidence.
4. **Prior-audit diff** — table of every finding from the prior audit documents listed in section 2:
   Fixed / Still open / Regressed / No longer applicable, with evidence.
5. **Spec 003 status** — each task in `specs/003-optional-project-budget/tasks.md`: done / partial /
   missing, with evidence.
6. **Findings by domain** (A–W), sorted by severity, each using this template:

   ```markdown
   #### [P1][F-017] Short title
   - **Status:** CONFIRMED | SUSPECTED
   - **Domain:** D. Cloud Functions
   - **Location:** `functions/src/index.ts:2423`, `lib/features/payments/data/payment_repository.dart:88`
   - **What's wrong:** one or two precise sentences.
   - **Failure scenario:** concrete inputs/state → observable wrong outcome.
   - **Evidence:** code excerpt (≤ 10 lines) or command output summary.
   - **Recommended fix:** specific change and where.
   - **Verification:** test to add or manual check that proves the fix.
   - **Effort:** S | M | L | XL  · **Fix risk:** low | medium | high
   - **Related:** F-003, prior audit P1-4, spec 003 FR-041
   ```

7. **Low-severity detail list** — every P3 item as a compact table (ID, file:line, issue, fix). This
   is where the "every small detail" lives; be exhaustive.
8. **Enhancements and suggestions** from section 6, grouped and prioritized (Now / Next / Later),
   with the competitor research sources you used (links).
9. **Quick wins** list (< 2 h each).
10. **Remediation roadmap** — ordered phases (Stop-the-bleeding → Stabilize → Harden → Improve →
    Grow), each with finding IDs, rough effort, and dependencies between items.
11. **Open questions for the product owner** — things you could not decide from the code
    (business rules, intended behaviours, market decisions).
12. **Appendix** — files reviewed, flows traced, commands run, anything skipped and why.

---

## 10. Definition of done

- Every domain A–W has been examined, with findings or an explicit "no issues found — checked X, Y, Z".
- Every lead in section 7 is marked confirmed, refuted, or refined.
- Every finding has location, scenario, fix, verification, effort.
- The enhancements section contains researched, justified ideas — not a generic list.
- No source, config, rules, or git state was changed; nothing was deployed; no secret values appear
  in the report.
- Finish by printing, in the terminal, the report path, counts per severity, the release-readiness
  verdict, and the top five actions.
