# Security notes

## Secrets

Repo-root service-account JSON, `.env`, and similar credential files are
gitignored. They must never be committed. If a secret was shared in chat,
email, or a zip, rotate it in Google Cloud / Firebase / OpenRouter before the
next deploy.

Do not delete a teammate’s local credential files as part of hygiene work.

## Public client configs

`android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist`
are **public client configs** required for app builds. They are not Admin SDK
keys. Still avoid pasting them into public issues; they identify the Firebase
project.

The `packages/cloud_firestore` path override is a vendored copy of hosted
`cloud_firestore` 6.6.0 (`scripts/patch_cloud_firestore.ps1`). Keep it until a
CI run on pub.dev 6.6.0/6.10.0 is proven. App `lib/` does not use Pipeline
APIs.

## Functions

Cloud Functions secrets (`OPENROUTER_*`, RevenueCat webhook auth) live in
Firebase / Codemagic env, not in the Flutter client.

Webhook authorization uses a timing-safe compare. Duplicate RevenueCat
`event.id` values are stored in `webhook_events` (client read/write denied).
