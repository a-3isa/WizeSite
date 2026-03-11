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
const TRANSCRIPTION_PROMPT = "Transcribe this construction-site expense voice note accurately. " +
    "The language may be Arabic, English, or mixed Arabic-English. " +
    "Expect vocabulary related to labor, materials, equipment, transport, contractors, workers, projects, and expenses. " +
    "Preserve numbers and project names exactly.";
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
function readResponseText(payload) {
    if (payload && typeof payload === "object") {
        const candidate = payload.text;
        if (typeof candidate === "string") {
            return candidate.trim();
        }
    }
    return "";
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
    const form = new FormData();
    form.append("model", "whisper-1");
    form.append("prompt", TRANSCRIPTION_PROMPT);
    if (params.languageHint && params.languageHint.trim().length > 0) {
        form.append("language", params.languageHint.trim());
    }
    const filename = storagePath.split("/").pop() ?? "voice-note.m4a";
    const bytes = new Uint8Array(buffer);
    const blob = new Blob([bytes], { type: "audio/mp4" });
    form.append("file", blob, filename);
    let response;
    try {
        response = await fetch("https://api.openai.com/v1/audio/transcriptions", {
            method: "POST",
            headers: {
                Authorization: `Bearer ${params.openAiApiKey}`,
            },
            body: form,
        });
    }
    catch (_error) {
        throw new https_1.HttpsError("internal", "Failed to reach transcription provider");
    }
    if (!response.ok) {
        const bodyText = await response.text();
        throw new https_1.HttpsError("internal", `Transcription failed (${response.status}): ${bodyText.slice(0, 180)}`);
    }
    const payload = await response.json();
    const transcript = readResponseText(payload);
    if (!transcript) {
        throw new https_1.HttpsError("failed-precondition", "Transcription was empty");
    }
    return transcript;
}
//# sourceMappingURL=transcription.service.js.map