# Contract: AI Receipt Extraction (server → OpenRouter)

**Owner**: `server/src/domain/voice/services/receipt_extraction.service.ts` (new)
**Callers**: `processVoiceExpense` (after transcription), `organizeExpenseText`
**Model**: `OPENROUTER_MODEL` env (today `openai/gpt-4o-mini`). Temperature 0.1. Timeout 20 s.

## Inputs to the prompt

| Input | Source |
|---|---|
| Original text | Transcript or pasted text (≤ 4,000 chars) |
| Normalized text | `normalizeTranscript()` (`utils/arabicNormalize.ts`) |
| Project names | Live projects of the workspace (≤ 100), names only |
| Supplier names | Workspace entities (≤ 200), names only |
| Allowed categories | Research R6 list |
| Default currency, today | From the request |

Names are listed as plain lines. IDs are **never** sent to the model. Mapping name → id happens after the
call (`mapLlmProjectNameToProvided` and an equivalent matcher for entities).

## Instructions (summary; the exact text lives in code and is covered by unit tests)

1. Extract **exactly one** receipt: one title plus its line items. If the text clearly holds more than
   one receipt, set `multipleReceiptsSuspected: true` and extract the first.
2. Word and line order are free. Pair each amount with the item it belongs to, whether the amount comes
   before or after the name.
3. Title: drop leading document words (`فاتورة`, `بون`, `وصل`, `إيصال`, `حساب`, "invoice", "receipt").
   **Keep numbers that qualify the title** (`شهر 10`, `دور 3`, `شقة 5`). They are never item amounts.
4. Currency words (`جنيه`, `ج`, `ج.م`, `EGP`, `دولار`) are currency, never part of a name.
5. Understand Western digits, Arabic-Indic digits (`١٠٠`) and spoken Egyptian Arabic numbers
   (`مية وخمسين` = 150, `ألف وميتين` = 1200).
6. A grand total stated by the user (`الإجمالي`, `المجموع`, `الكل`) goes to `statedTotal`, **not** to an
   item.
7. Only fill project, supplier, category, date or payment status when the text mentions them. Never
   guess. Project and supplier names must come from the provided lists, or be `null`.
8. Ignore chatter (`تمام يا باشا`, greetings, phone numbers).
9. Don't translate. Keep names in the source language.
10. Unknown → `null`. Never invent items or amounts.
11. A count before or after an item name is its `quantity`, and the stated amount is the **line total**:
    `2 حنفية بـ 200` → `{name: "حنفية", quantity: 2, amount: 200}`. Never multiply.

## Response JSON schema (strict)

```json
{
  "type": "object",
  "additionalProperties": false,
  "required": ["title", "items", "matchedProjectName", "category", "supplierName",
               "date", "paymentStatus", "currency", "statedTotal", "multipleReceiptsSuspected"],
  "properties": {
    "title": { "type": ["string", "null"] },
    "items": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["name", "amount", "quantity", "currency", "uncertain"],
        "properties": {
          "name": { "type": ["string", "null"] },
          "amount": { "type": ["number", "null"] },
          "quantity": { "type": ["number", "null"] },
          "currency": { "type": ["string", "null"], "enum": ["EGP", "USD", "SAR", "AED", null] },
          "uncertain": { "type": "boolean" }
        }
      }
    },
    "matchedProjectName": { "type": ["string", "null"] },
    "category": { "type": ["string", "null"],
                  "enum": ["materials", "equipment", "transport", "contractor", "storage", "rentals", "other", null] },
    "supplierName": { "type": ["string", "null"] },
    "date": { "type": ["string", "null"], "description": "YYYY-MM-DD" },
    "paymentStatus": { "type": ["string", "null"], "enum": ["unpaid", "partial", "paid", null] },
    "currency": { "type": ["string", "null"], "enum": ["EGP", "USD", "SAR", "AED", null] },
    "statedTotal": { "type": ["number", "null"] },
    "multipleReceiptsSuspected": { "type": "boolean" }
  }
}
```

The category enum is generated from `EXPENSE_CATEGORIES` minus `labor`, `worker` and `payments`, so the
two can't drift. A unit test asserts this.

## Deterministic post-processing → `proposal`

| Step | Rule |
|---|---|
| Amounts | `null` if not finite or ≤ 0. Otherwise rounded to 2 dp. |
| `needsReview` | `uncertain` OR name empty OR amount null OR item currency ≠ expense currency |
| Items cap | First 100 items. More than that sets `multipleReceiptsSuspected = true`. |
| Title | Trimmed, ≤ 200 chars. Empty → `null`. The client proposes one at save time (FR-008). |
| Project / supplier | Name → id via the matchers. Unmatched supplier keeps `entityName` with `entityId: null`. |
| Date | Valid `YYYY-MM-DD` and not more than 1 day after `today`. Otherwise `null`. |
| `totalMismatch` | `statedTotal != null && round2(statedTotal) != round2(Σ amounts)` |

## Failure handling

| Failure | Result |
|---|---|
| HTTP error, timeout, abort | Rules fallback (`extractExpenseByRules`), mapped to ≤ 1 item with `needsReview: true`, `source: "rules"` |
| Malformed or invalid JSON | Same as above |
| Rules find nothing | `items: []`, `title: null`, `source: "rules"` |
| Missing API key | `failed-precondition` (unchanged voice behavior) |

Logged per call: model, latency, item count, source, and fallback reason. **The raw text is never
logged** (same policy as the voice transcript).
