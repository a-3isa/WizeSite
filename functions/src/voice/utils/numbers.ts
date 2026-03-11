import {convertArabicDigitsToWestern} from "./arabicNormalize";

const AMOUNT_PATTERN = /\b\d{1,3}(?:[,\s]\d{3})*(?:\.\d+)?\b|\b\d+(?:\.\d+)?\b/g;

function cleanNumericToken(token: string): string {
  return token.replace(/,/g, "").replace(/\s+/g, "");
}

export function extractAmountCandidate(input: string): string | null {
  const normalized = convertArabicDigitsToWestern(input).replace(/٬/g, ",").replace(/٫/g, ".");
  const matches = normalized.match(AMOUNT_PATTERN);
  if (!matches || matches.length === 0) {
    return null;
  }

  for (const match of matches) {
    const cleaned = cleanNumericToken(match);
    const parsed = Number(cleaned);
    if (Number.isFinite(parsed) && parsed > 0) {
      return cleaned;
    }
  }

  return null;
}

export function parseAmount(input: string): number | null {
  const candidate = extractAmountCandidate(input);
  if (!candidate) {
    return null;
  }
  const parsed = Number(candidate);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return null;
  }
  return parsed;
}

