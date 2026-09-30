import type { Sql } from "../db/pool";

export interface RpcContext {
  uid: string;
  email?: string;
  name?: string;
  picture?: string;
  /** Pooled client for queries; for mutating functions, the transaction of this request. */
  sql: Sql;
}

export interface RpcFunction {
  /** Mutating functions require X-Idempotency-Key and run in one transaction. */
  mutating: boolean;
  /** Per-function timeout in ms (default 30 s; processVoiceExpense uses 120 s). */
  timeoutMs?: number;
  handler(ctx: RpcContext, data: unknown): Promise<unknown>;
}

export type RpcRegistry = Record<string, RpcFunction>;
