# Security notes

## Threat surface (self-hosted backend, spec 004)

| Surface | Protection |
|---|---|
| RPC API `https://api.buildozer.dpdns.org/v1/rpc/*` | Every call needs a valid Firebase ID token **and** an App Check token, verified on the server; per-caller rate limit (120/min); workspace role checks in each RPC; mutating calls idempotent (`X-Idempotency-Key`). |
| File uploads `POST /v1/files` | Same authentication; 10 MB cap; content type checked per kind; files land under the caller's own uid. |
| File downloads | Short-lived signed links (HMAC-SHA256 over path + expiry, 15 min, timing-safe compare), issued by `getAttachmentDownloadUrl` only to workspace members who can see the record. Profile photos (`/v1/public/profile-photos/{uid}/{uuid}.jpg|png`) are public by design: unguessable names, nothing else is served there. |
| Sync `https://sync.buildozer.dpdns.org` | PowerSync verifies the Firebase ID token against Google's JWKS. Sync rules (`server/powersync/sync_rules.yaml`) send a user only their own profile and the workspaces they are a member of; money data (`workspace_financial`) only to roles allowed to see it. |
| RevenueCat webhook | Shared secret, timing-safe compare; duplicate `event.id` values ignored via `webhook_events`. |
| `/internal/stats` | Answers loopback callers only (the heartbeat inside the container); 404 from outside. |
| Postgres | Never published on a host port; reachable only on the internal Docker network (checked by `ops/test/deploy_smoke.sh`). |

## VPS

- The stack has **no inbound ports**: public traffic arrives through a Cloudflare Tunnel
  (`cloudflared` container, outbound connection). TLS ends at Cloudflare.
- The VPS is shared with other services. Open items for the owner (not changed by this project):
  SSH password login for root is enabled and the host firewall (ufw) is inactive. Recommended:
  SSH keys only (`PasswordAuthentication no`, `PermitRootLogin prohibit-password`) and ufw allowing
  only SSH and the ports the other services need. `ops/bootstrap.sh` does this on a dedicated box.
- Rotate the Cloudflare Tunnel token if it was ever pasted outside the server.

## Secrets

All server secrets live on the VPS only, root-owned:

- `/srv/wizesite/.env` (mode 0600): database password, file-link signing key, OpenRouter key and
  models, RevenueCat webhook secret, Cloudflare Tunnel token, pgBackRest repository settings and
  passphrase.
- `/srv/wizesite/secrets/` (mode 0700): `firebase-auth-admin.json` (Auth admin for profile updates
  and account deletion), `firebase-service-account.json` (read-only, migration only),
  `restic.env`, `heartbeat.env`; `firebase-rollback.json` only during a rollback, deleted after.

Nothing secret is in the repository or the app bundle. Repo-root service-account JSON, `.env` and
similar files are gitignored; if a secret was shared in chat, email or a zip, rotate it before
the next deploy. Do not delete a teammate's local credential files as part of hygiene work.

## Backups

pgBackRest (database) and restic (files) encrypt everything before it leaves the VPS
(AES-256). The repository passphrases are not stored in the backup bucket: keep them in a
password manager, or the backups cannot be restored. Bucket keys are limited to the backup
bucket. See `ops/BACKUPS.md`.

## Public client configs

`android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist` are **public client
configs** required for app builds (Auth, App Check, Crashlytics, Remote Config). They are not
Admin SDK keys. Still avoid pasting them into public issues; they identify the Firebase project.

## Cloud Functions (until decommission)

`functions/` and its secrets (`OPENROUTER_*`, RevenueCat webhook auth) remain in Firebase until
the Firebase data is decommissioned (tasks.md T106–T108). During the 7-day rollback window
Firestore and Storage run with read-only rules (`firestore.readonly.rules`,
`storage.readonly.rules`).
