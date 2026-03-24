"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.transcribeAudioFromStorage = transcribeAudioFromStorage;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const MAX_AUDIO_BYTES = 25 * 1024 * 1024;
const ALLOWED_EXTENSIONS = new Set([".m4a", ".mp3", ".wav", ".webm", ".aac", ".mp4"]);
const TRANSCRIPTION_PROMPT = "You are a strict speech-to-text transcription engine for construction expense notes. " +
    "Transcribe the speech exactly as spoken. " +
    "Do not translate. Do not summarize. Do not explain. Do not normalize into another language. " +
    "Preserve the original spoken language and script exactly. " +
    "If the speaker uses Arabic, return Arabic. If the speaker uses English, return English. " +
    "If the speaker mixes Arabic and English, preserve the mixed-language transcript. " +
    "Preserve numbers, currency words, and project names exactly as spoken. " +
    "Return only the raw transcript text with no intro, no quotes, and no extra commentary.";
function extensionOf(path) {
    const index = path.lastIndexOf(".");
    if (index < 0) {
        return "";
    }
    return path.slice(index).toLowerCase();
}
function assertSupportedAudioPath(storagePath) {
    const ext = extensionOf(storagePath);
    if (!ALLOWED_EXTENSIONS.has(ext)) {
        throw new https_1.HttpsError("invalid-argument", "Unsupported audio file type");
    }
}
function audioFormatOf(storagePath) {
    switch (extensionOf(storagePath)) {
        case ".m4a":
        case ".mp4":
            return "m4a";
        case ".mp3":
            return "mp3";
        case ".wav":
            return "wav";
        case ".webm":
            return "webm";
        case ".aac":
            return "aac";
        default:
            return "m4a";
    }
}
function readResponseText(payload) {
    if (!payload || typeof payload !== "object") {
        return "";
    }
    const directText = payload.text;
    if (typeof directText === "string") {
        return directText.trim();
    }
    const choices = payload.choices;
    if (!Array.isArray(choices) || choices.length == 0) {
        return "";
    }
    const firstChoice = choices[0];
    if (!firstChoice || typeof firstChoice !== "object") {
        return "";
    }
    const message = firstChoice.message;
    if (!message || typeof message !== "object") {
        return "";
    }
    const content = message.content;
    if (typeof content === "string") {
        return content.trim();
    }
    if (Array.isArray(content)) {
        const merged = content
            .map((part) => {
            if (typeof part === "string") {
                return part;
            }
            if (!part || typeof part !== "object") {
                return "";
            }
            const candidate = part.text;
            return typeof candidate === "string" ? candidate : "";
        })
            .join("\n")
            .trim();
        if (merged) {
            return merged;
        }
    }
    return "";
}
function cleanupTranscript(text) {
    let normalized = text.trim();
    if (!normalized) {
        return "";
    }
    normalized = normalized.replace(/\r\n/g, "\n");
    // Strip common assistant-style wrappers if the model still adds them.
    normalized = normalized.replace(/^(sure|certainly|here(?:'s| is)|below is|the transcription(?: of the voice note)? is)[:,]?\s*/i, "");
    normalized = normalized.replace(/^(?:sure,\s*)?here is the transcription(?: of the voice note)?[:\s]*/i, "");
    const quotedMatch = normalized.match(/^["'](.*)["']$/s);
    if (quotedMatch?.[1]) {
        normalized = quotedMatch[1].trim();
    }
    return normalized.trim();
}
function readProviderErrorMessage(payload) {
    if (!payload || typeof payload !== "object") {
        return "";
    }
    const error = payload.error;
    if (!error || typeof error !== "object") {
        return "";
    }
    const message = error.message;
    return typeof message === "string" ? message.trim() : "";
}
function transcriptionFailureForStatus(status, providerMessage) {
    switch (status) {
        case 401:
        case 403:
            return new https_1.HttpsError("failed-precondition", "Voice transcription is not configured correctly. Please check the OpenRouter API key and billing setup.");
        case 429:
            return new https_1.HttpsError("resource-exhausted", "Voice transcription quota has been exceeded. Please top up or enable billing for the OpenRouter API key.");
        case 500:
        case 502:
        case 503:
        case 504:
            return new https_1.HttpsError("unavailable", "Voice transcription is temporarily unavailable. Please try again in a moment.");
        default:
            if (providerMessage) {
                return new https_1.HttpsError("internal", `Voice transcription failed: ${providerMessage}`);
            }
            return new https_1.HttpsError("internal", "Voice transcription failed");
    }
}
async function transcribeAudioFromStorage(params) {
    const storagePath = params.storagePath.trim();
    if (!storagePath) {
        throw new https_1.HttpsError("invalid-argument", "storagePath is required");
    }
    assertSupportedAudioPath(storagePath);
    const bucket = admin.storage().bucket();
    const file = bucket.file(storagePath);
    const [exists] = await file.exists();
    if (!exists) {
        throw new https_1.HttpsError("not-found", "Voice file was not found in Firebase Storage");
    }
    const [buffer] = await file.download();
    if (!buffer || buffer.length === 0) {
        throw new https_1.HttpsError("failed-precondition", "Audio file is empty");
    }
    if (buffer.length > MAX_AUDIO_BYTES) {
        throw new https_1.HttpsError("invalid-argument", "Audio file is too large");
    }
    const base64Audio = buffer.toString("base64");
    const audioFormat = audioFormatOf(storagePath);
    const transcriptionInstruction = params.languageHint && params.languageHint.trim().length > 0 ?
        `${TRANSCRIPTION_PROMPT} The likely spoken language code is ${params.languageHint.trim()}. Keep the transcript in that original spoken language unless the audio is clearly mixed.` :
        TRANSCRIPTION_PROMPT;
    let response;
    try {
        response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
            method: "POST",
            headers: {
                Authorization: `Bearer ${params.openRouterApiKey}`,
                "Content-Type": "application/json",
            },
            body: JSON.stringify({
                model: params.model,
                temperature: 0,
                messages: [
                    {
                        role: "system",
                        content: TRANSCRIPTION_PROMPT,
                    },
                    {
                        role: "user",
                        content: [
                            {
                                type: "text",
                                text: transcriptionInstruction,
                            },
                            {
                                type: "input_audio",
                                input_audio: {
                                    data: base64Audio,
                                    format: audioFormat,
                                },
                            },
                        ],
                    },
                ],
            }),
        });
    }
    catch (_error) {
        throw new https_1.HttpsError("internal", "Failed to reach transcription provider");
    }
    if (!response.ok) {
        const bodyText = await response.text();
        let providerMessage = "";
        try {
            providerMessage = readProviderErrorMessage(JSON.parse(bodyText));
        }
        catch {
            providerMessage = bodyText.trim().slice(0, 180);
        }
        throw transcriptionFailureForStatus(response.status, providerMessage);
    }
    const payload = await response.json();
    const transcript = cleanupTranscript(readResponseText(payload));
    if (!transcript) {
        throw new https_1.HttpsError("failed-precondition", "Transcription was empty");
    }
    return transcript;
}
//# sourceMappingURL=transcription.service.js.map