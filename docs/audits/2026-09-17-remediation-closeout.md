# 2026-09-17 audit close-out

Marks each 2026-09-17 finding against this remediation pass. Not a visual
rewrite of the UI audit.

Legend: **done** · **still-open** · **won’t-fix**

## P0 / money

| ID | Status | Notes |
| --- | --- | --- |
| F-E01 | done | Reports, export builder, and PDF use `cashCollectedAmount` / `paidAmount`. |
| F-E02 | done | Archive refunds `cashCollectedAmount`; unpaid archive is a no-op. |
| F-E03 | done | Dashboard pending/portfolio uses `_cashInFromMap`. |
| F-E06 | done | Display/aggregates round to 2 decimals. No integer minor-unit migration. |
| F-E07 | done | Client `paidAmount` persisted; no paid-split UX this pass. |
| F-E08 | done | Rules allow `refunded` / `cancelled`. |

## P1 / session, offline, billing, storage, rules

| ID | Status | Notes |
| --- | --- | --- |
| F-G01 | done | Session cleanup on stranded-loop, failed session, and Settings logout. |
| F-F01 | done | Queue stops at head-of-line backoff. |
| F-E04 | done | Contract/payment `failed-precondition` is invalid-target, not quota. |
| F-E05 | done | Dashboard week uses UTC ISO Monday bounds. |
| F-H01 / F-H02 | done | Cancellation stays active + `isAutoRenewing: false`; expiration expires. |
| F-D01 | done | Timing-safe webhook auth + `webhook_events` idempotency. |
| F-D02 | done | `revenuecatWebhook` `maxInstances: 20`. |
| F-H03 | done | Terms/privacy on plans screen. |
| F-C01 | done | Account deletion includes `receipts/{uid}/`; cascade deletes Storage paths. |
| F-D06 | done | Attachment path + Firebase Storage URL checks. |
| F-C02 | done | `getAttachmentDownloadUrl` callable; detail screens prefer it when online. |
| F-C03 | done | Zip still allowed; picker warning in EN/AR. |
| F-B01 | done | Payments read `canAccessAccounting`; expenses/worker_entries stay in-workspace. |
| F-B02 | done | Entity update allowlist. |
| F-B03 | done | `drafts` deny all. |

## UX / Now-tier

| ID | Status | Notes |
| --- | --- | --- |
| F-P02 | done | PDF `textDirection` from locale. |
| F-I01 | done | Voice Process gated offline. |
| F-L01 | done | Expense group titles are localization keys. |
| WhatsApp share | done | OS share sheet labeled “Share via WhatsApp or other apps”. |
| Duplicate last | done | Prefills last expense; date today; no attachments. |
| F-L02 | done | `EdgeInsetsDirectional` on screens this pass touched. |
| F-M01 | done | 48dp / semantics smokes for Add expense, Voice, Settings CTAs. |
| F-K01 | done | This appendix. |

## Hive / Google / perf / CI

| ID | Status | Notes |
| --- | --- | --- |
| F-F02 | done | Per-box encrypt flag after migrate. |
| F-G02 | done | Google `signOut` always initializes first. |
| F-F03 | done | `attachment_upload` wires `PendingAttachmentService.savePending`. |
| F-N01 | done | Dashboard metrics `.limit(200)`, unpaid `.limit(500)`; documented. |
| F-N02 | done | Project report PDF built via `compute` with a serializable DTO. |
| F-R01 | done | Codemagic Functions job runs Firestore/Storage emulators. |
| F-S01 | done | Android Codemagic workflow (analyze, test, signed AAB). |
| F-S02 | done | Node 22 in engines, README, and Codemagic. |
| F-D08 | done | Static test: every `onCall(` has `enforceAppCheck: true`. |
| F-D04 / F-D05 | done | Invite quota in transaction; uniform `INVITE_UNAVAILABLE`. |
| F-D07 | done | Voice LLM loads workspace projects server-side. |
| F-Q01 / F-W01 | done | PrivacyInfo collected types + Play listing voice-AI disclosure. |
| F-V01 | done | Remote Config `min_supported_build` + `voice_ai_enabled`. |
| F-D09 | done | ESLint script + `npm run check:build` drift check. |

## Hygiene

| ID | Status | Notes |
| --- | --- | --- |
| F-U01 | done | Root junk removed from git (`0`, `const`, `Gradle`, `onSelect(index)`, `store/play/$(node`). |
| F-A02 | done | google-services stay tracked; documented as public client config. |
| F-J01 | won’t-fix this pass | Keep `packages/cloud_firestore` path override (hosted `6.6.0` copy via `scripts/patch_cloud_firestore.ps1`) until CI proves pub.dev without the fork. |
| F-T01 | done | Unused `freezed_annotation` / `json_annotation` removed. |
| F-U02 | done | CONTRIBUTING Conventional Commits; no status-dump messages going forward. |
| F-O01 | won’t-fix | Indexes not deleted without Firebase console proof. |
| F-S03 | won’t-fix | Agent `ProgramFiles(x86)` flake is a playbook note only. |
| F-E06 full integer money | won’t-fix | Out of this pass. |
| F-D03 HTTP twins | done | Twins kept; static parity test added. |

## Older UI-audit P0/P1 (2026-07-24)

Treat visual rewrite items as **won’t-fix** here. Functional P0/P1 that overlap
this pass (RTL PDF, localization, a11y smokes, share) are **done**. Remaining
pixel-level design-system drift stays **still-open** for a dedicated UI pass.
