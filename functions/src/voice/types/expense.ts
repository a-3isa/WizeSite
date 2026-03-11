export type ExpenseCategory =
  | "labor"
  | "materials"
  | "equipment"
  | "transport"
  | "other";

export type ParseSource = "rules" | "llm" | "hybrid";

export type CurrencyCode = "EGP" | "USD" | "SAR" | "AED";

export type VoiceProjectInput = {
  id: string;
  name: string;
};

export type ParsedExpense = {
  amount: number | null;
  currency: CurrencyCode | null;
  category: ExpenseCategory | null;
  matchedProjectId: string | null;
  matchedProjectName: string | null;
  note: string | null;
};

export type ConfidenceScores = {
  amount: number;
  category: number;
  project: number;
  overall: number;
};

export type ProcessVoiceExpenseResponse = {
  transcript: string;
  parsed: ParsedExpense;
  confidence: ConfidenceScores;
  source: ParseSource;
  needsConfirmation: true;
  storagePath: string;
};

export type LlmExtractionResult = {
  amount: number | null;
  currency: CurrencyCode | null;
  category: ExpenseCategory | null;
  matchedProjectName: string | null;
  note: string | null;
};

export type RuleExtractionResult = {
  parsed: ParsedExpense;
  confidence: ConfidenceScores;
  shouldFallback: boolean;
  fallbackReasons: string[];
  normalizedTranscript: string;
};

