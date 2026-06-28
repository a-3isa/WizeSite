"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const node_path_1 = __importDefault(require("node:path"));
const promises_1 = require("node:fs/promises");
const node_test_1 = __importDefault(require("node:test"));
const rules_unit_testing_1 = require("@firebase/rules-unit-testing");
const emulatorHost = process.env.FIREBASE_STORAGE_EMULATOR_HOST;
if (!emulatorHost) {
    (0, node_test_1.default)("Storage security rules tests require FIREBASE_STORAGE_EMULATOR_HOST (skipped)", { skip: true }, () => { });
}
else {
    const projectId = "buildtrack-storage-rules-test";
    const bucketUrl = `gs://${projectId}.appspot.com`;
    let env;
    function attachmentRef(uid, pathSuffix) {
        return env
            .authenticatedContext(uid)
            .storage(bucketUrl)
            .ref(`attachments/${pathSuffix}`);
    }
    function putRawString(uid, pathSuffix, contentType = "application/pdf", content = "receipt") {
        return attachmentRef(uid, pathSuffix)
            .putString(content, "raw", { contentType })
            .then(() => undefined);
    }
    node_test_1.default.before(async () => {
        env = await (0, rules_unit_testing_1.initializeTestEnvironment)({
            projectId,
            storage: {
                host: emulatorHost.split(":")[0],
                port: Number(emulatorHost.split(":")[1]),
                rules: await (0, promises_1.readFile)(node_path_1.default.resolve(__dirname, "../../storage.rules"), "utf8"),
            },
        });
    });
    node_test_1.default.beforeEach(async () => {
        await env.clearStorage();
    });
    node_test_1.default.after(async () => {
        await env.cleanup();
    });
    (0, node_test_1.default)("authenticated users can upload only their own attachments", async () => {
        await (0, rules_unit_testing_1.assertSucceeds)(putRawString("owner_1", "owner_1/receipt.pdf"));
        await (0, rules_unit_testing_1.assertFails)(putRawString("attacker_1", "owner_1/receipt.pdf"));
    });
    (0, node_test_1.default)("attachment uploads reject unsupported content types and oversized files", async () => {
        await (0, rules_unit_testing_1.assertFails)(putRawString("owner_1", "owner_1/receipt.exe", "application/x-msdownload"));
        await (0, rules_unit_testing_1.assertFails)(putRawString("owner_1", "owner_1/huge.pdf", "application/pdf", "x".repeat(10 * 1024 * 1024 + 1)));
    });
}
//# sourceMappingURL=storage_rules.test.js.map