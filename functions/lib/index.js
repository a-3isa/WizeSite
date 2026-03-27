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
Object.defineProperty(exports, "__esModule", { value: true });
exports.onProjectWriteRecompute = exports.onWorkerEntryWriteRecompute = exports.onPaymentWriteRecompute = exports.onExpenseWriteRecompute = exports.revenuecatWebhook = exports.inviteMemberWithQuota = exports.inviteMemberByEmail = exports.updateUserProfile = exports.deleteProjectCascade = exports.archiveWorkerEntryWithQuotaRefundHttp = exports.archiveWorkerEntryWithQuotaRefund = exports.archivePaymentWithQuotaRefundHttp = exports.archivePaymentWithQuotaRefund = exports.archiveExpenseWithQuotaRefundHttp = exports.archiveExpenseWithQuotaRefund = exports.createWorkerEntryWithQuotaHttp = exports.createWorkerEntryWithQuota = exports.createPaymentWithQuotaHttp = exports.createPaymentWithQuota = exports.createExpenseWithQuotaHttp = exports.createExpenseWithQuota = exports.createProjectWithQuotaHttp = exports.createProjectWithQuota = exports.checkLimit = exports.processVoiceExpenseHttp = exports.processVoiceExpense = void 0;
const admin = __importStar(require("firebase-admin"));
const params_1 = require("firebase-functions/params");
const v2_1 = require("firebase-functions/v2");
const firestore_1 = require("firebase-functions/v2/firestore");
const https_1 = require("firebase-functions/v2/https");
var process_voice_expense_1 = require("./voice/process_voice_expense");
Object.defineProperty(exports, "processVoiceExpense", { enumerable: true, get: function () { return process_voice_expense_1.processVoiceExpense; } });
Object.defineProperty(exports, "processVoiceExpenseHttp", { enumerable: true, get: function () { return process_voice_expense_1.processVoiceExpenseHttp; } });
admin.initializeApp();
(0, v2_1.setGlobalOptions)({ region: "us-central1", maxInstances: 10 });
const db = admin.firestore();
const revenuecatWebhookSecret = (0, params_1.defineSecret)("REVENUECAT_WEBHOOK_SECRET");
const FREE_LIMITS = {
    activeProjects: 1,
    expensesPerMonth: 30,
    paymentsPerMonth: 10,
    workerEntriesPerMonth: 10,
    teamMembers: 1,
};
function periodKey(now = new Date()) {
    const month = `${now.getUTCMonth() + 1}`.padStart(2, "0");
    return `${now.getUTCFullYear()}${month}`;
}
function nextResetIso(now = new Date()) {
    const next = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 1));
    return next.toISOString();
}
function parseTimestamp(input) {
    if (input == null) {
        return null;
    }
    if (typeof input === "string") {
        const parsed = Date.parse(input);
        if (Number.isNaN(parsed)) {
            return null;
        }
        return admin.firestore.Timestamp.fromMillis(parsed);
    }
    if (typeof input === "number") {
        return admin.firestore.Timestamp.fromMillis(input);
    }
    return null;
}
function mapRevenueCatStatus(eventType, periodType) {
    if (eventType === "BILLING_ISSUE") {
        return "grace";
    }
    if (eventType === "EXPIRATION") {
        return "expired";
    }
    if (eventType === "CANCELLATION") {
        return "canceled";
    }
    if (eventType === "INITIAL_PURCHASE" ||
        eventType === "RENEWAL" ||
        eventType === "UNCANCELLATION") {
        return periodType === "TRIAL" ? "trial" : "active";
    }
    return "unknown";
}
function mapRevenueCatTier(entitlements) {
    if (!Array.isArray(entitlements)) {
        return "free";
    }
    const hasPro = entitlements.some((item) => `${item}`.toLowerCase().includes("pro"));
    return hasPro ? "pro" : "free";
}
async function getSubscription(workspaceId) {
    const snap = await db.collection("subscriptions").doc(workspaceId).get();
    if (!snap.exists) {
        return { tier: "free", status: "expired" };
    }
    const data = snap.data() ?? {};
    return {
        tier: data.tier === "pro" ? "pro" : "free",
        status: normalizeStatus(`${data.status ?? "unknown"}`),
    };
}
function normalizeStatus(input) {
    const allowed = [
        "trial",
        "active",
        "grace",
        "expired",
        "canceled",
        "unknown",
    ];
    if (allowed.includes(input)) {
        return input;
    }
    return "unknown";
}
function hasUnlimitedQuota(subscription) {
    return subscription.tier === "pro" &&
        (subscription.status === "active" || subscription.status === "trial" || subscription.status === "grace");
}
async function roleForUser(workspaceId, userId) {
    const membershipSnap = await db
        .collection("memberships")
        .where("workspaceId", "==", workspaceId)
        .where("userId", "==", userId)
        .limit(1)
        .get();
    if (membershipSnap.empty) {
        return null;
    }
    return `${membershipSnap.docs[0].data().role ?? "member"}`;
}
async function assertMember(workspaceId, userId) {
    const role = await roleForUser(workspaceId, userId);
    if (!role) {
        throw new https_1.HttpsError("permission-denied", "User is not a member of this workspace");
    }
    return role;
}
function requireString(data, key) {
    const value = data[key];
    if (typeof value !== "string" || value.trim().length === 0) {
        throw new https_1.HttpsError("invalid-argument", `Missing required field: ${key}`);
    }
    return value.trim();
}
function requireNumber(data, key) {
    const value = Number(data[key]);
    if (!Number.isFinite(value)) {
        throw new https_1.HttpsError("invalid-argument", `Invalid number: ${key}`);
    }
    return value;
}
function payloadFrom(input) {
    if (!input || typeof input !== "object") {
        return {};
    }
    return input;
}
function bearerTokenFrom(authorizationHeader) {
    if (!authorizationHeader) {
        return null;
    }
    const match = authorizationHeader.match(/^Bearer\s+(.+)$/i);
    return match ? match[1] : null;
}
function httpStatusFor(code) {
    switch (code) {
        case "invalid-argument":
            return 400;
        case "unauthenticated":
            return 401;
        case "permission-denied":
            return 403;
        case "not-found":
            return 404;
        case "already-exists":
            return 409;
        case "failed-precondition":
            return 412;
        case "resource-exhausted":
            return 429;
        default:
            return 500;
    }
}
function canonicalCode(code) {
    return code.replace(/-/g, "_").toUpperCase();
}
async function maybeVerifyAppCheck(appCheckToken) {
    if (!appCheckToken) {
        return;
    }
    try {
        await admin.appCheck().verifyToken(appCheckToken);
    }
    catch (error) {
        console.warn("HTTP callable endpoint received an invalid App Check token", error);
    }
}
async function getCurrentUsage(workspaceId, type) {
    if (type === "activeProjects") {
        const snap = await db
            .collection("projects")
            .where("workspaceId", "==", workspaceId)
            .where("status", "==", "active")
            .where("isArchived", "==", false)
            .get();
        return snap.size;
    }
    if (type === "teamMembers") {
        const snap = await db.collection("memberships").where("workspaceId", "==", workspaceId).get();
        return snap.size;
    }
    const usageSnap = await db.collection("usage_counters").doc(`${workspaceId}_${periodKey()}`).get();
    const data = usageSnap.data() ?? {};
    if (type === "expensesPerMonth") {
        return Number(data.expensesCount ?? 0);
    }
    if (type === "paymentsPerMonth") {
        return Number(data.paymentsCount ?? 0);
    }
    return Number(data.workerEntriesCount ?? 0);
}
function limitForType(type) {
    return FREE_LIMITS[type];
}
function quotaError(type, current, max) {
    throw new https_1.HttpsError("failed-precondition", "LIMIT_REACHED", {
        code: "LIMIT_REACHED",
        limitType: type,
        current,
        max,
    });
}
function normalizeEmail(input) {
    return input.trim().toLowerCase();
}
function currencyCode(input) {
    const raw = `${input ?? "EGP"}`.trim().toUpperCase();
    return ["EGP", "USD", "SAR", "AED"].includes(raw) ? raw : "EGP";
}
function asBooleanOrUndefined(input) {
    if (typeof input === "boolean") {
        return input;
    }
    return undefined;
}
async function membershipDocs(workspaceId) {
    return db.collection("memberships").where("workspaceId", "==", workspaceId).get();
}
async function notificationRecipients(workspaceId, requireRiskAlerts = false) {
    const membershipSnap = await membershipDocs(workspaceId);
    if (membershipSnap.empty) {
        return [];
    }
    const userIds = membershipSnap.docs
        .map((doc) => `${doc.data().userId ?? ""}`.trim())
        .filter((id) => id.length > 0);
    const recipients = [];
    await Promise.all(userIds.map(async (userId) => {
        if (!requireRiskAlerts) {
            recipients.push(userId);
            return;
        }
        const userSnap = await db.collection("users").doc(userId).get();
        const data = userSnap.data() ?? {};
        if (data.riskAlertsEnabled !== false) {
            recipients.push(userId);
        }
    }));
    return recipients;
}
async function upsertNotificationForUsers({ workspaceId, userIds, type, title, message, projectId, }) {
    await Promise.all(userIds.map(async (userId) => {
        const docId = [type, projectId ?? "workspace", userId].join("_");
        await db.collection("notifications").doc(docId).set({
            workspaceId,
            targetUserId: userId,
            type,
            projectId: projectId ?? null,
            title,
            message,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
    }));
}
async function deleteNotificationForUsers(type, projectId, userIds) {
    await Promise.all(userIds.map(async (userId) => {
        const docId = [type, projectId, userId].join("_");
        await db.collection("notifications").doc(docId).delete().catch(() => undefined);
    }));
}
function compareRisk(current) {
    switch (current) {
        case "high":
            return 3;
        case "medium":
            return 2;
        default:
            return 1;
    }
}
async function recomputeWorkspaceMetrics(workspaceId) {
    const projectsSnap = await db
        .collection("projects")
        .where("workspaceId", "==", workspaceId)
        .where("isArchived", "==", false)
        .get();
    const projects = projectsSnap.docs.map((doc) => doc.data());
    const activeProjects = projects.filter((project) => `${project.status ?? "active"}` === "active").length;
    const totalExpenses = projects.reduce((sum, project) => sum + Number(project.totalExpenses ?? 0), 0);
    const totalIncome = projects.reduce((sum, project) => sum + Number(project.totalPayments ?? 0), 0);
    await db.collection("workspace_metrics").doc(workspaceId).set({
        workspaceId,
        totalProjects: projects.length,
        activeProjects,
        totalExpenses,
        totalIncome,
        net: totalIncome - totalExpenses,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
}
exports.checkLimit = (0, https_1.onCall)(async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Authentication required");
    }
    const workspaceId = requireString(request.data, "workspaceId");
    await assertMember(workspaceId, request.auth.uid);
    const type = requireString(request.data, "type");
    const delta = Math.max(1, Number(request.data.delta ?? 1));
    const validTypes = [
        "activeProjects",
        "expensesPerMonth",
        "paymentsPerMonth",
        "workerEntriesPerMonth",
        "teamMembers",
    ];
    if (!validTypes.includes(type)) {
        throw new https_1.HttpsError("invalid-argument", "Unsupported limit type");
    }
    const subscription = await getSubscription(workspaceId);
    if (hasUnlimitedQuota(subscription)) {
        return {
            allowed: true,
            current: 0,
            max: 999999,
            resetAt: nextResetIso(),
        };
    }
    const current = await getCurrentUsage(workspaceId, type);
    const max = limitForType(type);
    return {
        allowed: current + delta <= max,
        current,
        max,
        resetAt: nextResetIso(),
    };
});
async function createProjectWithQuotaForUser(uid, data) {
    const workspaceId = requireString(data, "workspaceId");
    const role = await assertMember(workspaceId, uid);
    if (role !== "owner" && role !== "member") {
        throw new https_1.HttpsError("permission-denied", "Not allowed to create project");
    }
    const name = requireString(data, "name");
    const clientName = `${data.clientName ?? ""}`.trim();
    const contractValue = requireNumber(data, "contractValue");
    const startDate = parseTimestamp(data.startDate) ?? admin.firestore.Timestamp.now();
    const expectedEndDate = parseTimestamp(data.expectedEndDate);
    const location = `${data.location ?? ""}`.trim();
    const description = `${data.description ?? ""}`.trim();
    const completionPercentage = Number(data.completionPercentage ?? 0);
    const budgetLimit = Number(data.budgetLimit ?? 0) || null;
    const subscription = await getSubscription(workspaceId);
    if (!hasUnlimitedQuota(subscription)) {
        const current = await getCurrentUsage(workspaceId, "activeProjects");
        const max = limitForType("activeProjects");
        if (current + 1 > max) {
            quotaError("activeProjects", current, max);
        }
    }
    const projectRef = db.collection("projects").doc();
    await projectRef.set({
        id: projectRef.id,
        workspaceId,
        ownerId: uid,
        name,
        clientName,
        contractValue,
        startDate,
        expectedEndDate,
        location,
        description,
        budgetLimit,
        completionPercentage,
        status: "active",
        totalExpenses: 0,
        totalLaborCost: 0,
        totalPayments: 0,
        netProfit: 0,
        expectedFinalCost: 0,
        remainingBalance: contractValue,
        riskLevel: "low",
        healthStatus: "healthy",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        createdBy: uid,
        isArchived: false,
    });
    return { id: projectRef.id };
}
exports.createProjectWithQuota = (0, https_1.onCall)(async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Authentication required");
    }
    return createProjectWithQuotaForUser(request.auth.uid, request.data);
});
exports.createProjectWithQuotaHttp = (0, https_1.onRequest)(async (request, response) => {
    response.set("Access-Control-Allow-Origin", "*");
    response.set("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Firebase-AppCheck");
    if (request.method === "OPTIONS") {
        response.status(204).send("");
        return;
    }
    if (request.method !== "POST") {
        response.status(405).json({
            error: {
                code: "method-not-allowed",
                status: "METHOD_NOT_ALLOWED",
                message: "Method not allowed",
            },
        });
        return;
    }
    try {
        await maybeVerifyAppCheck(request.header("X-Firebase-AppCheck") ?? undefined);
        const bearerToken = bearerTokenFrom(request.header("Authorization") ?? undefined);
        if (!bearerToken) {
            throw new https_1.HttpsError("unauthenticated", "Authentication required");
        }
        const decodedToken = await admin.auth().verifyIdToken(bearerToken);
        const body = payloadFrom(request.body);
        const data = Object.keys(payloadFrom(body.data)).length > 0 ?
            payloadFrom(body.data) :
            body;
        const result = await createProjectWithQuotaForUser(decodedToken.uid, data);
        response.status(200).json({ result });
    }
    catch (error) {
        const handled = error instanceof https_1.HttpsError ?
            error :
            new https_1.HttpsError("internal", "Failed to create project");
        response.status(httpStatusFor(handled.code)).json({
            error: {
                code: handled.code,
                status: canonicalCode(handled.code),
                message: handled.message,
                details: handled.details ?? null,
            },
        });
    }
});
exports.createExpenseWithQuota = (0, https_1.onCall)(async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Authentication required");
    }
    return createExpenseWithQuotaForUser(request.auth.uid, request.data);
});
async function createExpenseWithQuotaForUser(uid, data) {
    const workspaceId = requireString(data, "workspaceId");
    await assertMember(workspaceId, uid);
    const projectId = requireString(data, "projectId");
    const category = requireString(data, "category");
    const allowedCategories = ["labor", "materials", "equipment", "transport", "other"];
    if (!allowedCategories.includes(category)) {
        throw new https_1.HttpsError("invalid-argument", "Unsupported expense category");
    }
    const amount = requireNumber(data, "amount");
    if (amount <= 0) {
        throw new https_1.HttpsError("invalid-argument", "Amount must be greater than zero");
    }
    const projectSnap = await db.collection("projects").doc(projectId).get();
    if (!projectSnap.exists) {
        throw new https_1.HttpsError("invalid-argument", "Project does not exist");
    }
    const projectData = projectSnap.data() ?? {};
    if (`${projectData.workspaceId ?? ""}` !== workspaceId || projectData.isArchived === true) {
        throw new https_1.HttpsError("permission-denied", "Project is not available in this workspace");
    }
    const currencyRaw = `${data.currency ?? "EGP"}`.trim().toUpperCase();
    const currency = ["EGP", "USD", "SAR", "AED"].includes(currencyRaw) ? currencyRaw : "EGP";
    const inputMethod = `${data.inputMethod ?? "manual"}`.trim().toLowerCase();
    if (inputMethod !== "manual" && inputMethod !== "voice") {
        throw new https_1.HttpsError("invalid-argument", "inputMethod must be manual or voice");
    }
    const sourceRaw = `${data.source ?? ""}`.trim().toLowerCase();
    const source = sourceRaw === "rules" || sourceRaw === "llm" || sourceRaw === "hybrid" ?
        sourceRaw :
        null;
    const transcript = `${data.transcript ?? ""}`.trim();
    const storagePath = `${data.storagePath ?? ""}`.trim();
    const projectName = `${data.projectName ?? ""}`.trim() || `${projectData.name ?? ""}`.trim();
    const subscription = await getSubscription(workspaceId);
    if (!hasUnlimitedQuota(subscription)) {
        const current = await getCurrentUsage(workspaceId, "expensesPerMonth");
        const max = limitForType("expensesPerMonth");
        if (current + 1 > max) {
            quotaError("expensesPerMonth", current, max);
        }
    }
    const expenseRef = db.collection("expenses").doc();
    const counterRef = db.collection("usage_counters").doc(`${workspaceId}_${periodKey()}`);
    await db.runTransaction(async (tx) => {
        tx.set(expenseRef, {
            id: expenseRef.id,
            workspaceId,
            projectId,
            projectName,
            category,
            amount,
            currency,
            date: parseTimestamp(data.date) ?? admin.firestore.Timestamp.now(),
            notes: `${data.notes ?? ""}`.trim(),
            supplierName: `${data.supplierName ?? ""}`.trim(),
            paymentMethod: `${data.paymentMethod ?? ""}`.trim(),
            inputMethod,
            transcript,
            source,
            storagePath,
            createdBy: uid,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            isArchived: false,
        });
        tx.set(counterRef, {
            workspaceId,
            periodKey: periodKey(),
            expensesCount: admin.firestore.FieldValue.increment(1),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
    });
    return { id: expenseRef.id };
}
exports.createExpenseWithQuotaHttp = (0, https_1.onRequest)(async (request, response) => {
    response.set("Access-Control-Allow-Origin", "*");
    response.set("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Firebase-AppCheck");
    if (request.method === "OPTIONS") {
        response.status(204).send("");
        return;
    }
    if (request.method !== "POST") {
        response.status(405).json({
            error: {
                code: "method-not-allowed",
                status: "METHOD_NOT_ALLOWED",
                message: "Method not allowed",
            },
        });
        return;
    }
    try {
        await maybeVerifyAppCheck(request.header("X-Firebase-AppCheck") ?? undefined);
        const bearerToken = bearerTokenFrom(request.header("Authorization") ?? undefined);
        if (!bearerToken) {
            throw new https_1.HttpsError("unauthenticated", "Authentication required");
        }
        const decodedToken = await admin.auth().verifyIdToken(bearerToken);
        const body = payloadFrom(request.body);
        const data = Object.keys(payloadFrom(body.data)).length > 0 ?
            payloadFrom(body.data) :
            body;
        const result = await createExpenseWithQuotaForUser(decodedToken.uid, data);
        response.status(200).json({ result });
    }
    catch (error) {
        const handled = error instanceof https_1.HttpsError ?
            error :
            new https_1.HttpsError("internal", "Failed to save expense");
        response.status(httpStatusFor(handled.code)).json({
            error: {
                code: handled.code,
                status: canonicalCode(handled.code),
                message: handled.message,
                details: handled.details ?? null,
            },
        });
    }
});
async function createPaymentWithQuotaForUser(uid, data) {
    const workspaceId = requireString(data, "workspaceId");
    await assertMember(workspaceId, uid);
    const projectId = requireString(data, "projectId");
    const amount = requireNumber(data, "amount");
    if (amount <= 0) {
        throw new https_1.HttpsError("invalid-argument", "Amount must be greater than zero");
    }
    const projectSnap = await db.collection("projects").doc(projectId).get();
    if (!projectSnap.exists || `${projectSnap.data()?.workspaceId ?? ""}` !== workspaceId) {
        throw new https_1.HttpsError("invalid-argument", "Project does not exist");
    }
    const subscription = await getSubscription(workspaceId);
    if (!hasUnlimitedQuota(subscription)) {
        const current = await getCurrentUsage(workspaceId, "paymentsPerMonth");
        const max = limitForType("paymentsPerMonth");
        if (current + 1 > max) {
            quotaError("paymentsPerMonth", current, max);
        }
    }
    const paymentRef = db.collection("payments").doc();
    const counterRef = db.collection("usage_counters").doc(`${workspaceId}_${periodKey()}`);
    await db.runTransaction(async (tx) => {
        tx.set(paymentRef, {
            id: paymentRef.id,
            workspaceId,
            projectId,
            amount,
            date: parseTimestamp(data.date) ?? admin.firestore.Timestamp.now(),
            paymentMethod: `${data.paymentMethod ?? "cash"}`.trim(),
            notes: `${data.notes ?? ""}`.trim(),
            createdBy: uid,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            isArchived: false,
        });
        tx.set(counterRef, {
            workspaceId,
            periodKey: periodKey(),
            paymentsCount: admin.firestore.FieldValue.increment(1),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
    });
    return { id: paymentRef.id };
}
exports.createPaymentWithQuota = (0, https_1.onCall)(async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Authentication required");
    }
    return createPaymentWithQuotaForUser(request.auth.uid, request.data);
});
exports.createPaymentWithQuotaHttp = (0, https_1.onRequest)(async (request, response) => {
    response.set("Access-Control-Allow-Origin", "*");
    response.set("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Firebase-AppCheck");
    if (request.method === "OPTIONS") {
        response.status(204).send("");
        return;
    }
    if (request.method !== "POST") {
        response.status(405).json({
            error: {
                code: "method-not-allowed",
                status: "METHOD_NOT_ALLOWED",
                message: "Method not allowed",
            },
        });
        return;
    }
    try {
        await maybeVerifyAppCheck(request.header("X-Firebase-AppCheck") ?? undefined);
        const bearerToken = bearerTokenFrom(request.header("Authorization") ?? undefined);
        if (!bearerToken) {
            throw new https_1.HttpsError("unauthenticated", "Authentication required");
        }
        const decodedToken = await admin.auth().verifyIdToken(bearerToken);
        const body = payloadFrom(request.body);
        const data = Object.keys(payloadFrom(body.data)).length > 0 ?
            payloadFrom(body.data) :
            body;
        const result = await createPaymentWithQuotaForUser(decodedToken.uid, data);
        response.status(200).json({ result });
    }
    catch (error) {
        const handled = error instanceof https_1.HttpsError ?
            error :
            new https_1.HttpsError("internal", "Failed to save payment");
        response.status(httpStatusFor(handled.code)).json({
            error: {
                code: handled.code,
                status: canonicalCode(handled.code),
                message: handled.message,
                details: handled.details ?? null,
            },
        });
    }
});
async function createWorkerEntryWithQuotaForUser(uid, data) {
    const workspaceId = requireString(data, "workspaceId");
    await assertMember(workspaceId, uid);
    const workerId = requireString(data, "workerId");
    const projectId = requireString(data, "projectId");
    const daysWorked = requireNumber(data, "daysWorked");
    const dailyWage = requireNumber(data, "dailyWage");
    if (daysWorked <= 0 || dailyWage <= 0) {
        throw new https_1.HttpsError("invalid-argument", "Days worked and daily wage must be > 0");
    }
    const totalCost = daysWorked * dailyWage;
    const [workerSnap, projectSnap] = await Promise.all([
        db.collection("workers").doc(workerId).get(),
        db.collection("projects").doc(projectId).get(),
    ]);
    if (!workerSnap.exists || `${workerSnap.data()?.workspaceId ?? ""}` !== workspaceId) {
        throw new https_1.HttpsError("invalid-argument", "Worker does not exist");
    }
    if (!projectSnap.exists || `${projectSnap.data()?.workspaceId ?? ""}` !== workspaceId) {
        throw new https_1.HttpsError("invalid-argument", "Project does not exist");
    }
    const subscription = await getSubscription(workspaceId);
    if (!hasUnlimitedQuota(subscription)) {
        const current = await getCurrentUsage(workspaceId, "workerEntriesPerMonth");
        const max = limitForType("workerEntriesPerMonth");
        if (current + 1 > max) {
            quotaError("workerEntriesPerMonth", current, max);
        }
    }
    const entryRef = db.collection("worker_entries").doc();
    const counterRef = db.collection("usage_counters").doc(`${workspaceId}_${periodKey()}`);
    await db.runTransaction(async (tx) => {
        tx.set(entryRef, {
            id: entryRef.id,
            workspaceId,
            workerId,
            projectId,
            daysWorked,
            dailyWage,
            totalCost,
            date: parseTimestamp(data.date) ?? admin.firestore.Timestamp.now(),
            notes: `${data.notes ?? ""}`.trim(),
            createdBy: uid,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            isArchived: false,
        });
        tx.set(counterRef, {
            workspaceId,
            periodKey: periodKey(),
            workerEntriesCount: admin.firestore.FieldValue.increment(1),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
    });
    return { id: entryRef.id };
}
exports.createWorkerEntryWithQuota = (0, https_1.onCall)(async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Authentication required");
    }
    return createWorkerEntryWithQuotaForUser(request.auth.uid, request.data);
});
exports.createWorkerEntryWithQuotaHttp = (0, https_1.onRequest)(async (request, response) => {
    response.set("Access-Control-Allow-Origin", "*");
    response.set("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Firebase-AppCheck");
    if (request.method === "OPTIONS") {
        response.status(204).send("");
        return;
    }
    if (request.method !== "POST") {
        response.status(405).json({
            error: {
                code: "method-not-allowed",
                status: "METHOD_NOT_ALLOWED",
                message: "Method not allowed",
            },
        });
        return;
    }
    try {
        await maybeVerifyAppCheck(request.header("X-Firebase-AppCheck") ?? undefined);
        const bearerToken = bearerTokenFrom(request.header("Authorization") ?? undefined);
        if (!bearerToken) {
            throw new https_1.HttpsError("unauthenticated", "Authentication required");
        }
        const decodedToken = await admin.auth().verifyIdToken(bearerToken);
        const body = payloadFrom(request.body);
        const data = Object.keys(payloadFrom(body.data)).length > 0 ?
            payloadFrom(body.data) :
            body;
        const result = await createWorkerEntryWithQuotaForUser(decodedToken.uid, data);
        response.status(200).json({ result });
    }
    catch (error) {
        const handled = error instanceof https_1.HttpsError ?
            error :
            new https_1.HttpsError("internal", "Failed to save worker entry");
        response.status(httpStatusFor(handled.code)).json({
            error: {
                code: handled.code,
                status: canonicalCode(handled.code),
                message: handled.message,
                details: handled.details ?? null,
            },
        });
    }
});
async function archiveExpenseWithQuotaRefundForUser(uid, data) {
    const workspaceId = requireString(data, "workspaceId");
    await assertMember(workspaceId, uid);
    const expenseId = requireString(data, "expenseId");
    const expenseRef = db.collection("expenses").doc(expenseId);
    const counterRef = db.collection("usage_counters").doc(`${workspaceId}_${periodKey()}`);
    await db.runTransaction(async (tx) => {
        const expenseSnap = await tx.get(expenseRef);
        if (!expenseSnap.exists) {
            throw new https_1.HttpsError("not-found", "Expense not found");
        }
        const expense = expenseSnap.data() ?? {};
        if (`${expense.workspaceId ?? ""}` !== workspaceId) {
            throw new https_1.HttpsError("permission-denied", "Expense is not available in this workspace");
        }
        if (expense.isArchived === true) {
            return;
        }
        tx.update(expenseRef, {
            isArchived: true,
            archivedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        const counterSnap = await tx.get(counterRef);
        const current = Number(counterSnap.data()?.expensesCount ?? 0);
        tx.set(counterRef, {
            workspaceId,
            periodKey: periodKey(),
            expensesCount: Math.max(0, current - 1),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
    });
}
exports.archiveExpenseWithQuotaRefund = (0, https_1.onCall)(async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Authentication required");
    }
    await archiveExpenseWithQuotaRefundForUser(request.auth.uid, request.data);
});
exports.archiveExpenseWithQuotaRefundHttp = (0, https_1.onRequest)(async (request, response) => {
    response.set("Access-Control-Allow-Origin", "*");
    response.set("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Firebase-AppCheck");
    if (request.method === "OPTIONS") {
        response.status(204).send("");
        return;
    }
    if (request.method !== "POST") {
        response.status(405).json({
            error: {
                code: "method-not-allowed",
                status: "METHOD_NOT_ALLOWED",
                message: "Method not allowed",
            },
        });
        return;
    }
    try {
        await maybeVerifyAppCheck(request.header("X-Firebase-AppCheck") ?? undefined);
        const bearerToken = bearerTokenFrom(request.header("Authorization") ?? undefined);
        if (!bearerToken) {
            throw new https_1.HttpsError("unauthenticated", "Authentication required");
        }
        const decodedToken = await admin.auth().verifyIdToken(bearerToken);
        const body = payloadFrom(request.body);
        const data = Object.keys(payloadFrom(body.data)).length > 0 ?
            payloadFrom(body.data) :
            body;
        await archiveExpenseWithQuotaRefundForUser(decodedToken.uid, data);
        response.status(200).json({ result: { ok: true } });
    }
    catch (error) {
        const handled = error instanceof https_1.HttpsError ?
            error :
            new https_1.HttpsError("internal", "Failed to archive expense");
        response.status(httpStatusFor(handled.code)).json({
            error: {
                code: handled.code,
                status: canonicalCode(handled.code),
                message: handled.message,
                details: handled.details ?? null,
            },
        });
    }
});
async function archivePaymentWithQuotaRefundForUser(uid, data) {
    const workspaceId = requireString(data, "workspaceId");
    await assertMember(workspaceId, uid);
    const paymentId = requireString(data, "paymentId");
    const paymentRef = db.collection("payments").doc(paymentId);
    const counterRef = db.collection("usage_counters").doc(`${workspaceId}_${periodKey()}`);
    await db.runTransaction(async (tx) => {
        const paymentSnap = await tx.get(paymentRef);
        if (!paymentSnap.exists) {
            throw new https_1.HttpsError("not-found", "Payment not found");
        }
        const payment = paymentSnap.data() ?? {};
        if (`${payment.workspaceId ?? ""}` !== workspaceId) {
            throw new https_1.HttpsError("permission-denied", "Payment is not available in this workspace");
        }
        if (payment.isArchived === true) {
            return;
        }
        tx.update(paymentRef, {
            isArchived: true,
            archivedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        const counterSnap = await tx.get(counterRef);
        const current = Number(counterSnap.data()?.paymentsCount ?? 0);
        tx.set(counterRef, {
            workspaceId,
            periodKey: periodKey(),
            paymentsCount: Math.max(0, current - 1),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
    });
}
exports.archivePaymentWithQuotaRefund = (0, https_1.onCall)(async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Authentication required");
    }
    await archivePaymentWithQuotaRefundForUser(request.auth.uid, request.data);
});
exports.archivePaymentWithQuotaRefundHttp = (0, https_1.onRequest)(async (request, response) => {
    response.set("Access-Control-Allow-Origin", "*");
    response.set("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Firebase-AppCheck");
    if (request.method === "OPTIONS") {
        response.status(204).send("");
        return;
    }
    if (request.method !== "POST") {
        response.status(405).json({
            error: {
                code: "method-not-allowed",
                status: "METHOD_NOT_ALLOWED",
                message: "Method not allowed",
            },
        });
        return;
    }
    try {
        await maybeVerifyAppCheck(request.header("X-Firebase-AppCheck") ?? undefined);
        const bearerToken = bearerTokenFrom(request.header("Authorization") ?? undefined);
        if (!bearerToken) {
            throw new https_1.HttpsError("unauthenticated", "Authentication required");
        }
        const decodedToken = await admin.auth().verifyIdToken(bearerToken);
        const body = payloadFrom(request.body);
        const data = Object.keys(payloadFrom(body.data)).length > 0 ?
            payloadFrom(body.data) :
            body;
        await archivePaymentWithQuotaRefundForUser(decodedToken.uid, data);
        response.status(200).json({ result: { ok: true } });
    }
    catch (error) {
        const handled = error instanceof https_1.HttpsError ?
            error :
            new https_1.HttpsError("internal", "Failed to archive payment");
        response.status(httpStatusFor(handled.code)).json({
            error: {
                code: handled.code,
                status: canonicalCode(handled.code),
                message: handled.message,
                details: handled.details ?? null,
            },
        });
    }
});
async function archiveWorkerEntryWithQuotaRefundForUser(uid, data) {
    const workspaceId = requireString(data, "workspaceId");
    await assertMember(workspaceId, uid);
    const entryId = requireString(data, "entryId");
    const entryRef = db.collection("worker_entries").doc(entryId);
    const counterRef = db.collection("usage_counters").doc(`${workspaceId}_${periodKey()}`);
    await db.runTransaction(async (tx) => {
        const entrySnap = await tx.get(entryRef);
        if (!entrySnap.exists) {
            throw new https_1.HttpsError("not-found", "Worker entry not found");
        }
        const entry = entrySnap.data() ?? {};
        if (`${entry.workspaceId ?? ""}` !== workspaceId) {
            throw new https_1.HttpsError("permission-denied", "Worker entry is not available in this workspace");
        }
        if (entry.isArchived === true) {
            return;
        }
        tx.update(entryRef, {
            isArchived: true,
            archivedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        const counterSnap = await tx.get(counterRef);
        const current = Number(counterSnap.data()?.workerEntriesCount ?? 0);
        tx.set(counterRef, {
            workspaceId,
            periodKey: periodKey(),
            workerEntriesCount: Math.max(0, current - 1),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
    });
}
exports.archiveWorkerEntryWithQuotaRefund = (0, https_1.onCall)(async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Authentication required");
    }
    await archiveWorkerEntryWithQuotaRefundForUser(request.auth.uid, request.data);
});
exports.archiveWorkerEntryWithQuotaRefundHttp = (0, https_1.onRequest)(async (request, response) => {
    response.set("Access-Control-Allow-Origin", "*");
    response.set("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Firebase-AppCheck");
    if (request.method === "OPTIONS") {
        response.status(204).send("");
        return;
    }
    if (request.method !== "POST") {
        response.status(405).json({
            error: {
                code: "method-not-allowed",
                status: "METHOD_NOT_ALLOWED",
                message: "Method not allowed",
            },
        });
        return;
    }
    try {
        await maybeVerifyAppCheck(request.header("X-Firebase-AppCheck") ?? undefined);
        const bearerToken = bearerTokenFrom(request.header("Authorization") ?? undefined);
        if (!bearerToken) {
            throw new https_1.HttpsError("unauthenticated", "Authentication required");
        }
        const decodedToken = await admin.auth().verifyIdToken(bearerToken);
        const body = payloadFrom(request.body);
        const data = Object.keys(payloadFrom(body.data)).length > 0 ?
            payloadFrom(body.data) :
            body;
        await archiveWorkerEntryWithQuotaRefundForUser(decodedToken.uid, data);
        response.status(200).json({ result: { ok: true } });
    }
    catch (error) {
        const handled = error instanceof https_1.HttpsError ?
            error :
            new https_1.HttpsError("internal", "Failed to archive worker entry");
        response.status(httpStatusFor(handled.code)).json({
            error: {
                code: handled.code,
                status: canonicalCode(handled.code),
                message: handled.message,
                details: handled.details ?? null,
            },
        });
    }
});
exports.deleteProjectCascade = (0, https_1.onCall)(async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Authentication required");
    }
    const data = request.data;
    const workspaceId = requireString(data, "workspaceId");
    await assertMember(workspaceId, request.auth.uid);
    const projectId = requireString(data, "projectId");
    const projectRef = db.collection("projects").doc(projectId);
    const projectSnap = await projectRef.get();
    if (!projectSnap.exists) {
        throw new https_1.HttpsError("not-found", "Project not found");
    }
    const project = projectSnap.data() ?? {};
    if (`${project.workspaceId ?? ""}` !== workspaceId) {
        throw new https_1.HttpsError("permission-denied", "Project is not available in this workspace");
    }
    const [expensesSnap, paymentsSnap, entriesSnap, notificationsSnap] = await Promise.all([
        db.collection("expenses")
            .where("workspaceId", "==", workspaceId)
            .where("projectId", "==", projectId)
            .get(),
        db.collection("payments")
            .where("workspaceId", "==", workspaceId)
            .where("projectId", "==", projectId)
            .get(),
        db.collection("worker_entries")
            .where("workspaceId", "==", workspaceId)
            .where("projectId", "==", projectId)
            .get(),
        db.collection("notifications")
            .where("workspaceId", "==", workspaceId)
            .where("projectId", "==", projectId)
            .get(),
    ]);
    const expenseRefund = expensesSnap.docs.filter((doc) => doc.data().isArchived !== true).length;
    const paymentRefund = paymentsSnap.docs.filter((doc) => doc.data().isArchived !== true).length;
    const entryRefund = entriesSnap.docs.filter((doc) => doc.data().isArchived !== true).length;
    const counterRef = db.collection("usage_counters").doc(`${workspaceId}_${periodKey()}`);
    const batch = db.batch();
    batch.delete(projectRef);
    batch.delete(db.collection("project_metrics").doc(projectId));
    for (const doc of expensesSnap.docs) {
        batch.delete(doc.ref);
    }
    for (const doc of paymentsSnap.docs) {
        batch.delete(doc.ref);
    }
    for (const doc of entriesSnap.docs) {
        batch.delete(doc.ref);
    }
    for (const doc of notificationsSnap.docs) {
        batch.delete(doc.ref);
    }
    const counterSnap = await counterRef.get();
    const currentData = counterSnap.data() ?? {};
    batch.set(counterRef, {
        workspaceId,
        periodKey: periodKey(),
        expensesCount: Math.max(0, Number(currentData.expensesCount ?? 0) - expenseRefund),
        paymentsCount: Math.max(0, Number(currentData.paymentsCount ?? 0) - paymentRefund),
        workerEntriesCount: Math.max(0, Number(currentData.workerEntriesCount ?? 0) - entryRefund),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    await batch.commit();
    await recomputeWorkspaceMetrics(workspaceId);
});
exports.updateUserProfile = (0, https_1.onCall)(async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Authentication required");
    }
    const data = request.data;
    const fullName = requireString(data, "fullName");
    const photoUrl = `${data.photoUrl ?? ""}`.trim();
    const defaultCurrency = currencyCode(data.defaultCurrency);
    const riskAlertsEnabled = asBooleanOrUndefined(data.riskAlertsEnabled);
    await admin.auth().updateUser(request.auth.uid, {
        displayName: fullName,
        photoURL: photoUrl || undefined,
    });
    await db.collection("users").doc(request.auth.uid).set({
        fullName,
        photoUrl,
        defaultCurrency,
        ...(riskAlertsEnabled == null ? {} : { riskAlertsEnabled }),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
});
exports.inviteMemberByEmail = (0, https_1.onCall)(async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Authentication required");
    }
    const data = request.data;
    const workspaceId = requireString(data, "workspaceId");
    const ownerRole = await assertMember(workspaceId, request.auth.uid);
    if (ownerRole !== "owner") {
        throw new https_1.HttpsError("permission-denied", "Only owner can invite members");
    }
    const email = normalizeEmail(requireString(data, "email"));
    const role = `${data.role ?? "member"}`.trim() || "member";
    const userSnap = await db.collection("users").where("email", "==", email).limit(1).get();
    if (userSnap.empty) {
        throw new https_1.HttpsError("not-found", "No existing user was found with that email");
    }
    const userId = userSnap.docs[0].id;
    const existingMembership = await db
        .collection("memberships")
        .where("workspaceId", "==", workspaceId)
        .where("userId", "==", userId)
        .limit(1)
        .get();
    if (!existingMembership.empty) {
        throw new https_1.HttpsError("already-exists", "User is already a member of this workspace");
    }
    const subscription = await getSubscription(workspaceId);
    if (!hasUnlimitedQuota(subscription)) {
        const current = await getCurrentUsage(workspaceId, "teamMembers");
        const max = limitForType("teamMembers");
        if (current + 1 > max) {
            quotaError("teamMembers", current, max);
        }
    }
    await db.collection("memberships").add({
        workspaceId,
        userId,
        role,
        createdBy: request.auth.uid,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    await upsertNotificationForUsers({
        workspaceId,
        userIds: [userId],
        type: "team_invite_added",
        title: "Workspace Access Granted",
        message: "You were added to a workspace team.",
    });
});
exports.inviteMemberWithQuota = (0, https_1.onCall)(async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Authentication required");
    }
    const data = request.data;
    const workspaceId = requireString(data, "workspaceId");
    const role = await assertMember(workspaceId, request.auth.uid);
    if (role !== "owner") {
        throw new https_1.HttpsError("permission-denied", "Only owner can invite members");
    }
    const newUserId = requireString(data, "userId");
    const memberRole = `${data.role ?? "member"}`;
    const subscription = await getSubscription(workspaceId);
    if (!hasUnlimitedQuota(subscription)) {
        const current = await getCurrentUsage(workspaceId, "teamMembers");
        const max = limitForType("teamMembers");
        if (current + 1 > max) {
            quotaError("teamMembers", current, max);
        }
    }
    await db.collection("memberships").add({
        workspaceId,
        userId: newUserId,
        role: memberRole,
        createdBy: request.auth.uid,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { ok: true };
});
exports.revenuecatWebhook = (0, https_1.onRequest)({ secrets: [revenuecatWebhookSecret] }, async (req, res) => {
    if (req.method !== "POST") {
        res.status(405).json({ error: "method_not_allowed" });
        return;
    }
    const expectedSecret = revenuecatWebhookSecret.value();
    if (!expectedSecret) {
        res.status(500).json({ error: "missing_server_secret" });
        return;
    }
    const incomingAuth = req.headers.authorization ?? "";
    if (incomingAuth !== `Bearer ${expectedSecret}`) {
        res.status(401).json({ error: "unauthorized" });
        return;
    }
    const event = (req.body?.event ?? req.body);
    const workspaceId = `${event.app_user_id ?? ""}`.trim();
    if (!workspaceId) {
        res.status(400).json({ error: "missing_workspace" });
        return;
    }
    const eventType = `${event.type ?? "UNKNOWN"}`;
    const periodType = `${event.period_type ?? "UNKNOWN"}`;
    const tier = mapRevenueCatTier(event.entitlement_ids);
    const status = mapRevenueCatStatus(eventType, periodType);
    const periodEndsAt = parseTimestamp(event.expiration_at_ms) ?? parseTimestamp(event.expires_date);
    const trialEndsAt = periodType === "TRIAL" ? periodEndsAt : null;
    const isAutoRenewing = status === "active" || status === "trial" || status === "grace";
    const store = `${event.store ?? "unknown"}`;
    await db.collection("subscriptions").doc(workspaceId).set({
        workspaceId,
        tier,
        status,
        store,
        isAutoRenewing,
        trialEndsAt,
        periodEndsAt,
        lastSyncedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    const recipients = await notificationRecipients(workspaceId, false);
    await upsertNotificationForUsers({
        workspaceId,
        userIds: recipients,
        type: "subscription_status_changed",
        title: "Subscription Updated",
        message: `Subscription is now ${tier.toUpperCase()} (${status})`,
    });
    res.status(200).json({ ok: true });
});
async function recomputeProjectSummary(workspaceId, projectId) {
    const [projectSnap, expensesSnap, paymentsSnap, workerEntriesSnap, workersSnap] = await Promise.all([
        db.collection("projects").doc(projectId).get(),
        db.collection("expenses")
            .where("workspaceId", "==", workspaceId)
            .where("projectId", "==", projectId)
            .where("isArchived", "==", false)
            .get(),
        db.collection("payments")
            .where("workspaceId", "==", workspaceId)
            .where("projectId", "==", projectId)
            .where("isArchived", "==", false)
            .get(),
        db.collection("worker_entries")
            .where("workspaceId", "==", workspaceId)
            .where("projectId", "==", projectId)
            .where("isArchived", "==", false)
            .get(),
        db.collection("workers")
            .where("workspaceId", "==", workspaceId)
            .where("isArchived", "==", false)
            .get(),
    ]);
    if (!projectSnap.exists) {
        return;
    }
    const project = projectSnap.data() ?? {};
    const contractValue = Number(project.contractValue ?? 0);
    const completionPercentage = Math.max(0, Number(project.completionPercentage ?? 0));
    const budgetLimit = Number(project.budgetLimit ?? 0) || null;
    const previousRiskLevel = `${project.riskLevel ?? "low"}`;
    const previousHealthStatus = `${project.healthStatus ?? "healthy"}`;
    const manualExpenses = expensesSnap.docs.reduce((sum, doc) => sum + Number(doc.data().amount ?? 0), 0);
    const laborExpenses = workerEntriesSnap.docs.reduce((sum, doc) => sum + Number(doc.data().totalCost ?? 0), 0);
    const totalExpenses = manualExpenses + laborExpenses;
    const totalPayments = paymentsSnap.docs.reduce((sum, doc) => sum + Number(doc.data().amount ?? 0), 0);
    const netProfit = totalPayments - totalExpenses;
    const remainingBalance = contractValue - totalPayments;
    const expectedFinalCost = completionPercentage > 0
        ? totalExpenses / (completionPercentage / 100)
        : totalExpenses;
    let riskLevel = "low";
    let healthStatus = "healthy";
    if (netProfit < 0 || expectedFinalCost > contractValue) {
        riskLevel = "high";
        healthStatus = "losing";
    }
    else if (expectedFinalCost >= contractValue * 0.9) {
        riskLevel = "medium";
        healthStatus = "warning";
    }
    const budgetExceeded = budgetLimit != null && totalExpenses > budgetLimit;
    await db.collection("projects").doc(projectId).set({
        totalExpenses,
        totalLaborCost: laborExpenses,
        totalPayments,
        netProfit,
        remainingBalance,
        expectedFinalCost,
        riskLevel,
        healthStatus,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    const categoryTotals = expensesSnap.docs.reduce((map, doc) => {
        const category = `${doc.data().category ?? "other"}`;
        map[category] = (map[category] ?? 0) + Number(doc.data().amount ?? 0);
        return map;
    }, {});
    const now = new Date();
    const monthlyFlow = Array.from({ length: 6 }).map((_, index) => {
        const monthDate = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - (5 - index), 1));
        const monthKey = `${monthDate.getUTCFullYear()}-${`${monthDate.getUTCMonth() + 1}`.padStart(2, "0")}`;
        return {
            month: monthKey,
            expenses: 0,
            income: 0,
        };
    });
    const monthlyIndex = new Map(monthlyFlow.map((item, index) => [item.month, index]));
    for (const doc of expensesSnap.docs) {
        const date = parseTimestamp(doc.data().date)?.toDate();
        if (!date) {
            continue;
        }
        const key = `${date.getUTCFullYear()}-${`${date.getUTCMonth() + 1}`.padStart(2, "0")}`;
        const index = monthlyIndex.get(key);
        if (index != null) {
            monthlyFlow[index].expenses += Number(doc.data().amount ?? 0);
        }
    }
    for (const doc of workerEntriesSnap.docs) {
        const date = parseTimestamp(doc.data().date)?.toDate();
        if (!date) {
            continue;
        }
        const key = `${date.getUTCFullYear()}-${`${date.getUTCMonth() + 1}`.padStart(2, "0")}`;
        const index = monthlyIndex.get(key);
        if (index != null) {
            monthlyFlow[index].expenses += Number(doc.data().totalCost ?? 0);
        }
    }
    for (const doc of paymentsSnap.docs) {
        const date = parseTimestamp(doc.data().date)?.toDate();
        if (!date) {
            continue;
        }
        const key = `${date.getUTCFullYear()}-${`${date.getUTCMonth() + 1}`.padStart(2, "0")}`;
        const index = monthlyIndex.get(key);
        if (index != null) {
            monthlyFlow[index].income += Number(doc.data().amount ?? 0);
        }
    }
    const workerNameMap = new Map();
    for (const doc of workersSnap.docs) {
        workerNameMap.set(doc.id, `${doc.data().name ?? doc.id}`);
    }
    const workerCosts = workerEntriesSnap.docs.reduce((map, doc) => {
        const workerId = `${doc.data().workerId ?? ""}`;
        const current = map[workerId] ?? {
            name: workerNameMap.get(workerId) ?? workerId,
            totalCost: 0,
            totalDays: 0,
        };
        current.totalCost += Number(doc.data().totalCost ?? 0);
        current.totalDays += Number(doc.data().daysWorked ?? 0);
        map[workerId] = current;
        return map;
    }, {});
    const topWorkers = Object.entries(workerCosts)
        .map(([workerId, data]) => ({ workerId, ...data }))
        .sort((a, b) => b.totalCost - a.totalCost)
        .slice(0, 5);
    const recentExpenses = expensesSnap.docs
        .map((doc) => ({ id: doc.id, ...doc.data() }))
        .sort((a, b) => {
        const aEntry = a;
        const bEntry = b;
        const aDate = parseTimestamp(aEntry["date"])?.toMillis() ?? 0;
        const bDate = parseTimestamp(bEntry["date"])?.toMillis() ?? 0;
        return bDate - aDate;
    })
        .slice(0, 5);
    const recentPayments = paymentsSnap.docs
        .map((doc) => ({ id: doc.id, ...doc.data() }))
        .sort((a, b) => {
        const aEntry = a;
        const bEntry = b;
        const aDate = parseTimestamp(aEntry["date"])?.toMillis() ?? 0;
        const bDate = parseTimestamp(bEntry["date"])?.toMillis() ?? 0;
        return bDate - aDate;
    })
        .slice(0, 5);
    await db.collection("project_metrics").doc(projectId).set({
        workspaceId,
        projectId,
        projectName: `${project.name ?? ""}`,
        status: `${project.status ?? "active"}`,
        isArchived: project.isArchived === true,
        totalExpenses,
        totalIncome: totalPayments,
        net: totalPayments - totalExpenses,
        categoryTotals,
        monthlyFlow,
        topWorkers,
        recentExpenses,
        recentPayments,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    await recomputeWorkspaceMetrics(workspaceId);
    const memberIds = (await membershipDocs(workspaceId)).docs
        .map((doc) => `${doc.data().userId ?? ""}`.trim())
        .filter((id) => id.length > 0);
    const riskAlertRecipients = await notificationRecipients(workspaceId, true);
    if (budgetExceeded) {
        await upsertNotificationForUsers({
            workspaceId,
            userIds: riskAlertRecipients,
            type: "budget_exceeded",
            projectId,
            title: "Budget Limit Exceeded",
            message: `Project ${project.name ?? "project"} exceeded its budget limit.`,
        });
    }
    else {
        await deleteNotificationForUsers("budget_exceeded", projectId, memberIds);
    }
    const riskWorsened = compareRisk(riskLevel) > compareRisk(previousRiskLevel) ||
        (previousHealthStatus === "healthy" && healthStatus !== "healthy");
    if (riskWorsened && riskLevel !== "low") {
        await upsertNotificationForUsers({
            workspaceId,
            userIds: riskAlertRecipients,
            type: "project_risk_alert",
            projectId,
            title: "Project Risk Alert",
            message: `Project ${project.name ?? "project"} is now ${riskLevel.toUpperCase()} risk (${healthStatus}).`,
        });
    }
    else if (riskLevel === "low" && healthStatus === "healthy") {
        await deleteNotificationForUsers("project_risk_alert", projectId, memberIds);
    }
    const expectedEndDate = parseTimestamp(project.expectedEndDate)?.toDate();
    if (expectedEndDate) {
        const daysRemaining = Math.ceil((expectedEndDate.getTime() - Date.now()) / (1000 * 60 * 60 * 24));
        if (`${project.status ?? "active"}` === "active" && daysRemaining <= 3) {
            const deadlineMessage = daysRemaining < 0 ?
                `Project ${project.name ?? "project"} is past its expected end date.` :
                `Project ${project.name ?? "project"} is due in ${daysRemaining} day(s).`;
            await upsertNotificationForUsers({
                workspaceId,
                userIds: riskAlertRecipients,
                type: "project_deadline_alert",
                projectId,
                title: "Project Deadline Reminder",
                message: deadlineMessage,
            });
        }
        else {
            await deleteNotificationForUsers("project_deadline_alert", projectId, memberIds);
        }
    }
}
exports.onExpenseWriteRecompute = (0, firestore_1.onDocumentWritten)("expenses/{expenseId}", async (event) => {
    const after = event.data?.after?.data();
    const before = event.data?.before?.data();
    const workspaceId = `${after?.workspaceId ?? before?.workspaceId ?? ""}`;
    const projectId = `${after?.projectId ?? before?.projectId ?? ""}`;
    if (!workspaceId || !projectId) {
        return;
    }
    await recomputeProjectSummary(workspaceId, projectId);
});
exports.onPaymentWriteRecompute = (0, firestore_1.onDocumentWritten)("payments/{paymentId}", async (event) => {
    const after = event.data?.after?.data();
    const before = event.data?.before?.data();
    const workspaceId = `${after?.workspaceId ?? before?.workspaceId ?? ""}`;
    const projectId = `${after?.projectId ?? before?.projectId ?? ""}`;
    if (!workspaceId || !projectId) {
        return;
    }
    await recomputeProjectSummary(workspaceId, projectId);
});
exports.onWorkerEntryWriteRecompute = (0, firestore_1.onDocumentWritten)("worker_entries/{entryId}", async (event) => {
    const after = event.data?.after?.data();
    const before = event.data?.before?.data();
    const workspaceId = `${after?.workspaceId ?? before?.workspaceId ?? ""}`;
    const projectId = `${after?.projectId ?? before?.projectId ?? ""}`;
    if (!workspaceId || !projectId) {
        return;
    }
    await recomputeProjectSummary(workspaceId, projectId);
});
exports.onProjectWriteRecompute = (0, firestore_1.onDocumentWritten)("projects/{projectId}", async (event) => {
    const after = event.data?.after?.data();
    const before = event.data?.before?.data();
    const workspaceId = `${after?.workspaceId ?? before?.workspaceId ?? ""}`;
    const projectId = `${event.params.projectId ?? ""}`;
    if (!workspaceId || !projectId) {
        return;
    }
    if (!after) {
        await db.collection("project_metrics").doc(projectId).delete().catch(() => undefined);
        await recomputeWorkspaceMetrics(workspaceId);
        return;
    }
    await recomputeProjectSummary(workspaceId, projectId);
});
//# sourceMappingURL=index.js.map