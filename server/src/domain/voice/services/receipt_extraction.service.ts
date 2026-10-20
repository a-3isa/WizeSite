import {EXPENSE_CATEGORIES} from "../../money";
import {
  CurrencyCode,
  EntityInput,
  ExpenseProposal,
  ExtractionSource,
  ProposalItem,
  ProposalPaymentStatus,
  VoiceProjectInput,
} from "../types/expense";
import {normalizeTranscript} from "../utils/arabicNormalize";
import {matchEntityName} from "./entity_matcher.service";
import {mapLlmProjectNameToProvided, safeJsonParse} from "./llm_extraction.service";
import {extractExpenseByRules} from "./rule_extraction.service";

/**
 * Feature 005: AI-first receipt extraction (contracts/ai-extraction.md). One structured LLM call
 * turns a voice transcript or pasted text into a title + ordered items + any mentioned project,
 * category, supplier, date and payment status, whatever the word or line order. The rules
 * extractor is only the fallback when the AI call fails.
 */

/** Categories the AI may choose: expense categories minus legacy/worker/payments (research R6). */
export const RECEIPT_CATEGORIES: string[] = EXPENSE_CATEGORIES.filter(
  (c) => c !== "labor" && c !== "worker" && c !== "payments",
);
const CURRENCIES: CurrencyCode[] = ["EGP", "USD", "SAR", "AED"];
const PAYMENT_STATUSES: ProposalPaymentStatus[] = ["unpaid", "partial", "paid"];
const MAX_ITEMS = 100;
const MAX_TITLE = 200;
const DAY_MS = 86_400_000;

export type ReceiptLogger = {
  info: (message: string, meta: Record<string, unknown>) => void;
  warn: (message: string, meta: Record<string, unknown>) => void;
};

const consoleLogger: ReceiptLogger = {
  info: (message, meta) => console.info(`[receipt] ${message}`, meta),
  warn: (message, meta) => console.warn(`[receipt] ${message}`, meta),
};

export type ReceiptPromptInput = {
  text: string;
  projects: VoiceProjectInput[];
  entities: EntityInput[];
  currency: CurrencyCode;
  today: string;
};

export function buildReceiptPrompt(params: ReceiptPromptInput): string {
  const list = (names: string[]) => (names.length ? names.map((n) => `- ${n}`).join("\n") : "- none");
  return [
    "Extract ONE expense receipt from the text below. Return VALID JSON only, matching the schema.",
    "",
    "Rules:",
    "1. Extract exactly one receipt: one title and its line items. If the text clearly holds more than " +
      "one receipt, set multipleReceiptsSuspected to true and extract only the first.",
    "2. Word and line order are free. Pair every amount with the item it belongs to, whether the amount " +
      "comes before the name (\"100 جنيه حنفية\") or after it (\"حنفية بـ 100\").",
    "3. Title: drop leading document words (فاتورة, بون, وصل, إيصال, حساب, invoice, receipt). KEEP numbers " +
      "that qualify the title, such as \"شهر 10\", \"دور 3\", \"شقة 5\"; they are never item amounts.",
    "4. Currency words (جنيه, ج, ج.م, EGP, دولار) are currency, never part of an item name.",
    "5. Understand Western digits, Arabic-Indic digits (١٠٠) and spoken Egyptian Arabic numbers " +
      "(\"مية وخمسين\" = 150, \"ألف وميتين\" = 1200).",
    "6. A grand total stated by the user (الإجمالي, المجموع, الكل) goes to statedTotal, NOT to an item.",
    "7. Only fill project, supplier, category, date or payment status when the text mentions them. Never " +
      "guess. Project and supplier names must come from the lists below, or be null.",
    "8. Ignore chatter (greetings, \"تمام يا باشا\", phone numbers).",
    "9. Do not translate. Keep item names and the title in the source language.",
    "10. Unknown means null. Never invent items or amounts. Set uncertain=true on an item you are unsure of.",
    "11. A count before or after an item name is its quantity, and the stated amount is the line total: " +
      "\"2 حنفية بـ 200\" → name \"حنفية\", quantity 2, amount 200. Never multiply.",
    "",
    `Allowed categories: ${RECEIPT_CATEGORIES.join(", ")}`,
    `Default currency: ${params.currency}`,
    `Today: ${params.today} (resolve relative dates like "امبارح" against it; date format YYYY-MM-DD)`,
    "Payment status words: مدفوع/خالص = paid, باقي/جزء = partial, آجل/لسه = unpaid.",
    "",
    "Original text:",
    params.text,
    "",
    "Normalized text:",
    normalizeTranscript(params.text),
    "",
    "Project names:",
    list(params.projects.map((p) => p.name)),
    "",
    "Supplier names:",
    list(params.entities.map((e) => e.name)),
  ].join("\n");
}

const nullable = (type: string) => ({type: [type, "null"]});

export function receiptJsonSchema(): Record<string, unknown> {
  return {
    type: "object",
    additionalProperties: false,
    required: ["title", "items", "matchedProjectName", "category", "supplierName",
      "date", "paymentStatus", "currency", "statedTotal", "multipleReceiptsSuspected"],
    properties: {
      title: nullable("string"),
      items: {
        type: "array",
        items: {
          type: "object",
          additionalProperties: false,
          required: ["name", "amount", "quantity", "currency", "uncertain"],
          properties: {
            name: nullable("string"),
            amount: nullable("number"),
            quantity: nullable("number"),
            currency: {...nullable("string"), enum: [...CURRENCIES, null]},
            uncertain: {type: "boolean"},
          },
        },
      },
      matchedProjectName: nullable("string"),
      category: {...nullable("string"), enum: [...RECEIPT_CATEGORIES, null]},
      supplierName: nullable("string"),
      date: nullable("string"),
      paymentStatus: {...nullable("string"), enum: [...PAYMENT_STATUSES, null]},
      currency: {...nullable("string"), enum: [...CURRENCIES, null]},
      statedTotal: nullable("number"),
      multipleReceiptsSuspected: {type: "boolean"},
    },
  };
}

const round2 = (value: number) => Math.round(value * 100) / 100;

function positiveOrNull(value: unknown): number | null {
  if (value === null || value === undefined || value === "" || typeof value === "boolean") {
    return null;
  }
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? round2(n) : null;
}

function textOrNull(value: unknown, max: number): string | null {
  const text = `${value ?? ""}`.replace(/\s+/g, " ").trim();
  return text ? text.slice(0, max) : null;
}

function asCurrency(value: unknown): CurrencyCode | null {
  const code = `${value ?? ""}`.trim().toUpperCase();
  return (CURRENCIES as string[]).includes(code) ? (code as CurrencyCode) : null;
}

/** Valid YYYY-MM-DD no more than one day after `today`. */
function validDate(value: unknown, today: string): string | null {
  const raw = `${value ?? ""}`.trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(raw)) {
    return null;
  }
  const time = Date.parse(`${raw}T00:00:00Z`);
  const todayTime = Date.parse(`${today}T00:00:00Z`);
  if (!Number.isFinite(time) || new Date(time).toISOString().slice(0, 10) !== raw) {
    return null;
  }
  return Number.isFinite(todayTime) && time - todayTime > DAY_MS ? null : raw;
}

function postProcess(
  json: Record<string, unknown>,
  params: ReceiptPromptInput,
): ExpenseProposal {
  const currency = asCurrency(json.currency) ?? params.currency;
  const rawItems = Array.isArray(json.items) ? json.items : [];
  const items: ProposalItem[] = rawItems.slice(0, MAX_ITEMS).map((entry) => {
    const item = entry && typeof entry === "object" ? (entry as Record<string, unknown>) : {};
    const name = textOrNull(item.name, 120);
    const amount = positiveOrNull(item.amount);
    const itemCurrency = asCurrency(item.currency);
    const needsReview = item.uncertain === true || name === null || amount === null ||
      (itemCurrency !== null && itemCurrency !== currency);
    return {name, amount, quantity: positiveOrNull(item.quantity), needsReview};
  });
  const sumPiastres = items.reduce((sum, i) => sum + Math.round((i.amount ?? 0) * 100), 0);
  const statedTotal = positiveOrNull(json.statedTotal);
  const project = mapLlmProjectNameToProvided({
    matchedProjectName: textOrNull(json.matchedProjectName, 200),
    projects: params.projects,
  });
  const entity = matchEntityName(textOrNull(json.supplierName, 200), params.entities);
  const category = `${json.category ?? ""}`.trim().toLowerCase();
  const payment = `${json.paymentStatus ?? ""}`.trim().toLowerCase();
  return {
    title: textOrNull(json.title, MAX_TITLE),
    items,
    projectId: project.projectId,
    projectName: project.projectName,
    category: RECEIPT_CATEGORIES.includes(category) ? category : null,
    entityId: entity.entityId,
    entityName: entity.entityName,
    date: validDate(json.date, params.today),
    paymentStatus: (PAYMENT_STATUSES as string[]).includes(payment) ? (payment as ProposalPaymentStatus) : null,
    currency,
    statedTotal,
    totalMismatch: statedTotal !== null && Math.round(statedTotal * 100) !== sumPiastres,
    multipleReceiptsSuspected: json.multipleReceiptsSuspected === true || rawItems.length > MAX_ITEMS,
  };
}

/** Today's single-amount rules result as a one-row proposal, every row flagged for review. */
function rulesFallback(params: ReceiptPromptInput): ExpenseProposal {
  const rules = extractExpenseByRules({
    transcript: params.text,
    projects: params.projects,
    currency: params.currency,
  });
  const amount = positiveOrNull(rules.parsed.amount);
  const category = rules.parsed.category ?? "";
  return {
    title: null,
    items: amount === null ? [] : [{name: textOrNull(rules.parsed.note, 120), amount, quantity: null, needsReview: true}],
    projectId: rules.parsed.matchedProjectId,
    projectName: rules.parsed.matchedProjectName,
    category: RECEIPT_CATEGORIES.includes(category) ? category : null,
    entityId: null,
    entityName: null,
    date: null,
    paymentStatus: null,
    currency: rules.parsed.currency ?? params.currency,
    statedTotal: null,
    totalMismatch: false,
    multipleReceiptsSuspected: false,
  };
}

export type ExtractReceiptParams = ReceiptPromptInput & {
  openRouterApiKey: string;
  model: string;
  timeoutMs?: number;
  fetchImpl?: typeof fetch;
  logger?: ReceiptLogger;
};

async function callLlm(params: ExtractReceiptParams): Promise<Record<string, unknown>> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), params.timeoutMs ?? 20_000);
  try {
    const response = await (params.fetchImpl ?? fetch)("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST",
      signal: controller.signal,
      headers: {
        "Authorization": `Bearer ${params.openRouterApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: params.model,
        temperature: 0.1,
        response_format: {
          type: "json_schema",
          json_schema: {name: "receipt_extraction", strict: true, schema: receiptJsonSchema()},
        },
        messages: [
          {
            role: "system",
            content: "You are an information extraction engine for construction expense receipts. " +
              "Return JSON only. Do not translate user content.",
          },
          {role: "user", content: buildReceiptPrompt(params)},
        ],
      }),
    });
    if (!response.ok) {
      throw new Error(`http_${response.status}`);
    }
    const payload = await response.json() as {choices?: Array<{message?: {content?: unknown}}>};
    const content = payload.choices?.[0]?.message?.content;
    const json = safeJsonParse(typeof content === "string" ? content : JSON.stringify(content ?? ""));
    if (!json) {
      throw new Error("malformed_json");
    }
    return json;
  } catch (error) {
    if (controller.signal.aborted) {
      throw new Error("timeout");
    }
    throw error;
  } finally {
    clearTimeout(timer);
  }
}

export async function extractReceipt(
  params: ExtractReceiptParams,
): Promise<{proposal: ExpenseProposal; source: ExtractionSource}> {
  const logger = params.logger ?? consoleLogger;
  const started = Date.now();
  try {
    const proposal = postProcess(await callLlm(params), params);
    logger.info("extracted", {
      model: params.model, latencyMs: Date.now() - started, itemCount: proposal.items.length, source: "llm",
    });
    return {proposal, source: "llm"};
  } catch (error) {
    const proposal = rulesFallback(params);
    // Only a short reason code is logged, never the raw text (same policy as the transcript).
    const reason = error instanceof Error ? error.message.slice(0, 40) : "unknown";
    logger.warn("fell back to rules", {
      model: params.model, latencyMs: Date.now() - started, itemCount: proposal.items.length,
      source: "rules", fallbackReason: /^[a-z_0-9 ]+$/i.test(reason) ? reason : "error",
    });
    return {proposal, source: "rules"};
  }
}
