"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.defaultCorsAllowedOrigins = defaultCorsAllowedOrigins;
exports.isAllowedCorsOrigin = isAllowedCorsOrigin;
exports.applyCorsHeaders = applyCorsHeaders;
const defaultOrigins = [
    "https://wize-site.web.app",
    "https://wize-site.firebaseapp.com",
];
const allowedHeaders = "Content-Type, Authorization, X-Firebase-AppCheck";
function defaultCorsAllowedOrigins() {
    const configured = process.env.CORS_ALLOWED_ORIGINS;
    if (configured?.trim()) {
        return configured
            .split(",")
            .map((origin) => origin.trim())
            .filter((origin) => origin.length > 0);
    }
    return [...defaultOrigins];
}
function isAllowedCorsOrigin(origin, options = {}) {
    if (!origin) {
        return false;
    }
    const allowedOrigins = options.allowedOrigins ?? defaultCorsAllowedOrigins();
    return allowedOrigins.includes(origin);
}
function applyCorsHeaders(request, response, options = {}) {
    const origin = request.header("Origin");
    response.set("Vary", "Origin");
    response.set("Access-Control-Allow-Headers", allowedHeaders);
    response.set("Access-Control-Allow-Methods", "POST, OPTIONS");
    if (isAllowedCorsOrigin(origin, options)) {
        response.set("Access-Control-Allow-Origin", origin);
    }
    else if (request.method === "OPTIONS" && origin) {
        response.status(403).send("");
        return true;
    }
    if (request.method === "OPTIONS") {
        response.status(204).send("");
        return true;
    }
    return false;
}
//# sourceMappingURL=http_cors.js.map