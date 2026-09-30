# Buildozer Audit Playbook

Operational source of truth for auditing this repository. Supersedes
`docs/audits/2026-09-14-full-audit-prompt.md` (keep that file as historical
input). This playbook is how an agent or human re-runs a full, risk-first, or
single-domain audit.

Last updated: 2026-09-17

---

## 0. Mission

Two equal halves:

1. **Audit** — find defects, risks, inconsistencies, and debt from P0 security
   and money bugs down to P3 hygiene. Small items go in the low-severity
   bucket; they are never omitted.
2. **Improve** — justified enhancements (architecture, missing contractor
   features, UX, cost, DX). Research outside the codebase where it helps.

## 1. Ground rules (non-negotiable)

1. **Read-only source.** Do not modify app source, rules, config, or git
   unless the user explicitly asks for remediation. Default writes are only
   under `docs/audits/`.
2. **No production Firebase.** Do not run commands against project `wize-site`
   that write data, deploy, or use production credentials beyond local
   read-only inspection of repo files.
3. **Evidence or it did not happen.** Every finding cites `path:line` or a
   command + summarized output. Mark `CONFIRMED` or `SUSPECTED`.
4. **Trust nothing written before today.** Prior audits, specs, READMEs,
   commit messages, comments, and `LEAD_REGISTER.md` are hypotheses.
   Re-verify against current code.
5. **Secrets.** Never print secret values. Report file path, key name, and
   whether the file is tracked or present in git history.
6. **Encoding.** Never round-trip non-ASCII files (especially
   `lib/app/localization/app_localizations.dart`) through PowerShell
   `Get-Content` / `Set-Content`. Use the Read tool.
7. **Context hygiene.** Read large files in chunks of ≤200 lines. Never dump
   `pubspec.lock`, `package-lock.json`, `*.g.dart`, `functions/node_modules/**`,
   `build/**`, or binaries. Cap command output.
8. **Be specific about fixes.** Every finding: concrete change, location,
   verification, effort (S ≤ 2h, M ≤ 1d, L ≤ 1wk, XL > 1wk), fix risk.
9. **`graphify-out/`** may be absent. Skip it. Do not regenerate unless asked.

## 2. How to run

| Mode | When | What |
| --- | --- | --- |
| **Full A–W** | Release gate, quarterly, after large uncommitted batches | All domains, prior-audit diff, spec 003 walk, competitor research |
| **Risk-first** | Time-boxed ship check | Waves 1–3 (security, accounting, offline/auth) then stop with a short verdict |
| **Single-domain** | After a targeted change | One letter from section 5 plus related tests |

**Wave order (full and risk-first):**

0. Baseline commands
1. Secrets, Firestore/Storage rules, Cloud Functions
2. Accounting correctness, money helpers, spec 003, quota/idempotency
3. Offline queue, Hive, session, account deletion
4. Subscription, voice, notifications
5. Architecture, UI/UX, i18n/RTL, a11y, performance
6. Indexes, reports, tests, CI/release, deps, hygiene, ops, privacy
7. Enhancements (competitor research)
8. Merge, constitution scores, dated report

Parallel subagents per wave are allowed. Each must return findings in the
template in `REPORT_TEMPLATE.md`. Deduplicate by location + failure scenario
before writing the report.

## 3. Skills

- Security: Cursor `auditing-security` + `security-review` (high-confidence
  exploitable issues only for the security-review pass; the full audit still
  records medium/low hygiene).
- Performance: Cursor `auditing-performance` adapted to Flutter/Firestore
  (queries, rebuilds, isolates, function cost) — not web Core Web Vitals.
- Accessibility: Flutter code + `test/widget/accessibility_rtl_test.dart`.
  Do not use the web-browser a11y skill on this mobile app.

## 4. Project snapshot (verify each run)

**Product.** Buildozer — mobile-first construction operations and accounting
for contractors (Egypt/MENA, bilingual EN/AR + RTL, offline-first).

**Naming drift (note where it matters):** repo `WizeSite`; Firebase `wize-site`;
Dart package `buildtrack_app`; constitution “BuildTrack”; app “Buildozer”;
bundle id `com.ahmed.buildozer`; functions package `buildtrack-functions`.

**Constitution.** `.specify/memory/constitution.md` v1.0.0:

- I Preserve existing behaviour
- II Accounting correctness and traceability
- III Test-backed change
- IV Offline, security, and recovery first
- V Scalable data access

Grade PASS / PARTIAL / FAIL with evidence.

**Client.** Flutter, Riverpod 3, go_router, Firebase, Hive (`app_prefs`,
`offline_actions`, `pending_attachments`), RevenueCat, pdf/printing, voice
(`record` + `audioplayers`), `file_picker` (check if still beta). Local
`cloud_firestore` fork at `packages/cloud_firestore`.

**Backend.** Cloud Functions v2, Node 22, TypeScript. Most HTTP/callables live
in `functions/src/index.ts` (thousands of lines). Extracted modules as of
2026-09: `money.ts`, `idempotency.ts`, `account_deletion.ts`, `voice/`,
`http_app_check.ts`, `http_cors.ts`. Global `region: us-central1`,
`maxInstances: 10`. Secrets via `defineSecret`: OpenRouter + RevenueCat webhook.

**New since 2026-09-14 prompt (re-verify, do not assume complete):**

- `enforceAppCheck: true` on `onCall` (static test in
  `functions/src/functions_structure_static.test.ts`)
- Hive AES (`lib/core/storage/hive_boxes.dart`)
- `deleteOwnAccount` callable + `functions/src/account_deletion.ts`
- Client: `cash_collected.dart`, `expense_category.dart`,
  `pending_id_remap.dart`, `local_session_cleanup.dart`
- Analyzer language: `strict-casts`, `strict-inference`, `strict-raw-types`
- Codemagic `--build-name=$PUBSPEC_VERSION` (no longer hardcoded `1.0.0`)
- `ios/Runner/PrivacyInfo.xcprivacy`

## 5. Domains A–W

Use the checklists in `docs/audits/2026-09-14-full-audit-prompt.md` section 5
as the detailed questions. Summary:

| ID | Domain | First-wave files |
| --- | --- | --- |
| A | Secrets / repo security | `.gitignore`, git history of adminsdk / `.env` / `key.properties` |
| B | Firestore rules | `firestore.rules`, `functions/src/firestore_rules.test.ts` |
| C | Storage rules | `storage.rules`, `functions/src/storage_rules.test.ts` |
| D | Cloud Functions | `functions/src/index.ts`, `voice/`, `http_*.ts`, webhook |
| E | Accounting | money helpers, dashboard/reports providers, recompute triggers |
| F | Offline / sync | `offline_action_queue.dart`, remap, Hive boxes |
| G | Auth / session / roles | router, auth services, `local_session_cleanup.dart` |
| H | Subscription / quota | `subscription/`, RevenueCat webhook, `checkLimit` |
| I | Voice (client) | `lib/features/voice_expense/` |
| J | Flutter architecture | large screens, Riverpod, dead deps |
| K | UI / UX / DS | `lib/core/widgets/ds/`, prior UI audits |
| L | Localization / RTL | `app_localizations.dart`, coverage test |
| M | Accessibility | semantics, 48dp, `accessibility_rtl_test.dart` |
| N | Performance | queries, pagination, PDF isolate, cold start |
| O | Data model / indexes | `firestore.indexes.json` vs actual queries |
| P | Reports / PDF | `report_pdf_exporter.dart`, role gates |
| Q | Notifications | FCM, Android 13, iOS background modes |
| R | Testing | `test/`, `functions/src/*.test.ts`, integration_test |
| S | Build / CI / native | `codemagic.yaml`, `tool/release_audit.dart` |
| T | Dependencies | `flutter pub outdated`, `npm outdated` / `npm audit` |
| U | Repo hygiene / docs | root junk, AGENTS.md vs CLAUDE.md |
| V | Observability | Crashlytics, telemetry, kill switches |
| W | Privacy / legal / store | deletion, AI disclosure, data safety |

**End-to-end flows to trace (at least on a full run):**

1. Sign up → verify email → workspace setup → first project
2. Create project with and without Contract Value; edit/clear it
3. Add expense (manual, attachment, offline then reconnect)
4. Voice expense: record → upload → process → review → confirm
5. Add payment (including project with no contract value — should fail)
6. Worker + entries + worker accounting
7. Contractor / equipment / transport accounting
8. Archive/unarchive with quota refund; `deleteProjectCascade`
9. Invite / role change / remove member / switch workspace
10. Hit plan limit → purchase → webhook → entitlement
11. Report + PDF export
12. Notifications create / FCM / read
13. Kill mid-sync, reinstall, sign-out with pending queue
14. Delete own account (reauth, owner-with-members block)

## 6. Phase 0 command catalog

Record pass/fail counts and the first meaningful errors. Missing SDK/emulator
is a reproducibility finding, not a silent skip.

```text
git status --short
git log --oneline -20
git branch -a
flutter --version
flutter analyze
flutter test --reporter compact
dart run tool/release_audit.dart
cd functions && npm test && npm audit --omit=dev && npm outdated
flutter pub outdated
```

Optional if emulators are installed:

```text
firebase emulators:exec --only firestore,storage "npm --prefix functions test"
```

Also record installed Flutter/Dart/Node vs declared versions, analyzer issue
counts, skipped tests.

## 7. Constitution scoring

For each principle and each product constraint: PASS / PARTIAL / FAIL plus
one-line evidence and finding IDs.

## 8. Prior-audit diff sources

- `docs/audits/2026-05-17-full-platform-audit.md`
- `docs/audits/2026-05-17-release-gate-checklist.md`
- `BUILDOZER_UI_UX_AUDIT.md`
- `Buildozer_—_Full_Project_Review_&_Improvement_Recommendations.md` (if present)
- `UX_Reconstruction_Proposal.md` (if present)
- `specs/001-review-improvement-pack/review-findings.md`
- `docs/expenses_plan_gap_audit.md`
- `docs/superpowers/plans/2026-07-24-buildozer-ui-ux-audit.md`

Table columns: Finding | Status (Fixed / Still open / Regressed / N/A) | Evidence

Walk `specs/003-optional-project-budget/tasks.md` independently. Do not trust
`[X]` checkboxes.

## 9. Output

Write `docs/audits/YYYY-MM-DD-full-audit-report.md` using `REPORT_TEMPLATE.md`.
Update `LEAD_REGISTER.md` with Confirmed / Refuted / Refined for every lead.

Finish by printing: report path, counts per severity, ship verdict, top five
actions.

## 10. Definition of done (full run)

- Every domain A–W examined, with findings or “no issues — checked X, Y, Z”
- Every lead in `LEAD_REGISTER.md` marked
- Every finding has location, scenario, fix, verification, effort
- Enhancements section is researched, not generic
- No source/config/rules/git changed; no secret values in the report
