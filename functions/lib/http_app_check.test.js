"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_test_1 = __importDefault(require("node:test"));
const https_1 = require("firebase-functions/v2/https");
const http_app_check_1 = require("./http_app_check");
(0, node_test_1.default)("HTTP App Check rejects missing tokens by default", async () => {
    await strict_1.default.rejects(() => (0, http_app_check_1.verifyHttpAppCheck)(undefined, async () => undefined), (error) => error instanceof https_1.HttpsError &&
        error.code === "failed-precondition" &&
        error.message === "Missing App Check token");
});
(0, node_test_1.default)("HTTP App Check rejects invalid tokens", async () => {
    const originalWarn = console.warn;
    const warnings = [];
    console.warn = (...args) => {
        warnings.push(args);
    };
    try {
        await strict_1.default.rejects(() => (0, http_app_check_1.verifyHttpAppCheck)("invalid-token", async () => {
            throw new Error("bad token");
        }), (error) => error instanceof https_1.HttpsError &&
            error.code === "failed-precondition" &&
            error.message === "Invalid App Check token");
    }
    finally {
        console.warn = originalWarn;
    }
    strict_1.default.deepEqual(warnings, [["HTTP callable endpoint received an invalid App Check token"]]);
});
(0, node_test_1.default)("HTTP App Check accepts valid tokens", async () => {
    let verifiedToken = "";
    await (0, http_app_check_1.verifyHttpAppCheck)("valid-token", async (token) => {
        verifiedToken = token;
    });
    strict_1.default.equal(verifiedToken, "valid-token");
});
//# sourceMappingURL=http_app_check.test.js.map