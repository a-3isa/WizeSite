# Audit Lead Register

Hypotheses only. Each audit run must mark every row Confirmed, Refuted, or
Refined against **current** code. Do not copy unverified leads into a report.

Legend: **Open** = not yet judged this run · **Confirmed** · **Refuted** ·
**Refined** (still a risk, but the original wording was wrong).

Last full pass: 2026-09-17

---

## From 2026-09-14 prompt §7

| ID | Lead | Disposition | Notes |
| --- | --- | --- | --- |
| L01 | Service-account JSON and `.env` exist on disk at repo root (gitignored) — check history | **Confirmed** | Present on disk; **not** in git history. |
| L02 | `onCall` functions show no `enforceAppCheck`; only HTTP twins verify App Check | **Refuted** | Every `onCall` including `deleteOwnAccount` and `processVoiceExpense` sets `enforceAppCheck: true`. |
| L03 | Hive boxes opened without encryption cipher | **Refuted** | AES via `lib/core/storage/hive_boxes.dart`. Residual is L24. |
| L04 | Storage rules per-uploader vs shared-workspace viewing | **Confirmed** | Owner-only Storage; teammates use long-lived `downloadUrl` tokens. |
| L05 | `maxInstances: 10` is global | **Confirmed** | `setGlobalOptions` in `functions/src/index.ts`. |
| L06 | Functions has no linter; `functions/lib/` committed | **Confirmed** | `"lint": "echo \"No lint configured\""`; `lib/` tracked. |
| L07 | `freezed_annotation` / `json_annotation` unused | **Confirmed** | Declared; zero generators / usages in `lib/`. |
| L08 | `file_picker` on a beta version | **Confirmed** | `12.0.0-beta.7` (stable 13.x available). |
| L09 | Local fork of `cloud_firestore` | **Refined** | Override exists; app `lib/` never uses Pipeline — unused surface. |
| L10 | Codemagic `--build-name=1.0.0`; no test steps | **Refined** | Now `$PUBSPEC_VERSION` + `flutter test` + `npm test`. Still **no Android workflow**. |
| L11 | `AGENTS.md` and `CLAUDE.md` disagree on active plan | **Refuted** | Both point at `specs/003-optional-project-budget/plan.md`. |
| L12 | Tracked junk files at root | **Confirmed** | Still in the git index; working tree shows them as deleted (`D`) uncommitted. |
| L13 | `functions/.env.example` mentions `OPENAI_API_KEY` | **Refuted** | Example uses `OPENROUTER_*` only. Local root `.env` may still have stale `OPENAI_API_KEY` key name. |
| L14 | Missing `POST_NOTIFICATIONS` / `UIBackgroundModes` / `CFBundleLocalizations` | **Refined** | No FCM stack → push permissions not required. `CFBundleLocalizations` + `PrivacyInfo.xcprivacy` present (manifest thin). |
| L15 | Default lints only; ~167 TODO/FIXME/HACK | **Refined** | Strict language flags on; real TODO/FIXME/HACK count ≈ 0. Still default `flutter_lints` rule set. |
| L16 | Crashlytics log before collection; all errors fatal | **Refuted** | Collection enabled first; `PlatformDispatcher` uses `fatal: false`. |
| L17 | Huge Dart files + huge `index.ts` | **Confirmed** | `index.ts` ~5k lines even after module extracts. |
| L18 | Money is `double` / `number` end to end | **Confirmed** | `money.ts` is not a decimal type. |
| L19 | Commits with `git status` as the message | **Confirmed** | e.g. `b607c69`, `dfd60b5`, `bca0ffc`, `25ceb78`. |
| L20 | Uncommitted `google-services.json` / `pubspec.yaml` | **Confirmed** | File still tracked despite `.gitignore`; local `M`. |

## New leads as of 2026-09-17

| ID | Lead | Disposition | Notes |
| --- | --- | --- | --- |
| L21 | `deleteOwnAccount` Storage prefixes omit `receipts/{uid}/` | **Confirmed** | Legacy path still in `storage.rules`; current client uploads `attachments/` only. |
| L22 | Client can forge `idempotency_keys` | **Refuted** | `allow read, write: if false`. |
| L23 | Client vs functions `cashCollectedAmount` drift | **Refuted** (helpers) | Helpers match. **Consumers** still disagree — see F-E01. |
| L24 | Hive AES migration crash window | **Confirmed** | Flag persisted only after all opens. |
| L25 | HTTP twins duplicated attack surface | **Refined** | Still used as callable fallback; App Check + Bearer required. |
| L26 | `graphify-out/` absent | **Refuted** (as product defect) | Skip; not a product bug. |
| L27 | Spec 003 checkboxes may not match code | **Refined** | Critical guards present; T034/T080/T082 still open; reports cash consistency not implied by `[X]`. |
| L28 | Owner-with-members deletion UI mismatch | **Refuted** | UI maps `TRANSFER_OWNERSHIP_REQUIRED`. |
| L29 | Voice AI disclosure vs store listing | **Confirmed** | In-app disclosure exists; Play listing / PrivacyInfo lag. |
| L30 | Dual `receipts/` vs `attachments/` Storage paths | **Refined** | Client uses `attachments/` only; `receipts/` is legacy rules + orphan risk. |
