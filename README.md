# Buildozer (Flutter + Firebase)

Buildozer is a mobile-first construction operations app.

This repository now includes a production-practical **voice expense pipeline**:
1. Flutter records audio.
2. Flutter uploads audio to Firebase Storage.
3. Flutter calls Firebase callable function `processVoiceExpense`.
4. Cloud Function transcribes audio with OpenAI.
5. Rule-based parser runs first.
6. OpenRouter LLM is used only when rules are uncertain.
7. Flutter shows review/edit confirmation.
8. Only confirmed data is saved (via callable `createExpenseWithQuota`).

## Architecture

- Frontend: Flutter + Riverpod + GoRouter
- Backend: Firebase Auth + Firestore + Storage + Cloud Functions
- AI calls: Server-side only (Cloud Functions)

## Security Notes

- No OpenAI/OpenRouter keys in Flutter client.
- Secrets are read on Functions side only:
  - `OPENAI_API_KEY`
  - `OPENROUTER_API_KEY`
  - `OPENROUTER_MODEL`
- Expense writes remain quota-enforced through callable functions.
- Voice files are scoped to user path in `storage.rules`.

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
firebase functions:secrets:set OPENAI_API_KEY
firebase functions:secrets:set OPENROUTER_API_KEY
firebase functions:secrets:set OPENROUTER_MODEL
firebase functions:secrets:set REVENUECAT_WEBHOOK_SECRET
```

3. Build and test functions:

```bash
npm run build
npm test
```

4. Deploy:

```bash
firebase deploy --only functions,firestore:rules,storage
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
