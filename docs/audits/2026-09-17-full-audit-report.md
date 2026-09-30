# Full Project Audit Report — Buildozer (WizeSite)

**Date:** 2026-09-17  
**Mode:** Full A–W, risk-first sequencing  
**Playbook:** [AUDIT_PLAYBOOK.md](./AUDIT_PLAYBOOK.md)  
**Leads:** [LEAD_REGISTER.md](./LEAD_REGISTER.md)  
**Source of checklists:** [2026-09-14-full-audit-prompt.md](./2026-09-14-full-audit-prompt.md) (historical; several leads were stale)  
**Constraint:** Read-only of app source. This report and the playbook files are the only writes.

**Release-readiness verdict: do not ship** as a financially trustworthy production release until P0 money-display bugs (F-E01, F-E02) are fixed. Core recording, Spec 003 payment guards, App Check on callables, analyzer, and unit tests are in good shape. A TestFlight/internal track is acceptable if reports are not treated as the source of truth.

---

## 1. Executive summary

Analyzer is clean. Flutter: **633 tests passed**. Functions: **51 passed, 3 skipped** (emulator-gated). `tool/release_audit.dart`: **all PASS**, including Android OAuth client for `com.ahmed.buildozer` (May 17 P0 is **fixed**). `npm audit --omit=dev`: **0 vulnerabilities**.

The product is a capable field-first contractor app (offline queue, bilingual, quotas, voice, optional contract value). The highest remaining risk is **inconsistent cash-collected math**: helpers match, but reports/PDF/export and payment-archive deltas still treat gross `amount` as cash. Secondary: **field roles can read full money ledgers** in Firestore rules; **RevenueCat cancellation** drops Pro immediately; **session sign-out** does not always clear the Hive queue.

### Health by domain (0–10)

| Domain | Score | One-line justification |
| --- | ---: | --- |
| A Secrets | 7 | No tracked private keys in history; local adminsdk/.env on disk; google-services still tracked |
| B Firestore rules | 6 | Isolation OK; `entryOnly` can read expenses/payments |
| C Storage | 6 | MIME/size OK; download-token ACL; cascade orphans |
| D Cloud Functions | 6 | App Check on callables; webhook/cascade/HTTP twins/quota-invite gaps |
| E Accounting | 4 | Helpers aligned; reports/archive/offline pending disagree |
| F Offline | 6 | Idempotency + remap work; FIFO broken during backoff; Hive crash window |
| G Auth/session | 7 | Splash loop fixed; cleanup not on every sign-out |
| H Subscription | 7 | Server quota solid; cancel/unknown mapping weak |
| I Voice | 8 | Permission/review/disclosure solid; no offline preflight |
| J Architecture | 6 | Layering OK; unused Firestore fork; mega-files |
| K UI/UX | 7 | DS + empty/offline states; prior UI P0 list not closed |
| L Localization/RTL | 7 | Coverage test OK; hardcoded expense groups; LTR EdgeInsets |
| M Accessibility | 7 | Targeted 48dp/RTL tests; not product-wide |
| N Performance | 6 | Pagination exists; unbounded dashboard streams; PDF on UI isolate |
| O Data/indexes | 8 | Queries largely indexed; a few likely-unused composites |
| P Reports/PDF | 5 | Role gate UI-only; Arabic PDF lacks RTL; cash vs gross |
| Q Notifications | 6 | In-app only (no FCM); PrivacyInfo thin |
| R Testing | 7 | Strong unit/widget; emulator rules skip in default CI |
| S Build/CI | 7 | iOS Codemagic + tests; no Android workflow |
| T Dependencies | 6 | Beta file_picker; dead codegen deps; Hive 2.x |
| U Hygiene/docs | 4 | Tracked junk, committed `functions/lib`, status-dump commits |
| V Observability | 6 | Crashlytics OK; no force-update/kill switch |
| W Privacy/legal | 6 | Account deletion exists; store/AI/PDPL disclosure lag |

### Top 10 risks

1. **F-E01** Reports/PDF/export sum unpaid payments as income.
2. **F-E02** Archiving a payment subtracts full `amount` from metrics (not cash collected).
3. **F-B01** Any workspace member (`entryOnly` included) can read expense/payment ledgers.
4. **F-H01** RevenueCat `CANCELLATION` immediately removes Pro quota.
5. **F-G01** Some sign-out paths leave Hive queues for the next user on the device.
6. **F-D01** Webhook secret compare is not constant-time and has no replay protection.
7. **F-F01** Queue backoff skips head-of-line → expense can sync before its pending project.
8. **F-C01** `deleteProjectCascade` / account deletion leave Storage files; `receipts/` omitted.
9. **F-F02** Hive AES crash between migrate and flag can empty the offline queue.
10. **F-N01** Dashboard live-streams all projects/metrics/unpaid payments (constitution V).

### Top 10 improvements

1. Use `cashCollectedAmount` in every aggregator (reports, PDF, pending, archive).
2. Align expense/payment **reads** with `canAccessAccounting` (product decision).
3. Keep Pro active until `EXPIRATION`; ignore unknown RC events.
4. Call `LocalSessionCleanup` on every sign-out.
5. Pause the whole queue while action 1 is in backoff.
6. Persist Hive encrypted flag per box immediately after migrate.
7. WhatsApp share of PDF statements (MENA default channel).
8. Progress billing / retention / cheques (Egypt contractor table stakes — later).
9. CI: run Firestore emulator rules tests; add Android Codemagic workflow.
10. Split `functions/src/index.ts`; drop unused `cloud_firestore` fork.

---

## 2. Baseline results

| Check | Result |
| --- | --- |
| Branch | `003-optional-project-budget` |
| Flutter | 3.44.4 stable · Dart 3.12.2 (pubspec SDK `^3.10.8`) |
| Node (local) | **v25.2.1** vs functions `engines.node: 22` |
| `flutter analyze` | **No issues found** (71s) |
| `flutter test` | **All tests passed — 633** |
| `dart run tool/release_audit.dart` | **11/11 PASS** including Android OAuth client for `com.ahmed.buildozer` |
| `functions npm test` | 51 pass, 0 fail, **3 skipped** (need `FIRESTORE_EMULATOR_HOST` / storage emulator) |
| `npm audit --omit=dev` | **0 vulnerabilities** |
| `npm outdated` | firebase-admin 13→14 major; typescript 6→7 major; others patch/minor |
| `flutter pub outdated` | `file_picker` beta.7 vs 13.1.0; `cloud_firestore` pinned/overridden 6.6.0 vs 6.10.0; many FlutterFire patches |
| Coverage (`flutter test --coverage`) | **Not run** this pass (time). |
| Firebase emulators | **Not run** — record as reproducibility/CI gap, not a silent skip. |
| First `flutter test` attempt | Failed until `ProgramFiles(x86)` was set in the agent shell. Reproducibility P3. |

Working tree: large uncommitted batch (accounting helpers, account deletion, Hive AES, Codemagic tests, junk deletions). Report judges **current files on disk**, including uncommitted work.

---

## 3. Constitution compliance

| Principle / constraint | Grade | Evidence |
| --- | --- | --- |
| I Preserve existing behaviour | PARTIAL | Spec 003 optional contract is additive; uncommitted surface is large; reports figures regress vs metrics |
| II Accounting correctness | **FAIL** | F-E01, F-E02, F-E03 — wrong money can display as correct |
| III Test-backed change | PARTIAL | Strong unit/widget; emulator rules/recompute skipped in default `npm test`; no integration_test in CI |
| IV Offline, security, recovery | PARTIAL | Queue + dead letters + Hive AES exist; sign-out cleanup incomplete; money **reads** not role-gated |
| V Scalable data access | PARTIAL | Paginated lists; dashboard unbounded project/metrics/unpaid streams |
| Attachment metadata only in Firestore | PASS | Storage paths + metadata on docs |
| Backend-enforced integrity | PARTIAL | Callables + write-deny on subscriptions; ledger **reads** open to all members |
| Indexes only for real queries | PARTIAL | Most match; inverted composites likely unused (F-O01) |

---

## 4. Prior-audit diff

Sources: [2026-05-17-full-platform-audit.md](./2026-05-17-full-platform-audit.md), [2026-05-17-release-gate-checklist.md](./2026-05-17-release-gate-checklist.md), [BUILDOZER_UI_UX_AUDIT.md](../../BUILDOZER_UI_UX_AUDIT.md).

| Prior finding | Status | Evidence |
| --- | --- | --- |
| May 17 P0: Android OAuth client missing for `com.ahmed.buildozer` | **Fixed** | `tool/release_audit.dart` PASS; google-services contains Android OAuth client |
| May 17 P1: queue errors classified from strings only | **Fixed** | `SyncErrorClassifier` + `lastErrorCode`; new issue is FIFO during backoff (F-F01) |
| May 17 P1: session restore strands signed-in users | **Fixed** (loop) | Splash loop broken via sign-out; **new** cleanup gap F-G01 |
| May 17 P1: iOS debug App Check weaker than Android | **Fixed** (claimed in May 17 + `enforceAppCheck` now on callables) | Console providers still **console-gated** |
| May 17 P2: release depends on Firebase Console | **Still open** | App Check providers, RevenueCat dashboard, signed Google Sign-In smoke |
| May 17 P3: observability gaps | **Fixed** | Crashlytics breadcrumbs; collection enabled before logs (L16 refuted) |
| Codemagic `--build-name=1.0.0` | **Fixed** | `$PUBSPEC_VERSION` + static test |
| App Check missing on `onCall` | **Fixed** | L02 refuted |
| Hive unencrypted | **Fixed** (AES) | Residual L24 |
| Account deletion missing | **Fixed** | `deleteOwnAccount` + settings UI |
| UI audit P0/P1 list | **Still open / partial** | Checklist in `BUILDOZER_UI_UX_AUDIT.md` not closed; much DS work shipped |
| AGENTS vs CLAUDE plan pointers | **Fixed** | Both spec 003 |

---

## 5. Spec 003 status

Walked against code; checkboxes not trusted blindly.

| Area | Judgment |
| --- | --- |
| Nullable `contractValue`; no `?? 0` as a fake contract | **Done** |
| Create/update payment blocked without contract (callable + client picker) | **Done** |
| Clear-contract blocked when any non-archived payment exists | **Done** |
| Offline classifier maps contract errors to `invalidTarget` | **Done** |
| Online `failed-precondition` UX | **Partial** — misroutes to quota UI (F-E04) |
| Risk classification suppressed when no contract | **Done** (functions tests) |
| Reports cash vs gross | **Not done** despite some `[X]` on US6 (F-E01) |
| T034 layout artefact audit | **Open** (`[ ]`) |
| T080 / T082 manual M1–M8 / checklist | **Open** (`[ ]`) |

---

## 6. Findings by domain

Finding IDs are unique across this report. Duplicate subagent IDs were merged.

### A. Secrets, credentials, repository security

#### [P1][F-A01] Local service-account JSON and `.env` on disk
- **Status:** CONFIRMED
- **Domain:** A
- **Location:** repo-root `wize-site-firebase-adminsdk-*.json` (gitignored); repo-root `.env` (keys `OPENROUTER_API_KEY`, `OPENROUTER_MODEL`, `OPENAI_API_KEY`)
- **What's wrong:** Full Admin credentials and LLM keys sit in the working tree.
- **Failure scenario:** Compromised laptop / backup → project admin + key abuse.
- **Evidence:** Files present; `.gitignore` matches; `git log --all --full-history` shows **no** commits of the adminsdk file or `.env`.
- **Recommended fix:** Keep only in Secret Manager / CI; rotate if the machine was shared; delete unused local copies.
- **Verification:** `git ls-files` empty for those names on all remotes.
- **Effort:** S · **Fix risk:** low
- **Related:** L01

#### [P3][F-A02] `google-services.json` / `GoogleService-Info.plist` still tracked
- **Status:** CONFIRMED · **Domain:** A
- **Location:** `android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist`
- **What's wrong:** `.gitignore` lists them but they remain in the index (public Firebase client config, not a private key).
- **Failure scenario:** Accidental extra secrets added to the same files get committed.
- **Evidence:** `git ls-files` lists both.
- **Recommended fix:** Document as public client config; never mix secrets; optional `git rm --cached` if policy allows.
- **Effort:** S · **Fix risk:** low · **Related:** L20

No issues found — checked: no `sk-live`, `ghp_`, `BEGIN PRIVATE KEY` in tracked app/functions source; `defineSecret` used for OpenRouter + RevenueCat; `AIza` only in public client configs.

---

### B. Firestore security rules

#### [P1][F-B01] Money ledgers readable by any workspace member
- **Status:** CONFIRMED
- **Domain:** B / P
- **Location:** `firestore.rules` expenses/payments/worker_entries `allow read: if inWorkspace(...)` vs `canAccessAccounting` on metrics/summaries/reports
- **What's wrong:** Constitution IV says financial reports/balances are for owner/admin/accounting. Raw ledgers are readable by `entryOnly`.
- **Failure scenario:** Invited field worker lists all expenses/payments and uses stored `downloadUrl`s.
- **Evidence:** rules ~359–374; no emulator test that `entryOnly` is denied ledger reads.
- **Recommended fix:** Product decision then align reads (`canAccessAccounting` or a `canViewMoney` role); update client queries + rules tests.
- **Verification:** Emulator: entryOnly get/list expenses fails; accounting succeeds.
- **Effort:** M · **Fix risk:** medium
- **Related:** F-P01

#### [P2][F-B02] `entities` update allowlist is open
- **Status:** CONFIRMED · **Domain:** B · **Location:** `firestore.rules` entities update
- **What's wrong:** Update only requires same `workspaceId`.
- **Failure scenario:** Member plants phishing `downloadUrl`s on shared entities.
- **Recommended fix:** `diff().affectedKeys()` allowlist.
- **Effort:** S · **Fix risk:** low

#### [P3][F-B03] `drafts` rules exist; client unused
- **Status:** CONFIRMED · **Domain:** B · **Location:** `firestore.rules` drafts match
- **Recommended fix:** Tighten or remove until used.
- **Effort:** S · **Fix risk:** low

No issues found — checked: `idempotency_keys` `allow read, write: if false` (L22 refuted); `subscriptions`/`usage_counters` client writes denied; `contractValue` null-or-positive tests exist; cross-workspace project reads denied in rules tests (when emulator runs).

---

### C. Storage security rules

#### [P1][F-C01] Cascade delete and account deletion leave Storage orphans
- **Status:** CONFIRMED
- **Domain:** C / D
- **Location:** `functions/src/index.ts` `deleteProjectCascade`; `functions/src/account_deletion.ts` `userStoragePrefixes`
- **What's wrong:** Cascade deletes Firestore only. Account deletion prefixes omit `receipts/{uid}/`.
- **Failure scenario:** Private receipts remain billable and reachable via old download tokens.
- **Evidence:** No Storage delete in cascade; prefixes are attachments / voice-expenses / profile-photos only.
- **Recommended fix:** Add `receipts/` prefix; walk `attachments[].storagePath` on cascade; chunk Firestore batches at 400–500.
- **Verification:** Emulator: delete account/project; prefixes empty.
- **Effort:** L · **Fix risk:** medium
- **Related:** L21, L30

#### [P2][F-C02] Shared attachments rely on long-lived download-token URLs
- **Status:** CONFIRMED · **Domain:** C
- **Location:** `storage.rules` owner-only read; expense detail prefers `attachment.downloadUrl`
- **Failure scenario:** Removed member keeps a copied URL.
- **Recommended fix:** Workspace-scoped Storage paths or short-lived signed URLs; rotate on member removal.
- **Effort:** L · **Fix risk:** high
- **Related:** L04

#### [P3][F-C03] Zip MIME allowed end-to-end
- **Status:** CONFIRMED · **Domain:** C
- **Recommended fix:** Drop zip or warn; 10 MB cap already both sides.
- **Effort:** S · **Fix risk:** low

No issues found — checked: voice `.m4a` → `audio/mp4` matches rules; client 10 MB + rules 10 MB; current uploads use `attachments/` not `receipts/`.

---

### D. Cloud Functions

#### [P1][F-D01] RevenueCat webhook: non-constant-time compare, no replay/idempotency
- **Status:** CONFIRMED
- **Domain:** D / H
- **Location:** `functions/src/index.ts` ~4754–4807
- **What's wrong:** `incomingAuth !== \`Bearer ${expectedSecret}\``; no `event.id` store.
- **Failure scenario:** Replay flips tier; theoretical timing leak on secret.
- **Evidence:**
```text
if (incomingAuth !== `Bearer ${expectedSecret}`) { res.status(401) ... }
```
- **Recommended fix:** `crypto.timingSafeEqual`; persist processed event ids; reject unknown workspaces.
- **Verification:** Duplicate event no-op unit test.
- **Effort:** M · **Fix risk:** low

#### [P2][F-D02] Global `maxInstances: 10`
- **Status:** CONFIRMED · **Domain:** D · **Location:** `setGlobalOptions` · **Related:** L05
- **Recommended fix:** Raise webhook / critical callables independently.
- **Effort:** S · **Fix risk:** low

#### [P2][F-D03] HTTP twins remain a parallel public surface
- **Status:** CONFIRMED · **Domain:** D · **Related:** L25
- **Evidence:** `CallableClient` falls back to `*Http` after callable `unauthenticated`. Twins do verify App Check.
- **Recommended fix:** Deprecate after callable session is stable, or generate twins from one handler; static test every `onRequest` twin calls `verifyHttpAppCheck`.
- **Effort:** M · **Fix risk:** medium

#### [P2][F-D04] Team invite quota not transactional
- **Status:** CONFIRMED · **Domain:** D · **Location:** invite functions ~4508–4610
- **Failure scenario:** Concurrent invites exceed free `teamMembers`.
- **Recommended fix:** Same transaction pattern as `commitIdempotentCreate`.
- **Effort:** M · **Fix risk:** medium

#### [P2][F-D05] Invite-by-email enumerates registered emails
- **Status:** CONFIRMED · **Domain:** D
- **Recommended fix:** Uniform client error; rate-limit.
- **Effort:** M · **Fix risk:** medium

#### [P2][F-D06] Attachment metadata accepts arbitrary URLs/paths
- **Status:** CONFIRMED · **Domain:** D · **Location:** `normalizeAttachmentItem` ~448–505
- **Recommended fix:** Require `attachments/{uid}/` prefix + Storage URL host.
- **Effort:** M · **Fix risk:** medium

#### [P3][F-D07] Voice LLM prompt injection (bounded)
- **Status:** CONFIRMED · **Domain:** D
- **What's wrong:** Transcript + client project names concatenated; output schema-clamped; save re-checks workspace.
- **Recommended fix:** Load projects server-side; delimit user content; rate-limit.
- **Effort:** M · **Fix risk:** low

#### [P3][F-D08] Static App Check test is a weak regex
- **Status:** CONFIRMED · **Domain:** D · **Location:** `functions_structure_static.test.ts`
- **Recommended fix:** Parse every `onCall(` across `src/**`.
- **Effort:** S · **Fix risk:** low

#### [P3][F-D09] No ESLint; committed `functions/lib/`
- **Status:** CONFIRMED · **Domain:** D / U · **Related:** L06
- **Effort:** M · **Fix risk:** low

No issues found — checked: all sampled `onCall` have `enforceAppCheck: true` + `request.auth`; CORS locked to Firebase Hosting origins; voice path `assertVoicePathOwnedByUser`; money creates use `commitIdempotentCreate`.

---

### E. Accounting correctness

#### [P0][F-E01] Reports / PDF / export use gross `payment.amount`, not cash collected
- **Status:** CONFIRMED
- **Domain:** E / P
- **Location:** `lib/features/reports/data/reports_providers.dart` `_metricsFromScopedRows` ~1064–1069; `report_export_data_builder.dart` ~272, 348–354; `report_pdf_exporter.dart` uses `payment.amount`
- **What's wrong:** Dashboard cash KPI and server `recomputeProjectSummary` use `cashCollectedAmount`. Reports add full `amount`.
- **Failure scenario:** Unpaid 10,000 EGP payment → report Total Income 10,000; cash-collected KPI 0.
- **Evidence:** Helpers in `cash_collected.dart` / `money.ts` match (L23 refuted). Consumers do not.
- **Recommended fix:** Sum via `cashCollectedAmount` everywhere; teach `PaymentRecord` status/`paidAmount` if needed.
- **Verification:** Unpaid payment fixture → reports income 0, matches metrics.
- **Effort:** M · **Fix risk:** medium
- **Related:** L23, L27

#### [P0][F-E02] Archive payment metrics delta uses full `amount`
- **Status:** CONFIRMED
- **Domain:** E
- **Location:** `functions/src/index.ts` ~3065–3094 vs create path using `cashCollectedAmount`
- **What's wrong:** Archive subtracts `Number(payment.amount)` from metrics.
- **Failure scenario:** Archive unpaid → understated `totalPayments`/`netProfit` until recompute (or permanently if trigger fails).
- **Recommended fix:** `-cashCollectedAmount(payment)` in the archive transaction.
- **Verification:** Create unpaid → metrics unchanged; archive → still unchanged.
- **Effort:** S · **Fix risk:** low

#### [P1][F-E03] Dashboard offline pending income ignores payment status
- **Status:** CONFIRMED
- **Domain:** E / F
- **Location:** `dashboard_providers.dart` pending paths ~78–85, 1369–1387 vs weekly `_cashInFromMap`
- **Recommended fix:** Use `cashCollectedAmount` / `_cashInFromMap` for pending too.
- **Effort:** S · **Fix risk:** low

#### [P1][F-E04] Online `failed-precondition` routes to quota screens
- **Status:** CONFIRMED
- **Domain:** E / H
- **Location:** `add_payment_screen.dart` ~277–281; `create_project_screen.dart` ~220–224
- **What's wrong:** Contract-required payment reject is also `failed-precondition`. Offline classifier handles this; online does not.
- **Failure scenario:** User told they hit plan limits instead of “project has no contract value”.
- **Recommended fix:** Branch on message like `sync_error_classifier.dart`.
- **Effort:** S · **Fix risk:** low

#### [P1][F-E05] “Today” / last-7-days: local client vs UTC server
- **Status:** CONFIRMED · **Domain:** E
- **Location:** client `DateTime.now()` vs server UTC week helpers
- **Recommended fix:** One policy (Egypt calendar or UTC) shared.
- **Effort:** M · **Fix risk:** medium

#### [P2][F-E06] IEEE double money end-to-end
- **Status:** CONFIRMED · **Domain:** E · **Related:** L18
- **Recommended fix:** Integer minor units or round-to-currency at write and display. Migration is XL.
- **Effort:** XL · **Fix risk:** high

#### [P2][F-E07] Client `partial` payments never persist `paidAmount`
- **Status:** CONFIRMED · **Domain:** E
- **What's wrong:** Helpers support split; UI/create path does not write `paidAmount` → partial counts as full cash.
- **Recommended fix:** Document as intentional **or** add paid-split UX.
- **Effort:** M · **Fix risk:** medium

#### [P3][F-E08] Rules `paymentStatus` vs callable statuses
- **Status:** CONFIRMED · **Domain:** E
- **What's wrong:** Rules allow `paid|unpaid|partial`; TS allows `refunded|cancelled`.
- **Effort:** S · **Fix risk:** low

**Consistency matrix (helpers vs consumers)**

| Figure | Match? | Notes |
| --- | --- | --- |
| `cashCollectedAmount` helper client vs server | Yes | L23 refuted |
| Dashboard cash KPI | Yes vs helper | |
| Project metrics (server recompute) | Yes vs helper | |
| Archive payment delta | **No** | F-E02 |
| Report / PDF / export income | **No** | F-E01 |
| Offline pending dashboard income | **No** | F-E03 |
| Remaining balance (contract − totalPayments) | Yes when metrics fresh | Null contract → no remaining |
| Worker entry cost | Yes | `totalCost` or days×wage |
| Weekly window | Formula yes; TZ **no** | F-E05 |

---

### F. Offline queue and sync

#### [P1][F-F01] Backoff skips head-of-line and breaks FIFO
- **Status:** CONFIRMED
- **Domain:** F
- **Location:** `offline_action_queue.dart` ~333–385
- **What's wrong:** Failed action sets `nextAttemptAt` and later drain `continue`s it, running newer actions first.
- **Failure scenario:** Offline create project → create expense; project backoff → expense syncs first → invalid target / dead letter.
- **Recommended fix:** Do not process later actions while any earlier item is pending/backoff.
- **Verification:** Unit test: action1 future `nextAttemptAt`, action2 pending → handler for 2 not called.
- **Effort:** S · **Fix risk:** low

#### [P1][F-F02] Hive AES crash between migrate and flag can empty boxes
- **Status:** CONFIRMED
- **Domain:** F
- **Location:** `lib/core/storage/hive_boxes.dart` ~17–87
- **What's wrong:** Ciphertext on disk + `hiveNeedsPlaintextMigration == true` after crash before `persistHiveEncryptionReady`.
- **Failure scenario:** Lost offline mutations on first encrypted launch.
- **Recommended fix:** Persist per-box encrypted flag immediately after each migrate.
- **Verification:** Migrate, skip persist, new process, data survives.
- **Effort:** M · **Fix risk:** medium
- **Related:** L24

#### [P2][F-F03] PendingAttachmentService never used in production
- **Status:** CONFIRMED · **Domain:** F
- **Location:** `workspace_mutation_service.dart` attachment_upload no-op; `savePending` only in tests
- **Recommended fix:** Wire enqueue → savePending **or** delete the dead path.
- **Effort:** M · **Fix risk:** medium

No issues found — checked: `pending_id_remap` for create-project-offline → expense; `clientMutationId` + server `idempotency.ts`; dead-letter UX; Firestore persistence is cache not a second outbox; L03 encryption present.

---

### G. Auth, session, workspaces, roles

#### [P1][F-G01] Some sign-out paths skip Hive queue cleanup
- **Status:** CONFIRMED
- **Domain:** G / F
- **Location:** `session_restore_service.dart` `_signOutToBreakStrandedSessionLoop` ~92–97; `verify_email_screen.dart`; `auth_session.dart` vs `settings_screen.dart` which does call `LocalSessionCleanup`
- **What's wrong:** `LocalSessionCleanup.clearQueuedUserData()` only on settings logout/delete.
- **Failure scenario:** User A queued offline work → restore/verify sign-out → User B on same device drains A’s payloads.
- **Recommended fix:** Cleanup on every sign-out path.
- **Verification:** Enqueue → forced restore sign-out → boxes empty; second user pendingCount 0.
- **Effort:** S · **Fix risk:** low

#### [P2][F-G02] Google `signOut` no-ops if SDK never initialized this process
- **Status:** CONFIRMED · **Domain:** G · **Location:** `google_auth_service.dart` ~106–116
- **Recommended fix:** Always initialize then `signOut()` (consider `disconnect()`).
- **Effort:** S · **Fix risk:** low

No issues found — checked: splash/login loop fix still present; unverified email gating; account deletion UI matches `ownerDeletionBlocked` (L28 refuted); Crashlytics order (L16 refuted).

---

### H. Subscription, quota, monetization

#### [P1][F-H01] `CANCELLATION` drops Pro immediately
- **Status:** CONFIRMED
- **Domain:** H
- **Location:** `mapRevenueCatStatus` / `hasUnlimitedQuota` in `functions/src/index.ts` ~183–252
- **What's wrong:** Cancel → `canceled` → not in `{active, trial, grace}` → free limits while period may still be paid.
- **Recommended fix:** Keep `active` until `EXPIRATION`; set `isAutoRenewing: false`.
- **Verification:** Webhook fixture cancel-before-expiry still unlimited.
- **Effort:** S · **Fix risk:** low

#### [P2][F-H02] Unmapped RC events become `unknown` (lose Pro)
- **Status:** CONFIRMED · **Domain:** H
- **Recommended fix:** Treat entitlement-bearing events as `active` when pro entitlement present.
- **Effort:** S · **Fix risk:** low

#### [P2][F-H03] Store subscription legal copy depends on RevenueCat paywall template
- **Status:** CONFIRMED · **Domain:** H / W
- **Recommended fix:** Confirm RC offering has Terms/Privacy + auto-renew copy; mirror links on `PlansScreen`.
- **Effort:** S · **Fix risk:** low

No issues found — checked: client limit checks are advisory; `subscriptions`/`usage_counters` write-deny; money creates go through quota callables.

---

### I. Voice expense (client)

#### [P3][F-I01] No offline preflight before processing
- **Status:** CONFIRMED · **Domain:** I
- **Recommended fix:** Gate Process on `isOfflineProvider`.
- **Effort:** S · **Fix risk:** low

No issues found — checked: mic permission denied UX, 60s max, review screen, `voice_ai_disclosure_store.dart`.

---

### J. Flutter architecture

#### [P2][F-J01] Vendored `cloud_firestore` unused by app
- **Status:** CONFIRMED · **Domain:** J / T · **Related:** L09
- **Location:** `pubspec.yaml` path override; `packages/cloud_firestore`
- **Recommended fix:** Drop override unless Pipeline is adopted.
- **Effort:** M · **Fix risk:** medium

#### [P3][F-J02] Mega-files / monolith `index.ts`
- **Status:** CONFIRMED · **Domain:** J · **Related:** L17
- **Effort:** L · **Fix risk:** medium

No issues found — checked: presentation→Firestore layering scan was clean; TODO/FIXME/HACK ≈ 0 (L15 refined). `freezed_annotation` unused (L07).

---

### K. UI / UX / design system

#### [P2][F-K01] Prior UI/UX audit P0/P1 items not formally closed
- **Status:** CONFIRMED · **Domain:** K
- **Location:** `BUILDOZER_UI_UX_AUDIT.md` priority order still lists unfinished Critical/High
- **Recommended fix:** Reconcile checklist vs current screens; close or re-scope.
- **Effort:** L · **Fix risk:** low

No issues found — checked: `AppEmptyState` / skeletons / offline banner; `dark_mode_smoke_test.dart`; DS tokens exist.

---

### L. Localization and RTL

#### [P2][F-L01] Hard-coded English expense group titles
- **Status:** CONFIRMED · **Domain:** L
- **Location:** `lib/features/expenses/presentation/models/expense_group.dart`
- **Recommended fix:** Move to `_en`/`_ar`; coverage test.
- **Effort:** S · **Fix risk:** low

#### [P3][F-L02] LTR `EdgeInsets` dominates
- **Status:** CONFIRMED · **Domain:** L
- **Recommended fix:** Prefer `EdgeInsetsDirectional` on horizontal padding.
- **Effort:** M · **Fix risk:** low

No issues found — checked: `localization_coverage_test.dart` exists; map-based i18n is intentional (not missing gen-l10n as a defect).

---

### M. Accessibility

#### [P3][F-M01] a11y tests are sample-based
- **Status:** CONFIRMED · **Domain:** M
- **Location:** `test/widget/accessibility_rtl_test.dart`
- **Recommended fix:** Smoke semantics on Add / Voice / Settings primary CTAs.
- **Effort:** M · **Fix risk:** low

No issues found — checked: profit not color-only on dashboard net row; 48dp back target in tests.

---

### N. Performance

#### [P2][F-N01] Dashboard live queries can be unbounded
- **Status:** CONFIRMED · **Domain:** N
- **Location:** `dashboard_providers.dart` ~539–547, 1154–1159
- **What's wrong:** All non-archived projects + all `project_metrics` + unpaid payments streamed without `.limit`.
- **Recommended fix:** Prefer `workspace_metrics`; cap/paginate unpaid.
- **Effort:** M · **Fix risk:** medium
- **Related:** constitution V

#### [P2][F-N02] PDF built on the UI isolate
- **Status:** CONFIRMED · **Domain:** N / P
- **Location:** `report_pdf_exporter.dart`
- **Recommended fix:** `compute`/isolate with a DTO.
- **Effort:** M · **Fix risk:** medium

No issues found — checked: list repositories paginate; prefetcher exists.

---

### O. Data model, indexes, migrations

#### [P3][F-O01] Likely-unused inverted composite indexes
- **Status:** CONFIRMED · **Domain:** O
- **Location:** `firestore.indexes.json` expenses/payments `isArchived, projectId, workspaceId, date`
- **Recommended fix:** Confirm unused in console, then delete.
- **Effort:** S · **Fix risk:** low

No issues found — checked: common `workspaceId + projectId + isArchived + date` queries have matching indexes. Backup/PITR not documented (open question).

---

### P. Reports and exports

Covered by F-E01 (cash), F-B01 (role gate), F-N02 (isolate).

#### [P2][F-P02] PDF Arabic loads Cairo but no RTL `textDirection`
- **Status:** CONFIRMED · **Domain:** P
- **Location:** `report_pdf_exporter.dart` ~31–81
- **Recommended fix:** Page theme `textDirection` from locale.
- **Effort:** S · **Fix risk:** low

---

### Q. Notifications

No FCM / `firebase_messaging` — in-app Firestore notifications only. Missing `POST_NOTIFICATIONS` / `UIBackgroundModes` is **not** a functional bug (L14 refined).

#### [P2][F-Q01] Privacy Manifest collected-types are too thin
- **Status:** CONFIRMED · **Domain:** Q / W
- **Location:** `ios/Runner/PrivacyInfo.xcprivacy`
- **What's wrong:** Email only; app also uses mic, contacts, photos, financial data, Crashlytics, third-party AI audio.
- **Recommended fix:** Expand Nutrition Labels + PrivacyInfo to match reality.
- **Effort:** S · **Fix risk:** low
- **Related:** L29

---

### R. Testing

#### [P2][F-R01] Emulator rules/recompute/storage tests skip in default CI
- **Status:** CONFIRMED · **Domain:** R / S
- **Location:** `firestore_rules.test.ts` skip without emulator; Codemagic `npm test` / `flutter test` only
- **Failure scenario:** Rules regressions ship while “tests passed”.
- **Recommended fix:** Emulator job in Codemagic/GitHub; optional `integration_test` lane.
- **Effort:** M · **Fix risk:** low

No issues found — checked: 633 Flutter tests green; static tests under `test/static/` including Codemagic build-name; functions 51 pass.

---

### S. Build, release, CI/CD, native

#### [P2][F-S01] Codemagic is iOS-only
- **Status:** CONFIRMED · **Domain:** S
- **Location:** `codemagic.yaml` workflows `ios_release_artifact`, `ios_testflight`
- **Recommended fix:** Android workflow with same analyze/test + Play artifact.
- **Effort:** M · **Fix risk:** low
- **Related:** L10 refined

#### [P3][F-S02] Local Node 25 vs declared Node 22
- **Status:** CONFIRMED · **Domain:** S
- **Recommended fix:** Document/engine-strict CI image `node:22`.
- **Effort:** S · **Fix risk:** low

#### [P3][F-S03] Agent shell missing `ProgramFiles(x86)` broke first `flutter test`
- **Status:** CONFIRMED · **Domain:** S
- **Recommended fix:** Document Windows CI env; not a product bug.
- **Effort:** S · **Fix risk:** low

No issues found — checked: `minSdk`/`targetSdk` Flutter defaults; usage descriptions present; release_audit OAuth PASS; `--build-name=$PUBSPEC_VERSION`.

---

### T. Dependencies

#### [P3][F-T01] Beta `file_picker`, dead codegen annotations, Hive 2.x
- **Status:** CONFIRMED · **Domain:** T · **Related:** L07, L08
- **Evidence:** `file_picker 12.0.0-beta.7`; `purchases_ui_flutter` **is** used (`RevenueCatUI.presentPaywallIfNeeded`).
- **Recommended fix:** Stable file_picker 13 when tested; remove unused annotations; plan Hive CE / Isar.
- **Effort:** S–M · **Fix risk:** low–medium

---

### U. Repository hygiene and documentation

#### [P3][F-U01] Tracked root junk still in the index
- **Status:** CONFIRMED · **Domain:** U · **Related:** L12
- **Location:** git-tracked `0`, `const`, `Gradle`, `onSelect(index)`, `store/play/$(node` (working tree `D` = deleted, not committed)
- **Recommended fix:** Commit the deletions.
- **Effort:** S · **Fix risk:** low

#### [P3][F-U02] Status-dump commit messages
- **Status:** CONFIRMED · **Domain:** U · **Related:** L19
- **Effort:** S · **Fix risk:** low

No issues found — checked: AGENTS.md / CLAUDE.md both spec 003 (L11 refuted).

---

### V. Observability and operations

#### [P2][F-V01] No Remote Config / force-update / kill switch
- **Status:** CONFIRMED · **Domain:** V
- **Recommended fix:** Min-version Remote Config + blocking dialog; kill switch for voice AI / purchases.
- **Effort:** M · **Fix risk:** low

No issues found — checked: Crashlytics collection + route observer breadcrumbs.

---

### W. Privacy, legal, store compliance

#### [P2][F-W01] Voice AI / third-party processing not in Play listing or PrivacyInfo
- **Status:** CONFIRMED · **Domain:** W · **Related:** L29
- **Location:** in-app strings vs `store/play/LISTING.md` vs `PrivacyInfo.xcprivacy`
- **Recommended fix:** Align listing + privacy policy + Nutrition Labels with OpenRouter audio/transcript processing; mention Egypt PDPL if users are in Egypt.
- **Effort:** S · **Fix risk:** low

No issues found — checked: contacts used locally to fill worker fields (not uploaded as an address book); `deleteOwnAccount` exists; owner-with-members blocked in UI and backend.

---

## 7. Low-severity (P3) compact list

| ID | Location | Issue | Fix |
| --- | --- | --- | --- |
| F-A02 | google-services tracked | gitignore vs index | Document / untrack policy |
| F-B03 | drafts rules | unused weak CRUD | Deny or schema |
| F-C03 | zip MIME | malware content | Drop or warn |
| F-D07 | voice LLM prompt | bounded injection | Server-load projects |
| F-D08 | App Check static test | weak regex | Parse all onCall |
| F-D09 | functions lint / lib/ | no ESLint, committed JS | CI compile |
| F-E08 | paymentStatus enums | rules vs TS | Align allowlist |
| F-I01 | voice offline | no preflight | Gate Process |
| F-J02 | mega files | review risk | Extract modules |
| F-L02 | EdgeInsets | RTL spacing | Directional insets |
| F-M01 | a11y tests | sample-only | Widen smoke |
| F-O01 | inverted indexes | unused? | Console then delete |
| F-S02 | Node 25 vs 22 | engine drift | Pin CI to 22 |
| F-S03 | ProgramFiles(x86) | agent test flake | Doc Windows env |
| F-T01 | beta/dead deps | upgrade noise | Clean pubspec |
| F-U01 | root junk | still tracked | Commit `git rm` |
| F-U02 | commit messages | status dumps | Convention |

---

## 8. Enhancements and suggestions

Sources: [LiveCosts 2026 construction accounting roundup](https://livecosts.com/blog/construction-accounting-software-2026/), [Banamind contractor software guide](https://banamind.ai/ar/blog/best-accounting-software-for-builders-how-to-choose), [Hunt ERP Egypt construction](https://hunt-eg.com/en/industries/construction), [Matix Build](https://matixerp.com/construction/), [Odoo construction EG/UAE/KSA](https://etriplesoft.com/odoo-for-construction/), Procore/Buildertrend feature sets (progress billing, change orders, client portal).

Buildozer’s wedge is **mobile + offline + Arabic + site money**, not a full ERP. Do not clone Hunt/Matix. Steal the few field workflows users will miss immediately.

### Now (fits the current product)

| Idea | Value | Evidence | Effort | Risk |
| --- | --- | --- | --- | --- |
| Cash-collected everywhere | Trust | F-E01–E03 | M | Medium |
| WhatsApp share of PDF/statement | MENA default share path | Hunt WhatsApp Business; field WhatsApp culture | S | Low |
| Duplicate last expense / recent values | Faster site entry | Friction on add-expense | S | Low |
| Queue-wide pause on backoff | Offline correctness | F-F01 | S | Low |
| Session cleanup on all sign-outs | Shared-device safety | F-G01 | S | Low |
| RC cancel-until-expiry | Paid-period fairness / store | F-H01 | S | Low |
| Arabic RTL PDF | Bilingual reports usable | F-P02 | S | Low |

### Next

| Idea | Value | Evidence | Effort | Risk |
| --- | --- | --- | --- | --- |
| Role-gated ledger reads | Constitution IV | F-B01 | M | Medium (breaks field-worker expense lists unless a viewer role exists) |
| Signed download URLs | Ex-member revocation | F-C02 | L | High |
| Petty cash / site custody | Egypt site engineer workflow | Hunt “work custody”; gap vs expenses-only | L | Medium |
| Supplier dues + post-dated cheques | How contractors actually pay | Hunt banks/cheques; NTS claims | L | Medium |
| Overspend alerts + budget-by-category | Spec 003 natural sequel | Optional contract already shipped | M | Medium |
| Excel/CSV export | Accountants demand it | QuickBooks/Xero habit | M | Low |
| CI emulator + Android Codemagic | Stop shipping rules-blind | F-R01, F-S01 | M | Low |
| Split `index.ts` | Reviewability | L17 | L | Medium |
| Drop unused Firestore fork | Upgrade path | L09 | M | Medium |
| Force-update Remote Config | Kill bad clients | F-V01 | M | Low |
| Receipt OCR (on-device or API) | Complements voice | Voice already exists | L | Medium (cost/PII) |

### Later (ERP-shaped; do not start now)

Progress / IPC billing, BOQ, change orders, retention, advances, ETA e-invoicing, client portal, material inventory, QR attendance, payroll/WPS, multi-currency, FIDIC claims. These are table stakes for Hunt/Matix/Odoo in Egypt/KSA and **out of scope** until cash-collected and offline recovery are trustworthy. ETA in particular is a compliance program, not a feature toggle ([Egypt ETA via construction ERPs](https://etriplesoft.com/odoo-for-construction/)).

### Architecture / quality (also Wave 7)

- Shared validation schemas between Dart and TS for money fields.
- Integer minor units (follow F-E06 only after consumer alignment).
- `gen-l10n` ARB migration (benefit vs hand-rolled maps — L, after coverage is 100%).
- GitHub PR gate: analyze + test + functions test + emulator rules.
- Dependabot/Renovate; Conventional Commits.

---

## 9. Quick wins (< 2 h each)

1. Archive payment delta = `cashCollectedAmount` (F-E02).
2. Reports `_metricsFromScopedRows` use cash collected (F-E01 start).
3. Pending dashboard income use `_cashInFromMap` (F-E03).
4. Online `failed-precondition` contract messages (F-E04).
5. `LocalSessionCleanup` on restore/verify sign-out (F-G01).
6. Queue drain: do not skip head-of-line (F-F01).
7. `receipts/` prefix in `userStoragePrefixes` (L21).
8. RC `CANCELLATION` → keep active until expiration (F-H01).
9. PDF `textDirection` for Arabic (F-P02).
10. Commit deletion of root junk files (F-U01).
11. Voice offline preflight (F-I01).
12. Expense group titles via l10n (F-L01).
13. Google `signOut` always initializes (F-G02).
14. Timing-safe webhook compare (part of F-D01).
15. Pin CI Node 22 (F-S02).

---

## 10. Remediation roadmap

### Stop-the-bleeding
F-E01, F-E02, F-E03 (money display) · F-G01 (queue leak) · F-H01 (paid period).

### Stabilize
F-F01, F-F02 · F-E04 · F-D01 · F-C01 prefixes · F-R01 emulator in CI · F-U01 junk.

### Harden
F-B01 (product decision) · F-C02 · F-D03/D04 · F-N01 · F-H02 · F-W01 / F-Q01 disclosures.

### Improve
F-P02 · WhatsApp share · duplicate expense · DS/UI audit close · split `index.ts` · drop Firestore fork.

### Grow
Petty cash, cheques, category budgets, Excel export, force-update, then (only if the market demands) IPC/retention/ETA.

---

## 11. Open questions for the product owner

1. Should `entryOnly` **see** expense/payment amounts, or only create them? (F-B01)
2. Is payment `partial` meant to be full cash until a paid split exists? (F-E07)
3. Workspace timezone: Egypt calendar (Sat-week?) vs UTC? (F-E05)
4. Keep HTTP twins permanently for App Check/session fallback?
5. Ship Android on Codemagic or stay iOS-first?
6. Target Egypt ETA e-invoicing this year, or stay a site ledger?
7. Was the `cloud_firestore` fork intended for a Pipeline migration that was dropped?
8. Is `receipts/` Storage prefix still in production with files?
9. Backup/PITR: is Firestore PITR enabled on `wize-site`?
10. Should Pro continue through billing issues only (`grace`) or also through user-initiated cancel until period end?

---

## 12. Appendix

### Lead dispositions
See [LEAD_REGISTER.md](./LEAD_REGISTER.md) — all L01–L30 marked this run.

### Commands run
- `git status --short`, `git log --oneline -20`, `git branch -a`
- `git log --all --full-history` on adminsdk/`.env`/`key.properties`/`*.jks` (no hits); `git ls-files` google-services
- `flutter --version`, `flutter analyze`, `flutter test --reporter compact` (633 pass)
- `dart run tool/release_audit.dart`
- `cd functions; npm test; npm audit --omit=dev; npm outdated`
- `flutter pub outdated`
- Emulators: **not run**

### Skipped and why
- `graphify-out/`: absent (L26)
- `flutter test --coverage`: time
- Firebase Console App Check / RevenueCat dashboard: out of repo
- Production `wize-site`: not touched
- Device/integration_test: not executed

### Flows traced in code (not device)
Signup/workspace, optional contract + payment guards, expense create/offline/remap, voice process/review, archive+quota, invite/roles, limit+RevenueCat webhook, reports/PDF, account deletion, session restore.

### Subagent passes merged
- Security A–D: [Wave 1 security audit](5f29e673-bb98-43d6-a3b0-9bc67852d787)
- Accounting E: [Wave 2 accounting audit](d232e3d2-f332-400f-9b6e-7ae18e3faedc)
- Offline/auth F–G: [Wave 3 offline auth audit](e5791d7f-13fa-4424-9c80-29c502d8312c)
- Remaining H–W: [Waves 4-6 remaining domains](c563326e-f957-47aa-93b0-14f52b538e8a)

Parent verified P0/P1 locations: reports `payment.amount`, archive `-archivedAmount`, `LocalSessionCleanup` call sites, RC `CANCELLATION`, release_audit OAuth PASS, AGENTS/CLAUDE plan pointers.

### Counts

| Severity | Count (this report) |
| --- | ---: |
| P0 | 2 |
| P1 | 11 |
| P2 | 22 |
| P3 | 17 |
| Idea | see §8 |

### Top five actions
1. Fix reports/PDF/export + archive delta + pending income to use `cashCollectedAmount`.
2. Clear Hive queues on every sign-out.
3. Keep Pro entitlement until RevenueCat `EXPIRATION`.
4. Pause offline drain while the head action is in backoff.
5. Decide whether field roles may read ledgers; then fix rules + tests.

---

*End of 2026-09-17 full audit. Re-run via [AUDIT_PLAYBOOK.md](./AUDIT_PLAYBOOK.md).*
