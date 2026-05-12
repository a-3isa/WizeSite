"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_path_1 = __importDefault(require("node:path"));
const promises_1 = require("node:fs/promises");
const node_test_1 = __importDefault(require("node:test"));
const rules_unit_testing_1 = require("@firebase/rules-unit-testing");
const firestore_1 = require("firebase/firestore");
const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
if (!emulatorHost) {
    (0, node_test_1.default)("Firestore security rules tests require FIRESTORE_EMULATOR_HOST (skipped)", { skip: true }, () => { });
}
else {
    const projectId = "buildtrack-rules-test";
    let env;
    async function seedBaseData() {
        await env.clearFirestore();
        await env.withSecurityRulesDisabled(async (context) => {
            const db = context.firestore();
            await (0, firestore_1.setDoc)((0, firestore_1.doc)(db, "workspaces", "workspace_owner"), {
                id: "workspace_owner",
                ownerId: "owner_1",
            });
            await (0, firestore_1.setDoc)((0, firestore_1.doc)(db, "workspaces", "workspace_other"), {
                id: "workspace_other",
                ownerId: "owner_2",
            });
            await (0, firestore_1.setDoc)((0, firestore_1.doc)(db, "users", "owner_1"), {
                id: "owner_1",
                workspaceId: "workspace_owner",
            });
            await (0, firestore_1.setDoc)((0, firestore_1.doc)(db, "users", "member_1"), {
                id: "member_1",
                workspaceId: "workspace_owner",
            });
            await (0, firestore_1.setDoc)((0, firestore_1.doc)(db, "users", "attacker_1"), {
                id: "attacker_1",
                workspaceId: "workspace_owner",
            });
            await (0, firestore_1.setDoc)((0, firestore_1.doc)(db, "projects", "project_other"), {
                id: "project_other",
                workspaceId: "workspace_other",
            });
            await (0, firestore_1.setDoc)((0, firestore_1.doc)(db, "projects", "project_owner"), {
                id: "project_owner",
                workspaceId: "workspace_owner",
            });
            await (0, firestore_1.setDoc)((0, firestore_1.doc)(db, "memberships", "workspace_owner_member_1"), {
                workspaceId: "workspace_owner",
                userId: "member_1",
                role: "member",
            });
        });
    }
    node_test_1.default.before(async () => {
        env = await (0, rules_unit_testing_1.initializeTestEnvironment)({
            projectId,
            firestore: {
                host: emulatorHost.split(":")[0],
                port: Number(emulatorHost.split(":")[1]),
                rules: await (0, promises_1.readFile)(node_path_1.default.resolve(__dirname, "../../firestore.rules"), "utf8"),
            },
        });
    });
    node_test_1.default.after(async () => {
        await env.cleanup();
    });
    (0, node_test_1.default)("user cannot change own workspace claim", async () => {
        await seedBaseData();
        const attackerDb = env.authenticatedContext("attacker_1").firestore();
        const attackerUserDoc = (0, firestore_1.doc)(attackerDb, "users", "attacker_1");
        await (0, rules_unit_testing_1.assertFails)((0, firestore_1.setDoc)(attackerUserDoc, { workspaceId: "workspace_other" }, { merge: true }));
        await env.withSecurityRulesDisabled(async (context) => {
            const db = context.firestore();
            const snap = await (0, firestore_1.getDoc)((0, firestore_1.doc)(db, "users", "attacker_1"));
            strict_1.default.equal(snap.data()?.workspaceId, "workspace_owner");
        });
    });
    (0, node_test_1.default)("non-owner cannot self-add membership to another workspace", async () => {
        await seedBaseData();
        const attackerDb = env.authenticatedContext("attacker_1").firestore();
        const membershipDoc = (0, firestore_1.doc)(attackerDb, "memberships", "workspace_other_attacker_1");
        await (0, rules_unit_testing_1.assertFails)((0, firestore_1.setDoc)(membershipDoc, {
            workspaceId: "workspace_other",
            userId: "attacker_1",
            role: "member",
        }));
    });
    (0, node_test_1.default)("non-member cannot read another workspace project", async () => {
        await seedBaseData();
        const attackerDb = env.authenticatedContext("attacker_1").firestore();
        await (0, rules_unit_testing_1.assertFails)((0, firestore_1.getDoc)((0, firestore_1.doc)(attackerDb, "projects", "project_other")));
    });
    (0, node_test_1.default)("member can read project in own workspace", async () => {
        await seedBaseData();
        const memberDb = env.authenticatedContext("member_1").firestore();
        await (0, rules_unit_testing_1.assertSucceeds)((0, firestore_1.getDoc)((0, firestore_1.doc)(memberDb, "projects", "project_owner")));
    });
    (0, node_test_1.default)("workspace owner can add members", async () => {
        await seedBaseData();
        const ownerDb = env.authenticatedContext("owner_1").firestore();
        const membershipDoc = (0, firestore_1.doc)(ownerDb, "memberships", "workspace_owner_member_2");
        await (0, rules_unit_testing_1.assertSucceeds)((0, firestore_1.setDoc)(membershipDoc, {
            workspaceId: "workspace_owner",
            userId: "member_2",
            role: "member",
        }));
    });
}
//# sourceMappingURL=firestore_rules.test.js.map