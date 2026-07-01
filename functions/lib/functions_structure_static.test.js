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
});
//# sourceMappingURL=functions_structure_static.test.js.map