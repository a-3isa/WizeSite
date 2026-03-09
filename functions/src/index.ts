import * as admin from "firebase-admin";
import {defineSecret} from "firebase-functions/params";
import {setGlobalOptions} from "firebase-functions/v2";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {HttpsError, onCall, onRequest} from "firebase-functions/v2/https";

admin.initializeApp();
setGlobalOptions({region: "us-central1", maxInstances: 10});

const db = admin.firestore();
const revenuecatWebhookSecret = defineSecret("REVENUECAT_WEBHOOK_SECRET");

type LimitType =
  | "activeProjects"
  | "expensesPerMonth"
  | "paymentsPerMonth"
  | "workerEntriesPerMonth"
  | "teamMembers";

const FREE_LIMITS: Record<LimitType, number> = {
  activeProjects: 1,
  expensesPerMonth: 30,
  paymentsPerMonth: 10,
  workerEntriesPerMonth: 10,
  teamMembers: 1,
};

type SubscriptionTier = "free" | "pro";
type SubscriptionStatus = "trial" | "active" | "grace" | "expired" | "canceled" | "unknown";

type SubscriptionDoc = {
  tier: SubscriptionTier;
  status: SubscriptionStatus;
};

function periodKey(now = new Date()): string {
  const month = `${now.getUTCMonth() + 1}`.padStart(2, "0");
  return `${now.getUTCFullYear()}${month}`;
}

function nextResetIso(now = new Date()): string {
  const next = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 1));
  return next.toISOString();
}

function parseTimestamp(input: unknown): admin.firestore.Timestamp | null {
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

function mapRevenueCatStatus(eventType: string, periodType: string): SubscriptionStatus {
  if (eventType === "BILLING_ISSUE") {
    return "grace";
  }
  if (eventType === "EXPIRATION") {
    return "expired";
  }
  if (eventType === "CANCELLATION") {
    return "canceled";
  }
  if (
    eventType === "INITIAL_PURCHASE" ||
    eventType === "RENEWAL" ||
    eventType === "UNCANCELLATION"
  ) {
    return periodType === "TRIAL" ? "trial" : "active";
  }
  return "unknown";
}

function mapRevenueCatTier(entitlements: unknown): SubscriptionTier {
  if (!Array.isArray(entitlements)) {
    return "free";
  }
  const hasPro = entitlements.some((item) => `${item}`.toLowerCase().includes("pro"));
  return hasPro ? "pro" : "free";
}

async function getSubscription(workspaceId: string): Promise<SubscriptionDoc> {
  const snap = await db.collection("subscriptions").doc(workspaceId).get();
  if (!snap.exists) {
    return {tier: "free", status: "expired"};
  }
  const data = snap.data() ?? {};
  return {
    tier: data.tier === "pro" ? "pro" : "free",
    status: normalizeStatus(`${data.status ?? "unknown"}`),
  };
}

function normalizeStatus(input: string): SubscriptionStatus {
  const allowed: SubscriptionStatus[] = [
    "trial",
    "active",
    "grace",
    "expired",
    "canceled",
    "unknown",
  ];
  if (allowed.includes(input as SubscriptionStatus)) {
    return input as SubscriptionStatus;
  }
  return "unknown";
}

function hasUnlimitedQuota(subscription: SubscriptionDoc): boolean {
  return subscription.tier === "pro" &&
    (subscription.status === "active" || subscription.status === "trial" || subscription.status === "grace");
}

async function roleForUser(workspaceId: string, userId: string): Promise<string | null> {
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

async function assertMember(workspaceId: string, userId: string): Promise<string> {
  const role = await roleForUser(workspaceId, userId);
  if (!role) {
    throw new HttpsError("permission-denied", "User is not a member of this workspace");
  }
  return role;
}

function requireString(data: Record<string, unknown>, key: string): string {
  const value = data[key];
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpsError("invalid-argument", `Missing required field: ${key}`);
  }
  return value.trim();
}

function requireNumber(data: Record<string, unknown>, key: string): number {
  const value = Number(data[key]);
  if (!Number.isFinite(value)) {
    throw new HttpsError("invalid-argument", `Invalid number: ${key}`);
  }
  return value;
}

async function getCurrentUsage(workspaceId: string, type: LimitType): Promise<number> {
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

function limitForType(type: LimitType): number {
  return FREE_LIMITS[type];
}

function quotaError(type: LimitType, current: number, max: number): never {
  throw new HttpsError("failed-precondition", "LIMIT_REACHED", {
    code: "LIMIT_REACHED",
    limitType: type,
    current,
    max,
  });
}

export const checkLimit = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }
  const workspaceId = requireString(request.data as Record<string, unknown>, "workspaceId");
  await assertMember(workspaceId, request.auth.uid);

  const type = requireString(request.data as Record<string, unknown>, "type") as LimitType;
  const delta = Math.max(1, Number(request.data.delta ?? 1));
  const validTypes: LimitType[] = [
    "activeProjects",
    "expensesPerMonth",
    "paymentsPerMonth",
    "workerEntriesPerMonth",
    "teamMembers",
  ];
  if (!validTypes.includes(type)) {
    throw new HttpsError("invalid-argument", "Unsupported limit type");
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

export const createProjectWithQuota = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }
  const data = request.data as Record<string, unknown>;
  const workspaceId = requireString(data, "workspaceId");
  const role = await assertMember(workspaceId, request.auth.uid);
  if (role !== "owner" && role !== "member") {
    throw new HttpsError("permission-denied", "Not allowed to create project");
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
    ownerId: request.auth.uid,
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
    createdBy: request.auth.uid,
    isArchived: false,
  });

  return {id: projectRef.id};
});

export const createExpenseWithQuota = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }
  const data = request.data as Record<string, unknown>;
  const workspaceId = requireString(data, "workspaceId");
  await assertMember(workspaceId, request.auth.uid);

  const projectId = requireString(data, "projectId");
  const category = requireString(data, "category");
  const amount = requireNumber(data, "amount");
  if (amount <= 0) {
    throw new HttpsError("invalid-argument", "Amount must be greater than zero");
  }

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
      category,
      amount,
      date: parseTimestamp(data.date) ?? admin.firestore.Timestamp.now(),
      notes: `${data.notes ?? ""}`.trim(),
      supplierName: `${data.supplierName ?? ""}`.trim(),
      paymentMethod: `${data.paymentMethod ?? ""}`.trim(),
      createdBy: request.auth!.uid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      isArchived: false,
    });
    tx.set(counterRef, {
      workspaceId,
      periodKey: periodKey(),
      expensesCount: admin.firestore.FieldValue.increment(1),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  });

  return {id: expenseRef.id};
});

export const createPaymentWithQuota = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }
  const data = request.data as Record<string, unknown>;
  const workspaceId = requireString(data, "workspaceId");
  await assertMember(workspaceId, request.auth.uid);

  const projectId = requireString(data, "projectId");
  const amount = requireNumber(data, "amount");
  if (amount <= 0) {
    throw new HttpsError("invalid-argument", "Amount must be greater than zero");
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
      createdBy: request.auth!.uid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      isArchived: false,
    });
    tx.set(counterRef, {
      workspaceId,
      periodKey: periodKey(),
      paymentsCount: admin.firestore.FieldValue.increment(1),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  });
  return {id: paymentRef.id};
});

export const createWorkerEntryWithQuota = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }
  const data = request.data as Record<string, unknown>;
  const workspaceId = requireString(data, "workspaceId");
  await assertMember(workspaceId, request.auth.uid);

  const workerId = requireString(data, "workerId");
  const projectId = requireString(data, "projectId");
  const daysWorked = requireNumber(data, "daysWorked");
  const dailyWage = requireNumber(data, "dailyWage");
  if (daysWorked <= 0 || dailyWage <= 0) {
    throw new HttpsError("invalid-argument", "Days worked and daily wage must be > 0");
  }
  const totalCost = daysWorked * dailyWage;

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
      createdBy: request.auth!.uid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      isArchived: false,
    });
    tx.set(counterRef, {
      workspaceId,
      periodKey: periodKey(),
      workerEntriesCount: admin.firestore.FieldValue.increment(1),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  });
  return {id: entryRef.id};
});

export const inviteMemberWithQuota = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }
  const data = request.data as Record<string, unknown>;
  const workspaceId = requireString(data, "workspaceId");
  const role = await assertMember(workspaceId, request.auth.uid);
  if (role !== "owner") {
    throw new HttpsError("permission-denied", "Only owner can invite members");
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

  return {ok: true};
});

export const revenuecatWebhook = onRequest(
  {secrets: [revenuecatWebhookSecret]},
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({error: "method_not_allowed"});
      return;
    }

    const expectedSecret = revenuecatWebhookSecret.value();
    if (!expectedSecret) {
      res.status(500).json({error: "missing_server_secret"});
      return;
    }
    const incomingAuth = req.headers.authorization ?? "";
    if (incomingAuth !== `Bearer ${expectedSecret}`) {
      res.status(401).json({error: "unauthorized"});
      return;
    }

    const event = (req.body?.event ?? req.body) as Record<string, unknown>;
    const workspaceId = `${event.app_user_id ?? ""}`.trim();
    if (!workspaceId) {
      res.status(400).json({error: "missing_workspace"});
      return;
    }

    const eventType = `${event.type ?? "UNKNOWN"}`;
    const periodType = `${event.period_type ?? "UNKNOWN"}`;
    const tier = mapRevenueCatTier(event.entitlement_ids);
    const status = mapRevenueCatStatus(eventType, periodType);
    const periodEndsAt =
      parseTimestamp(event.expiration_at_ms) ?? parseTimestamp(event.expires_date);
    const trialEndsAt = periodType === "TRIAL" ? periodEndsAt : null;
    const isAutoRenewing =
      status === "active" || status === "trial" || status === "grace";
    const store = `${event.store ?? "unknown"}`;

    await db.collection("subscriptions").doc(workspaceId).set(
      {
        workspaceId,
        tier,
        status,
        store,
        isAutoRenewing,
        trialEndsAt,
        periodEndsAt,
        lastSyncedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true},
    );

    await db.collection("notifications").add({
      workspaceId,
      type: "subscription_status_changed",
      title: "Subscription Updated",
      message: `Subscription is now ${tier.toUpperCase()} (${status})`,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    res.status(200).json({ok: true});
  },
);

async function recomputeProjectSummary(workspaceId: string, projectId: string): Promise<void> {
  const [projectSnap, expensesSnap, paymentsSnap, workerEntriesSnap] = await Promise.all([
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
  ]);

  if (!projectSnap.exists) {
    return;
  }
  const project = projectSnap.data() ?? {};
  const contractValue = Number(project.contractValue ?? 0);
  const completionPercentage = Math.max(0, Number(project.completionPercentage ?? 0));

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
  } else if (expectedFinalCost >= contractValue * 0.9) {
    riskLevel = "medium";
    healthStatus = "warning";
  }

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
  }, {merge: true});
}

export const onExpenseWriteRecompute = onDocumentWritten(
  "expenses/{expenseId}",
  async (event) => {
    const after = event.data?.after?.data();
    const before = event.data?.before?.data();
    const workspaceId = `${after?.workspaceId ?? before?.workspaceId ?? ""}`;
    const projectId = `${after?.projectId ?? before?.projectId ?? ""}`;
    if (!workspaceId || !projectId) {
      return;
    }
    await recomputeProjectSummary(workspaceId, projectId);
  },
);

export const onPaymentWriteRecompute = onDocumentWritten(
  "payments/{paymentId}",
  async (event) => {
    const after = event.data?.after?.data();
    const before = event.data?.before?.data();
    const workspaceId = `${after?.workspaceId ?? before?.workspaceId ?? ""}`;
    const projectId = `${after?.projectId ?? before?.projectId ?? ""}`;
    if (!workspaceId || !projectId) {
      return;
    }
    await recomputeProjectSummary(workspaceId, projectId);
  },
);

export const onWorkerEntryWriteRecompute = onDocumentWritten(
  "worker_entries/{entryId}",
  async (event) => {
    const after = event.data?.after?.data();
    const before = event.data?.before?.data();
    const workspaceId = `${after?.workspaceId ?? before?.workspaceId ?? ""}`;
    const projectId = `${after?.projectId ?? before?.projectId ?? ""}`;
    if (!workspaceId || !projectId) {
      return;
    }
    await recomputeProjectSummary(workspaceId, projectId);
  },
);
