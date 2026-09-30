/**
 * Error thrown by RPC handlers and domain code. Same constructor shape and code set as
 * firebase-functions `HttpsError`, so logic ported from `functions/src` can keep throwing
 * `new HttpsError(code, message, details)` via `import {RpcError as HttpsError}`.
 * The RPC router maps `code` to the HTTP status in contracts/rpc-api.md.
 */
export type RpcErrorCode =
  | "ok"
  | "cancelled"
  | "unknown"
  | "invalid-argument"
  | "deadline-exceeded"
  | "not-found"
  | "already-exists"
  | "permission-denied"
  | "resource-exhausted"
  | "failed-precondition"
  | "aborted"
  | "out-of-range"
  | "unimplemented"
  | "internal"
  | "unavailable"
  | "data-loss"
  | "unauthenticated";

export class RpcError extends Error {
  constructor(
    public readonly code: RpcErrorCode,
    message: string,
    public readonly details?: unknown,
  ) {
    super(message);
    this.name = "RpcError";
  }
}
