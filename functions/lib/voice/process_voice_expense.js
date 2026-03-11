"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.processVoiceExpense = exports.openRouterModelSecret = exports.openRouterApiKeySecret = exports.openAiApiKeySecret = void 0;
const params_1 = require("firebase-functions/params");
const https_1 = require("firebase-functions/v2/https");
const transcription_service_1 = require("./services/transcription.service");
const expense_parser_service_1 = require("./services/expense_parser.service");
exports.openAiApiKeySecret = (0, params_1.defineSecret)("OPENAI_API_KEY");
exports.openRouterApiKeySecret = (0, params_1.defineSecret)("OPENROUTER_API_KEY");
exports.openRouterModelSecret = (0, params_1.defineSecret)("OPENROUTER_MODEL");
function parseProjects(input) {
    if (!Array.isArray(input)) {
        return [];
    }
    return input
        .map((item) => {
        if (!item || typeof item !== "object") {
            return null;
        }
        const candidate = item;
        const id = `${candidate.id ?? ""}`.trim();
        const name = `${candidate.name ?? ""}`.trim();
        if (!id || !name) {
            return null;
        }
        return { id, name };
    })
        .filter((item) => item != null);
}
function parseCurrency(input) {
    const value = `${input ?? ""}`.trim().toUpperCase();
    if (value === "EGP" || value === "USD" || value === "SAR" || value === "AED") {
        return value;
    }
    return "EGP";
}
function parseLanguageHint(input) {
    const value = `${input ?? ""}`.trim().toLowerCase();
    if (!value) {
        return null;
    }
    if (/^[a-z]{2,5}(-[a-z]{2,5})?$/i.test(value)) {
        return value.split("-")[0];
    }
    return null;
}
function assertVoicePathOwnedByUser(storagePath, uid) {
    const expectedPrefix = `voice-expenses/${uid}/`;
    if (!storagePath.startsWith(expectedPrefix)) {
        throw new https_1.HttpsError("permission-denied", "storagePath is not owned by current user");
    }
}
function emptyResult(storagePath) {
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
exports.processVoiceExpense = (0, https_1.onCall)({
    timeoutSeconds: 120,
    memory: "1GiB",
    secrets: [exports.openAiApiKeySecret, exports.openRouterApiKeySecret, exports.openRouterModelSecret],
}, async (request) => {
    if (!request.auth?.uid) {
        throw new https_1.HttpsError("unauthenticated", "Authentication required");
    }
    const payload = (request.data ?? {});
    const storagePath = `${payload.storagePath ?? ""}`.trim();
    if (!storagePath) {
        throw new https_1.HttpsError("invalid-argument", "storagePath is required");
    }
    assertVoicePathOwnedByUser(storagePath, request.auth.uid);
    const projects = parseProjects(payload.projects);
    const currency = parseCurrency(payload.currency);
    const languageHint = parseLanguageHint(payload.languageHint);
    const openAiApiKey = exports.openAiApiKeySecret.value() || process.env.OPENAI_API_KEY || "";
    if (!openAiApiKey) {
        throw new https_1.HttpsError("failed-precondition", "OPENAI_API_KEY is not configured");
    }
    let transcript = "";
    try {
        transcript = await (0, transcription_service_1.transcribeAudioFromStorage)({
            storagePath,
            openAiApiKey,
            languageHint,
        });
    }
    catch (error) {
        if (error instanceof https_1.HttpsError) {
            throw error;
        }
        throw new https_1.HttpsError("internal", "Failed to transcribe voice expense");
    }
    if (!transcript.trim()) {
        return emptyResult(storagePath);
    }
    const openRouterApiKey = exports.openRouterApiKeySecret.value() || process.env.OPENROUTER_API_KEY || "";
    const openRouterModel = exports.openRouterModelSecret.value() ||
        process.env.OPENROUTER_MODEL ||
        "openai/gpt-4o-mini";
    return (0, expense_parser_service_1.parseExpenseFromTranscript)({
        transcript,
        projects,
        currency,
        storagePath,
        openRouterApiKey,
        openRouterModel,
    });
});
//# sourceMappingURL=process_voice_expense.js.map