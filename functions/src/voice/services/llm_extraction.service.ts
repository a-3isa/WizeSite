import {HttpsError} from "firebase-functions/v2/https";
import {
  CurrencyCode,
  ExpenseCategory,
  LlmExtractionResult,
  VoiceProjectInput,
} from "../types/expense";
import {normalizeTranscript} from "../utils/arabicNormalize";

const ALLOWED_CATEGORIES: ExpenseCategory[] = [
  "labor",
  "materials",
  "equipment",
  "transport",
  "other",
];

function safeJsonParse(input: string): Record<string, unknown> | null {
  const raw = input.trim();
  if (!raw) {
    return null;
  }

  const markdownMatch = raw.match(/```(?:json)?\s*([\s\S]*?)\s*```/i);
  const candidate = markdownMatch?.[1] ?? raw;
  try {
    const parsed = JSON.parse(candidate);
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
      return parsed as Record<string, unknown>;
    }
    return null;
  } catch {
    return null;
  }
}

function asCurrency(value: unknown, fallback: CurrencyCode): CurrencyCode {
  const normalized = `${value ?? ""}`.trim().toUpperCase();
  if (normalized === "EGP" || normalized === "USD" || normalized === "SAR" || normalized === "AED") {
    return normalized;
  }
  return fallback;
}

function asCategory(value: unknown): ExpenseCategory | null {
  const normalized = `${value ?? ""}`.trim().toLowerCase();
  if (ALLOWED_CATEGORIES.includes(normalized as ExpenseCategory)) {
    return normalized as ExpenseCategory;
  }
  return null;
}

function asAmount(value: unknown): number | null {
  if (value == null || value === "") {
    return null;
  }
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return null;
  }
  return parsed;
}

function asShortNote(value: unknown): string | null {
  const text = `${value ?? ""}`.trim();
  if (!text) {
    return null;
  }
  if (text.length <= 120) {
    return text;
  }
  return `${text.slice(0, 117).trim()}...`;
}

function buildPrompt(params: {
  transcriptOriginal: string;
  transcriptNormalized: string;
  projects: VoiceProjectInput[];
  defaultCurrency: CurrencyCode;
}): string {
  const projectsList = params.projects.map((p) => `- ${p.name}`).join("\n");
  return [
    "Extract exactly one expense from the transcript.",
    "Return VALID JSON only. No prose.",
    "Do not invent project names outside the provided list.",
    "If unknown set value to null.",
    "Allowed categories: labor, materials, equipment, transport, other.",
    `Default currency: ${params.defaultCurrency}`,
    "",
    "Original transcript:",
    params.transcriptOriginal,
    "",
    "Normalized transcript:",
    params.transcriptNormalized,
    "",
    "Available project names:",
    projectsList || "- none",
    "",
    "JSON schema:",
    "{",
    '  "amount": number | null,',
    '  "currency": "EGP" | "USD" | "SAR" | "AED" | null,',
    '  "category": "labor" | "materials" | "equipment" | "transport" | "other" | null,',
    '  "matchedProjectName": string | null,',
    '  "note": string | null',
    "}",
  ].join("\n");
}

export async function extractExpenseByLlm(params: {
  openRouterApiKey: string;
  model: string;
  transcriptOriginal: string;
  transcriptNormalized: string;
  projects: VoiceProjectInput[];
  defaultCurrency: CurrencyCode;
  timeoutMs?: number;
}): Promise<LlmExtractionResult> {
  const prompt = buildPrompt(params);
  const timeoutMs = params.timeoutMs ?? 15000;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST",
      signal: controller.signal,
      headers: {
        Authorization: `Bearer ${params.openRouterApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: params.model,
        temperature: 0.1,
        response_format: {
          type: "json_schema",
          json_schema: {
            name: "voice_expense_extraction",
            strict: true,
            schema: {
              type: "object",
              additionalProperties: false,
              properties: {
                amount: {type: ["number", "null"]},
                currency: {
                  type: ["string", "null"],
                  enum: ["EGP", "USD", "SAR", "AED", null],
                },
                category: {
                  type: ["string", "null"],
                  enum: ["labor", "materials", "equipment", "transport", "other", null],
                },
                matchedProjectName: {type: ["string", "null"]},
                note: {type: ["string", "null"]},
              },
              required: ["amount", "currency", "category", "matchedProjectName", "note"],
            },
          },
        },
        messages: [
          {
            role: "system",
            content: "You are an information extraction engine. Return JSON only.",
          },
          {
            role: "user",
            content: prompt,
          },
        ],
      }),
    });

    if (!response.ok) {
      const text = await response.text();
      throw new HttpsError(
        "internal",
        `LLM extraction failed (${response.status}): ${text.slice(0, 180)}`,
      );
    }

    const payload = await response.json() as Record<string, unknown>;
    const choices = payload.choices as Array<Record<string, unknown>> | undefined;
    const first = choices?.[0];
    const message = first?.message as Record<string, unknown> | undefined;
    const content = message?.content;
    const contentText = Array.isArray(content)
      ? content
        .map((part) => (typeof part === "string" ? part : JSON.stringify(part)))
        .join("\n")
      : `${content ?? ""}`;

    const json = safeJsonParse(contentText);
    if (!json) {
      throw new HttpsError("internal", "LLM returned malformed JSON");
    }

    return {
      amount: asAmount(json.amount),
      currency: asCurrency(json.currency, params.defaultCurrency),
      category: asCategory(json.category),
      matchedProjectName: `${json.matchedProjectName ?? ""}`.trim() || null,
      note: asShortNote(json.note),
    };
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    throw new HttpsError("deadline-exceeded", "LLM extraction timeout or network error");
  } finally {
    clearTimeout(timer);
  }
}

export function mapLlmProjectNameToProvided(params: {
  matchedProjectName: string | null;
  projects: VoiceProjectInput[];
}): {projectId: string | null; projectName: string | null} {
  const target = normalizeTranscript(params.matchedProjectName ?? "");
  if (!target) {
    return {projectId: null, projectName: null};
  }
  for (const project of params.projects) {
    const normalized = normalizeTranscript(project.name);
    if (normalized === target || normalized.includes(target) || target.includes(normalized)) {
      return {projectId: project.id, projectName: project.name};
    }
  }
  return {projectId: null, projectName: null};
}

