# Buildozer (Flutter + self-hosted backend)

Buildozer is a mobile-first construction operations app. It works offline: every screen reads a
local copy of the workspace's data, and changes are queued and sent to the server when online.

Expenses are receipts: one title and one or more line items (name + amount, optional quantity and
note), with project, category, supplier, payment details and attachments shared by the whole
receipt. The expense total is the sum of its items (spec `specs/005-multi-item-expenses/`).

Voice expenses:
1. Flutter records audio.
2. Flutter uploads it to the server (`POST /v1/files`, kind `voice-expenses`).
3. Flutter calls the `processVoiceExpense` RPC.
4. The server transcribes the audio with OpenRouter audio input.
5. One structured OpenRouter call extracts the title, the items and any mentioned project, category,
   supplier, date and payment status, in any word order. The rule-based parser is only the fallback
   when that call fails.
6. Flutter shows a review/edit confirmation.
7. Only confirmed data is saved (`createExpenseWithQuota` RPC).

Pasted receipt text: on the Add Expense screen, **Paste text** → **Organize with AI** sends the text
to the `organizeExpenseText` RPC (same extraction, no records written) and fills the form for
review. Fields the user already set are never overwritten.

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
- AI first: one OpenRouter call with a strict JSON schema returns a `proposal` (title, ordered
  items, mentioned fields, stated total, several-receipts flag); see
  `specs/005-multi-item-expenses/contracts/ai-extraction.md`.
- Rules fallback: on an AI error, timeout or malformed reply, the rule-based parser returns today's
  single-amount result as one flagged item (`source: "rules"`).
- The legacy `parsed`/`confidence` fields are still returned (`parsed.amount` = the items' total).
- Always return confirmation-ready payload.
- Never auto-save without user confirmation.
- Quality check before changing the prompt or model: `cd server && npm run eval:receipts` (needs
  `OPENROUTER_API_KEY`; ≥ 85% item accuracy, no title number turned into an item, p95 ≤ 8 s).

## Tests

- App: `flutter analyze`, `flutter test --reporter compact`.
- Server: unit, migration, integration (Postgres) and parity (against the old Cloud Functions on
  the emulators) suites; see **Server** above.
