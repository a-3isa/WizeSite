import { randomBytes } from "node:crypto";

import { RpcError } from "../domain/errors";

/** Ported helpers from functions/src/index.ts, same messages. */
export function requireString(data: Record<string, unknown>, key: string): string {
  const value = data[key];
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new RpcError("invalid-argument", `Missing required field: ${key}`);
  }
  return value.trim();
}

export function asRecord(data: unknown): Record<string, unknown> {
  return data && typeof data === "object" && !Array.isArray(data)
    ? (data as Record<string, unknown>)
    : {};
}

export function normalizeEmail(input: string): string {
  return input.trim().toLowerCase();
}

export function nonEmptyStringOrUndefined(input: string): string | undefined {
  return input.trim().length > 0 ? input.trim() : undefined;
}

const ID_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";

/** Same shape as Firestore auto-ids (20 chars, [A-Za-z0-9]) so ids look identical before/after. */
export function newDocId(): string {
  const bytes = randomBytes(20);
  let id = "";
  for (const byte of bytes) {
    id += ID_ALPHABET[byte % ID_ALPHABET.length];
  }
  return id;
}
