import * as admin from "firebase-admin";
import {defineBoolean, defineSecret} from "firebase-functions/params";
import {setGlobalOptions} from "firebase-functions/v2";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {HttpsError, onCall, onRequest} from "firebase-functions/v2/https";
export {processVoiceExpense, processVoiceExpenseHttp} from "./voice/process_voice_expense";

admin.initializeApp();
setGlobalOptions({region: "us-central1", maxInstances: 10});

const db = admin.firestore();
const revenuecatWebhookSecret = defineSecret("REVENUECAT_WEBHOOK_SECRET");
const enforceHttpAppCheck = defineBoolean("ENFORCE_HTTP_APP_CHECK");

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
  const deterministicMembership = await membershipRef(workspaceId, userId).get();
  if (deterministicMembership.exists) {
    return `${deterministicMembership.data()?.role ?? "member"}`;
  }

  const membershipSnap = await db
    .collection("memberships")
    .where("workspaceId", "==", workspaceId)
    .where("userId", "==", userId)
    .limit(1)
    .get();
  if (membershipSnap.empty) {
    return null;
  }
  const legacyData = membershipSnap.docs[0].data();
  await membershipRef(workspaceId, userId).set(
    {
      workspaceId,
      userId,
      role: `${legacyData.role ?? "member"}`,
      createdAt: legacyData.createdAt ?? admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
  return `${legacyData.role ?? "member"}`;
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

function payloadFrom(input: unknown): Record<string, unknown> {
  if (!input || typeof input !== "object") {
    return {};
  }
  return input as Record<string, unknown>;
}

function bearerTokenFrom(authorizationHeader: string | undefined): string | null {
  if (!authorizationHeader) {
    return null;
  }
  const match = authorizationHeader.match(/^Bearer\s+(.+)$/i);
  return match ? match[1] : null;
}

function httpStatusFor(code: string): number {
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

function canonicalCode(code: string): string {
  return code.replace(/-/g, "_").toUpperCase();
}

function membershipDocId(workspaceId: string, userId: string): string {
  return `${workspaceId}_${userId}`;
}

function membershipRef(workspaceId: string, userId: string) {
  return db.collection("memberships").doc(membershipDocId(workspaceId, userId));
}

async function verifyHttpAppCheck(appCheckToken: string | undefined): Promise<void> {
  const enforce = enforceHttpAppCheck.value();
  if (!appCheckToken) {
    if (enforce) {
      throw new HttpsError("failed-precondition", "Missing App Check token");
    }
    return;
  }

  try {
    await admin.appCheck().verifyToken(appCheckToken);
  } catch (error) {
    if (enforce) {
      throw new HttpsError("failed-precondition", "Invalid App Check token");
    }
    console.warn("HTTP callable endpoint received an invalid App Check token", error);
  }
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

function normalizeEmail(input: string): string {
  return input.trim().toLowerCase();
}

function currencyCode(input: unknown): string {
  const raw = `${input ?? "EGP"}`.trim().toUpperCase();
  return ["EGP", "USD", "SAR", "AED"].includes(raw) ? raw : "EGP";
}

function asBooleanOrUndefined(input: unknown): boolean | undefined {
  if (typeof input === "boolean") {
    return input;
  }
  return undefined;
}

type TriggerDocData = Record<string, unknown>;

type TriggerSnapshotLike = {
  data: () => TriggerDocData | undefined;
};

type FirestoreWrittenEventLike<TParams extends Record<string, string | undefined>> = {
  data?: {
    before?: TriggerSnapshotLike;
    after?: TriggerSnapshotLike;
  };
  params: TParams;
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === "object" && !Array.isArray(value);
}

function asComparable(value: unknown): unknown {
  if (value instanceof admin.firestore.Timestamp) {
    return value.toMillis();
  }
  if (value instanceof Date) {
    return value.getTime();
  }
  if (value && typeof value === "object" && "toMillis" in value && typeof (value as {toMillis?: unknown}).toMillis === "function") {
    return (value as {toMillis: () => number}).toMillis();
  }
  return value;
}

export function shallowEqualDerivedState(left: unknown, right: unknown): boolean {
  const a = asComparable(left);
  const b = asComparable(right);
  if (a === b) {
    return true;
  }
  if (Array.isArray(a) && Array.isArray(b)) {
    if (a.length !== b.length) {
      return false;
    }
    return a.every((item, index) => shallowEqualDerivedState(item, b[index]));
  }
  if (!isRecord(a) || !isRecord(b)) {
    return false;
  }
  const keysA = Object.keys(a).sort();
  const keysB = Object.keys(b).sort();
  if (keysA.length !== keysB.length) {
    return false;
  }
  for (let index = 0; index < keysA.length; index += 1) {
    if (keysA[index] !== keysB[index]) {
      return false;
    }
    if (!shallowEqualDerivedState(a[keysA[index]], b[keysB[index]])) {
      return false;
    }
  }
  return true;
}

function hasSubsetChanged(current: TriggerDocData, next: TriggerDocData): boolean {
  return Object.entries(next).some(([key, value]) => !shallowEqualDerivedState(current[key], value));
}

export async function writeIfChanged(
  ref: admin.firestore.DocumentReference,
  nextData: TriggerDocData,
  merge = true,
): Promise<boolean> {
  const currentSnap = await ref.get();
  const current = currentSnap.data() ?? {};
  if (!hasSubsetChanged(current as TriggerDocData, nextData)) {
    return false;
  }

  await ref.set(
    {
      ...nextData,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    {merge},
  );
  return true;
}

function changedString(before: TriggerDocData, after: TriggerDocData, key: string): boolean {
  return `${before[key] ?? ""}` !== `${after[key] ?? ""}`;
}

function changedBoolean(before: TriggerDocData, after: TriggerDocData, key: string): boolean {
  return Boolean(before[key]) !== Boolean(after[key]);
}

function changedNumber(before: TriggerDocData, after: TriggerDocData, key: string): boolean {
  return Number(before[key] ?? 0) !== Number(after[key] ?? 0);
}

function changedTimestamp(before: TriggerDocData, after: TriggerDocData, key: string): boolean {
  const beforeMillis = parseTimestamp(before[key])?.toMillis() ?? null;
  const afterMillis = parseTimestamp(after[key])?.toMillis() ?? null;
  return beforeMillis !== afterMillis;
}

export function hasRelevantProjectFieldsChanged(
  before: TriggerDocData,
  after: TriggerDocData,
): boolean {
  return changedString(before, after, "workspaceId") ||
    changedString(before, after, "name") ||
    changedString(before, after, "status") ||
    changedBoolean(before, after, "isArchived") ||
    changedNumber(before, after, "contractValue") ||
    changedNumber(before, after, "completionPercentage") ||
    changedNumber(before, after, "budgetLimit") ||
    changedTimestamp(before, after, "expectedEndDate");
}

export function hasRelevantExpenseFieldsChanged(
  before: TriggerDocData,
  after: TriggerDocData,
): boolean {
  return changedString(before, after, "workspaceId") ||
    changedString(before, after, "projectId") ||
    changedString(before, after, "category") ||
    changedNumber(before, after, "amount") ||
    changedBoolean(before, after, "isArchived") ||
    changedTimestamp(before, after, "date");
}

export function hasRelevantPaymentFieldsChanged(
  before: TriggerDocData,
  after: TriggerDocData,
): boolean {
  return changedString(before, after, "workspaceId") ||
    changedString(before, after, "projectId") ||
    changedNumber(before, after, "amount") ||
    changedBoolean(before, after, "isArchived") ||
    changedTimestamp(before, after, "date");
}

export function hasRelevantWorkerEntryFieldsChanged(
  before: TriggerDocData,
  after: TriggerDocData,
): boolean {
  return changedString(before, after, "workspaceId") ||
    changedString(before, after, "projectId") ||
    changedString(before, after, "workerId") ||
    changedNumber(before, after, "daysWorked") ||
    changedNumber(before, after, "totalCost") ||
    changedBoolean(before, after, "isArchived") ||
    changedTimestamp(before, after, "date");
}

type AggregateTarget = {
  workspaceId: string;
  projectId: string;
};

function aggregateTargetFromDoc(data: TriggerDocData | undefined): AggregateTarget | null {
  if (!data || data.isArchived === true) {
    return null;
  }
  const workspaceId = `${data.workspaceId ?? ""}`.trim();
  const projectId = `${data.projectId ?? ""}`.trim();
  if (!workspaceId || !projectId) {
    return null;
  }
  return {workspaceId, projectId};
}

function aggregateTargetsFromChange(
  before: TriggerDocData | undefined,
  after: TriggerDocData | undefined,
): AggregateTarget[] {
  const targets = new Map<string, AggregateTarget>();
  for (const item of [before, after]) {
    const target = aggregateTargetFromDoc(item);
    if (!target) {
      continue;
    }
    targets.set(`${target.workspaceId}::${target.projectId}`, target);
  }
  return [...targets.values()];
}

async function membershipDocs(workspaceId: string) {
  return db.collection("memberships").where("workspaceId", "==", workspaceId).get();
}

async function notificationRecipients(workspaceId: string, requireRiskAlerts = false): Promise<string[]> {
  const membershipSnap = await membershipDocs(workspaceId);
  if (membershipSnap.empty) {
    return [];
  }

  const userIds = membershipSnap.docs
    .map((doc) => `${doc.data().userId ?? ""}`.trim())
    .filter((id) => id.length > 0);

  if (!requireRiskAlerts) {
    return userIds;
  }
  return riskAlertRecipientsFromMembers(userIds);
}

async function riskAlertRecipientsFromMembers(userIds: string[]): Promise<string[]> {
  if (userIds.length === 0) {
    return [];
  }
  const refs = userIds.map((userId) => db.collection("users").doc(userId));
  const snaps = await db.getAll(...refs);
  return snaps
    .map((snap, index) => {
      const data = snap.data() ?? {};
      if (data.riskAlertsEnabled === false) {
        return null;
      }
      return userIds[index];
    })
    .filter((id): id is string => !!id);
}

async function upsertNotificationForUsers({
  workspaceId,
  userIds,
  type,
  title,
  message,
  projectId,
}: {
  workspaceId: string;
  userIds: string[];
  type: string;
  title: string;
  message: string;
  projectId?: string;
}): Promise<void> {
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
    }, {merge: true});
  }));
}

async function deleteNotificationForUsers(type: string, projectId: string, userIds: string[]): Promise<void> {
  await Promise.all(userIds.map(async (userId) => {
    const docId = [type, projectId, userId].join("_");
    await db.collection("notifications").doc(docId).delete().catch(() => undefined);
  }));
}

function compareRisk(current: string): number {
  switch (current) {
  case "high":
    return 3;
  case "medium":
    return 2;
  default:
    return 1;
  }
}

async function workerNameMapForEntries(
  workspaceId: string,
  workerIds: string[],
): Promise<Map<string, string>> {
  if (workerIds.length === 0) {
    return new Map<string, string>();
  }
  const workerRefs = workerIds.map((workerId) => db.collection("workers").doc(workerId));
  const workerSnaps = await db.getAll(...workerRefs);
  const map = new Map<string, string>();
  for (const snap of workerSnaps) {
    if (!snap.exists) {
      continue;
    }
    const data = snap.data() ?? {};
    if (`${data.workspaceId ?? ""}` !== workspaceId || data.isArchived === true) {
      continue;
    }
    map.set(snap.id, `${data.name ?? snap.id}`);
  }
  return map;
}

type MonthlyFlowPoint = {
  month: string;
  expenses: number;
  income: number;
};

type TopWorkerMetric = {
  workerId: string;
  name: string;
  totalCost: number;
  totalDays: number;
};

function buildProjectMetricsPayload(input: {
  workspaceId: string;
  projectId: string;
  project: TriggerDocData;
  contractValue: number;
  completionPercentage: number;
  budgetLimit: number | null;
  budgetExceeded: boolean;
  totalExpenses: number;
  laborExpenses: number;
  totalPayments: number;
  netProfit: number;
  remainingBalance: number;
  expectedFinalCost: number;
  riskLevel: string;
  healthStatus: string;
  categoryTotals: Record<string, number>;
  monthlyFlow: MonthlyFlowPoint[];
  topWorkers: TopWorkerMetric[];
  recentExpenses: Record<string, unknown>[];
  recentPayments: Record<string, unknown>[];
}): TriggerDocData {
  return {
    workspaceId: input.workspaceId,
    projectId: input.projectId,
    projectName: `${input.project.name ?? ""}`,
    status: `${input.project.status ?? "active"}`,
    isArchived: input.project.isArchived === true,
    contractValue: input.contractValue,
    completionPercentage: input.completionPercentage,
    budgetLimit: input.budgetLimit,
    budgetExceeded: input.budgetExceeded,
    totalExpenses: input.totalExpenses,
    totalLaborCost: input.laborExpenses,
    totalPayments: input.totalPayments,
    totalIncome: input.totalPayments,
    net: input.totalPayments - input.totalExpenses,
    netProfit: input.netProfit,
    remainingBalance: input.remainingBalance,
    expectedFinalCost: input.expectedFinalCost,
    riskLevel: input.riskLevel,
    healthStatus: input.healthStatus,
    categoryTotals: input.categoryTotals,
    monthlyFlow: input.monthlyFlow,
    topWorkers: input.topWorkers,
    recentExpenses: input.recentExpenses,
    recentPayments: input.recentPayments,
  };
}

async function recomputeWorkspaceMetrics(workspaceId: string): Promise<void> {
  const projectMetricsSnap = await db
    .collection("project_metrics")
    .where("workspaceId", "==", workspaceId)
    .where("isArchived", "==", false)
    .get();

  const metrics = projectMetricsSnap.docs.map((doc) => doc.data());
  const activeProjects = metrics.filter((project) => `${project.status ?? "active"}` === "active").length;
  const totalExpenses = metrics.reduce(
    (sum, project) => sum + Number(project.totalExpenses ?? 0),
    0,
  );
  const totalIncome = metrics.reduce(
    (sum, project) => sum + Number(project.totalIncome ?? 0),
    0,
  );

  await writeIfChanged(db.collection("workspace_metrics").doc(workspaceId), {
    workspaceId,
    totalProjects: metrics.length,
    activeProjects,
    totalExpenses,
    totalIncome,
    net: totalIncome - totalExpenses,
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

async function createProjectWithQuotaForUser(
  uid: string,
  data: Record<string, unknown>,
): Promise<{id: string}> {
  const workspaceId = requireString(data, "workspaceId");
  const role = await assertMember(workspaceId, uid);
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
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    createdBy: uid,
    isArchived: false,
  });

  return {id: projectRef.id};
}

export const createProjectWithQuota = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }
  return createProjectWithQuotaForUser(request.auth.uid, request.data as Record<string, unknown>);
});

export const createProjectWithQuotaHttp = onRequest(async (request, response) => {
  response.set("Access-Control-Allow-Origin", "*");
  response.set(
    "Access-Control-Allow-Headers",
    "Content-Type, Authorization, X-Firebase-AppCheck",
  );

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
    await verifyHttpAppCheck(request.header("X-Firebase-AppCheck") ?? undefined);

    const bearerToken = bearerTokenFrom(request.header("Authorization") ?? undefined);
    if (!bearerToken) {
      throw new HttpsError("unauthenticated", "Authentication required");
    }

    const decodedToken = await admin.auth().verifyIdToken(bearerToken);
    const body = payloadFrom(request.body);
    const data = Object.keys(payloadFrom(body.data)).length > 0 ?
      payloadFrom(body.data) :
      body;

    const result = await createProjectWithQuotaForUser(decodedToken.uid, data);
    response.status(200).json({result});
  } catch (error) {
    const handled = error instanceof HttpsError ?
      error :
      new HttpsError("internal", "Failed to create project");
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

export const createExpenseWithQuota = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }
  return createExpenseWithQuotaForUser(request.auth.uid, request.data as Record<string, unknown>);
});

async function createExpenseWithQuotaForUser(
  uid: string,
  data: Record<string, unknown>,
): Promise<{id: string}> {
  const workspaceId = requireString(data, "workspaceId");
  await assertMember(workspaceId, uid);

  const projectId = requireString(data, "projectId");
  const category = requireString(data, "category");
  const allowedCategories = ["labor", "materials", "equipment", "transport", "other"];
  if (!allowedCategories.includes(category)) {
    throw new HttpsError("invalid-argument", "Unsupported expense category");
  }
  const amount = requireNumber(data, "amount");
  if (amount <= 0) {
    throw new HttpsError("invalid-argument", "Amount must be greater than zero");
  }

  const projectSnap = await db.collection("projects").doc(projectId).get();
  if (!projectSnap.exists) {
    throw new HttpsError("invalid-argument", "Project does not exist");
  }
  const projectData = projectSnap.data() ?? {};
  if (`${projectData.workspaceId ?? ""}` !== workspaceId || projectData.isArchived === true) {
    throw new HttpsError("permission-denied", "Project is not available in this workspace");
  }

  const currencyRaw = `${data.currency ?? "EGP"}`.trim().toUpperCase();
  const currency = ["EGP", "USD", "SAR", "AED"].includes(currencyRaw) ? currencyRaw : "EGP";
  const inputMethod = `${data.inputMethod ?? "manual"}`.trim().toLowerCase();
  if (inputMethod !== "manual" && inputMethod !== "voice") {
    throw new HttpsError("invalid-argument", "inputMethod must be manual or voice");
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
    }, {merge: true});
  });

  return {id: expenseRef.id};
}

export const createExpenseWithQuotaHttp = onRequest(async (request, response) => {
  response.set("Access-Control-Allow-Origin", "*");
  response.set(
    "Access-Control-Allow-Headers",
    "Content-Type, Authorization, X-Firebase-AppCheck",
  );

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
    await verifyHttpAppCheck(request.header("X-Firebase-AppCheck") ?? undefined);

    const bearerToken = bearerTokenFrom(request.header("Authorization") ?? undefined);
    if (!bearerToken) {
      throw new HttpsError("unauthenticated", "Authentication required");
    }

    const decodedToken = await admin.auth().verifyIdToken(bearerToken);
    const body = payloadFrom(request.body);
    const data = Object.keys(payloadFrom(body.data)).length > 0 ?
      payloadFrom(body.data) :
      body;

    const result = await createExpenseWithQuotaForUser(decodedToken.uid, data);
    response.status(200).json({result});
  } catch (error) {
    const handled = error instanceof HttpsError ?
      error :
      new HttpsError("internal", "Failed to save expense");
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

async function createPaymentWithQuotaForUser(
  uid: string,
  data: Record<string, unknown>,
): Promise<{id: string}> {
  const workspaceId = requireString(data, "workspaceId");
  await assertMember(workspaceId, uid);

  const projectId = requireString(data, "projectId");
  const amount = requireNumber(data, "amount");
  if (amount <= 0) {
    throw new HttpsError("invalid-argument", "Amount must be greater than zero");
  }
  const projectSnap = await db.collection("projects").doc(projectId).get();
  if (!projectSnap.exists || `${projectSnap.data()?.workspaceId ?? ""}` !== workspaceId) {
    throw new HttpsError("invalid-argument", "Project does not exist");
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
    }, {merge: true});
  });
  return {id: paymentRef.id};
}

export const createPaymentWithQuota = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }
  return createPaymentWithQuotaForUser(request.auth.uid, request.data as Record<string, unknown>);
});

export const createPaymentWithQuotaHttp = onRequest(async (request, response) => {
  response.set("Access-Control-Allow-Origin", "*");
  response.set(
    "Access-Control-Allow-Headers",
    "Content-Type, Authorization, X-Firebase-AppCheck",
  );

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
    await verifyHttpAppCheck(request.header("X-Firebase-AppCheck") ?? undefined);

    const bearerToken = bearerTokenFrom(request.header("Authorization") ?? undefined);
    if (!bearerToken) {
      throw new HttpsError("unauthenticated", "Authentication required");
    }

    const decodedToken = await admin.auth().verifyIdToken(bearerToken);
    const body = payloadFrom(request.body);
    const data = Object.keys(payloadFrom(body.data)).length > 0 ?
      payloadFrom(body.data) :
      body;

    const result = await createPaymentWithQuotaForUser(decodedToken.uid, data);
    response.status(200).json({result});
  } catch (error) {
    const handled = error instanceof HttpsError ?
      error :
      new HttpsError("internal", "Failed to save payment");
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

async function createWorkerEntryWithQuotaForUser(
  uid: string,
  data: Record<string, unknown>,
): Promise<{id: string}> {
  const workspaceId = requireString(data, "workspaceId");
  await assertMember(workspaceId, uid);

  const workerId = requireString(data, "workerId");
  const projectId = requireString(data, "projectId");
  const daysWorked = requireNumber(data, "daysWorked");
  const dailyWage = requireNumber(data, "dailyWage");
  if (daysWorked <= 0 || dailyWage <= 0) {
    throw new HttpsError("invalid-argument", "Days worked and daily wage must be > 0");
  }
  const totalCost = daysWorked * dailyWage;
  const [workerSnap, projectSnap] = await Promise.all([
    db.collection("workers").doc(workerId).get(),
    db.collection("projects").doc(projectId).get(),
  ]);
  if (!workerSnap.exists || `${workerSnap.data()?.workspaceId ?? ""}` !== workspaceId) {
    throw new HttpsError("invalid-argument", "Worker does not exist");
  }
  if (!projectSnap.exists || `${projectSnap.data()?.workspaceId ?? ""}` !== workspaceId) {
    throw new HttpsError("invalid-argument", "Project does not exist");
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
    }, {merge: true});
  });
  return {id: entryRef.id};
}

export const createWorkerEntryWithQuota = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }
  return createWorkerEntryWithQuotaForUser(request.auth.uid, request.data as Record<string, unknown>);
});

export const createWorkerEntryWithQuotaHttp = onRequest(async (request, response) => {
  response.set("Access-Control-Allow-Origin", "*");
  response.set(
    "Access-Control-Allow-Headers",
    "Content-Type, Authorization, X-Firebase-AppCheck",
  );

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
    await verifyHttpAppCheck(request.header("X-Firebase-AppCheck") ?? undefined);

    const bearerToken = bearerTokenFrom(request.header("Authorization") ?? undefined);
    if (!bearerToken) {
      throw new HttpsError("unauthenticated", "Authentication required");
    }

    const decodedToken = await admin.auth().verifyIdToken(bearerToken);
    const body = payloadFrom(request.body);
    const data = Object.keys(payloadFrom(body.data)).length > 0 ?
      payloadFrom(body.data) :
      body;

    const result = await createWorkerEntryWithQuotaForUser(decodedToken.uid, data);
    response.status(200).json({result});
  } catch (error) {
    const handled = error instanceof HttpsError ?
      error :
      new HttpsError("internal", "Failed to save worker entry");
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

async function archiveExpenseWithQuotaRefundForUser(
  uid: string,
  data: Record<string, unknown>,
): Promise<void> {
  const workspaceId = requireString(data, "workspaceId");
  await assertMember(workspaceId, uid);
  const expenseId = requireString(data, "expenseId");
  const expenseRef = db.collection("expenses").doc(expenseId);
  const counterRef = db.collection("usage_counters").doc(`${workspaceId}_${periodKey()}`);

  await db.runTransaction(async (tx) => {
    const expenseSnap = await tx.get(expenseRef);
    if (!expenseSnap.exists) {
      throw new HttpsError("not-found", "Expense not found");
    }
    const expense = expenseSnap.data() ?? {};
    if (`${expense.workspaceId ?? ""}` !== workspaceId) {
      throw new HttpsError("permission-denied", "Expense is not available in this workspace");
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
    }, {merge: true});
  });
}

export const archiveExpenseWithQuotaRefund = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }
  await archiveExpenseWithQuotaRefundForUser(request.auth.uid, request.data as Record<string, unknown>);
});

export const archiveExpenseWithQuotaRefundHttp = onRequest(async (request, response) => {
  response.set("Access-Control-Allow-Origin", "*");
  response.set(
    "Access-Control-Allow-Headers",
    "Content-Type, Authorization, X-Firebase-AppCheck",
  );

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
    await verifyHttpAppCheck(request.header("X-Firebase-AppCheck") ?? undefined);
    const bearerToken = bearerTokenFrom(request.header("Authorization") ?? undefined);
    if (!bearerToken) {
      throw new HttpsError("unauthenticated", "Authentication required");
    }
    const decodedToken = await admin.auth().verifyIdToken(bearerToken);
    const body = payloadFrom(request.body);
    const data = Object.keys(payloadFrom(body.data)).length > 0 ?
      payloadFrom(body.data) :
      body;
    await archiveExpenseWithQuotaRefundForUser(decodedToken.uid, data);
    response.status(200).json({result: {ok: true}});
  } catch (error) {
    const handled = error instanceof HttpsError ?
      error :
      new HttpsError("internal", "Failed to archive expense");
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

async function archivePaymentWithQuotaRefundForUser(
  uid: string,
  data: Record<string, unknown>,
): Promise<void> {
  const workspaceId = requireString(data, "workspaceId");
  await assertMember(workspaceId, uid);
  const paymentId = requireString(data, "paymentId");
  const paymentRef = db.collection("payments").doc(paymentId);
  const counterRef = db.collection("usage_counters").doc(`${workspaceId}_${periodKey()}`);

  await db.runTransaction(async (tx) => {
    const paymentSnap = await tx.get(paymentRef);
    if (!paymentSnap.exists) {
      throw new HttpsError("not-found", "Payment not found");
    }
    const payment = paymentSnap.data() ?? {};
    if (`${payment.workspaceId ?? ""}` !== workspaceId) {
      throw new HttpsError("permission-denied", "Payment is not available in this workspace");
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
    }, {merge: true});
  });
}

export const archivePaymentWithQuotaRefund = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }
  await archivePaymentWithQuotaRefundForUser(request.auth.uid, request.data as Record<string, unknown>);
});

export const archivePaymentWithQuotaRefundHttp = onRequest(async (request, response) => {
  response.set("Access-Control-Allow-Origin", "*");
  response.set(
    "Access-Control-Allow-Headers",
    "Content-Type, Authorization, X-Firebase-AppCheck",
  );

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
    await verifyHttpAppCheck(request.header("X-Firebase-AppCheck") ?? undefined);
    const bearerToken = bearerTokenFrom(request.header("Authorization") ?? undefined);
    if (!bearerToken) {
      throw new HttpsError("unauthenticated", "Authentication required");
    }
    const decodedToken = await admin.auth().verifyIdToken(bearerToken);
    const body = payloadFrom(request.body);
    const data = Object.keys(payloadFrom(body.data)).length > 0 ?
      payloadFrom(body.data) :
      body;
    await archivePaymentWithQuotaRefundForUser(decodedToken.uid, data);
    response.status(200).json({result: {ok: true}});
  } catch (error) {
    const handled = error instanceof HttpsError ?
      error :
      new HttpsError("internal", "Failed to archive payment");
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

async function archiveWorkerEntryWithQuotaRefundForUser(
  uid: string,
  data: Record<string, unknown>,
): Promise<void> {
  const workspaceId = requireString(data, "workspaceId");
  await assertMember(workspaceId, uid);
  const entryId = requireString(data, "entryId");
  const entryRef = db.collection("worker_entries").doc(entryId);
  const counterRef = db.collection("usage_counters").doc(`${workspaceId}_${periodKey()}`);

  await db.runTransaction(async (tx) => {
    const entrySnap = await tx.get(entryRef);
    if (!entrySnap.exists) {
      throw new HttpsError("not-found", "Worker entry not found");
    }
    const entry = entrySnap.data() ?? {};
    if (`${entry.workspaceId ?? ""}` !== workspaceId) {
      throw new HttpsError("permission-denied", "Worker entry is not available in this workspace");
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
    }, {merge: true});
  });
}

export const archiveWorkerEntryWithQuotaRefund = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }
  await archiveWorkerEntryWithQuotaRefundForUser(request.auth.uid, request.data as Record<string, unknown>);
});

export const archiveWorkerEntryWithQuotaRefundHttp = onRequest(async (request, response) => {
  response.set("Access-Control-Allow-Origin", "*");
  response.set(
    "Access-Control-Allow-Headers",
    "Content-Type, Authorization, X-Firebase-AppCheck",
  );

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
    await verifyHttpAppCheck(request.header("X-Firebase-AppCheck") ?? undefined);
    const bearerToken = bearerTokenFrom(request.header("Authorization") ?? undefined);
    if (!bearerToken) {
      throw new HttpsError("unauthenticated", "Authentication required");
    }
    const decodedToken = await admin.auth().verifyIdToken(bearerToken);
    const body = payloadFrom(request.body);
    const data = Object.keys(payloadFrom(body.data)).length > 0 ?
      payloadFrom(body.data) :
      body;
    await archiveWorkerEntryWithQuotaRefundForUser(decodedToken.uid, data);
    response.status(200).json({result: {ok: true}});
  } catch (error) {
    const handled = error instanceof HttpsError ?
      error :
      new HttpsError("internal", "Failed to archive worker entry");
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

export const deleteProjectCascade = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }
  const data = request.data as Record<string, unknown>;
  const workspaceId = requireString(data, "workspaceId");
  await assertMember(workspaceId, request.auth.uid);
  const projectId = requireString(data, "projectId");
  const projectRef = db.collection("projects").doc(projectId);
  const projectSnap = await projectRef.get();
  if (!projectSnap.exists) {
    throw new HttpsError("not-found", "Project not found");
  }
  const project = projectSnap.data() ?? {};
  if (`${project.workspaceId ?? ""}` !== workspaceId) {
    throw new HttpsError("permission-denied", "Project is not available in this workspace");
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
  }, {merge: true});

  await batch.commit();
  await recomputeWorkspaceMetrics(workspaceId);
});

export const updateUserProfile = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }

  const data = request.data as Record<string, unknown>;
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
    ...(riskAlertsEnabled == null ? {} : {riskAlertsEnabled}),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
});

export const inviteMemberByEmail = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }
  const data = request.data as Record<string, unknown>;
  const workspaceId = requireString(data, "workspaceId");
  const ownerRole = await assertMember(workspaceId, request.auth.uid);
  if (ownerRole !== "owner") {
    throw new HttpsError("permission-denied", "Only owner can invite members");
  }

  const email = normalizeEmail(requireString(data, "email"));
  const role = `${data.role ?? "member"}`.trim() || "member";
  const userSnap = await db.collection("users").where("email", "==", email).limit(1).get();
  if (userSnap.empty) {
    throw new HttpsError("not-found", "No existing user was found with that email");
  }

  const userId = userSnap.docs[0].id;
  const deterministicMembership = await membershipRef(workspaceId, userId).get();
  if (deterministicMembership.exists) {
    throw new HttpsError("already-exists", "User is already a member of this workspace");
  }

  const existingMembership = await db
    .collection("memberships")
    .where("workspaceId", "==", workspaceId)
    .where("userId", "==", userId)
    .limit(1)
    .get();
  if (!existingMembership.empty) {
    throw new HttpsError("already-exists", "User is already a member of this workspace");
  }

  const subscription = await getSubscription(workspaceId);
  if (!hasUnlimitedQuota(subscription)) {
    const current = await getCurrentUsage(workspaceId, "teamMembers");
    const max = limitForType("teamMembers");
    if (current + 1 > max) {
      quotaError("teamMembers", current, max);
    }
  }

  await membershipRef(workspaceId, userId).set({
    workspaceId,
    userId,
    role,
    createdBy: request.auth.uid,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await db.collection("users").doc(userId).set({
    workspaceId,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});

  await upsertNotificationForUsers({
    workspaceId,
    userIds: [userId],
    type: "team_invite_added",
    title: "Workspace Access Granted",
    message: "You were added to a workspace team.",
  });
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
  const deterministicMembership = await membershipRef(workspaceId, newUserId).get();
  if (deterministicMembership.exists) {
    throw new HttpsError("already-exists", "User is already a member of this workspace");
  }
  const legacyMembership = await db
    .collection("memberships")
    .where("workspaceId", "==", workspaceId)
    .where("userId", "==", newUserId)
    .limit(1)
    .get();
  if (!legacyMembership.empty) {
    throw new HttpsError("already-exists", "User is already a member of this workspace");
  }

  const subscription = await getSubscription(workspaceId);
  if (!hasUnlimitedQuota(subscription)) {
    const current = await getCurrentUsage(workspaceId, "teamMembers");
    const max = limitForType("teamMembers");
    if (current + 1 > max) {
      quotaError("teamMembers", current, max);
    }
  }

  await membershipRef(workspaceId, newUserId).set({
    workspaceId,
    userId: newUserId,
    role: memberRole,
    createdBy: request.auth.uid,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await db.collection("users").doc(newUserId).set({
    workspaceId,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});

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

    const recipients = await notificationRecipients(workspaceId, false);
    await upsertNotificationForUsers({
      workspaceId,
      userIds: recipients,
      type: "subscription_status_changed",
      title: "Subscription Updated",
      message: `Subscription is now ${tier.toUpperCase()} (${status})`,
    });

    res.status(200).json({ok: true});
  },
);

async function recomputeProjectSummary(workspaceId: string, projectId: string): Promise<void> {
  const projectMetricsRef = db.collection("project_metrics").doc(projectId);
  const [projectSnap, projectMetricsSnap, expensesSnap, paymentsSnap, workerEntriesSnap] = await Promise.all([
    db.collection("projects").doc(projectId).get(),
    projectMetricsRef.get(),
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
  const budgetLimit = Number(project.budgetLimit ?? 0) || null;
  const previousMetrics = projectMetricsSnap.data() ?? {};
  const previousRiskLevel = `${previousMetrics.riskLevel ?? "low"}`;
  const previousHealthStatus = `${previousMetrics.healthStatus ?? "healthy"}`;

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
  const budgetExceeded = budgetLimit != null && totalExpenses > budgetLimit;

  const categoryTotals = expensesSnap.docs.reduce<Record<string, number>>((map, doc) => {
    const category = `${doc.data().category ?? "other"}`;
    map[category] = (map[category] ?? 0) + Number(doc.data().amount ?? 0);
    return map;
  }, {});

  const now = new Date();
  const monthlyFlow = Array.from({length: 6}).map((_, index) => {
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

  const workerIdsInEntries = Array.from(
    new Set(workerEntriesSnap.docs.map((doc) => `${doc.data().workerId ?? ""}`.trim()).filter((id) => id.length > 0)),
  );
  const workerNameMap = await workerNameMapForEntries(workspaceId, workerIdsInEntries);
  const workerCosts = workerEntriesSnap.docs.reduce<Record<string, {name: string; totalCost: number; totalDays: number}>>((map, doc) => {
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
    .map(([workerId, data]) => ({workerId, ...data}))
    .sort((a, b) => b.totalCost - a.totalCost)
    .slice(0, 5);

  const recentExpenses: Record<string, unknown>[] = expensesSnap.docs
    .map((doc) => ({id: doc.id, ...(doc.data() as Record<string, unknown>)}))
    .sort((a, b) => {
      const aEntry = a as Record<string, unknown>;
      const bEntry = b as Record<string, unknown>;
      const aDate = parseTimestamp(aEntry["date"])?.toMillis() ?? 0;
      const bDate = parseTimestamp(bEntry["date"])?.toMillis() ?? 0;
      return bDate - aDate;
    })
    .slice(0, 5);
  const recentPayments: Record<string, unknown>[] = paymentsSnap.docs
    .map((doc) => ({id: doc.id, ...(doc.data() as Record<string, unknown>)}))
    .sort((a, b) => {
      const aEntry = a as Record<string, unknown>;
      const bEntry = b as Record<string, unknown>;
      const aDate = parseTimestamp(aEntry["date"])?.toMillis() ?? 0;
      const bDate = parseTimestamp(bEntry["date"])?.toMillis() ?? 0;
      return bDate - aDate;
    })
    .slice(0, 5);

  await writeIfChanged(projectMetricsRef, buildProjectMetricsPayload({
    workspaceId,
    projectId,
    project,
    contractValue,
    completionPercentage,
    budgetLimit,
    budgetExceeded,
    totalExpenses,
    laborExpenses,
    totalPayments,
    netProfit,
    remainingBalance,
    expectedFinalCost,
    riskLevel,
    healthStatus,
    categoryTotals,
    monthlyFlow,
    topWorkers,
    recentExpenses,
    recentPayments,
  }));

  await recomputeWorkspaceMetrics(workspaceId);

  const memberIds = (await membershipDocs(workspaceId)).docs
    .map((doc) => `${doc.data().userId ?? ""}`.trim())
    .filter((id) => id.length > 0);
  const riskAlertRecipients = await riskAlertRecipientsFromMembers(memberIds);

  if (budgetExceeded) {
    await upsertNotificationForUsers({
      workspaceId,
      userIds: riskAlertRecipients,
      type: "budget_exceeded",
      projectId,
      title: "Budget Limit Exceeded",
      message: `Project ${project.name ?? "project"} exceeded its budget limit.`,
    });
  } else {
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
  } else if (riskLevel === "low" && healthStatus === "healthy") {
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
    } else {
      await deleteNotificationForUsers("project_deadline_alert", projectId, memberIds);
    }
  }
}

type ExpenseWrittenParams = {expenseId?: string};
type PaymentWrittenParams = {paymentId?: string};
type WorkerEntryWrittenParams = {entryId?: string};

export async function handleExpenseWriteRecompute(
  event: FirestoreWrittenEventLike<ExpenseWrittenParams>,
): Promise<void> {
  const after = event.data?.after?.data();
  const before = event.data?.before?.data();
  if (before && after && !hasRelevantExpenseFieldsChanged(before, after)) {
    return;
  }
  const targets = aggregateTargetsFromChange(before, after);
  if (targets.length === 0) {
    return;
  }
  await Promise.all(targets.map(({workspaceId, projectId}) => recomputeProjectSummary(workspaceId, projectId)));
}

export async function handlePaymentWriteRecompute(
  event: FirestoreWrittenEventLike<PaymentWrittenParams>,
): Promise<void> {
  const after = event.data?.after?.data();
  const before = event.data?.before?.data();
  if (before && after && !hasRelevantPaymentFieldsChanged(before, after)) {
    return;
  }
  const targets = aggregateTargetsFromChange(before, after);
  if (targets.length === 0) {
    return;
  }
  await Promise.all(targets.map(({workspaceId, projectId}) => recomputeProjectSummary(workspaceId, projectId)));
}

export async function handleWorkerEntryWriteRecompute(
  event: FirestoreWrittenEventLike<WorkerEntryWrittenParams>,
): Promise<void> {
  const after = event.data?.after?.data();
  const before = event.data?.before?.data();
  if (before && after && !hasRelevantWorkerEntryFieldsChanged(before, after)) {
    return;
  }
  const targets = aggregateTargetsFromChange(before, after);
  if (targets.length === 0) {
    return;
  }
  await Promise.all(targets.map(({workspaceId, projectId}) => recomputeProjectSummary(workspaceId, projectId)));
}

export const onExpenseWriteRecompute = onDocumentWritten(
  "expenses/{expenseId}",
  handleExpenseWriteRecompute,
);

export const onPaymentWriteRecompute = onDocumentWritten(
  "payments/{paymentId}",
  handlePaymentWriteRecompute,
);

export const onWorkerEntryWriteRecompute = onDocumentWritten(
  "worker_entries/{entryId}",
  handleWorkerEntryWriteRecompute,
);

type ProjectWrittenParams = {projectId?: string};

export async function handleProjectWriteRecompute(
  event: FirestoreWrittenEventLike<ProjectWrittenParams>,
): Promise<void> {
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

  if (before && !hasRelevantProjectFieldsChanged(before, after)) {
    return;
  }

  await recomputeProjectSummary(workspaceId, projectId);
}

export const onProjectWriteRecompute = onDocumentWritten(
  "projects/{projectId}",
  handleProjectWriteRecompute,
);
