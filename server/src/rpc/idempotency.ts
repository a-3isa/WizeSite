import type { Sql } from "../db/pool";
import { withTransaction } from "../db/tx";

/**
 * Runs a mutating RPC exactly once per (uid, function, X-Idempotency-Key).
 * The stored response and the mutation commit in the same transaction, so a failed
 * attempt stores nothing and a retry runs again; a replay after success returns the
 * stored response without touching data. A transaction-scoped advisory lock serialises
 * concurrent requests carrying the same key.
 */
export async function runIdempotent(
  sql: Sql,
  input: { uid: string; functionName: string; idempotencyKey: string },
  run: (tx: Sql) => Promise<unknown>,
): Promise<unknown> {
  const key = `${input.uid}:${input.functionName}:${input.idempotencyKey}`;
  return withTransaction(sql, async (tx) => {
    await tx`SELECT pg_advisory_xact_lock(hashtextextended(${key}, 0))`;
    const existing = await tx<{ response: unknown }[]>`
      SELECT response FROM idempotency_keys WHERE key = ${key}`;
    if (existing.length > 0) {
      return existing[0].response;
    }
    const result = (await run(tx)) ?? null;
    await tx`
      INSERT INTO idempotency_keys (key, uid, function_name, response)
      VALUES (${key}, ${input.uid}, ${input.functionName}, ${tx.json(result as never)})`;
    return result;
  });
}
