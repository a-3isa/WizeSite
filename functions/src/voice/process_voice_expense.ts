import {defineSecret} from "firebase-functions/params";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {CurrencyCode, ProcessVoiceExpenseResponse, VoiceProjectInput} from "./types/expense";
import {transcribeAudioFromStorage} from "./services/transcription.service";
import {parseExpenseFromTranscript} from "./services/expense_parser.service";

export const openAiApiKeySecret = defineSecret("OPENAI_API_KEY");
export const openRouterApiKeySecret = defineSecret("OPENROUTER_API_KEY");
export const openRouterModelSecret = defineSecret("OPENROUTER_MODEL");

function parseProjects(input: unknown): VoiceProjectInput[] {
  if (!Array.isArray(input)) {
    return [];
  }
  return input
    .map((item) => {
      if (!item || typeof item !== "object") {
        return null;
      }
      const candidate = item as Record<string, unknown>;
      const id = `${candidate.id ?? ""}`.trim();
      const name = `${candidate.name ?? ""}`.trim();
      if (!id || !name) {
        return null;
      }
      return {id, name};
    })
    .filter((item): item is VoiceProjectInput => item != null);
}

function parseCurrency(input: unknown): CurrencyCode {
  const value = `${input ?? ""}`.trim().toUpperCase();
  if (value === "EGP" || value === "USD" || value === "SAR" || value === "AED") {
    return value;
  }
  return "EGP";
}

function parseLanguageHint(input: unknown): string | null {
  const value = `${input ?? ""}`.trim().toLowerCase();
  if (!value) {
    return null;
  }
  if (/^[a-z]{2,5}(-[a-z]{2,5})?$/i.test(value)) {
    return value.split("-")[0];
  }
  return null;
}

function assertVoicePathOwnedByUser(storagePath: string, uid: string): void {
  const expectedPrefix = `voice-expenses/${uid}/`;
  if (!storagePath.startsWith(expectedPrefix)) {
    throw new HttpsError("permission-denied", "storagePath is not owned by current user");
  }
}

function emptyResult(storagePath: string): ProcessVoiceExpenseResponse {
  return {
    transcript: "",
    parsed: {
      amount: null,
      currency: null,
      category: null,
      matchedProjectId: null,
      matchedProjectName: null,
      note: null,
    },
    confidence: {
      amount: 0,
      category: 0,
      project: 0,
      overall: 0,
    },
    source: "rules",
    needsConfirmation: true,
    storagePath,
  };
}

export const processVoiceExpense = onCall(
  {
    timeoutSeconds: 120,
    memory: "1GiB",
    secrets: [openAiApiKeySecret, openRouterApiKeySecret, openRouterModelSecret],
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Authentication required");
    }
    const payload = (request.data ?? {}) as Record<string, unknown>;
    const storagePath = `${payload.storagePath ?? ""}`.trim();
    if (!storagePath) {
      throw new HttpsError("invalid-argument", "storagePath is required");
    }

    assertVoicePathOwnedByUser(storagePath, request.auth.uid);

    const projects = parseProjects(payload.projects);
    const currency = parseCurrency(payload.currency);
    const languageHint = parseLanguageHint(payload.languageHint);

    const openAiApiKey = openAiApiKeySecret.value() || process.env.OPENAI_API_KEY || "";
    if (!openAiApiKey) {
      throw new HttpsError("failed-precondition", "OPENAI_API_KEY is not configured");
    }

    let transcript = "";
    try {
      transcript = await transcribeAudioFromStorage({
        storagePath,
        openAiApiKey,
        languageHint,
      });
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError("internal", "Failed to transcribe voice expense");
    }

    if (!transcript.trim()) {
      return emptyResult(storagePath);
    }

    const openRouterApiKey = openRouterApiKeySecret.value() || process.env.OPENROUTER_API_KEY || "";
    const openRouterModel =
      openRouterModelSecret.value() ||
      process.env.OPENROUTER_MODEL ||
      "openai/gpt-4o-mini";

    return parseExpenseFromTranscript({
      transcript,
      projects,
      currency,
      storagePath,
      openRouterApiKey,
      openRouterModel,
    });
  },
);

