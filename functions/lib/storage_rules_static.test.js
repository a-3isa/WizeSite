"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const promises_1 = require("node:fs/promises");
const node_path_1 = __importDefault(require("node:path"));
const node_test_1 = __importDefault(require("node:test"));
(0, node_test_1.default)("storage rules enforce upload size and content type server-side", async () => {
    const rules = await (0, promises_1.readFile)(node_path_1.default.resolve(__dirname, "../../storage.rules"), "utf8");
    strict_1.default.match(rules, /request\.resource\.size\s*<=\s*10\s*\*\s*1024\s*\*\s*1024/);
    strict_1.default.match(rules, /request\.resource\.contentType\.matches/);
    strict_1.default.match(rules, /audio\/\(wav\|mpeg\|aac\|webm\|mp4\)/);
});
//# sourceMappingURL=storage_rules_static.test.js.map