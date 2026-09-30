import type { Sql } from "./pool";

const RETRYABLE = new Set(["40001", "40P01"]); // serialization_failure, deadlock_detected
const MAX_ATTEMPTS = 3;

/**
 * Runs `fn` in one transaction, retrying on serialization failures and deadlocks.
 * `fn` must be safe to re-run: nothing it does is visible until the transaction commits.
 */
export async function withTransaction<T>(sql: Sql, fn: (tx: Sql) => Promise<T>): Promise<T> {
  for (let attempt = 1; ; attempt++) {
    try {
      return (await sql.begin((tx) => fn(tx as unknown as Sql))) as T;
    } catch (error) {
      const code = (error as { code?: string }).code;
      if (attempt < MAX_ATTEMPTS && code && RETRYABLE.has(code)) {
        continue;
      }
      throw error;
    }
  }
}
