"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const http_cors_1 = require("./http_cors");
class FakeResponse {
    headers = new Map();
    statusCode = 0;
    body = "";
    set(name, value) {
        this.headers.set(name, value);
    }
    status(code) {
        this.statusCode = code;
        return this;
    }
    send(body) {
        this.body = body;
    }
}
(0, node_test_1.default)("CORS allows Firebase Hosting origins by default", () => {
    strict_1.default.deepEqual((0, http_cors_1.defaultCorsAllowedOrigins)(), [
        "https://wize-site.web.app",
        "https://wize-site.firebaseapp.com",
    ]);
    strict_1.default.equal((0, http_cors_1.isAllowedCorsOrigin)("https://wize-site.web.app"), true);
    strict_1.default.equal((0, http_cors_1.isAllowedCorsOrigin)("https://wize-site.firebaseapp.com"), true);
});
(0, node_test_1.default)("CORS does not reflect arbitrary origins", () => {
    strict_1.default.equal((0, http_cors_1.isAllowedCorsOrigin)("https://evil.example"), false);
    const response = new FakeResponse();
    const handled = (0, http_cors_1.applyCorsHeaders)({
        method: "POST",
        header: (name) => name.toLowerCase() === "origin" ? "https://evil.example" : undefined,
    }, response);
    strict_1.default.equal(handled, false);
    strict_1.default.equal(response.headers.has("Access-Control-Allow-Origin"), false);
});
(0, node_test_1.default)("CORS rejects disallowed preflight requests", () => {
    const response = new FakeResponse();
    const handled = (0, http_cors_1.applyCorsHeaders)({
        method: "OPTIONS",
        header: (name) => name.toLowerCase() === "origin" ? "https://evil.example" : undefined,
    }, response);
    strict_1.default.equal(handled, true);
    strict_1.default.equal(response.statusCode, 403);
    strict_1.default.equal(response.body, "");
    strict_1.default.equal(response.headers.has("Access-Control-Allow-Origin"), false);
});
(0, node_test_1.default)("CORS reflects configured custom origins", () => {
    const response = new FakeResponse();
    const handled = (0, http_cors_1.applyCorsHeaders)({
        method: "OPTIONS",
        header: (name) => name.toLowerCase() === "origin" ? "https://app.example" : undefined,
    }, response, { allowedOrigins: ["https://app.example"] });
    strict_1.default.equal(handled, true);
    strict_1.default.equal(response.statusCode, 204);
    strict_1.default.equal(response.headers.get("Access-Control-Allow-Origin"), "https://app.example");
});
//# sourceMappingURL=http_cors.test.js.map