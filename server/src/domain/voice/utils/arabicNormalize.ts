const ARABIC_TO_ASCII_DIGITS: Record<string, string> = {
  "٠": "0",
  "١": "1",
  "٢": "2",
  "٣": "3",
  "٤": "4",
  "٥": "5",
  "٦": "6",
  "٧": "7",
  "٨": "8",
  "٩": "9",
  "۰": "0",
  "۱": "1",
  "۲": "2",
  "۳": "3",
  "۴": "4",
  "۵": "5",
  "۶": "6",
  "۷": "7",
  "۸": "8",
  "۹": "9",
};

export function convertArabicDigitsToWestern(input: string): string {
  return input.replace(/[٠-٩۰-۹]/g, (digit) => ARABIC_TO_ASCII_DIGITS[digit] ?? digit);
}

export function normalizeArabicCharacters(input: string): string {
  return input
    .replace(/[أإآٱ]/g, "ا")
    .replace(/ى/g, "ي")
    .replace(/ؤ/g, "و")
    .replace(/ئ/g, "ي")
    .replace(/ة/g, "ه")
    .replace(/[ـ]/g, "")
    .replace(/[\u064B-\u065F]/g, "");
}

export function collapseSpaces(input: string): string {
  return input.replace(/\s+/g, " ").trim();
}

export function normalizeTranscript(input: string): string {
  const normalized = normalizeArabicCharacters(
    convertArabicDigitsToWestern(input),
  )
    .replace(/٬/g, ",")
    .replace(/٫/g, ".")
    .toLowerCase();

  return collapseSpaces(normalized);
}

