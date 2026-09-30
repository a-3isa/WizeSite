"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.processVoiceExpenseHttp = exports.processVoiceExpense = exports.openRouterTranscriptionModelSecret = exports.openRouterModelSecret = exports.openRouterApiKeySecret = void 0;
exports.verifyVoiceHttpAppCheck = verifyVoiceHttpAppCheck;
const app_check_1 = require("firebase-admin/app-check");
const auth_1 = require("firebase-admin/auth");
const firestore_1 = require("firebase-admin/firestore");
const params_1 = require("firebase-functions/params");
const https_1 = require("firebase-functions/v2/https");
const http_cors_1 = require("../http_cors");
const transcription_service_1 = require("./services/transcription.service");
const expense_parser_service_1 = require("./services/expense_parser.service");
exports.openRouterApiKeySecret = (0, params_1.defineSecret)("OPENROUTER_API_KEY");
exports.openRouterModelSecret = (0, params_1.defineSecret)("OPENROUTER_MODEL");
exports.openRouterTranscriptionModelSecret = (0, params_1.defineSecret)("OPENROUTER_TRANSCRIPTION_MODEL");
const DEFAULT_OPENROUTER_TRANSCRIPTION_MODEL = "openai/gpt-audio-mini";
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
function payloadFrom(input) {
    if (!input || typeof input !== "object") {
        return {};
    }
    return input;
}
function bearerTokenFrom(authorizationHeader) {
    if (!authorizationHeader) {
        return null;
    }
    const match = authorizationHeader.match(/^Bearer\s+(.+)$/i);
    return match ? match[1] : null;
}
function httpStatusFor(code) {
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
function canonicalCode(code) {
    return code.replace(/-/g, "_").toUpperCase();
}
async function verifyVoiceHttpAppCheck(appCheckToken, verifyToken = (token) => (0, app_check_1.getAppCheck)().verifyToken(token)) {
    if (!appCheckToken) {
        throw new https_1.HttpsError("failed-precondition", "Missing App Check token");
    }
    try {
        await verifyToken(appCheckToken);
    }
    catch (error) {
        throw new https_1.HttpsError("failed-precondition", "Invalid App Check token");
    }
}
async function loadWorkspaceProjectsForUser(uid) {
    const db = (0, firestore_1.getFirestore)();
    const userSnap = await db.collection("users").doc(uid).get();
    const workspaceId = `${userSnap.data()?.workspaceId ?? ""}`.trim();
    if (!workspaceId) {
        return [];
    }
    const snap = await db
        .collection("projects")
        .where("workspaceId", "==", workspaceId)
        .where("isArchived", "==", false)
        .limit(100)
        .get();
    return snap.docs
        .map((doc) => {
        const name = `${doc.data().name ?? ""}`.trim();
        if (!name) {
            return null;
        }
        return { id: doc.id, name };
    })
        .filter((item) => item != null);
}
async function processVoiceExpenseForUser(uid, payload) {
    const storagePath = `${payload.storagePath ?? ""}`.trim();
    if (!storagePath) {
        throw new https_1.HttpsError("invalid-argument", "storagePath is required");
    }
    assertVoicePathOwnedByUser(storagePath, uid);
    const projects = await loadWorkspaceProjectsForUser(uid);
    const currency = parseCurrency(payload.currency);
    const languageHint = parseLanguageHint(payload.languageHint);
    const openRouterApiKey = exports.openRouterApiKeySecret.value() || process.env.OPENROUTER_API_KEY || "";
    if (!openRouterApiKey) {
        throw new https_1.HttpsError("failed-precondition", "OPENROUTER_API_KEY is not configured");
    }
    let transcript = "";
    try {
        transcript = await (0, transcription_service_1.transcribeAudioFromStorage)({
            storagePath,
            openRouterApiKey,
            model: (exports.openRouterTranscriptionModelSecret.value() ||
                process.env.OPENROUTER_TRANSCRIPTION_MODEL ||
                DEFAULT_OPENROUTER_TRANSCRIPTION_MODEL).replace(/^﻿|\r?\n/g, "").trim(),
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
}
exports.processVoiceExpense = (0, https_1.onCall)({
    enforceAppCheck: true,
    timeoutSeconds: 120,
    memory: "1GiB",
    secrets: [
        exports.openRouterApiKeySecret,
        exports.openRouterModelSecret,
        exports.openRouterTranscriptionModelSecret,
    ],
}, async (request) => {
    if (!request.auth?.uid) {
        throw new https_1.HttpsError("unauthenticated", "Authentication required");
    }
    const payload = payloadFrom(request.data);
    return processVoiceExpenseForUser(request.auth.uid, payload);
});
exports.processVoiceExpenseHttp = (0, https_1.onRequest)({
    timeoutSeconds: 120,
    memory: "1GiB",
    secrets: [
        exports.openRouterApiKeySecret,
        exports.openRouterModelSecret,
        exports.openRouterTranscriptionModelSecret,
    ],
}, async (request, response) => {
    if ((0, http_cors_1.applyCorsHeaders)(request, response)) {
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
        await verifyVoiceHttpAppCheck(request.header("X-Firebase-AppCheck") ?? undefined);
        const bearerToken = bearerTokenFrom(request.header("Authorization") ?? undefined);
        if (!bearerToken) {
            throw new https_1.HttpsError("unauthenticated", "Authentication required");
        }
        const decodedToken = await (0, auth_1.getAuth)().verifyIdToken(bearerToken);
        const body = payloadFrom(request.body);
        const payload = Object.keys(payloadFrom(body.data)).length > 0 ?
            payloadFrom(body.data) :
            body;
        const result = await processVoiceExpenseForUser(decodedToken.uid, payload);
        response.status(200).json({ result });
    }
    catch (error) {
        const handled = error instanceof https_1.HttpsError ?
            error :
            new https_1.HttpsError("internal", "Failed to process voice expense");
        response.status(httpStatusFor(handled.code)).json({
            error: {
                code: handled.code,
                status: canonicalCode(handled.code),
                message: handled.message,
            },
        });
    }
});
//# sourceMappingURL=process_voice_expense.js.map