"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const promises_1 = require("node:fs/promises");
const node_path_1 = __importDefault(require("node:path"));
const node_test_1 = __importDefault(require("node:test"));
(0, node_test_1.default)("HTTP App Check verification lives outside the main functions index", async () => {
    const indexSource = await (0, promises_1.readFile)(node_path_1.default.resolve(__dirname, "../src/index.ts"), "utf8");
    const helperSource = await (0, promises_1.readFile)(node_path_1.default.resolve(__dirname, "../src/http_app_check.ts"), "utf8");
    strict_1.default.doesNotMatch(indexSource, /function verifyHttpAppCheck/);
    strict_1.default.match(indexSource, /from "\.\/http_app_check"/);
    strict_1.default.match(helperSource, /export async function verifyHttpAppCheck/);
    strict_1.default.match(indexSource, /onCall\(\{\s*enforceAppCheck:\s*true/);
    strict_1.default.match(indexSource, /export const deleteOwnAccount = onCall/);
    strict_1.default.match(indexSource, /from "\.\/idempotency"/);
    strict_1.default.match(indexSource, /commitIdempotentCreate/);
    strict_1.default.match(indexSource, /deleteUserStorage/);
    strict_1.default.match(indexSource, /assertCanMutateMoney/);
    strict_1.default.match(indexSource, /assertCanManageProject/);
    strict_1.default.match(indexSource, /quota:\s*\{/);
    const createProjectSource = indexSource.slice(indexSource.indexOf("export async function createProjectWithQuotaForUser"), indexSource.indexOf("export const createProjectWithQuota ="));
    strict_1.default.match(createProjectSource, /quota:\s*\{/);
    strict_1.default.match(createProjectSource, /field:\s*"activeProjectsCount"/);
    strict_1.default.match(createProjectSource, /\$\{workspaceId\}_projects/);
    strict_1.default.doesNotMatch(createProjectSource, /getCurrentUsage\(workspaceId, "activeProjects"\)/);
    strict_1.default.match(indexSource, /async function getCurrentUsage[\s\S]*_projects[\s\S]*activeProjectsCount/);
    const globalOptions = indexSource.match(/setGlobalOptions\(\{[\s\S]*?\}\);/)?.[0] ?? "";
    strict_1.default.doesNotMatch(globalOptions, /enforceAppCheck/);
});
(0, node_test_1.default)("every onCall enforces App Check", async () => {
    const files = ["index.ts", "voice/process_voice_expense.ts"];
    for (const rel of files) {
        const source = await (0, promises_1.readFile)(node_path_1.default.resolve(__dirname, `../src/${rel}`), "utf8");
        const onCalls = source.match(/onCall\(/g) ?? [];
        const enforced = source.match(/enforceAppCheck:\s*true/g) ?? [];
        strict_1.default.equal(onCalls.length, enforced.length, `${rel} onCall count must match enforceAppCheck: true`);
    }
});
(0, node_test_1.default)("quota HTTP twins stay paired with callables", async () => {
    const indexSource = await (0, promises_1.readFile)(node_path_1.default.resolve(__dirname, "../src/index.ts"), "utf8");
    const twins = [
        ["createProjectWithQuota", "createProjectWithQuotaHttp"],
        ["createExpenseWithQuota", "createExpenseWithQuotaHttp"],
        ["createPaymentWithQuota", "createPaymentWithQuotaHttp"],
        ["createWorkerEntryWithQuota", "createWorkerEntryWithQuotaHttp"],
        ["archiveExpenseWithQuotaRefund", "archiveExpenseWithQuotaRefundHttp"],
        ["archivePaymentWithQuotaRefund", "archivePaymentWithQuotaRefundHttp"],
        ["archiveWorkerEntryWithQuotaRefund", "archiveWorkerEntryWithQuotaRefundHttp"],
    ];
    for (const [callable, http] of twins) {
        strict_1.default.match(indexSource, new RegExp(`export const ${callable} = onCall`));
        strict_1.default.match(indexSource, new RegExp(`export const ${http} = onRequest`));
    }
});
//# sourceMappingURL=functions_structure_static.test.js.map