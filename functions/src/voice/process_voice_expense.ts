import * as admin from "firebase-admin";
import {defineSecret} from "firebase-functions/params";
import {HttpsError, onCall, onRequest} from "firebase-functions/v2/https";
import {CurrencyCode, ProcessVoiceExpenseResponse, VoiceProjectInput} from "./types/expense";
import {transcribeAudioFromStorage} from "./services/transcription.service";
import {parseExpenseFromTranscript} from "./services/expense_parser.service";

export const openRouterApiKeySecret = defineSecret("OPENROUTER_API_KEY");
export const openRouterModelSecret = defineSecret("OPENROUTER_MODEL");
export const openRouterTranscriptionModelSecret = defineSecret("OPENROUTER_TRANSCRIPTION_MODEL");

const DEFAULT_OPENROUTER_TRANSCRIPTION_MODEL = "openai/gpt-audio-mini";

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

type VoiceExpensePayload = Record<string, unknown>;

function payloadFrom(input: unknown): VoiceExpensePayload {
  if (!input || typeof input !== "object") {
    return {};
  }
  return input as VoiceExpensePayload;
}

function bearerTokenFrom(authorizationHeader: string | undefined): string | null {
  if (!authorizationHeader) {
    return null;
  }
  const match = authorizationHeader.match(/^Bearer\s+(.+)$/i);
  return match ? match[1] : null;
}

function httpStatusFor(code: string): number {
  switch (code) {
  case "invalid-argument":
    return 400;
  case "unauthenticated":
    return 401;
  case "permission-denied":
    return 403;
  case "not-found":
    return 404;
  case "already-exists":
    return 409;
  case "failed-precondition":
    return 412;
  case "resource-exhausted":
    return 429;
  default:
    return 500;
  }
}

function canonicalCode(code: string): string {
  return code.replace(/-/g, "_").toUpperCase();
}

async function maybeVerifyAppCheck(appCheckToken: string | undefined): Promise<void> {
  if (!appCheckToken) {
    return;
  }

  try {
    await admin.appCheck().verifyToken(appCheckToken);
  } catch (error) {
    console.warn("Voice HTTP endpoint received an invalid App Check token", error);
  }
}

async function processVoiceExpenseForUser(
  uid: string,
  payload: VoiceExpensePayload,
): Promise<ProcessVoiceExpenseResponse> {
  const storagePath = `${payload.storagePath ?? ""}`.trim();
  if (!storagePath) {
    throw new HttpsError("invalid-argument", "storagePath is required");
  }

  assertVoicePathOwnedByUser(storagePath, uid);

  const projects = parseProjects(payload.projects);
  const currency = parseCurrency(payload.currency);
  const languageHint = parseLanguageHint(payload.languageHint);

  const openRouterApiKey = openRouterApiKeySecret.value() || process.env.OPENROUTER_API_KEY || "";
  if (!openRouterApiKey) {
    throw new HttpsError("failed-precondition", "OPENROUTER_API_KEY is not configured");
  }

  let transcript = "";
  try {
    transcript = await transcribeAudioFromStorage({
      storagePath,
      openRouterApiKey,
      model:
        openRouterTranscriptionModelSecret.value() ||
        process.env.OPENROUTER_TRANSCRIPTION_MODEL ||
        DEFAULT_OPENROUTER_TRANSCRIPTION_MODEL,
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
}

export const processVoiceExpense = onCall(
  {
    timeoutSeconds: 120,
    memory: "1GiB",
    secrets: [
      openRouterApiKeySecret,
      openRouterModelSecret,
      openRouterTranscriptionModelSecret,
    ],
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Authentication required");
    }
    const payload = payloadFrom(request.data);
    return processVoiceExpenseForUser(request.auth.uid, payload);
  },
);

export const processVoiceExpenseHttp = onRequest(
  {
    timeoutSeconds: 120,
    memory: "1GiB",
    secrets: [
      openRouterApiKeySecret,
      openRouterModelSecret,
      openRouterTranscriptionModelSecret,
    ],
  },
  async (request, response) => {
    response.set("Access-Control-Allow-Origin", "*");
    response.set(
      "Access-Control-Allow-Headers",
      "Content-Type, Authorization, X-Firebase-AppCheck",
    );

    if (request.method === "OPTIONS") {
      response.status(204).send("");
      return;
    }

    if (request.method !== "POST") {
      response.status(405).json({
        error: {
          code: "method-not-allowed",
          status: "METHOD_NOT_ALLOWED",
          message: "Method not allowed",
        },
      });
      return;
    }

    try {
      await maybeVerifyAppCheck(request.header("X-Firebase-AppCheck") ?? undefined);

      const bearerToken = bearerTokenFrom(request.header("Authorization") ?? undefined);
      if (!bearerToken) {
        throw new HttpsError("unauthenticated", "Authentication required");
      }

      const decodedToken = await admin.auth().verifyIdToken(bearerToken);
      const body = payloadFrom(request.body);
      const payload = Object.keys(payloadFrom(body.data)).length > 0 ?
        payloadFrom(body.data) :
        body;

      const result = await processVoiceExpenseForUser(decodedToken.uid, payload);
      response.status(200).json({result});
    } catch (error) {
      const handled = error instanceof HttpsError ?
        error :
        new HttpsError("internal", "Failed to process voice expense");
      response.status(httpStatusFor(handled.code)).json({
        error: {
          code: handled.code,
          status: canonicalCode(handled.code),
          message: handled.message,
        },
      });
    }
  },
);
