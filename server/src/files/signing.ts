import { createHmac, timingSafeEqual } from "node:crypto";

export interface FilesConfig {
  /** Directory holding attachment files at `<root>/<storagePath>`. */
  root: string;
  /** HMAC key for signed download URLs (FILES_SIGNING_KEY). */
  signingKey: string;
  /** Public base URL of the API, e.g. https://api.buildozer.dpdns.org. */
  publicUrl: string;
}

export const SIGNED_URL_TTL_SECONDS = 15 * 60;

function signature(config: FilesConfig, storagePath: string, exp: number): string {
  return createHmac("sha256", config.signingKey).update(`${storagePath}|${exp}`).digest("hex");
}

/** Encodes each path segment (Arabic and spaces included) but keeps the slashes. */
export function encodeStoragePath(storagePath: string): string {
  return storagePath.split("/").map(encodeURIComponent).join("/");
}

/** URL valid for SIGNED_URL_TTL_SECONDS from `issuedAtMs`. */
export function signedFileUrl(config: FilesConfig, storagePath: string, issuedAtMs = Date.now()): string {
  const exp = Math.floor(issuedAtMs / 1000) + SIGNED_URL_TTL_SECONDS;
  const base = config.publicUrl.replace(/\/+$/, "");
  return `${base}/v1/files/signed/${encodeStoragePath(storagePath)}?exp=${exp}&sig=${signature(config, storagePath, exp)}`;
}

/** True when `sig` matches `storagePath` + `exp` and `exp` has not passed. Constant-time compare. */
export function verifySignedFile(
  config: FilesConfig,
  storagePath: string,
  exp: number,
  sig: string,
  nowMs = Date.now(),
): boolean {
  if (!Number.isInteger(exp) || exp * 1000 < nowMs || !/^[0-9a-f]{64}$/.test(sig)) {
    return false;
  }
  const expected = Buffer.from(signature(config, storagePath, exp), "hex");
  const given = Buffer.from(sig, "hex");
  return expected.length === given.length && timingSafeEqual(expected, given);
}
