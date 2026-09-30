# Contract: Files API (replaces Firebase Storage)

## Upload

```
POST /v1/files
Authorization: Bearer <Firebase ID token>
X-Firebase-AppCheck: <token>
X-Idempotency-Key: <uuid>
Content-Type: multipart/form-data
  kind = receipts | attachments | voice-expenses | profile-photos
  file = <binary>
```

Server builds the path `{kind}/{uid}/{uuid}.{ext}` (same scheme as today — owner is always the caller,
so the `owner(userId)` rule from `storage.rules` holds by construction).

Validation — identical to `storage.rules` (`validAttachmentUpload`, `validVoiceUpload`,
`validProfilePhotoUpload`): allowed content types and max sizes are copied verbatim during
implementation; violations → `400 invalid-argument`.

`201` response:

```json
{ "storagePath": "receipts/<uid>/<uuid>.jpg", "contentType": "image/jpeg", "sizeBytes": 123456, "sha256": "…" }
```

The client stores `storagePath` in the record exactly as it stores the Firebase Storage path today;
`PendingAttachmentService` keeps queuing uploads offline and calls this endpoint on reconnect.

## Download

Client calls RPC `getAttachmentDownloadUrl { storagePath }` (unchanged contract) → server checks the
caller is a member of the workspace that owns the referencing record (or owns the path) and returns:

```json
{ "url": "https://api.<domain>/v1/files/signed/<storagePath>?exp=<unix>&sig=<hmac>", "expiresAt": "…" }
```

- Signature: HMAC-SHA256 over `storagePath|exp` with `FILES_SIGNING_KEY`; TTL 15 min.
- `GET` on an expired/invalid signature → `403`.
- Response headers: correct `Content-Type`, `Cache-Control: private, max-age=900`,
  `Content-Disposition: inline; filename*=UTF-8''<encoded>` (non-ASCII names safe).

## Delete

No direct delete endpoint. Files are deleted server-side by `deleteProjectCascade`, record archive
policies that already delete today, and `deleteOwnAccount`.

## Storage layout on VPS

`/srv/wizesite/files/<storagePath>`; owned by the API container user; mode 0600; backed up by restic
every 10 min (research R7).
