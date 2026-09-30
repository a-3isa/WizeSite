# Buildozer (Flutter + Firebase)

Buildozer is a mobile-first construction operations app.

This repository now includes a production-practical **voice expense pipeline**:
1. Flutter records audio.
2. Flutter uploads audio to Firebase Storage.
3. Flutter calls Firebase callable function `processVoiceExpense`.
4. Cloud Function transcribes audio with OpenRouter audio input.
5. Rule-based parser runs first.
6. OpenRouter LLM is used only when rules are uncertain.
7. Flutter shows review/edit confirmation.
8. Only confirmed data is saved (via callable `createExpenseWithQuota`).

## Architecture

- Frontend: Flutter + Riverpod + GoRouter
- Backend: Firebase Auth + Firestore + Storage + Cloud Functions
- AI calls: Server-side only (Cloud Functions)

## Security Notes

See [docs/SECURITY.md](docs/SECURITY.md) for secrets vs public client configs.

- No AI provider keys in Flutter client.
- Secrets are read on Functions side only:
  - `OPENROUTER_API_KEY`
  - `OPENROUTER_MODEL`
  - `OPENROUTER_TRANSCRIPTION_MODEL`
- Expense writes remain quota-enforced through callable functions.
- Voice files are scoped to user path in `storage.rules`.

## Cloud Functions

Use **Node 22** (`functions/package.json` `engines.node` and Codemagic `node: 22`).

```bash
cd functions
npm ci
npm run lint
npm test
```

The local `packages/cloud_firestore` path override is a copy of hosted `6.6.0`
from `scripts/patch_cloud_firestore.ps1`. Keep it until CI proves pub.dev
`cloud_firestore` without the fork. App code does not use Pipeline APIs.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for Conventional Commits. Do not paste
`git status` dumps as commit messages.

## Storage Paths

- Voice notes: `voice-expenses/{userId}/{timestamp}.m4a`
- Receipts: `receipts/{userId}/{fileName}`

## Firestore Save Shape (confirmed voice expense)

`expenses/{expenseId}` includes:
- `projectId`
- `projectName`
- `amount`
- `currency`
- `category`
- `notes`
- `inputMethod: "voice"`
- `transcript`
- `source` (`rules` | `llm` | `hybrid`)
- `storagePath`
- `createdBy`
- `createdAt`
- `updatedAt`
- `isArchived`

## Flutter Setup

1. Install dependencies:

```bash
flutter pub get
```

2. Run app:

```bash
flutter run
```

3. Voice flow entry:
- `Add Expense` screen -> microphone icon -> record -> process -> review -> confirm.

## Firebase Functions Setup

1. Install functions dependencies:

```bash
cd functions
npm install
```

2. Set Firebase secrets (recommended for production):

```bash
firebase functions:secrets:set OPENROUTER_API_KEY
firebase functions:secrets:set OPENROUTER_MODEL
firebase functions:secrets:set OPENROUTER_TRANSCRIPTION_MODEL
firebase functions:secrets:set REVENUECAT_WEBHOOK_SECRET
```

Notes:
- Voice transcription now uses OpenRouter audio input and defaults to `openai/gpt-audio-mini`.
- You can override the transcription model with `OPENROUTER_TRANSCRIPTION_MODEL`.
- Expense parsing still uses `OPENROUTER_MODEL` so you keep the same structured extraction model as before.

3. Build and test functions:

```bash
npm run build
npm test
```

4. Deploy:

```bash
firebase deploy --only functions,firestore:rules,storage --config firebase.deploy.json
```

## Voice Callable API

### `processVoiceExpense` (callable)

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

## Local env template

Use `functions/.env.example` as backend reference.

## Tests Added

Functions tests now cover:
- Arabic numeral conversion
- Transcript normalization
- Category matching
- Project matching
- Confidence calculation
- Fallback decision
- Confirmation response shape
