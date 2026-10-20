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
  /** Feature 005: title + items proposal; additive, older clients ignore it. */
  proposal?: ExpenseProposal;
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


/** Feature 005: one line of an AI receipt proposal (data-model.md §6). */
export type ProposalItem = {
  name: string | null;
  amount: number | null;
  quantity: number | null;
  needsReview: boolean;
};

export type ProposalPaymentStatus = "unpaid" | "partial" | "paid";

/** AI understanding of a recording or pasted text; transient, shown for review, never stored. */
export type ExpenseProposal = {
  title: string | null;
  items: ProposalItem[];
  projectId: string | null;
  projectName: string | null;
  category: string | null;
  entityId: string | null;
  entityName: string | null;
  date: string | null;
  paymentStatus: ProposalPaymentStatus | null;
  currency: CurrencyCode;
  statedTotal: number | null;
  totalMismatch: boolean;
  multipleReceiptsSuspected: boolean;
};

export type ExtractionSource = "llm" | "rules";

/** organizeExpenseText response (contracts/rpc-expense-items.md §3). */
export type ExpenseProposalResponse = {
  text: string;
  proposal: ExpenseProposal;
  source: ExtractionSource;
  needsConfirmation: true;
};

export type EntityInput = {
  id: string;
  name: string;
};
