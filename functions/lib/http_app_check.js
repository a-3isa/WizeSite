"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.verifyHttpAppCheck = verifyHttpAppCheck;
const app_check_1 = require("firebase-admin/app-check");
const https_1 = require("firebase-functions/v2/https");
async function verifyHttpAppCheck(appCheckToken, verifyToken = (token) => (0, app_check_1.getAppCheck)().verifyToken(token)) {
    if (!appCheckToken) {
        throw new https_1.HttpsError("failed-precondition", "Missing App Check token");
    }
    try {
        await verifyToken(appCheckToken);
    }
    catch {
        console.warn("HTTP callable endpoint received an invalid App Check token");
        throw new https_1.HttpsError("failed-precondition", "Invalid App Check token");
    }
}
//# sourceMappingURL=http_app_check.js.map