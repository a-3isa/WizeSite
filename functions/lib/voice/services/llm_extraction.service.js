"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.extractExpenseByLlm = extractExpenseByLlm;
exports.mapLlmProjectNameToProvided = mapLlmProjectNameToProvided;
const https_1 = require("firebase-functions/v2/https");
const arabicNormalize_1 = require("../utils/arabicNormalize");
const ALLOWED_CATEGORIES = [
    "labor",
    "materials",
    "equipment",
    "transport",
    "other",
];
function safeJsonParse(input) {
    const raw = input.trim();
    if (!raw) {
        return null;
    }
    const markdownMatch = raw.match(/```(?:json)?\s*([\s\S]*?)\s*```/i);
    const candidate = markdownMatch?.[1] ?? raw;
    try {
        const parsed = JSON.parse(candidate);
        if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
            return parsed;
        }
        return null;
    }
    catch {
        return null;
    }
}
function asCurrency(value, fallback) {
    const normalized = `${value ?? ""}`.trim().toUpperCase();
    if (normalized === "EGP" || normalized === "USD" || normalized === "SAR" || normalized === "AED") {
        return normalized;
    }
    return fallback;
}
function asCategory(value) {
    const normalized = `${value ?? ""}`.trim().toLowerCase();
    if (ALLOWED_CATEGORIES.includes(normalized)) {
        return normalized;
    }
    return null;
}
function asAmount(value) {
    if (value == null || value === "") {
        return null;
    }
    const parsed = Number(value);
    if (!Number.isFinite(parsed) || parsed <= 0) {
        return null;
    }
    return parsed;
}
function asShortNote(value) {
    const text = `${value ?? ""}`.trim();
    if (!text) {
        return null;
    }
    if (text.length <= 120) {
        return text;
    }
    return `${text.slice(0, 117).trim()}...`;
}
function buildPrompt(params) {
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
async function extractExpenseByLlm(params) {
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
                                amount: { type: ["number", "null"] },
                                currency: {
                                    type: ["string", "null"],
                                    enum: ["EGP", "USD", "SAR", "AED", null],
                                },
                                category: {
                                    type: ["string", "null"],
                                    enum: ["labor", "materials", "equipment", "transport", "other", null],
                                },
                                matchedProjectName: { type: ["string", "null"] },
                                note: { type: ["string", "null"] },
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
            throw new https_1.HttpsError("internal", `LLM extraction failed (${response.status}): ${text.slice(0, 180)}`);
        }
        const payload = await response.json();
        const choices = payload.choices;
        const first = choices?.[0];
        const message = first?.message;
        const content = message?.content;
        const contentText = Array.isArray(content)
            ? content
                .map((part) => (typeof part === "string" ? part : JSON.stringify(part)))
                .join("\n")
            : `${content ?? ""}`;
        const json = safeJsonParse(contentText);
        if (!json) {
            throw new https_1.HttpsError("internal", "LLM returned malformed JSON");
        }
        return {
            amount: asAmount(json.amount),
            currency: asCurrency(json.currency, params.defaultCurrency),
            category: asCategory(json.category),
            matchedProjectName: `${json.matchedProjectName ?? ""}`.trim() || null,
            note: asShortNote(json.note),
        };
    }
    catch (error) {
        if (error instanceof https_1.HttpsError) {
            throw error;
        }
        throw new https_1.HttpsError("deadline-exceeded", "LLM extraction timeout or network error");
    }
    finally {
        clearTimeout(timer);
    }
}
function mapLlmProjectNameToProvided(params) {
    const target = (0, arabicNormalize_1.normalizeTranscript)(params.matchedProjectName ?? "");
    if (!target) {
        return { projectId: null, projectName: null };
    }
    for (const project of params.projects) {
        const normalized = (0, arabicNormalize_1.normalizeTranscript)(project.name);
        if (normalized === target || normalized.includes(target) || target.includes(normalized)) {
            return { projectId: project.id, projectName: project.name };
        }
    }
    return { projectId: null, projectName: null };
}
//# sourceMappingURL=llm_extraction.service.js.map