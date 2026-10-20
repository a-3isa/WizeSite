import { RpcError as HttpsError } from "../domain/errors";
import { newDocId } from "./validation";

/**
 * Expense line items (feature 005, data-model.md §2). Items live in the `expenses.items` JSONB
 * column; `expenses.amount` stays the total and must equal their sum (Postgres CHECK
 * `expenses_amount_matches_items` backs this up).
 */
export type ExpenseItem = {
  id: string;
  name: string;
  amount: number;
  quantity: number | null;
  note: string;
};

export const MAX_EXPENSE_ITEMS = 100;
const MAX_NAME = 120;
const MAX_NOTE = 200;
const ID_PATTERN = /^[A-Za-z0-9_-]{6,36}$/;

/** Money compared and summed in integer piastres (2-decimal NUMERIC on the server). */
export const toPiastres = (value: number): number => Math.round(value * 100);

function itemError(index: number, message: string): HttpsError {
  return new HttpsError("invalid-argument", `Item ${index + 1}: ${message}`);
}

function positiveTwoDecimals(raw: unknown, index: number, field: "amount" | "quantity"): number {
  const value = raw === "" || raw === null || typeof raw === "boolean" ? Number.NaN : Number(raw);
  if (!Number.isFinite(value) || value <= 0) {
    throw itemError(index, `${field} must be greater than zero`);
  }
  if (Math.abs(Math.round(value * 100) / 100 - value) >= 1e-9) {
    throw itemError(index, `${field} can have at most 2 decimal places`);
  }
  return value;
}

/**
 * Validates `data.items`. Returns null when the caller sent no items (a legacy payload, e.g. an
 * offline action queued by an app build older than feature 005), otherwise the normalized items
 * and their total.
 */
export function parseExpenseItems(
  data: Record<string, unknown>,
): { items: ExpenseItem[]; total: number } | null {
  const raw = data.items;
  if (raw === undefined || raw === null) {
    return null;
  }
  if (!Array.isArray(raw) || raw.length < 1 || raw.length > MAX_EXPENSE_ITEMS) {
    throw new HttpsError("invalid-argument", `Expense must have between 1 and ${MAX_EXPENSE_ITEMS} items`);
  }
  const seen = new Set<string>();
  let totalPiastres = 0;
  const items = raw.map((entry, index): ExpenseItem => {
    const record = entry && typeof entry === "object" && !Array.isArray(entry)
      ? (entry as Record<string, unknown>)
      : {};
    const name = typeof record.name === "string" ? record.name.trim() : "";
    if (!name) {
      throw itemError(index, "name is required");
    }
    if (name.length > MAX_NAME) {
      throw itemError(index, "name is too long");
    }
    const amount = positiveTwoDecimals(record.amount, index, "amount");
    const quantity = record.quantity === undefined || record.quantity === null || record.quantity === ""
      ? null
      : positiveTwoDecimals(record.quantity, index, "quantity");
    const note = typeof record.note === "string" ? record.note.trim() : "";
    if (note.length > MAX_NOTE) {
      throw itemError(index, "note is too long");
    }
    const rawId = typeof record.id === "string" ? record.id.trim() : "";
    if (rawId && !ID_PATTERN.test(rawId)) {
      throw itemError(index, "invalid id");
    }
    const id = rawId || newDocId().slice(0, 12);
    if (seen.has(id)) {
      throw itemError(index, "duplicate id");
    }
    seen.add(id);
    totalPiastres += toPiastres(amount);
    return { id, name, amount, quantity, note };
  });
  return { items, total: totalPiastres / 100 };
}

/** When the caller also sent `amount`, it must equal the item total to the piastre. */
export function assertAmountMatchesItems(amount: number | null, total: number): void {
  if (amount !== null && toPiastres(amount) !== toPiastres(total)) {
    throw new HttpsError("invalid-argument", "Amount must equal the sum of items");
  }
}
