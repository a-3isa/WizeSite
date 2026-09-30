# Contract: RPC API (`https://api.<domain>`)

Replaces Firebase callable + HTTP twin functions. **Payloads and results are identical to today's
callables** — this contract defines only the transport envelope. The parity test suite is the
source of truth for per-function shapes.

## Transport

```
POST /v1/rpc/{functionName}
Authorization: Bearer <Firebase ID token>
X-Firebase-AppCheck: <App Check token>
X-Idempotency-Key: <uuid>            # required for every mutating function
Content-Type: application/json

{ "data": { ...same payload as today's httpsCallable(...).call(payload) } }
```

Success `200`:

```json
{ "result": { ...same object today's callable returns... } }
```

Error (non-2xx), body:

```json
{ "error": { "code": "invalid-argument", "message": "User-facing message", "details": {} } }
```

| `code` (unchanged from `HttpsError`) | HTTP |
|---|---|
| `invalid-argument` | 400 |
| `failed-precondition` | 412 |
| `unauthenticated` | 401 |
| `permission-denied` | 403 |
| `not-found` | 404 |
| `already-exists` | 409 |
| `resource-exhausted` (quota) | 429 |
| `internal` | 500 |
| `unavailable` | 503 |

Client mapping: `CallableClient` converts this envelope into the same `CallableClientException(code, message)`
it throws today, so `sync_error_classifier.dart`, `firebase_functions_error_message.dart` and the offline queue's
retry/permanent-failure decisions are unchanged.

## Authentication & authorization (every request)

1. Missing/invalid ID token → `unauthenticated`.
2. Missing/invalid App Check token → `unauthenticated` (same behavior as `enforceAppCheck: true`).
3. Workspace-scoped functions: caller must have an active membership in the target workspace with a
   role allowed for that function (same matrix as today's functions + `firestore.rules`) → else
   `permission-denied`.

## Idempotency

`X-Idempotency-Key` + uid + functionName stored in `idempotency_keys` with the response, inside the
same transaction as the mutation. A replay returns the stored response with `200`. Records also keep
their `clientMutationId` uniqueness as today.

## Function catalogue (name preserved = path segment)

**Workspace & user**: `ensureUserWorkspaceBootstrap`, `completeInitialWorkspaceSetup`, `setActiveWorkspace`,
`createWorkspace`, `updateWorkspaceMemberRole`, `removeWorkspaceMember`, `inviteMemberByEmail`,
`inviteMemberWithQuota`, `updateUserProfile`, `updateUserSettings`, `deleteOwnAccount`, `checkLimit`.

**Projects**: `createProjectWithQuota`, `updateProject`, `archiveProject`, `unarchiveProject`, `deleteProjectCascade`.

**Expenses / payments / workers**: `createExpenseWithQuota`, `updateExpense`, `archiveExpenseWithQuotaRefund`,
`createPaymentWithQuota`, `updatePayment`, `archivePaymentWithQuotaRefund`, `createWorker`, `updateWorker`,
`archiveWorker`, `createWorkerEntryWithQuota`, `updateWorkerEntry`, `archiveWorkerEntryWithQuotaRefund`.

**Attachments / voice**: `getAttachmentDownloadUrl`, `processVoiceExpense`.

**New (were direct client Firestore writes; research R3)**:

| Function | Replaces direct write in |
|---|---|
| `upsertEntity`, `archiveEntity`, `deleteEntity`, `touchEntityLastUsed` | `entities/data/entity_repository.dart` |
| `upsertWorkerAccountingRecord` | `workers/data/worker_accounting_repository.dart` and the worker accounting screen (added during implementation: the app writes these records directly too) |
| `upsertContractorAccountingRecord` | `contractors/data/contractor_accounting_repository.dart` |
| `upsertEquipmentAccountingRecord` | `equipment/data/equipment_accounting_repository.dart` |
| `upsertTransportProviderAccountingRecord` | `transport/data/transport_provider_accounting_repository.dart` |
| `markNotificationsRead` | `notifications/data/notification_repository.dart` |
| `restoreMembership` | `core/services/session_restore_service.dart` |

(`user_settings_repository.dart` direct writes → existing `updateUserSettings`.)

Where `firestore.rules` blocked what the app does, the RPCs follow the app (found while porting,
T063): equipment records use `providerId`/`providerName` (the rules demanded `equipmentId`, so every
equipment save failed); contact edits may change `phoneNumber`, `notes` and `rateUnit` (left out of
the rules' update allow-list); `deleteEntity` is allowed for owners and admins (the rules refused all
deletes). `restoreMembership` only repairs the owner's missing membership (the client write it
replaces was always refused).

**Removed**: the `*Http` twins (`createProjectWithQuotaHttp`, …, `processVoiceExpenseHttp`) — every
function is HTTP now. The five `on*WriteRecompute` triggers become in-transaction recompute (research R6).

## Operational endpoints

- `GET /healthz` → `200 {"status":"ok","db":"ok","sync":"ok"}` (no auth) — for external uptime probe.
- `POST /v1/webhooks/revenuecat` — see [webhooks.md](./webhooks.md).
- `POST /v1/files`, `GET /v1/files/signed/...` — see [files-api.md](./files-api.md).

## Limits

- Request body ≤ 1 MB (files go through `/v1/files`).
- Rate limit per uid: 60 req/min burst 120 → `resource-exhausted` with `details.retryAfterSeconds`.
- Timeouts: 30 s default; `processVoiceExpense` 120 s.
