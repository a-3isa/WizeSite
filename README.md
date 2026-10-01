# Buildozer (Flutter + self-hosted backend)

Buildozer is a mobile-first construction operations app. It works offline: every screen reads a
local copy of the workspace's data, and changes are queued and sent to the server when online.

Voice expenses:
1. Flutter records audio.
2. Flutter uploads it to the server (`POST /v1/files`, kind `voice-expenses`).
3. Flutter calls the `processVoiceExpense` RPC.
4. The server transcribes the audio with OpenRouter audio input.
5. A rule-based parser runs first; the OpenRouter LLM is used only when the rules are uncertain.
6. Flutter shows a review/edit confirmation.
7. Only confirmed data is saved (`createExpenseWithQuota` RPC).

## Architecture

- App: Flutter + Riverpod + GoRouter. Local replica: PowerSync (SQLite). Offline writes: Hive queue.
- Server (`server/`): Node 22 + TypeScript + Fastify, PostgreSQL 17, PowerSync service, on one VPS
  behind a Cloudflare Tunnel (`api.` and `sync.buildozer.dpdns.org`). RPC contract:
  `specs/004-vps-backend-migration/contracts/`.
- Firebase keeps only Auth (ID tokens verified by the server), App Check, Crashlytics and
  Remote Config.
- AI calls: server-side only.
- Operations (`ops/`): deploy, backups (`ops/BACKUPS.md`), monitoring (`ops/MONITORING.md`),
  restore, cutover (`ops/CUTOVER.md`).

## Security Notes

See [docs/SECURITY.md](docs/SECURITY.md).

- No AI provider keys or server secrets in the Flutter app.
- Server secrets live only in `/srv/wizesite/.env` and `/srv/wizesite/secrets/` on the VPS
  (root-only): `OPENROUTER_API_KEY`, `OPENROUTER_MODEL`, `OPENROUTER_TRANSCRIPTION_MODEL`,
  `REVENUECAT_WEBHOOK_SECRET`, the Firebase Auth admin key, backup credentials.
- Writes are quota-enforced on the server; every mutating RPC is idempotent.

## Server

```bash
cd server
npm ci
npm run lint
npm test                    # unit + migration tests
docker compose -f compose.test.yml up -d --wait postgres
DATABASE_URL=<test url> npm run migrate
TEST_DATABASE_URL=<test url> npm run test:integration
```

Deploy (on the VPS): `bash /srv/wizesite/app/ops/deploy.sh --build`.

`functions/` holds the old Cloud Functions until the Firebase data is decommissioned
(tasks.md T108); the server's parity tests run against it.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for Conventional Commits. Do not paste
`git status` dumps as commit messages.

## File Paths

Files are stored under `/srv/wizesite/files` on the VPS and opened through short-lived signed
links (`getAttachmentDownloadUrl`); profile photos have a permanent public link.

- Voice notes: `voice-expenses/{userId}/...`
- Attachments: `attachments/{userId}/...`
- Profile photos: `profile-photos/{userId}/...`

## Flutter Setup

1. Install dependencies:

```bash
flutter pub get
```

2. Run the app (uses `https://api.buildozer.dpdns.org` / `https://sync.buildozer.dpdns.org`
   unless overridden):

```bash
flutter run
# another backend:
flutter run --dart-define=API_BASE_URL=https://api.example.com --dart-define=SYNC_URL=https://sync.example.com
```

3. Voice flow entry:
- `Add Expense` screen -> microphone icon -> record -> process -> review -> confirm.

## Voice RPC

### `processVoiceExpense` (`POST /v1/rpc/processVoiceExpense`)

Input:

```json
{
  "storagePath": "voice-expenses/uid/timestamp.m4a",
  "projects": [
    { "id": "p1", "name": "Villa October" },
    { "id": "p2", "name": "Narges Building" }
  ],
  "currency": "EGP",
  "languageHint": "ar"
}
```

Output:

```json
{
  "transcript": "Paid 3200 EGP for steel in Narges Building project",
  "parsed": {
    "amount": 3200,
    "currency": "EGP",
    "category": "materials",
    "matchedProjectId": "p2",
    "matchedProjectName": "Narges Building",
    "note": "steel"
  },
  "confidence": {
    "amount": 0.99,
    "category": 0.95,
    "project": 0.9,
    "overall": 0.95
  },
  "source": "rules",
  "needsConfirmation": true,
  "storagePath": "voice-expenses/uid/timestamp.m4a"
}
```

## Rule + LLM Formula

- Normalize transcript (Arabic-aware + numeral conversion).
- Extract amount/category/project/note using rules first.
- Compute confidence scores.
- Fallback to OpenRouter only if fields are missing or confidence is low.
- Always return confirmation-ready payload.
- Never auto-save without user confirmation.

## Tests

- App: `flutter analyze`, `flutter test --reporter compact`.
- Server: unit, migration, integration (Postgres) and parity (against the old Cloud Functions on
  the emulators) suites; see **Server** above.
