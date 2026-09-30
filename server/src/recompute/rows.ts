import type { TriggerDocData } from "../domain/accounting";

/**
 * NUMERIC columns (postgres.js returns them as strings). Converted to numbers only here, for
 * the ported builders, which did Number(...) on Firestore doubles anyway. Money is still stored
 * exactly as NUMERIC(14,2); this conversion never feeds a write without going back through SQL.
 */
export const NUMERIC_COLUMNS = new Set([
  "amount",
  "paid_amount",
  "contract_value",
  "budget_limit",
  "completion_percentage",
  "daily_wage",
  "days_worked",
  "total_cost",
  "default_rate",
]);

/** Columns that exist only on the server side of the migration and have no Firestore twin. */
const INTERNAL_COLUMNS = new Set(["legacy"]);

function camelCase(column: string): string {
  return column.replace(/_([a-z])/g, (_, c: string) => c.toUpperCase());
}

/**
 * Turns a Postgres row into the Firestore document shape the ported code expects:
 * snake_case → camelCase, NUMERIC → number, NULL → absent (like a missing Firestore field),
 * timestamptz stays a Date (parseTimestamp accepts it). Unmapped source fields preserved in
 * `legacy` are restored first, so mapped columns always win.
 */
export function rowToDoc(row: Record<string, unknown>): TriggerDocData {
  const legacy =
    row.legacy && typeof row.legacy === "object" ? (row.legacy as Record<string, unknown>) : {};
  const doc: TriggerDocData = { ...legacy };
  for (const [column, value] of Object.entries(row)) {
    if (INTERNAL_COLUMNS.has(column) || value === null || value === undefined) {
      continue;
    }
    doc[camelCase(column)] =
      NUMERIC_COLUMNS.has(column) && typeof value === "string" ? Number(value) : value;
  }
  return doc;
}
