"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
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
    let bootstrapWorkspaceForUser;
    let setActiveWorkspaceForUser;
    let inviteMemberByEmailForUser;
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
                name: "Other Project",
                clientName: "Other Client",
                contractValue: 900,
                startDate: new Date().toISOString(),
                completionPercentage: 5,
                status: "active",
                isArchived: false,
            });
            await (0, firestore_1.setDoc)((0, firestore_1.doc)(db, "projects", "project_owner"), {
                id: "project_owner",
                workspaceId: "workspace_owner",
                name: "Owner Project",
                clientName: "Client",
                contractValue: 1200,
                startDate: new Date().toISOString(),
                completionPercentage: 10,
                status: "active",
                isArchived: false,
            });
            await (0, firestore_1.setDoc)((0, firestore_1.doc)(db, "expenses", "expense_owner"), {
                id: "expense_owner",
                workspaceId: "workspace_owner",
                projectId: "project_owner",
                category: "materials",
                amount: 100,
                date: new Date().toISOString(),
                isArchived: false,
            });
            await (0, firestore_1.setDoc)((0, firestore_1.doc)(db, "payments", "payment_owner"), {
                id: "payment_owner",
                workspaceId: "workspace_owner",
                projectId: "project_owner",
                amount: 120,
                date: new Date().toISOString(),
                paymentMethod: "cash",
                isArchived: false,
            });
            await (0, firestore_1.setDoc)((0, firestore_1.doc)(db, "workers", "worker_owner"), {
                id: "worker_owner",
                workspaceId: "workspace_owner",
                name: "Worker Owner",
                phoneNumber: "0100",
                dailyWage: 100,
                billingType: "daily",
                workerType: "laborer",
                notes: "",
                isArchived: false,
                createdBy: "owner_1",
                createdAt: new Date(),
                updatedAt: new Date(),
            });
            await (0, firestore_1.setDoc)((0, firestore_1.doc)(db, "worker_entries", "entry_owner"), {
                id: "entry_owner",
                workspaceId: "workspace_owner",
                workerId: "worker_1",
                projectId: "project_owner",
                daysWorked: 1,
                dailyWage: 90,
                totalCost: 90,
                date: new Date().toISOString(),
                isArchived: false,
            });
            await (0, firestore_1.setDoc)((0, firestore_1.doc)(db, "memberships", "workspace_owner_member_1"), {
                workspaceId: "workspace_owner",
                userId: "member_1",
                role: "member",
            });
            await (0, firestore_1.setDoc)((0, firestore_1.doc)(db, "memberships", "workspace_owner_admin_1"), {
                workspaceId: "workspace_owner",
                userId: "admin_1",
                role: "admin",
            });
            await (0, firestore_1.setDoc)((0, firestore_1.doc)(db, "memberships", "workspace_owner_accounting_1"), {
                workspaceId: "workspace_owner",
                userId: "accounting_1",
                role: "accountingApproved",
            });
            await (0, firestore_1.setDoc)((0, firestore_1.doc)(db, "memberships", "workspace_owner_entry_1"), {
                workspaceId: "workspace_owner",
                userId: "entry_1",
                role: "entryOnly",
            });
            await (0, firestore_1.setDoc)((0, firestore_1.doc)(db, "entity_summaries", "entity_summary_owner"), {
                id: "entity_summary_owner",
                workspaceId: "workspace_owner",
                projectId: "project_owner",
                entityId: "entity_1",
                entityName: "Acme Materials",
                entityType: "supplier",
                totalExpenses: 100,
                totalPayments: 25,
            });
            await (0, firestore_1.setDoc)((0, firestore_1.doc)(db, "attachments", "attachment_owner"), {
                id: "attachment_owner",
                workspaceId: "workspace_owner",
                ownerType: "expense",
                ownerId: "expense_owner",
                fileName: "receipt.pdf",
                storagePath: "attachments/owner/receipt.pdf",
                contentType: "application/pdf",
            });
            await (0, firestore_1.setDoc)((0, firestore_1.doc)(db, "entities", "entity_owner"), {
                id: "entity_owner",
                workspaceId: "workspace_owner",
                name: "Acme Contractors",
                normalizedName: "acme contractors",
                type: "contractor",
                lastUsedAt: new Date(),
                createdAt: new Date(),
            });
            await (0, firestore_1.setDoc)((0, firestore_1.doc)(db, "notifications", "notification_owner"), {
                workspaceId: "workspace_owner",
                targetUserId: "member_1",
                title: "Budget updated",
                message: "Review the latest totals",
                createdAt: new Date(),
            });
            await (0, firestore_1.setDoc)((0, firestore_1.doc)(db, "workspace_metrics", "workspace_owner"), {
                workspaceId: "workspace_owner",
                totalExpenses: 100,
            });
            await (0, firestore_1.setDoc)((0, firestore_1.doc)(db, "project_metrics", "project_owner"), {
                workspaceId: "workspace_owner",
                projectId: "project_owner",
                totalExpenses: 100,
            });
            await (0, firestore_1.setDoc)((0, firestore_1.doc)(db, "worker_accounting_records", "worker_record_owner"), {
                workspaceId: "workspace_owner",
                projectId: "project_owner",
                workerId: "worker_owner",
                workerName: "Worker Owner",
                description: "Weekly settlement",
                amount: 300,
                date: new Date(),
                paymentMethod: "cash",
                paymentStatus: "partial",
                paidAmount: 125,
                notes: "",
            });
            await (0, firestore_1.setDoc)((0, firestore_1.doc)(db, "contractor_accounting_records", "contractor_record_owner"), {
                workspaceId: "workspace_owner",
                projectId: "project_owner",
                contractorId: "contractor_owner",
                contractorName: "Contractor Owner",
                description: "Contractor invoice",
                amount: 400,
                date: new Date(),
                paymentMethod: "cash",
                paymentStatus: "paid",
                notes: "",
            });
            await (0, firestore_1.setDoc)((0, firestore_1.doc)(db, "worker_accounting_summaries", "workspace_owner_worker_owner"), {
                workspaceId: "workspace_owner",
                workerId: "worker_owner",
                totalAmount: 300,
                confirmedPaid: 125,
                confirmedOutstanding: 175,
                unresolvedLegacyCount: 0,
                recordCount: 1,
            });
        });
    }
    node_test_1.default.before(async () => {
        process.env.GCLOUD_PROJECT = projectId;
        process.env.FIREBASE_CONFIG = JSON.stringify({ projectId });
        env = await (0, rules_unit_testing_1.initializeTestEnvironment)({
            projectId,
            firestore: {
                host: emulatorHost.split(":")[0],
                port: Number(emulatorHost.split(":")[1]),
                rules: await (0, promises_1.readFile)(node_path_1.default.resolve(__dirname, "../../firestore.rules"), "utf8"),
            },
        });
        const indexModule = await Promise.resolve().then(() => __importStar(require("./index")));
        bootstrapWorkspaceForUser = indexModule.bootstrapWorkspaceForUser;
        setActiveWorkspaceForUser = indexModule.setActiveWorkspaceForUser;
        inviteMemberByEmailForUser = indexModule.inviteMemberByEmailForUser;
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
    (0, node_test_1.default)("ordinary members cannot read role-restricted accounting summaries or attachments", async () => {
        await seedBaseData();
        const memberDb = env.authenticatedContext("member_1").firestore();
        await (0, rules_unit_testing_1.assertFails)((0, firestore_1.getDoc)((0, firestore_1.doc)(memberDb, "entity_summaries", "entity_summary_owner")));
        await (0, rules_unit_testing_1.assertFails)((0, firestore_1.getDoc)((0, firestore_1.doc)(memberDb, "attachments", "attachment_owner")));
    });
    (0, node_test_1.default)("accounting-approved roles can read role-restricted summaries and attachments", async () => {
        await seedBaseData();
        const adminDb = env.authenticatedContext("admin_1").firestore();
        const accountingDb = env.authenticatedContext("accounting_1").firestore();
        await (0, rules_unit_testing_1.assertSucceeds)((0, firestore_1.getDoc)((0, firestore_1.doc)(adminDb, "entity_summaries", "entity_summary_owner")));
        await (0, rules_unit_testing_1.assertSucceeds)((0, firestore_1.getDoc)((0, firestore_1.doc)(accountingDb, "attachments", "attachment_owner")));
    });
    (0, node_test_1.default)("workspace members can read the entity directory; non-members cannot", async () => {
        await seedBaseData();
        const memberDb = env.authenticatedContext("member_1").firestore();
        const attackerDb = env.authenticatedContext("attacker_1").firestore();
        await (0, rules_unit_testing_1.assertSucceeds)((0, firestore_1.getDoc)((0, firestore_1.doc)(memberDb, "entities", "entity_owner")));
        await (0, rules_unit_testing_1.assertFails)((0, firestore_1.getDoc)((0, firestore_1.doc)(attackerDb, "entities", "entity_owner")));
    });
    (0, node_test_1.default)("workspace members can create and touch entities but not reassign workspace", async () => {
        await seedBaseData();
        const memberDb = env.authenticatedContext("member_1").firestore();
        await (0, rules_unit_testing_1.assertSucceeds)((0, firestore_1.setDoc)((0, firestore_1.doc)(memberDb, "entities", "entity_new"), {
            workspaceId: "workspace_owner",
            name: "New Supplier",
            normalizedName: "new supplier",
            type: "supplier",
            createdAt: new Date(),
            lastUsedAt: new Date(),
        }));
        await (0, rules_unit_testing_1.assertSucceeds)((0, firestore_1.updateDoc)((0, firestore_1.doc)(memberDb, "entities", "entity_owner"), {
            lastUsedAt: new Date(),
        }));
        await (0, rules_unit_testing_1.assertFails)((0, firestore_1.updateDoc)((0, firestore_1.doc)(memberDb, "entities", "entity_owner"), {
            workspaceId: "workspace_other",
        }));
    });
    (0, node_test_1.default)("notification target can change only readAt", async () => {
        await seedBaseData();
        const memberDb = env.authenticatedContext("member_1").firestore();
        const ownerDb = env.authenticatedContext("owner_1").firestore();
        const notificationRef = (0, firestore_1.doc)(memberDb, "notifications", "notification_owner");
        await (0, rules_unit_testing_1.assertSucceeds)((0, firestore_1.updateDoc)(notificationRef, { readAt: new Date() }));
        await (0, rules_unit_testing_1.assertFails)((0, firestore_1.updateDoc)(notificationRef, { title: "Changed" }));
        await (0, rules_unit_testing_1.assertFails)((0, firestore_1.updateDoc)((0, firestore_1.doc)(ownerDb, "notifications", "notification_owner"), {
            readAt: new Date(),
        }));
    });
    (0, node_test_1.default)("financial metrics are accounting-role restricted", async () => {
        await seedBaseData();
        const memberDb = env.authenticatedContext("member_1").firestore();
        const entryDb = env.authenticatedContext("entry_1").firestore();
        const adminDb = env.authenticatedContext("admin_1").firestore();
        await (0, rules_unit_testing_1.assertFails)((0, firestore_1.getDoc)((0, firestore_1.doc)(memberDb, "workspace_metrics", "workspace_owner")));
        await (0, rules_unit_testing_1.assertFails)((0, firestore_1.getDoc)((0, firestore_1.doc)(memberDb, "project_metrics", "project_owner")));
        await (0, rules_unit_testing_1.assertFails)((0, firestore_1.getDoc)((0, firestore_1.doc)(entryDb, "workspace_metrics", "workspace_owner")));
        await (0, rules_unit_testing_1.assertFails)((0, firestore_1.getDoc)((0, firestore_1.doc)(entryDb, "project_metrics", "project_owner")));
        await (0, rules_unit_testing_1.assertSucceeds)((0, firestore_1.getDoc)((0, firestore_1.doc)(adminDb, "workspace_metrics", "workspace_owner")));
        await (0, rules_unit_testing_1.assertSucceeds)((0, firestore_1.getDoc)((0, firestore_1.doc)(adminDb, "project_metrics", "project_owner")));
    });
    (0, node_test_1.default)("domain accounting records and worker summaries are accounting-role restricted", async () => {
        await seedBaseData();
        const memberDb = env.authenticatedContext("member_1").firestore();
        const entryDb = env.authenticatedContext("entry_1").firestore();
        const accountingDb = env.authenticatedContext("accounting_1").firestore();
        await (0, rules_unit_testing_1.assertFails)((0, firestore_1.getDoc)((0, firestore_1.doc)(memberDb, "worker_accounting_records", "worker_record_owner")));
        await (0, rules_unit_testing_1.assertFails)((0, firestore_1.getDoc)((0, firestore_1.doc)(entryDb, "worker_accounting_records", "worker_record_owner")));
        await (0, rules_unit_testing_1.assertFails)((0, firestore_1.getDoc)((0, firestore_1.doc)(memberDb, "contractor_accounting_records", "contractor_record_owner")));
        await (0, rules_unit_testing_1.assertFails)((0, firestore_1.getDoc)((0, firestore_1.doc)(entryDb, "worker_accounting_summaries", "workspace_owner_worker_owner")));
        await (0, rules_unit_testing_1.assertSucceeds)((0, firestore_1.getDoc)((0, firestore_1.doc)(accountingDb, "worker_accounting_records", "worker_record_owner")));
        await (0, rules_unit_testing_1.assertSucceeds)((0, firestore_1.getDoc)((0, firestore_1.doc)(accountingDb, "contractor_accounting_records", "contractor_record_owner")));
        await (0, rules_unit_testing_1.assertSucceeds)((0, firestore_1.getDoc)((0, firestore_1.doc)(accountingDb, "worker_accounting_summaries", "workspace_owner_worker_owner")));
    });
    (0, node_test_1.default)("worker accounting partial writes require a valid paid amount", async () => {
        await seedBaseData();
        const accountingDb = env.authenticatedContext("accounting_1").firestore();
        const validRecord = {
            workspaceId: "workspace_owner",
            projectId: "project_owner",
            workerId: "worker_owner",
            workerName: "Worker Owner",
            description: "Valid partial",
            amount: 300,
            date: new Date(),
            paymentMethod: "cash",
            paymentStatus: "partial",
            notes: "",
        };
        await (0, rules_unit_testing_1.assertFails)((0, firestore_1.setDoc)((0, firestore_1.doc)(accountingDb, "worker_accounting_records", "partial_missing"), {
            ...validRecord,
        }));
        await (0, rules_unit_testing_1.assertFails)((0, firestore_1.setDoc)((0, firestore_1.doc)(accountingDb, "worker_accounting_records", "partial_too_high"), {
            ...validRecord,
            paidAmount: 300,
        }));
        await (0, rules_unit_testing_1.assertSucceeds)((0, firestore_1.setDoc)((0, firestore_1.doc)(accountingDb, "worker_accounting_records", "partial_valid"), {
            ...validRecord,
            paidAmount: 125,
        }));
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
    (0, node_test_1.default)("direct project create is denied even for workspace members", async () => {
        await seedBaseData();
        const memberDb = env.authenticatedContext("member_1").firestore();
        await (0, rules_unit_testing_1.assertFails)((0, firestore_1.setDoc)((0, firestore_1.doc)(memberDb, "projects", "project_new"), {
            id: "project_new",
            workspaceId: "workspace_owner",
            name: "New Project",
            clientName: "Client",
            contractValue: 500,
            startDate: new Date().toISOString(),
            completionPercentage: 0,
            status: "active",
            isArchived: false,
        }));
    });
    (0, node_test_1.default)("direct expense create is denied", async () => {
        await seedBaseData();
        const memberDb = env.authenticatedContext("member_1").firestore();
        await (0, rules_unit_testing_1.assertFails)((0, firestore_1.setDoc)((0, firestore_1.doc)(memberDb, "expenses", "expense_new"), {
            id: "expense_new",
            workspaceId: "workspace_owner",
            projectId: "project_owner",
            category: "materials",
            amount: -10,
            date: new Date().toISOString(),
            isArchived: false,
        }));
    });
    (0, node_test_1.default)("direct payment delete is denied", async () => {
        await seedBaseData();
        const memberDb = env.authenticatedContext("member_1").firestore();
        await (0, rules_unit_testing_1.assertFails)((0, firestore_1.deleteDoc)((0, firestore_1.doc)(memberDb, "payments", "payment_owner")));
    });
    (0, node_test_1.default)("expense update cannot move records across workspaces", async () => {
        await seedBaseData();
        const memberDb = env.authenticatedContext("member_1").firestore();
        await (0, rules_unit_testing_1.assertFails)((0, firestore_1.updateDoc)((0, firestore_1.doc)(memberDb, "expenses", "expense_owner"), {
            workspaceId: "workspace_other",
        }));
    });
    (0, node_test_1.default)("worker entry update rejects negative fields", async () => {
        await seedBaseData();
        const memberDb = env.authenticatedContext("member_1").firestore();
        await (0, rules_unit_testing_1.assertFails)((0, firestore_1.updateDoc)((0, firestore_1.doc)(memberDb, "worker_entries", "entry_owner"), {
            daysWorked: -1,
        }));
    });
    (0, node_test_1.default)("worker create allows project billing with zero daily wage", async () => {
        await seedBaseData();
        const memberDb = env.authenticatedContext("member_1").firestore();
        await (0, rules_unit_testing_1.assertSucceeds)((0, firestore_1.setDoc)((0, firestore_1.doc)(memberDb, "workers", "worker_project"), {
            id: "worker_project",
            workspaceId: "workspace_owner",
            name: "Project Billed Worker",
            phoneNumber: "0100111",
            dailyWage: 0,
            billingType: "project",
            workerType: "laborer",
            notes: "",
            isArchived: false,
        }));
    });
    (0, node_test_1.default)("worker create rejects daily billing with zero wage", async () => {
        await seedBaseData();
        const memberDb = env.authenticatedContext("member_1").firestore();
        await (0, rules_unit_testing_1.assertFails)((0, firestore_1.setDoc)((0, firestore_1.doc)(memberDb, "workers", "worker_daily_invalid"), {
            id: "worker_daily_invalid",
            workspaceId: "workspace_owner",
            name: "Daily Billed Worker",
            phoneNumber: "0100111",
            dailyWage: 0,
            billingType: "daily",
            workerType: "laborer",
            notes: "",
            isArchived: false,
        }));
    });
    (0, node_test_1.default)("worker update rejects invalid billing type", async () => {
        await seedBaseData();
        const memberDb = env.authenticatedContext("member_1").firestore();
        await (0, rules_unit_testing_1.assertFails)((0, firestore_1.updateDoc)((0, firestore_1.doc)(memberDb, "workers", "worker_owner"), {
            billingType: "weekly",
            updatedAt: new Date(),
        }));
    });
    (0, node_test_1.default)("worker writes reject invalid status while preserving legacy default", async () => {
        await seedBaseData();
        const memberDb = env.authenticatedContext("member_1").firestore();
        await (0, rules_unit_testing_1.assertFails)((0, firestore_1.setDoc)((0, firestore_1.doc)(memberDb, "workers", "worker_bad_status"), {
            id: "worker_bad_status",
            workspaceId: "workspace_owner",
            name: "Invalid Status Worker",
            phoneNumber: "0100111",
            dailyWage: 100,
            billingType: "daily",
            workerType: "laborer",
            notes: "",
            isArchived: false,
            status: "suspended",
        }));
        await (0, rules_unit_testing_1.assertSucceeds)((0, firestore_1.updateDoc)((0, firestore_1.doc)(memberDb, "workers", "worker_owner"), {
            status: "inactive",
            updatedAt: new Date(),
        }));
    });
    (0, node_test_1.default)("bootstrap function creates workspace user and membership for first-time auth user", async () => {
        await env.clearFirestore();
        const result = await bootstrapWorkspaceForUser({
            uid: "google_user_1",
            email: "google@example.com",
            fullName: "Google User",
            photoUrl: "https://example.com/photo.png",
        });
        await env.withSecurityRulesDisabled(async (context) => {
            const db = context.firestore();
            const workspaceSnap = await (0, firestore_1.getDoc)((0, firestore_1.doc)(db, "workspaces", result.workspaceId));
            const userSnap = await (0, firestore_1.getDoc)((0, firestore_1.doc)(db, "users", "google_user_1"));
            const membershipSnap = await (0, firestore_1.getDoc)((0, firestore_1.doc)(db, "memberships", `${result.workspaceId}_google_user_1`));
            strict_1.default.equal(result.created, true);
            strict_1.default.equal(workspaceSnap.exists(), true);
            strict_1.default.equal(userSnap.data()?.workspaceId, result.workspaceId);
            strict_1.default.equal(membershipSnap.data()?.role, "owner");
        });
    });
    (0, node_test_1.default)("bootstrap preserves existing user settings and profile fields", async () => {
        await env.clearFirestore();
        await env.withSecurityRulesDisabled(async (context) => {
            const db = context.firestore();
            await (0, firestore_1.setDoc)((0, firestore_1.doc)(db, "users", "existing_user"), {
                id: "existing_user",
                workspaceId: "legacy_workspace",
                email: "saved@example.com",
                fullName: "Saved Name",
                photoUrl: "https://example.com/saved.png",
                defaultCurrency: "USD",
                riskAlertsEnabled: false,
            });
            await (0, firestore_1.setDoc)((0, firestore_1.doc)(db, "workspaces", "legacy_workspace"), {
                id: "legacy_workspace",
                ownerId: "existing_user",
                name: "Existing Workspace",
            });
        });
        const result = await bootstrapWorkspaceForUser({
            uid: "existing_user",
            email: "incoming@example.com",
            fullName: "Incoming Name",
            photoUrl: "https://example.com/incoming.png",
        });
        await env.withSecurityRulesDisabled(async (context) => {
            const db = context.firestore();
            const userSnap = await (0, firestore_1.getDoc)((0, firestore_1.doc)(db, "users", "existing_user"));
            const membershipSnap = await (0, firestore_1.getDoc)((0, firestore_1.doc)(db, "memberships", `${result.workspaceId}_existing_user`));
            strict_1.default.equal(result.workspaceId, "legacy_workspace");
            strict_1.default.equal(userSnap.data()?.defaultCurrency, "USD");
            strict_1.default.equal(userSnap.data()?.riskAlertsEnabled, false);
            strict_1.default.equal(userSnap.data()?.fullName, "Saved Name");
            strict_1.default.equal(userSnap.data()?.photoUrl, "https://example.com/saved.png");
            strict_1.default.equal(userSnap.data()?.email, "saved@example.com");
            strict_1.default.equal(membershipSnap.data()?.role, "owner");
        });
    });
    (0, node_test_1.default)("bootstrap omits missing optional profile fields for new users", async () => {
        await env.clearFirestore();
        const result = await bootstrapWorkspaceForUser({
            uid: "minimal_user",
            email: "minimal@example.com",
            fullName: null,
            photoUrl: null,
        });
        await env.withSecurityRulesDisabled(async (context) => {
            const db = context.firestore();
            const userSnap = await (0, firestore_1.getDoc)((0, firestore_1.doc)(db, "users", "minimal_user"));
            strict_1.default.equal(result.created, true);
            strict_1.default.equal(userSnap.data()?.email, "minimal@example.com");
            strict_1.default.equal("fullName" in (userSnap.data() ?? {}), false);
            strict_1.default.equal("photoUrl" in (userSnap.data() ?? {}), false);
        });
    });
    (0, node_test_1.default)("bootstrap preserves missing default currency on existing users without writing undefined", async () => {
        await env.clearFirestore();
        await env.withSecurityRulesDisabled(async (context) => {
            const db = context.firestore();
            await (0, firestore_1.setDoc)((0, firestore_1.doc)(db, "users", "existing_without_currency"), {
                id: "existing_without_currency",
                workspaceId: "legacy_workspace",
                riskAlertsEnabled: false,
            });
            await (0, firestore_1.setDoc)((0, firestore_1.doc)(db, "workspaces", "legacy_workspace"), {
                id: "legacy_workspace",
                ownerId: "existing_without_currency",
                name: "Legacy Workspace",
            });
        });
        const result = await bootstrapWorkspaceForUser({
            uid: "existing_without_currency",
            email: "existing@example.com",
            fullName: "",
            photoUrl: "",
        });
        await env.withSecurityRulesDisabled(async (context) => {
            const db = context.firestore();
            const userSnap = await (0, firestore_1.getDoc)((0, firestore_1.doc)(db, "users", "existing_without_currency"));
            strict_1.default.equal(result.workspaceId, "legacy_workspace");
            strict_1.default.equal(userSnap.data()?.riskAlertsEnabled, false);
            strict_1.default.equal("defaultCurrency" in (userSnap.data() ?? {}), false);
            strict_1.default.equal("fullName" in (userSnap.data() ?? {}), false);
            strict_1.default.equal("photoUrl" in (userSnap.data() ?? {}), false);
            strict_1.default.equal(userSnap.data()?.email, "existing@example.com");
        });
    });
    (0, node_test_1.default)("bootstrap fails when legacy workspace belongs to someone else without membership", async () => {
        await env.clearFirestore();
        await env.withSecurityRulesDisabled(async (context) => {
            const db = context.firestore();
            await (0, firestore_1.setDoc)((0, firestore_1.doc)(db, "users", "legacy_user"), {
                id: "legacy_user",
                workspaceId: "shared_workspace",
                defaultCurrency: "USD",
                riskAlertsEnabled: false,
            });
            await (0, firestore_1.setDoc)((0, firestore_1.doc)(db, "workspaces", "shared_workspace"), {
                id: "shared_workspace",
                ownerId: "different_owner",
                name: "Shared Workspace",
            });
        });
        await strict_1.default.rejects(bootstrapWorkspaceForUser({
            uid: "legacy_user",
            email: "legacy@example.com",
            fullName: "Legacy User",
            photoUrl: "https://example.com/legacy.png",
        }), (error) => {
            strict_1.default.equal(error.code, "failed-precondition");
            strict_1.default.match(`${error.message ?? ""}`, /legacy workspace/i);
            return true;
        });
        await env.withSecurityRulesDisabled(async (context) => {
            const db = context.firestore();
            const workspaceSnap = await (0, firestore_1.getDoc)((0, firestore_1.doc)(db, "workspaces", "shared_workspace"));
            const membershipSnap = await (0, firestore_1.getDoc)((0, firestore_1.doc)(db, "memberships", "shared_workspace_legacy_user"));
            const userSnap = await (0, firestore_1.getDoc)((0, firestore_1.doc)(db, "users", "legacy_user"));
            strict_1.default.equal(workspaceSnap.data()?.ownerId, "different_owner");
            strict_1.default.equal(membershipSnap.exists(), false);
            strict_1.default.equal(userSnap.data()?.workspaceId, "shared_workspace");
        });
    });
    (0, node_test_1.default)("active workspace switch persists only valid memberships", async () => {
        await env.clearFirestore();
        await env.withSecurityRulesDisabled(async (context) => {
            const db = context.firestore();
            await (0, firestore_1.setDoc)((0, firestore_1.doc)(db, "users", "member_1"), {
                id: "member_1",
                workspaceId: "personal_ws",
            });
            await (0, firestore_1.setDoc)((0, firestore_1.doc)(db, "workspaces", "personal_ws"), {
                id: "personal_ws",
                ownerId: "member_1",
                name: "Personal Workspace",
            });
            await (0, firestore_1.setDoc)((0, firestore_1.doc)(db, "workspaces", "shared_ws"), {
                id: "shared_ws",
                ownerId: "owner_2",
                name: "Shared Workspace",
            });
            await (0, firestore_1.setDoc)((0, firestore_1.doc)(db, "workspaces", "other_ws"), {
                id: "other_ws",
                ownerId: "owner_3",
                name: "Other Workspace",
            });
            await (0, firestore_1.setDoc)((0, firestore_1.doc)(db, "memberships", "personal_ws_member_1"), {
                workspaceId: "personal_ws",
                userId: "member_1",
                role: "owner",
            });
            await (0, firestore_1.setDoc)((0, firestore_1.doc)(db, "memberships", "shared_ws_member_1"), {
                workspaceId: "shared_ws",
                userId: "member_1",
                role: "member",
            });
        });
        const result = await setActiveWorkspaceForUser({
            uid: "member_1",
            workspaceId: "shared_ws",
        });
        strict_1.default.equal(result.workspaceId, "shared_ws");
        await strict_1.default.rejects(setActiveWorkspaceForUser({
            uid: "member_1",
            workspaceId: "other_ws",
        }), (error) => {
            strict_1.default.equal(error.code, "permission-denied");
            return true;
        });
        await env.withSecurityRulesDisabled(async (context) => {
            const db = context.firestore();
            const userSnap = await (0, firestore_1.getDoc)((0, firestore_1.doc)(db, "users", "member_1"));
            strict_1.default.equal(userSnap.data()?.workspaceId, "shared_ws");
        });
    });
    (0, node_test_1.default)("active workspace switch repairs owned workspace without membership", async () => {
        await env.clearFirestore();
        await env.withSecurityRulesDisabled(async (context) => {
            const db = context.firestore();
            await (0, firestore_1.setDoc)((0, firestore_1.doc)(db, "users", "owner_1"), {
                id: "owner_1",
                workspaceId: "other_ws",
            });
            await (0, firestore_1.setDoc)((0, firestore_1.doc)(db, "workspaces", "personal_ws"), {
                id: "personal_ws",
                ownerId: "owner_1",
                name: "Personal Workspace",
            });
        });
        const result = await setActiveWorkspaceForUser({
            uid: "owner_1",
            workspaceId: "personal_ws",
        });
        strict_1.default.equal(result.workspaceId, "personal_ws");
        await env.withSecurityRulesDisabled(async (context) => {
            const db = context.firestore();
            const userSnap = await (0, firestore_1.getDoc)((0, firestore_1.doc)(db, "users", "owner_1"));
            const membershipSnap = await (0, firestore_1.getDoc)((0, firestore_1.doc)(db, "memberships", "personal_ws_owner_1"));
            strict_1.default.equal(userSnap.data()?.workspaceId, "personal_ws");
            strict_1.default.equal(membershipSnap.data()?.role, "owner");
        });
    });
    (0, node_test_1.default)("email invite adds membership without changing invitee active workspace", async () => {
        await env.clearFirestore();
        await env.withSecurityRulesDisabled(async (context) => {
            const db = context.firestore();
            await (0, firestore_1.setDoc)((0, firestore_1.doc)(db, "users", "owner_1"), {
                id: "owner_1",
                email: "owner@example.com",
                workspaceId: "owner_ws",
            });
            await (0, firestore_1.setDoc)((0, firestore_1.doc)(db, "users", "invitee_1"), {
                id: "invitee_1",
                email: "invitee@example.com",
                workspaceId: "personal_ws",
            });
            await (0, firestore_1.setDoc)((0, firestore_1.doc)(db, "workspaces", "owner_ws"), {
                id: "owner_ws",
                ownerId: "owner_1",
                name: "Owner Workspace",
            });
            await (0, firestore_1.setDoc)((0, firestore_1.doc)(db, "memberships", "owner_ws_owner_1"), {
                workspaceId: "owner_ws",
                userId: "owner_1",
                role: "owner",
            });
        });
        const result = await inviteMemberByEmailForUser({
            ownerUid: "owner_1",
            workspaceId: "owner_ws",
            email: "INVITEE@example.com",
            role: "member",
        });
        strict_1.default.equal(result.userId, "invitee_1");
        await env.withSecurityRulesDisabled(async (context) => {
            const db = context.firestore();
            const userSnap = await (0, firestore_1.getDoc)((0, firestore_1.doc)(db, "users", "invitee_1"));
            const membershipSnap = await (0, firestore_1.getDoc)((0, firestore_1.doc)(db, "memberships", "owner_ws_invitee_1"));
            const notificationSnap = await (0, firestore_1.getDoc)((0, firestore_1.doc)(db, "notifications", "team_invite_added_workspace_invitee_1"));
            strict_1.default.equal(userSnap.data()?.workspaceId, "personal_ws");
            strict_1.default.equal(membershipSnap.data()?.role, "member");
            strict_1.default.equal(notificationSnap.data()?.workspaceId, "owner_ws");
            strict_1.default.equal(notificationSnap.data()?.targetUserId, "invitee_1");
        });
    });
}
//# sourceMappingURL=firestore_rules.test.js.map