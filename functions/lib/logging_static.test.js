"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const promises_1 = require("node:fs/promises");
const node_path_1 = __importDefault(require("node:path"));
const node_test_1 = __importDefault(require("node:test"));
(0, node_test_1.default)("functions do not log payment amounts or metric deltas", async () => {
    const source = await (0, promises_1.readFile)(node_path_1.default.resolve(__dirname, "../src/index.ts"), "utf8");
    strict_1.default.doesNotMatch(source, /\[payment\.create\./);
    strict_1.default.doesNotMatch(source, /\[metrics\.applyDelta\.tx\]/);
});
(0, node_test_1.default)("transcription provider error logs do not include response bodies", async () => {
    const source = await (0, promises_1.readFile)(node_path_1.default.resolve(__dirname, "../src/voice/services/transcription.service.ts"), "utf8");
    strict_1.default.doesNotMatch(source, /console\.error\([^)]*bodyText/s);
    strict_1.default.doesNotMatch(source, /console\.error\([^)]*body=/s);
});
//# sourceMappingURL=logging_static.test.js.map