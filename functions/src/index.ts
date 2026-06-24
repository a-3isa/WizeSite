import * as admin from "firebase-admin";
import { defineBoolean, defineSecret } from "firebase-functions/params";
import { setGlobalOptions } from "firebase-functions/v2";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { HttpsError, onCall, onRequest } from "firebase-functions/v2/https";
export {
  processVoiceExpense,
  processVoiceExpenseHttp,
} from "./voice/process_voice_expense";

admin.initializeApp();
setGlobalOptions({ region: "us-central1", maxInstances: 10 });

const db = admin.firestore();
const revenuecatWebhookSecret = defineSecret("REVENUECAT_WEBHOOK_SECRET");
const enforceHttpAppCheck = defineBoolean("ENFORCE_HTTP_APP_CHECK");
const ENFORCE_TEAM_MEMBER_LIMITS = false;

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
const USAGE_LIMITS_DISABLED = true;

type SubscriptionTier = "free" | "pro";
type SubscriptionStatus =
  | "trial"
  | "active"
  | "grace"
  | "expired"
  | "canceled"
  | "unknown";

type SubscriptionDoc = {
  tier: SubscriptionTier;
  status: SubscriptionStatus;
};

function periodKey(now = new Date()): string {
  const month = `${now.getUTCMonth() + 1}`.padStart(2, "0");
  return `${now.getUTCFullYear()}${month}`;
}

function nextResetIso(now = new Date()): string {
  const next = new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 1),
  );
  return next.toISOString();
}

function parseTimestamp(input: unknown): admin.firestore.Timestamp | null {
  if (input == null) {
    return null;
  }
  if (input instanceof admin.firestore.Timestamp) {
    return input;
  }
  if (input instanceof Date) {
    return admin.firestore.Timestamp.fromDate(input);
  }
  if (typeof input === "object" && input !== null) {
    const candidate = input as {
      toDate?: () => Date;
      seconds?: unknown;
      nanoseconds?: unknown;
      _seconds?: unknown;
      _nanoseconds?: unknown;
    };

    if (typeof candidate.toDate === "function") {
      const converted = candidate.toDate();
      if (converted instanceof Date && !Number.isNaN(converted.getTime())) {
        return admin.firestore.Timestamp.fromDate(converted);
      }
    }

    const seconds = Number(candidate.seconds ?? candidate._seconds);
    const nanoseconds = Number(
      candidate.nanoseconds ?? candidate._nanoseconds ?? 0,
    );
    if (Number.isFinite(seconds) && Number.isFinite(nanoseconds)) {
      return new admin.firestore.Timestamp(seconds, nanoseconds);
    }
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

function dateKey(input: Date): string {
  return input.toISOString().slice(0, 10);
}

function startOfUtcDay(input: Date): Date {
  return new Date(
    Date.UTC(input.getUTCFullYear(), input.getUTCMonth(), input.getUTCDate()),
  );
}

function startOfUtcWeek(input: Date): Date {
  const day = startOfUtcDay(input);
  const mondayOffset = day.getUTCDay() === 0 ? 6 : day.getUTCDay() - 1;
  day.setUTCDate(day.getUTCDate() - mondayOffset);
  return day;
}

function endOfUtcWeek(input: Date): Date {
  const end = startOfUtcWeek(input);
  end.setUTCDate(end.getUTCDate() + 6);
  end.setUTCHours(23, 59, 59, 999);
  return end;
}

function sameUtcDay(left: Date, right: Date): boolean {
  return dateKey(left) === dateKey(right);
}

function sameUtcMonth(left: Date, right: Date): boolean {
  return (
    left.getUTCFullYear() === right.getUTCFullYear() &&
    left.getUTCMonth() === right.getUTCMonth()
  );
}

function withinUtcWeek(input: Date, weekStart: Date): boolean {
  const day = startOfUtcDay(input);
  const end = endOfUtcWeek(weekStart);
  return day.getTime() >= weekStart.getTime() && day.getTime() <= end.getTime();
}

function mapRevenueCatStatus(
  eventType: string,
  periodType: string,
): SubscriptionStatus {
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
  const hasPro = entitlements.some((item) =>
    `${item}`.toLowerCase().includes("pro"),
  );
  return hasPro ? "pro" : "free";
}

async function getSubscription(workspaceId: string): Promise<SubscriptionDoc> {
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
  if (USAGE_LIMITS_DISABLED) {
    return true;
  }
  return (
    subscription.tier === "pro" &&
    (subscription.status === "active" ||
      subscription.status === "trial" ||
      subscription.status === "grace")
  );
}

async function roleForUser(
  workspaceId: string,
  userId: string,
): Promise<string | null> {
  const deterministicMembership = await membershipRef(
    workspaceId,
    userId,
  ).get();
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
      createdAt:
        legacyData.createdAt ?? admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  return `${legacyData.role ?? "member"}`;
}

async function assertMember(
  workspaceId: string,
  userId: string,
): Promise<string> {
  const role = await roleForUser(workspaceId, userId);
  if (!role) {
    throw new HttpsError(
      "permission-denied",
      "User is not a member of this workspace",
    );
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

function deriveAttachmentType(contentType: string, fileName: string): string {
  const normalized = contentType.toLowerCase();
  if (normalized.startsWith("image/")) {
    return "image";
  }
  if (normalized == "application/pdf") {
    return "pdf";
  }
  if (normalized.startsWith("video/")) {
    return "video";
  }
  if (fileName.toLowerCase().endsWith(".pdf")) {
    return "pdf";
  }
  return "file";
}

function normalizeAttachmentItem(
  raw: unknown,
  key: string,
): Record<string, unknown> {
  if (!raw || typeof raw !== "object") {
    throw new HttpsError("invalid-argument", `Invalid attachment item: ${key}`);
  }
  const attachment = raw as Record<string, unknown>;
  const id = requireString(attachment, "id");
  const fileName = requireString(attachment, "fileName");
  const urlValue =
    typeof attachment.downloadUrl === "string" &&
    attachment.downloadUrl.trim().length > 0
      ? attachment.downloadUrl.trim()
      : typeof attachment.url === "string" && attachment.url.trim().length > 0
        ? attachment.url.trim()
        : "";
  if (urlValue.length === 0) {
    throw new HttpsError(
      "invalid-argument",
      `Missing required field: ${key}.downloadUrl or ${key}.url`,
    );
  }
  const uploadedAt = parseTimestamp(attachment.uploadedAt);
  if (uploadedAt == null) {
    throw new HttpsError(
      "invalid-argument",
      `Invalid or missing uploadedAt for ${key}`,
    );
  }
  const contentType =
    typeof attachment.contentType === "string" &&
    attachment.contentType.trim().length > 0
      ? attachment.contentType.trim()
      : typeof attachment.mimeType === "string" &&
          attachment.mimeType.trim().length > 0
        ? attachment.mimeType.trim()
        : "application/octet-stream";
  const storagePath =
    typeof attachment.storagePath === "string"
      ? attachment.storagePath.trim()
      : "";
  const type =
    typeof attachment.type === "string" && attachment.type.trim().length > 0
      ? attachment.type.trim()
      : deriveAttachmentType(contentType, fileName);
  const sizeRaw = attachment.size;
  const normalized: Record<string, unknown> = {
    id,
    fileName,
    url: urlValue,
    downloadUrl: urlValue,
    storagePath,
    contentType,
    mimeType: contentType,
    type,
    uploadedAt,
  };
  if (sizeRaw != null) {
    const size = Number(sizeRaw);
    if (!Number.isFinite(size)) {
      throw new HttpsError(
        "invalid-argument",
        `Invalid attachment size for ${key}`,
      );
    }
    normalized.size = size;
  }
  return normalized;
}

function ensureAttachmentItems(
  data: Record<string, unknown>,
  key: string,
): Array<Record<string, unknown>> {
  const raw = data[key];
  if (raw == null) {
    return [];
  }
  if (!Array.isArray(raw)) {
    throw new HttpsError(
      "invalid-argument",
      `Invalid attachments format: ${key}`,
    );
  }
  return raw.map((item, index) =>
    normalizeAttachmentItem(item, `${key}[${index}]`),
  );
}

function bearerTokenFrom(
  authorizationHeader: string | undefined,
): string | null {
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

async function verifyHttpAppCheck(
  appCheckToken: string | undefined,
): Promise<void> {
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
    console.warn(
      "HTTP callable endpoint received an invalid App Check token",
      error,
    );
  }
}

async function getCurrentUsage(
  workspaceId: string,
  type: LimitType,
): Promise<number> {
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
    const snap = await db
      .collection("memberships")
      .where("workspaceId", "==", workspaceId)
      .get();
    return snap.size;
  }

  const usageSnap = await db
    .collection("usage_counters")
    .doc(`${workspaceId}_${periodKey()}`)
    .get();
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
  return supportedCurrencyCode(raw) ? raw : "EGP";
}

function supportedCurrencyCode(input: string): boolean {
  return [
    "EGP",
    "USD",
    "SAR",
    "AED",
    "KWD",
    "QAR",
    "BHD",
    "OMR",
    "JOD",
  ].includes(input);
}

function requireCurrencyCode(input: unknown): string {
  const raw = `${input ?? ""}`.trim().toUpperCase();
  if (!supportedCurrencyCode(raw)) {
    throw new HttpsError("invalid-argument", "Unsupported currency");
  }
  return raw;
}

function asBooleanOrUndefined(input: unknown): boolean | undefined {
  if (typeof input === "boolean") {
    return input;
  }
  return undefined;
}

function userWorkspaceName(input: string): string {
  const trimmed = input.trim();
  return trimmed.length > 0 ? `${trimmed} Workspace` : "New Workspace";
}

function nonEmptyStringOrUndefined(input: string): string | undefined {
  return input.trim().length > 0 ? input.trim() : undefined;
}

function assignIfDefined(
  target: Record<string, unknown>,
  key: string,
  value: unknown,
): void {
  if (value !== undefined) {
    target[key] = value;
  }
}

function applyMetricsDeltaInTx(
  tx: admin.firestore.Transaction,
  projectId: string,
  workspaceId: string,
  expensesDelta: number,
  paymentsDelta: number,
): void {
  if (expensesDelta === 0 && paymentsDelta === 0) return;
  const metricsRef = db.collection("project_metrics").doc(projectId);
  const netDelta = paymentsDelta - expensesDelta;
  const updates: Record<string, unknown> = { workspaceId, projectId };
  if (expensesDelta !== 0)
    updates.totalExpenses = admin.firestore.FieldValue.increment(expensesDelta);
  if (paymentsDelta !== 0)
    updates.totalPayments = admin.firestore.FieldValue.increment(paymentsDelta);
  if (netDelta !== 0)
    updates.netProfit = admin.firestore.FieldValue.increment(netDelta);
  console.log("[metrics.applyDelta.tx]", {
    workspaceId,
    projectId,
    expensesDelta,
    paymentsDelta,
    netDelta,
    updateKeys: Object.keys(updates),
  });
  tx.set(metricsRef, updates, { merge: true });
}

function applyMetricsDeltaInBatch(
  batch: admin.firestore.WriteBatch,
  projectId: string,
  workspaceId: string,
  expensesDelta: number,
  paymentsDelta: number,
): void {
  if (expensesDelta === 0 && paymentsDelta === 0) return;
  const metricsRef = db.collection("project_metrics").doc(projectId);
  const netDelta = paymentsDelta - expensesDelta;
  const updates: Record<string, unknown> = { workspaceId, projectId };
  if (expensesDelta !== 0)
    updates.totalExpenses = admin.firestore.FieldValue.increment(expensesDelta);
  if (paymentsDelta !== 0)
    updates.totalPayments = admin.firestore.FieldValue.increment(paymentsDelta);
  if (netDelta !== 0)
    updates.netProfit = admin.firestore.FieldValue.increment(netDelta);
  batch.set(metricsRef, updates, { merge: true });
}

type TriggerDocData = Record<string, unknown>;

type TriggerSnapshotLike = {
  data: () => TriggerDocData | undefined;
};

type FirestoreWrittenEventLike<
  TParams extends Record<string, string | undefined>,
> = {
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
  if (
    value &&
    typeof value === "object" &&
    "toMillis" in value &&
    typeof (value as { toMillis?: unknown }).toMillis === "function"
  ) {
    return (value as { toMillis: () => number }).toMillis();
  }
  return value;
}

export function shallowEqualDerivedState(
  left: unknown,
  right: unknown,
): boolean {
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

function hasSubsetChanged(
  current: TriggerDocData,
  next: TriggerDocData,
): boolean {
  return Object.entries(next).some(
    ([key, value]) => !shallowEqualDerivedState(current[key], value),
  );
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
    { merge },
  );
  return true;
}

function changedString(
  before: TriggerDocData,
  after: TriggerDocData,
  key: string,
): boolean {
  return `${before[key] ?? ""}` !== `${after[key] ?? ""}`;
}

function changedBoolean(
  before: TriggerDocData,
  after: TriggerDocData,
  key: string,
): boolean {
  return Boolean(before[key]) !== Boolean(after[key]);
}

function changedNumber(
  before: TriggerDocData,
  after: TriggerDocData,
  key: string,
): boolean {
  return Number(before[key] ?? 0) !== Number(after[key] ?? 0);
}

function finiteNumber(input: unknown): number {
  const value = Number(input ?? 0);
  return Number.isFinite(value) ? value : 0;
}

export function workerEntryTotalCost(data: TriggerDocData): number {
  if (data.totalCost != null) {
    const explicitTotal = Number(data.totalCost);
    if (Number.isFinite(explicitTotal)) {
      return explicitTotal;
    }
  }
  return finiteNumber(data.daysWorked) * finiteNumber(data.dailyWage);
}

const VALID_WORKER_STATUSES = new Set(["active", "inactive", "terminated"]);

export function normalizeWorkerStatus(input: unknown): string {
  const status = `${input ?? "active"}`.trim().toLowerCase();
  if (!VALID_WORKER_STATUSES.has(status)) {
    throw new HttpsError(
      "invalid-argument",
      "Worker status must be active, inactive, or terminated.",
    );
  }
  return status;
}

export function workerAccountingAmounts(data: TriggerDocData): {
  totalAmount: number;
  confirmedPaid: number;
  confirmedOutstanding: number;
  unresolvedLegacyCount: number;
} {
  const totalAmount = finiteNumber(data.amount);
  const paymentStatus = `${data.paymentStatus ?? ""}`.trim().toLowerCase();
  if (paymentStatus === "paid") {
    return {
      totalAmount,
      confirmedPaid: totalAmount,
      confirmedOutstanding: 0,
      unresolvedLegacyCount: 0,
    };
  }
  if (paymentStatus === "unpaid") {
    return {
      totalAmount,
      confirmedPaid: 0,
      confirmedOutstanding: totalAmount,
      unresolvedLegacyCount: 0,
    };
  }
  if (paymentStatus === "partial") {
    const rawPaid = data.paidAmount;
    const paidAmount = rawPaid == null ? Number.NaN : Number(rawPaid);
    if (
      !Number.isFinite(paidAmount) ||
      paidAmount <= 0 ||
      paidAmount >= totalAmount
    ) {
      return {
        totalAmount,
        confirmedPaid: 0,
        confirmedOutstanding: 0,
        unresolvedLegacyCount: 1,
      };
    }
    return {
      totalAmount,
      confirmedPaid: paidAmount,
      confirmedOutstanding: totalAmount - paidAmount,
      unresolvedLegacyCount: 0,
    };
  }
  return {
    totalAmount,
    confirmedPaid: 0,
    confirmedOutstanding: 0,
    unresolvedLegacyCount: 1,
  };
}

export function buildWorkerAccountingSummaryPayload(input: {
  workspaceId: string;
  workerId: string;
  records: TriggerDocData[];
}): TriggerDocData {
  const totals = input.records.reduce<{
    totalAmount: number;
    confirmedPaid: number;
    confirmedOutstanding: number;
    unresolvedLegacyCount: number;
  }>(
    (sum, record) => {
      const amounts = workerAccountingAmounts(record);
      sum.totalAmount += amounts.totalAmount;
      sum.confirmedPaid += amounts.confirmedPaid;
      sum.confirmedOutstanding += amounts.confirmedOutstanding;
      sum.unresolvedLegacyCount += amounts.unresolvedLegacyCount;
      return sum;
    },
    {
      totalAmount: 0,
      confirmedPaid: 0,
      confirmedOutstanding: 0,
      unresolvedLegacyCount: 0,
    },
  );
  return {
    workspaceId: input.workspaceId,
    workerId: input.workerId,
    totalAmount: totals.totalAmount,
    confirmedPaid: totals.confirmedPaid,
    confirmedOutstanding: totals.confirmedOutstanding,
    unresolvedLegacyCount: totals.unresolvedLegacyCount,
    recordCount: input.records.length,
  };
}

function changedTimestamp(
  before: TriggerDocData,
  after: TriggerDocData,
  key: string,
): boolean {
  const beforeMillis = parseTimestamp(before[key])?.toMillis() ?? null;
  const afterMillis = parseTimestamp(after[key])?.toMillis() ?? null;
  return beforeMillis !== afterMillis;
}

export function hasRelevantProjectFieldsChanged(
  before: TriggerDocData,
  after: TriggerDocData,
): boolean {
  return (
    changedString(before, after, "workspaceId") ||
    changedString(before, after, "name") ||
    changedString(before, after, "status") ||
    changedBoolean(before, after, "isArchived") ||
    changedNumber(before, after, "contractValue") ||
    changedNumber(before, after, "completionPercentage") ||
    changedNumber(before, after, "budgetLimit") ||
    changedTimestamp(before, after, "expectedEndDate")
  );
}

export function hasRelevantExpenseFieldsChanged(
  before: TriggerDocData,
  after: TriggerDocData,
): boolean {
  return (
    changedString(before, after, "workspaceId") ||
    changedString(before, after, "projectId") ||
    changedString(before, after, "category") ||
    changedString(before, after, "entityId") ||
    changedString(before, after, "entityName") ||
    changedString(before, after, "entityType") ||
    changedString(before, after, "supplierId") ||
    changedString(before, after, "supplierName") ||
    changedNumber(before, after, "amount") ||
    !shallowEqualDerivedState(before.attachments, after.attachments) ||
    changedBoolean(before, after, "isArchived") ||
    changedTimestamp(before, after, "date")
  );
}

export function hasRelevantPaymentFieldsChanged(
  before: TriggerDocData,
  after: TriggerDocData,
): boolean {
  return (
    changedString(before, after, "workspaceId") ||
    changedString(before, after, "projectId") ||
    changedString(before, after, "entityId") ||
    changedString(before, after, "entityName") ||
    changedString(before, after, "entityType") ||
    changedString(before, after, "paymentMethod") ||
    changedNumber(before, after, "amount") ||
    !shallowEqualDerivedState(before.attachments, after.attachments) ||
    changedBoolean(before, after, "isArchived") ||
    changedTimestamp(before, after, "date")
  );
}

export function hasRelevantWorkerEntryFieldsChanged(
  before: TriggerDocData,
  after: TriggerDocData,
): boolean {
  return (
    changedString(before, after, "workspaceId") ||
    changedString(before, after, "projectId") ||
    changedString(before, after, "workerId") ||
    changedString(before, after, "workerName") ||
    changedNumber(before, after, "daysWorked") ||
    changedNumber(before, after, "dailyWage") ||
    changedNumber(before, after, "totalCost") ||
    !shallowEqualDerivedState(before.attachments, after.attachments) ||
    changedBoolean(before, after, "isArchived") ||
    changedTimestamp(before, after, "date")
  );
}

export function hasRelevantWorkerAccountingFieldsChanged(
  before: TriggerDocData,
  after: TriggerDocData,
): boolean {
  return (
    changedString(before, after, "workspaceId") ||
    changedString(before, after, "workerId") ||
    changedNumber(before, after, "amount") ||
    changedNumber(before, after, "paidAmount") ||
    changedString(before, after, "paymentStatus")
  );
}

type AggregateTarget = {
  workspaceId: string;
  projectId: string;
};

type WorkerAccountingTarget = {
  workspaceId: string;
  workerId: string;
};

function aggregateTargetFromDoc(
  data: TriggerDocData | undefined,
): AggregateTarget | null {
  if (!data || data.isArchived === true) {
    return null;
  }
  const workspaceId = `${data.workspaceId ?? ""}`.trim();
  const projectId = `${data.projectId ?? ""}`.trim();
  if (!workspaceId || !projectId) {
    return null;
  }
  return { workspaceId, projectId };
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

function workerAccountingTargetFromDoc(
  data: TriggerDocData | undefined,
): WorkerAccountingTarget | null {
  if (!data) {
    return null;
  }
  const workspaceId = `${data.workspaceId ?? ""}`.trim();
  const workerId = `${data.workerId ?? ""}`.trim();
  if (!workspaceId || !workerId) {
    return null;
  }
  return { workspaceId, workerId };
}

function workerAccountingTargetsFromChange(
  before: TriggerDocData | undefined,
  after: TriggerDocData | undefined,
): WorkerAccountingTarget[] {
  const targets = new Map<string, WorkerAccountingTarget>();
  for (const item of [before, after]) {
    const target = workerAccountingTargetFromDoc(item);
    if (!target) {
      continue;
    }
    targets.set(`${target.workspaceId}::${target.workerId}`, target);
  }
  return [...targets.values()];
}

async function membershipDocs(workspaceId: string) {
  return db
    .collection("memberships")
    .where("workspaceId", "==", workspaceId)
    .get();
}

async function notificationRecipients(
  workspaceId: string,
  requireRiskAlerts = false,
): Promise<string[]> {
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

async function riskAlertRecipientsFromMembers(
  userIds: string[],
): Promise<string[]> {
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
  await Promise.all(
    userIds.map(async (userId) => {
      const docId = [type, projectId ?? "workspace", userId].join("_");
      await db
        .collection("notifications")
        .doc(docId)
        .set(
          {
            workspaceId,
            targetUserId: userId,
            type,
            projectId: projectId ?? null,
            title,
            message,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
    }),
  );
}

async function deleteNotificationForUsers(
  type: string,
  projectId: string,
  userIds: string[],
): Promise<void> {
  await Promise.all(
    userIds.map(async (userId) => {
      const docId = [type, projectId, userId].join("_");
      await db
        .collection("notifications")
        .doc(docId)
        .delete()
        .catch(() => undefined);
    }),
  );
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
  const workerRefs = workerIds.map((workerId) =>
    db.collection("workers").doc(workerId),
  );
  const workerSnaps = await db.getAll(...workerRefs);
  const map = new Map<string, string>();
  for (const snap of workerSnaps) {
    if (!snap.exists) {
      continue;
    }
    const data = snap.data() ?? {};
    if (
      `${data.workspaceId ?? ""}` !== workspaceId ||
      data.isArchived === true
    ) {
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

type AccountingSummaryRecord = Record<string, unknown>;

type AccountingSummaryPayloads = {
  projectSummary: AccountingSummaryRecord;
  weeklySummaries: AccountingSummaryRecord[];
  entitySummaries: AccountingSummaryRecord[];
  categorySummaries: AccountingSummaryRecord[];
};

function summaryDocKey(...parts: string[]): string {
  return parts
    .map((part) =>
      part
        .trim()
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, "_")
        .replace(/^_+|_+$/g, ""),
    )
    .filter((part) => part.length > 0)
    .join("__");
}

function attachmentsCount(data: TriggerDocData): number {
  return Array.isArray(data.attachments) ? data.attachments.length : 0;
}

function recordDate(data: TriggerDocData): Date | null {
  return parseTimestamp(data.date)?.toDate() ?? null;
}

function incrementMap(
  target: Record<string, number>,
  key: string,
  amount: number,
): void {
  target[key] = (target[key] ?? 0) + amount;
}

function topMapEntry(map: Record<string, number>): Record<string, unknown> {
  const [key, amount] =
    Object.entries(map).sort((left, right) => right[1] - left[1])[0] ?? [];
  if (!key) {
    return {};
  }
  return { id: key, name: key, total: amount };
}

function entityIdentity(
  data: TriggerDocData,
  fallbackType: string,
): { entityId: string; entityName: string; entityType: string } {
  const entityName = `${data.entityName ?? data.supplierName ?? data.name ?? ""}`
    .trim();
  const entityType = `${data.entityType ?? fallbackType}`.trim() || fallbackType;
  const rawId = `${data.entityId ?? data.supplierId ?? ""}`.trim();
  const fallbackId = entityName.length > 0 ? entityName : "unassigned";
  const entityId = rawId.length > 0 ? rawId : summaryDocKey(fallbackId);
  return {
    entityId,
    entityName: entityName.length > 0 ? entityName : "Unassigned",
    entityType,
  };
}

export function buildAccountingSummaryPayloads(input: {
  workspaceId: string;
  projectId: string;
  expenses: Array<TriggerDocData & { id?: string }>;
  payments: Array<TriggerDocData & { id?: string }>;
  workerEntries: Array<TriggerDocData & { id?: string }>;
  now?: Date;
}): AccountingSummaryPayloads {
  const now = input.now ?? new Date();
  const weekStart = startOfUtcWeek(now);
  const todayExpenses = input.expenses.reduce((sum, expense) => {
    const date = recordDate(expense);
    return date && sameUtcDay(date, now)
      ? sum + finiteNumber(expense.amount)
      : sum;
  }, 0);
  const weeklyExpenses = input.expenses.reduce((sum, expense) => {
    const date = recordDate(expense);
    return date && withinUtcWeek(date, weekStart)
      ? sum + finiteNumber(expense.amount)
      : sum;
  }, 0);
  const monthlyExpenses = input.expenses.reduce((sum, expense) => {
    const date = recordDate(expense);
    return date && sameUtcMonth(date, now)
      ? sum + finiteNumber(expense.amount)
      : sum;
  }, 0);
  const attachmentCount =
    input.expenses.reduce((sum, item) => sum + attachmentsCount(item), 0) +
    input.payments.reduce((sum, item) => sum + attachmentsCount(item), 0) +
    input.workerEntries.reduce((sum, item) => sum + attachmentsCount(item), 0);

  const projectSummary = {
    id: summaryDocKey(input.workspaceId, input.projectId),
    workspaceId: input.workspaceId,
    projectId: input.projectId,
    todayExpenses,
    weeklyExpenses,
    monthlyExpenses,
    transactionCount:
      input.expenses.length + input.payments.length + input.workerEntries.length,
    totalPayments: input.payments.reduce(
      (sum, payment) => sum + finiteNumber(payment.amount),
      0,
    ),
    attachmentCount,
  };

  const weeklyMap = new Map<string, AccountingSummaryRecord>();
  const entityMap = new Map<string, AccountingSummaryRecord>();
  const categoryMap = new Map<string, AccountingSummaryRecord>();

  const weeklyFor = (date: Date): AccountingSummaryRecord => {
    const start = startOfUtcWeek(date);
    const key = dateKey(start);
    const existing = weeklyMap.get(key);
    if (existing) return existing;
    const summary = {
      id: summaryDocKey(input.workspaceId, input.projectId, key),
      workspaceId: input.workspaceId,
      projectId: input.projectId,
      weekStart: admin.firestore.Timestamp.fromDate(start),
      weekEnd: admin.firestore.Timestamp.fromDate(endOfUtcWeek(start)),
      totalExpenses: 0,
      totalPayments: 0,
      topEntity: {},
      topCategory: {},
      laborSummary: { total: 0, transactionCount: 0 },
      equipmentSummary: { total: 0, transactionCount: 0 },
      paymentSummary: {},
      recentTransactionRefs: [] as string[],
      _entityTotals: {} as Record<string, number>,
      _categoryTotals: {} as Record<string, number>,
      _paymentMethodTotals: {} as Record<string, number>,
    };
    weeklyMap.set(key, summary);
    return summary;
  };

  const entityFor = (
    identity: { entityId: string; entityName: string; entityType: string },
  ): AccountingSummaryRecord => {
    const key = summaryDocKey(
      input.workspaceId,
      input.projectId,
      identity.entityType,
      identity.entityId,
    );
    const existing = entityMap.get(key);
    if (existing) return existing;
    const summary = {
      id: key,
      workspaceId: input.workspaceId,
      projectId: input.projectId,
      entityId: identity.entityId,
      entityName: identity.entityName,
      entityType: identity.entityType,
      totalExpenses: 0,
      totalPayments: 0,
      totalPaid: 0,
      remainingBalance: 0,
      transactionCount: 0,
      attachmentCount: 0,
      latestTransactionDate: admin.firestore.Timestamp.fromMillis(0),
      categoryBreakdown: {} as Record<string, number>,
      paymentMethodBreakdown: {} as Record<string, number>,
    };
    entityMap.set(key, summary);
    return summary;
  };

  const categoryFor = (category: string): AccountingSummaryRecord => {
    const key = summaryDocKey(input.workspaceId, input.projectId, category);
    const existing = categoryMap.get(key);
    if (existing) return existing;
    const summary = {
      id: key,
      workspaceId: input.workspaceId,
      projectId: input.projectId,
      category,
      totalAmount: 0,
      transactionCount: 0,
      latestTransactionDate: admin.firestore.Timestamp.fromMillis(0),
    };
    categoryMap.set(key, summary);
    return summary;
  };

  const rememberLatest = (summary: AccountingSummaryRecord, date: Date): void => {
    const current =
      parseTimestamp(summary.latestTransactionDate)?.toMillis() ?? 0;
    if (date.getTime() > current) {
      summary.latestTransactionDate = admin.firestore.Timestamp.fromDate(date);
    }
  };

  for (const expense of input.expenses) {
    const amount = finiteNumber(expense.amount);
    const date = recordDate(expense);
    const category = `${expense.category ?? "other"}`.trim() || "other";
    const entity = entityFor(entityIdentity(expense, "supplier"));
    entity.totalExpenses = finiteNumber(entity.totalExpenses) + amount;
    entity.remainingBalance =
      finiteNumber(entity.totalExpenses) - finiteNumber(entity.totalPayments);
    entity.transactionCount = finiteNumber(entity.transactionCount) + 1;
    entity.attachmentCount =
      finiteNumber(entity.attachmentCount) + attachmentsCount(expense);
    incrementMap(entity.categoryBreakdown as Record<string, number>, category, amount);
    if (date) rememberLatest(entity, date);

    const categorySummary = categoryFor(category);
    categorySummary.totalAmount =
      finiteNumber(categorySummary.totalAmount) + amount;
    categorySummary.transactionCount =
      finiteNumber(categorySummary.transactionCount) + 1;
    if (date) rememberLatest(categorySummary, date);

    if (date) {
      const weekly = weeklyFor(date);
      weekly.totalExpenses = finiteNumber(weekly.totalExpenses) + amount;
      incrementMap(weekly._entityTotals as Record<string, number>, entity.entityName as string, amount);
      incrementMap(weekly._categoryTotals as Record<string, number>, category, amount);
      if (category === "labor" || category === "equipment") {
        const key = category === "labor" ? "laborSummary" : "equipmentSummary";
        const section = weekly[key] as Record<string, number>;
        section.total = finiteNumber(section.total) + amount;
        section.transactionCount = finiteNumber(section.transactionCount) + 1;
      }
      (weekly.recentTransactionRefs as string[]).push(`expenses/${expense.id ?? ""}`);
    }
  }

  for (const entry of input.workerEntries) {
    const amount = workerEntryTotalCost(entry);
    const date = recordDate(entry);
    const entity = entityFor({
      entityId: `${entry.workerId ?? "unassigned"}`,
      entityName: `${entry.workerName ?? entry.workerId ?? "Unassigned"}`,
      entityType: "worker",
    });
    entity.totalExpenses = finiteNumber(entity.totalExpenses) + amount;
    entity.remainingBalance =
      finiteNumber(entity.totalExpenses) - finiteNumber(entity.totalPayments);
    entity.transactionCount = finiteNumber(entity.transactionCount) + 1;
    entity.attachmentCount =
      finiteNumber(entity.attachmentCount) + attachmentsCount(entry);
    incrementMap(entity.categoryBreakdown as Record<string, number>, "labor", amount);
    if (date) rememberLatest(entity, date);

    const categorySummary = categoryFor("labor");
    categorySummary.totalAmount =
      finiteNumber(categorySummary.totalAmount) + amount;
    categorySummary.transactionCount =
      finiteNumber(categorySummary.transactionCount) + 1;
    if (date) rememberLatest(categorySummary, date);

    if (date) {
      const weekly = weeklyFor(date);
      weekly.totalExpenses = finiteNumber(weekly.totalExpenses) + amount;
      incrementMap(weekly._entityTotals as Record<string, number>, entity.entityName as string, amount);
      incrementMap(weekly._categoryTotals as Record<string, number>, "labor", amount);
      const labor = weekly.laborSummary as Record<string, number>;
      labor.total = finiteNumber(labor.total) + amount;
      labor.transactionCount = finiteNumber(labor.transactionCount) + 1;
      (weekly.recentTransactionRefs as string[]).push(`worker_entries/${entry.id ?? ""}`);
    }
  }

  for (const payment of input.payments) {
    const amount = finiteNumber(payment.amount);
    const date = recordDate(payment);
    const method = `${payment.paymentMethod ?? "unknown"}`.trim() || "unknown";
    const entity = entityFor(entityIdentity(payment, "client"));
    entity.totalPayments = finiteNumber(entity.totalPayments) + amount;
    entity.totalPaid = finiteNumber(entity.totalPaid) + amount;
    entity.remainingBalance =
      finiteNumber(entity.totalExpenses) - finiteNumber(entity.totalPayments);
    entity.transactionCount = finiteNumber(entity.transactionCount) + 1;
    entity.attachmentCount =
      finiteNumber(entity.attachmentCount) + attachmentsCount(payment);
    incrementMap(entity.paymentMethodBreakdown as Record<string, number>, method, amount);
    if (date) rememberLatest(entity, date);

    if (date) {
      const weekly = weeklyFor(date);
      weekly.totalPayments = finiteNumber(weekly.totalPayments) + amount;
      incrementMap(weekly._entityTotals as Record<string, number>, entity.entityName as string, amount);
      incrementMap(weekly._paymentMethodTotals as Record<string, number>, method, amount);
      (weekly.recentTransactionRefs as string[]).push(`payments/${payment.id ?? ""}`);
    }
  }

  for (const weekly of weeklyMap.values()) {
    weekly.topEntity = topMapEntry(weekly._entityTotals as Record<string, number>);
    weekly.topCategory = topMapEntry(
      weekly._categoryTotals as Record<string, number>,
    );
    weekly.paymentSummary = weekly._paymentMethodTotals;
    delete weekly._entityTotals;
    delete weekly._categoryTotals;
    delete weekly._paymentMethodTotals;
  }

  for (const entity of entityMap.values()) {
    entity.remainingBalance =
      finiteNumber(entity.totalExpenses) - finiteNumber(entity.totalPayments);
  }

  return {
    projectSummary,
    weeklySummaries: [...weeklyMap.values()],
    entitySummaries: [...entityMap.values()],
    categorySummaries: [...categoryMap.values()],
  };
}

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
  entityTotals: Record<string, number>;
  paymentMethodTotals: Record<string, number>;
  weeklyExpenses: number;
  weeklyIncome: number;
  equipmentExpenses: number;
  recentTransactions: Record<string, unknown>[];
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
    entityTotals: input.entityTotals,
    paymentMethodTotals: input.paymentMethodTotals,
    weeklyExpenses: input.weeklyExpenses,
    weeklyIncome: input.weeklyIncome,
    weeklyNet: input.weeklyIncome - input.weeklyExpenses,
    totalEquipmentCost: input.equipmentExpenses,
    recentTransactions: input.recentTransactions,
    monthlyFlow: input.monthlyFlow,
    topWorkers: input.topWorkers,
    recentExpenses: input.recentExpenses,
    recentPayments: input.recentPayments,
  };
}

export function buildWorkspaceMetricsPayload(
  workspaceId: string,
  metrics: TriggerDocData[],
): TriggerDocData {
  const activeProjects = metrics.filter(
    (project) => `${project.status ?? "active"}` === "active",
  ).length;
  const totalExpenses = metrics.reduce(
    (sum, project) => sum + Number(project.totalExpenses ?? 0),
    0,
  );
  const totalIncome = metrics.reduce(
    (sum, project) =>
      sum + Number(project.totalIncome ?? project.totalPayments ?? 0),
    0,
  );

  const weeklyExpenses = metrics.reduce(
    (sum, project) => sum + Number(project.weeklyExpenses ?? 0),
    0,
  );
  const weeklyIncome = metrics.reduce(
    (sum, project) => sum + Number(project.weeklyIncome ?? 0),
    0,
  );
  const categoryTotals: Record<string, number> = {};
  const entityTotals: Record<string, number> = {};
  const paymentMethodTotals: Record<string, number> = {};
  const recentTransactions: Record<string, unknown>[] = [];
  let laborTotal = 0;
  let equipmentTotal = 0;

  for (const project of metrics) {
    for (const [key, value] of Object.entries(
      (project.categoryTotals as Record<string, number> | undefined) ?? {},
    )) {
      categoryTotals[key] = (categoryTotals[key] ?? 0) + Number(value);
    }
    for (const [key, value] of Object.entries(
      (project.entityTotals as Record<string, number> | undefined) ?? {},
    )) {
      entityTotals[key] = (entityTotals[key] ?? 0) + Number(value);
    }
    for (const [key, value] of Object.entries(
      (project.paymentMethodTotals as Record<string, number> | undefined) ?? {},
    )) {
      paymentMethodTotals[key] =
        (paymentMethodTotals[key] ?? 0) + Number(value);
    }
    laborTotal += Number(project.totalLaborCost ?? 0);
    equipmentTotal += Number(project.totalEquipmentCost ?? 0);
    recentTransactions.push(
      ...(((project.recentTransactions as Record<string, unknown>[] | undefined) ?? [])),
    );
  }

  const topKey = (totals: Record<string, number>): string | null => {
    const sorted = Object.entries(totals).sort((a, b) => {
      const difference = b[1] - a[1];
      return difference !== 0 ? difference : a[0].localeCompare(b[0]);
    });
    return sorted[0]?.[0] ?? null;
  };

  recentTransactions.sort((a, b) => {
    const aDate = Date.parse(`${a.date ?? ""}`) || 0;
    const bDate = Date.parse(`${b.date ?? ""}`) || 0;
    return bDate - aDate;
  });

  return {
    workspaceId,
    totalProjects: metrics.length,
    activeProjects,
    totalExpenses,
    totalIncome,
    totalPayments: totalIncome,
    net: totalIncome - totalExpenses,
    netProfit: totalIncome - totalExpenses,
    weeklyExpenses,
    weeklyIncome,
    weeklyNet: weeklyIncome - weeklyExpenses,
    topCategory: topKey(categoryTotals),
    topEntity: topKey(entityTotals),
    categoryTotals,
    entityTotals,
    laborTotal,
    equipmentTotal,
    paymentMethodTotals,
    recentTransactions: recentTransactions.slice(0, 10),
  };
}

async function recomputeWorkspaceMetrics(workspaceId: string): Promise<void> {
  const projectMetricsSnap = await db
    .collection("project_metrics")
    .where("workspaceId", "==", workspaceId)
    .where("isArchived", "==", false)
    .get();
  const metrics = projectMetricsSnap.docs.map((doc) => doc.data());
  await writeIfChanged(
    db.collection("workspace_metrics").doc(workspaceId),
    buildWorkspaceMetricsPayload(workspaceId, metrics),
  );
}

async function recomputeWorkerAccountingSummary(
  workspaceId: string,
  workerId: string,
): Promise<void> {
  const summaryRef = db
    .collection("worker_accounting_summaries")
    .doc(`${workspaceId}_${workerId}`);
  const recordsSnap = await db
    .collection("worker_accounting_records")
    .where("workspaceId", "==", workspaceId)
    .where("workerId", "==", workerId)
    .get();

  if (recordsSnap.empty) {
    await summaryRef.delete().catch(() => undefined);
    return;
  }

  await writeIfChanged(
    summaryRef,
    buildWorkerAccountingSummaryPayload({
      workspaceId,
      workerId,
      records: recordsSnap.docs.map((doc) => doc.data()),
    }),
  );
}

async function replaceScopedSummaryDocs(
  collectionName: string,
  workspaceId: string,
  projectId: string,
  summaries: AccountingSummaryRecord[],
): Promise<void> {
  const existingSnap = await db
    .collection(collectionName)
    .where("workspaceId", "==", workspaceId)
    .where("projectId", "==", projectId)
    .get();
  const nextIds = new Set(
    summaries.map((summary) => `${summary.id ?? ""}`).filter(Boolean),
  );

  await Promise.all(
    existingSnap.docs
      .filter((doc) => !nextIds.has(doc.id))
      .map((doc) => doc.ref.delete()),
  );

  await Promise.all(
    summaries.map((summary) => {
      const id = `${summary.id ?? ""}`;
      const { id: _id, ...payload } = summary;
      return writeIfChanged(db.collection(collectionName).doc(id), payload);
    }),
  );
}

async function writeAccountingSummaries(input: {
  workspaceId: string;
  projectId: string;
  expenses: Array<TriggerDocData & { id?: string }>;
  payments: Array<TriggerDocData & { id?: string }>;
  workerEntries: Array<TriggerDocData & { id?: string }>;
}): Promise<void> {
  const summaries = buildAccountingSummaryPayloads(input);
  const projectSummaryId = `${summaries.projectSummary.id ?? ""}`;
  const { id: _id, ...projectSummary } = summaries.projectSummary;
  await Promise.all([
    writeIfChanged(
      db.collection("project_summaries").doc(projectSummaryId),
      projectSummary,
    ),
    replaceScopedSummaryDocs(
      "weekly_summaries",
      input.workspaceId,
      input.projectId,
      summaries.weeklySummaries,
    ),
    replaceScopedSummaryDocs(
      "entity_summaries",
      input.workspaceId,
      input.projectId,
      summaries.entitySummaries,
    ),
    replaceScopedSummaryDocs(
      "category_summaries",
      input.workspaceId,
      input.projectId,
      summaries.categorySummaries,
    ),
  ]);
}

export const checkLimit = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }
  const workspaceId = requireString(
    request.data as Record<string, unknown>,
    "workspaceId",
  );
  await assertMember(workspaceId, request.auth.uid);

  const type = requireString(
    request.data as Record<string, unknown>,
    "type",
  ) as LimitType;
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
): Promise<{ id: string; clientMutationId?: string }> {
  const workspaceId = requireString(data, "workspaceId");
  const role = await assertMember(workspaceId, uid);
  if (role !== "owner" && role !== "member") {
    throw new HttpsError("permission-denied", "Not allowed to create project");
  }

  const name = requireString(data, "name");
  const clientName = `${data.clientName ?? ""}`.trim();
  const contractValue = requireNumber(data, "contractValue");
  const startDate =
    parseTimestamp(data.startDate) ?? admin.firestore.Timestamp.now();
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
    clientMutationId: `${data.clientMutationId ?? ""}`.trim(),
    clientCreatedAt: parseTimestamp(data.clientCreatedAt),
    clientUpdatedAt: parseTimestamp(data.clientUpdatedAt),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    createdBy: uid,
    isArchived: false,
  });

  return {
    id: projectRef.id,
    clientMutationId: `${data.clientMutationId ?? ""}`.trim(),
  };
}

export const createProjectWithQuota = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }
  return createProjectWithQuotaForUser(
    request.auth.uid,
    request.data as Record<string, unknown>,
  );
});

export const createProjectWithQuotaHttp = onRequest(
  async (request, response) => {
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
      await verifyHttpAppCheck(
        request.header("X-Firebase-AppCheck") ?? undefined,
      );

      const bearerToken = bearerTokenFrom(
        request.header("Authorization") ?? undefined,
      );
      if (!bearerToken) {
        throw new HttpsError("unauthenticated", "Authentication required");
      }

      const decodedToken = await admin.auth().verifyIdToken(bearerToken);
      const body = payloadFrom(request.body);
      const data =
        Object.keys(payloadFrom(body.data)).length > 0
          ? payloadFrom(body.data)
          : body;

      const result = await createProjectWithQuotaForUser(
        decodedToken.uid,
        data,
      );
      response.status(200).json({ result });
    } catch (error) {
      const handled =
        error instanceof HttpsError
          ? error
          : new HttpsError("internal", "Failed to create project");
      response.status(httpStatusFor(handled.code)).json({
        error: {
          code: handled.code,
          status: canonicalCode(handled.code),
          message: handled.message,
          details: handled.details ?? null,
        },
      });
    }
  },
);

export const updateProject = onCall(async (request) => {
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
    throw new HttpsError(
      "permission-denied",
      "Project is not available in this workspace",
    );
  }
  if (project.isArchived === true) {
    throw new HttpsError(
      "failed-precondition",
      "Archived projects cannot be edited.",
    );
  }

  await projectRef.update({
    name: requireString(data, "name"),
    clientName: `${data.clientName ?? ""}`.trim(),
    contractValue: requireNumber(data, "contractValue"),
    startDate:
      parseTimestamp(data.startDate) ?? admin.firestore.Timestamp.now(),
    expectedEndDate: parseTimestamp(data.expectedEndDate),
    location: `${data.location ?? ""}`.trim(),
    description: `${data.description ?? ""}`.trim(),
    budgetLimit: Number(data.budgetLimit ?? 0) || null,
    completionPercentage: Number(data.completionPercentage ?? 0),
    status: `${data.status ?? "active"}`.trim() || "active",
    clientMutationId: `${data.clientMutationId ?? ""}`.trim(),
    clientUpdatedAt: parseTimestamp(data.clientUpdatedAt),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
});

export const archiveProject = onCall(async (request) => {
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
    throw new HttpsError(
      "permission-denied",
      "Project is not available in this workspace",
    );
  }

  await projectRef.update({
    isArchived: true,
    clientMutationId: `${data.clientMutationId ?? ""}`.trim(),
    clientUpdatedAt: parseTimestamp(data.clientUpdatedAt),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
});

export const unarchiveProject = onCall(async (request) => {
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
    throw new HttpsError(
      "permission-denied",
      "Project is not available in this workspace",
    );
  }

  await projectRef.update({
    isArchived: false,
    clientMutationId: `${data.clientMutationId ?? ""}`.trim(),
    clientUpdatedAt: parseTimestamp(data.clientUpdatedAt),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
});

export const createExpenseWithQuota = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }
  return createExpenseWithQuotaForUser(
    request.auth.uid,
    request.data as Record<string, unknown>,
  );
});

export async function createExpenseWithQuotaForUser(
  uid: string,
  data: Record<string, unknown>,
): Promise<{ id: string; clientMutationId?: string }> {
  const workspaceId = requireString(data, "workspaceId");
  await assertMember(workspaceId, uid);

  const projectId = requireString(data, "projectId");
  const category = requireString(data, "category");
  const allowedCategories = [
    "labor",
    "materials",
    "equipment",
    "transport",
    "other",
  ];
  if (!allowedCategories.includes(category)) {
    throw new HttpsError("invalid-argument", "Unsupported expense category");
  }
  const amount = requireNumber(data, "amount");
  if (amount <= 0) {
    throw new HttpsError(
      "invalid-argument",
      "Amount must be greater than zero",
    );
  }

  const projectSnap = await db.collection("projects").doc(projectId).get();
  if (!projectSnap.exists) {
    throw new HttpsError("invalid-argument", "Project does not exist");
  }
  const projectData = projectSnap.data() ?? {};
  if (
    `${projectData.workspaceId ?? ""}` !== workspaceId ||
    projectData.isArchived === true
  ) {
    throw new HttpsError(
      "permission-denied",
      "Project is not available in this workspace",
    );
  }

  const currencyRaw = `${data.currency ?? "EGP"}`.trim().toUpperCase();
  const currency = ["EGP", "USD", "SAR", "AED"].includes(currencyRaw)
    ? currencyRaw
    : "EGP";
  const inputMethod = `${data.inputMethod ?? "manual"}`.trim().toLowerCase();
  if (inputMethod !== "manual" && inputMethod !== "voice") {
    throw new HttpsError(
      "invalid-argument",
      "inputMethod must be manual or voice",
    );
  }

  const sourceRaw = `${data.source ?? ""}`.trim().toLowerCase();
  const source =
    sourceRaw === "rules" || sourceRaw === "llm" || sourceRaw === "hybrid"
      ? sourceRaw
      : null;

  const transcript = `${data.transcript ?? ""}`.trim();
  const storagePath = `${data.storagePath ?? ""}`.trim();
  const projectName =
    `${data.projectName ?? ""}`.trim() || `${projectData.name ?? ""}`.trim();

  const subscription = await getSubscription(workspaceId);
  if (!hasUnlimitedQuota(subscription)) {
    const current = await getCurrentUsage(workspaceId, "expensesPerMonth");
    const max = limitForType("expensesPerMonth");
    if (current + 1 > max) {
      quotaError("expensesPerMonth", current, max);
    }
  }

  const expenseRef = db.collection("expenses").doc();
  const counterRef = db
    .collection("usage_counters")
    .doc(`${workspaceId}_${periodKey()}`);

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
      attachments: ensureAttachmentItems(data, "attachments"),
      clientMutationId: `${data.clientMutationId ?? ""}`.trim(),
      clientCreatedAt: parseTimestamp(data.clientCreatedAt),
      clientUpdatedAt: parseTimestamp(data.clientUpdatedAt),
      createdBy: uid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      isArchived: false,
    });
    tx.set(
      counterRef,
      {
        workspaceId,
        periodKey: periodKey(),
        expensesCount: admin.firestore.FieldValue.increment(1),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    applyMetricsDeltaInTx(tx, projectId, workspaceId, amount, 0);
  });

  return {
    id: expenseRef.id,
    clientMutationId: `${data.clientMutationId ?? ""}`.trim(),
  };
}

export const createExpenseWithQuotaHttp = onRequest(
  async (request, response) => {
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
      await verifyHttpAppCheck(
        request.header("X-Firebase-AppCheck") ?? undefined,
      );

      const bearerToken = bearerTokenFrom(
        request.header("Authorization") ?? undefined,
      );
      if (!bearerToken) {
        throw new HttpsError("unauthenticated", "Authentication required");
      }

      const decodedToken = await admin.auth().verifyIdToken(bearerToken);
      const body = payloadFrom(request.body);
      const data =
        Object.keys(payloadFrom(body.data)).length > 0
          ? payloadFrom(body.data)
          : body;

      const result = await createExpenseWithQuotaForUser(
        decodedToken.uid,
        data,
      );
      response.status(200).json({ result });
    } catch (error) {
      const handled =
        error instanceof HttpsError
          ? error
          : new HttpsError("internal", "Failed to save expense");
      response.status(httpStatusFor(handled.code)).json({
        error: {
          code: handled.code,
          status: canonicalCode(handled.code),
          message: handled.message,
          details: handled.details ?? null,
        },
      });
    }
  },
);

export async function createPaymentWithQuotaForUser(
  uid: string,
  data: Record<string, unknown>,
): Promise<{ id: string; clientMutationId?: string }> {
  const workspaceId = requireString(data, "workspaceId");
  await assertMember(workspaceId, uid);

  const projectId = requireString(data, "projectId");
  const amount = requireNumber(data, "amount");
  if (amount <= 0) {
    throw new HttpsError(
      "invalid-argument",
      "Amount must be greater than zero",
    );
  }
  const projectSnap = await db.collection("projects").doc(projectId).get();
  if (!projectSnap.exists) {
    throw new HttpsError("invalid-argument", "Project does not exist");
  }
  const projectData = projectSnap.data() ?? {};
  if (`${projectData.workspaceId ?? ""}` !== workspaceId) {
    throw new HttpsError("invalid-argument", "Project does not exist");
  }
  if (projectData.isArchived === true) {
    throw new HttpsError(
      "permission-denied",
      "Project is archived and can no longer accept payments.",
    );
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
  const counterRef = db
    .collection("usage_counters")
    .doc(`${workspaceId}_${periodKey()}`);
  console.log("[payment.create.start]", {
    uid,
    workspaceId,
    projectId,
    amount,
    clientMutationId: `${data.clientMutationId ?? ""}`.trim(),
  });
  await db.runTransaction(async (tx) => {
    const attachments = ensureAttachmentItems(data, "attachments");
    tx.set(paymentRef, {
      id: paymentRef.id,
      workspaceId,
      projectId,
      amount,
      date: parseTimestamp(data.date) ?? admin.firestore.Timestamp.now(),
      paymentMethod: `${data.paymentMethod ?? "cash"}`.trim(),
      notes: `${data.notes ?? ""}`.trim(),
      attachments,
      clientMutationId: `${data.clientMutationId ?? ""}`.trim(),
      clientCreatedAt: parseTimestamp(data.clientCreatedAt),
      clientUpdatedAt: parseTimestamp(data.clientUpdatedAt),
      createdBy: uid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      isArchived: false,
    });
    tx.set(
      counterRef,
      {
        workspaceId,
        periodKey: periodKey(),
        paymentsCount: admin.firestore.FieldValue.increment(1),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    applyMetricsDeltaInTx(tx, projectId, workspaceId, 0, amount);
  });
  console.log("[payment.create.done]", {
    workspaceId,
    projectId,
    paymentId: paymentRef.id,
    amount,
    clientMutationId: `${data.clientMutationId ?? ""}`.trim(),
  });
  return {
    id: paymentRef.id,
    clientMutationId: `${data.clientMutationId ?? ""}`.trim(),
  };
}

export const createPaymentWithQuota = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }
  return createPaymentWithQuotaForUser(
    request.auth.uid,
    request.data as Record<string, unknown>,
  );
});

export const createPaymentWithQuotaHttp = onRequest(
  async (request, response) => {
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
      await verifyHttpAppCheck(
        request.header("X-Firebase-AppCheck") ?? undefined,
      );

      const bearerToken = bearerTokenFrom(
        request.header("Authorization") ?? undefined,
      );
      if (!bearerToken) {
        throw new HttpsError("unauthenticated", "Authentication required");
      }

      const decodedToken = await admin.auth().verifyIdToken(bearerToken);
      const body = payloadFrom(request.body);
      const data =
        Object.keys(payloadFrom(body.data)).length > 0
          ? payloadFrom(body.data)
          : body;

      const result = await createPaymentWithQuotaForUser(
        decodedToken.uid,
        data,
      );
      response.status(200).json({ result });
    } catch (error) {
      const handled =
        error instanceof HttpsError
          ? error
          : new HttpsError("internal", "Failed to save payment");
      response.status(httpStatusFor(handled.code)).json({
        error: {
          code: handled.code,
          status: canonicalCode(handled.code),
          message: handled.message,
          details: handled.details ?? null,
        },
      });
    }
  },
);

export async function createWorkerEntryWithQuotaForUser(
  uid: string,
  data: Record<string, unknown>,
): Promise<{ id: string; clientMutationId?: string }> {
  const workspaceId = requireString(data, "workspaceId");
  await assertMember(workspaceId, uid);

  const workerId = requireString(data, "workerId");
  const projectId = requireString(data, "projectId");
  const daysWorked = requireNumber(data, "daysWorked");
  const dailyWage = requireNumber(data, "dailyWage");
  if (daysWorked <= 0 || dailyWage <= 0) {
    throw new HttpsError(
      "invalid-argument",
      "Days worked and daily wage must be > 0",
    );
  }
  const totalCost = daysWorked * dailyWage;
  const [workerSnap, projectSnap] = await Promise.all([
    db.collection("workers").doc(workerId).get(),
    db.collection("projects").doc(projectId).get(),
  ]);
  if (!workerSnap.exists) {
    throw new HttpsError("invalid-argument", "Worker does not exist");
  }
  const workerData = workerSnap.data() ?? {};
  if (`${workerData.workspaceId ?? ""}` !== workspaceId) {
    throw new HttpsError("invalid-argument", "Worker does not exist");
  }
  if (workerData.isArchived === true) {
    throw new HttpsError(
      "permission-denied",
      "Worker is archived and can no longer accept new entries.",
    );
  }
  if (!projectSnap.exists) {
    throw new HttpsError("invalid-argument", "Project does not exist");
  }
  const projectData = projectSnap.data() ?? {};
  if (`${projectData.workspaceId ?? ""}` !== workspaceId) {
    throw new HttpsError("invalid-argument", "Project does not exist");
  }
  if (projectData.isArchived === true) {
    throw new HttpsError(
      "permission-denied",
      "Project is archived and can no longer accept worker entries.",
    );
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
  const attachments = ensureAttachmentItems(data, "attachments");
  const counterRef = db
    .collection("usage_counters")
    .doc(`${workspaceId}_${periodKey()}`);
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
      attachments,
      clientMutationId: `${data.clientMutationId ?? ""}`.trim(),
      clientCreatedAt: parseTimestamp(data.clientCreatedAt),
      clientUpdatedAt: parseTimestamp(data.clientUpdatedAt),
      createdBy: uid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      isArchived: false,
    });
    tx.set(
      counterRef,
      {
        workspaceId,
        periodKey: periodKey(),
        workerEntriesCount: admin.firestore.FieldValue.increment(1),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    applyMetricsDeltaInTx(tx, projectId, workspaceId, totalCost, 0);
  });
  return {
    id: entryRef.id,
    clientMutationId: `${data.clientMutationId ?? ""}`.trim(),
  };
}

export const createWorkerEntryWithQuota = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }
  return createWorkerEntryWithQuotaForUser(
    request.auth.uid,
    request.data as Record<string, unknown>,
  );
});

export const createWorkerEntryWithQuotaHttp = onRequest(
  async (request, response) => {
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
      await verifyHttpAppCheck(
        request.header("X-Firebase-AppCheck") ?? undefined,
      );

      const bearerToken = bearerTokenFrom(
        request.header("Authorization") ?? undefined,
      );
      if (!bearerToken) {
        throw new HttpsError("unauthenticated", "Authentication required");
      }

      const decodedToken = await admin.auth().verifyIdToken(bearerToken);
      const body = payloadFrom(request.body);
      const data =
        Object.keys(payloadFrom(body.data)).length > 0
          ? payloadFrom(body.data)
          : body;

      const result = await createWorkerEntryWithQuotaForUser(
        decodedToken.uid,
        data,
      );
      response.status(200).json({ result });
    } catch (error) {
      const handled =
        error instanceof HttpsError
          ? error
          : new HttpsError("internal", "Failed to save worker entry");
      response.status(httpStatusFor(handled.code)).json({
        error: {
          code: handled.code,
          status: canonicalCode(handled.code),
          message: handled.message,
          details: handled.details ?? null,
        },
      });
    }
  },
);

async function archiveExpenseWithQuotaRefundForUser(
  uid: string,
  data: Record<string, unknown>,
): Promise<void> {
  const workspaceId = requireString(data, "workspaceId");
  await assertMember(workspaceId, uid);
  const expenseId = requireString(data, "expenseId");
  const expenseRef = db.collection("expenses").doc(expenseId);
  const counterRef = db
    .collection("usage_counters")
    .doc(`${workspaceId}_${periodKey()}`);

  await db.runTransaction(async (tx) => {
    const expenseSnap = await tx.get(expenseRef);
    if (!expenseSnap.exists) {
      throw new HttpsError("not-found", "Expense not found");
    }
    const expense = expenseSnap.data() ?? {};
    if (`${expense.workspaceId ?? ""}` !== workspaceId) {
      throw new HttpsError(
        "permission-denied",
        "Expense is not available in this workspace",
      );
    }
    if (expense.isArchived === true) {
      return;
    }

    const archivedAmount = Number(expense.amount ?? 0);
    const archivedProjectId = `${expense.projectId ?? ""}`;

    tx.update(expenseRef, {
      isArchived: true,
      archivedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const counterSnap = await tx.get(counterRef);
    const current = Number(counterSnap.data()?.expensesCount ?? 0);
    tx.set(
      counterRef,
      {
        workspaceId,
        periodKey: periodKey(),
        expensesCount: Math.max(0, current - 1),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    if (archivedProjectId) {
      applyMetricsDeltaInTx(
        tx,
        archivedProjectId,
        workspaceId,
        -archivedAmount,
        0,
      );
    }
  });
}

export const archiveExpenseWithQuotaRefund = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }
  await archiveExpenseWithQuotaRefundForUser(
    request.auth.uid,
    request.data as Record<string, unknown>,
  );
});

export const archiveExpenseWithQuotaRefundHttp = onRequest(
  async (request, response) => {
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
      await verifyHttpAppCheck(
        request.header("X-Firebase-AppCheck") ?? undefined,
      );
      const bearerToken = bearerTokenFrom(
        request.header("Authorization") ?? undefined,
      );
      if (!bearerToken) {
        throw new HttpsError("unauthenticated", "Authentication required");
      }
      const decodedToken = await admin.auth().verifyIdToken(bearerToken);
      const body = payloadFrom(request.body);
      const data =
        Object.keys(payloadFrom(body.data)).length > 0
          ? payloadFrom(body.data)
          : body;
      await archiveExpenseWithQuotaRefundForUser(decodedToken.uid, data);
      response.status(200).json({ result: { ok: true } });
    } catch (error) {
      const handled =
        error instanceof HttpsError
          ? error
          : new HttpsError("internal", "Failed to archive expense");
      response.status(httpStatusFor(handled.code)).json({
        error: {
          code: handled.code,
          status: canonicalCode(handled.code),
          message: handled.message,
          details: handled.details ?? null,
        },
      });
    }
  },
);

async function archivePaymentWithQuotaRefundForUser(
  uid: string,
  data: Record<string, unknown>,
): Promise<void> {
  const workspaceId = requireString(data, "workspaceId");
  await assertMember(workspaceId, uid);
  const paymentId = requireString(data, "paymentId");
  const paymentRef = db.collection("payments").doc(paymentId);
  const counterRef = db
    .collection("usage_counters")
    .doc(`${workspaceId}_${periodKey()}`);

  await db.runTransaction(async (tx) => {
    const paymentSnap = await tx.get(paymentRef);
    if (!paymentSnap.exists) {
      throw new HttpsError("not-found", "Payment not found");
    }
    const payment = paymentSnap.data() ?? {};
    if (`${payment.workspaceId ?? ""}` !== workspaceId) {
      throw new HttpsError(
        "permission-denied",
        "Payment is not available in this workspace",
      );
    }
    if (payment.isArchived === true) {
      return;
    }

    const archivedAmount = Number(payment.amount ?? 0);
    const archivedProjectId = `${payment.projectId ?? ""}`;

    tx.update(paymentRef, {
      isArchived: true,
      archivedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const counterSnap = await tx.get(counterRef);
    const current = Number(counterSnap.data()?.paymentsCount ?? 0);
    tx.set(
      counterRef,
      {
        workspaceId,
        periodKey: periodKey(),
        paymentsCount: Math.max(0, current - 1),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    if (archivedProjectId) {
      applyMetricsDeltaInTx(
        tx,
        archivedProjectId,
        workspaceId,
        0,
        -archivedAmount,
      );
    }
  });
}

export const archivePaymentWithQuotaRefund = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }
  await archivePaymentWithQuotaRefundForUser(
    request.auth.uid,
    request.data as Record<string, unknown>,
  );
});

export const archivePaymentWithQuotaRefundHttp = onRequest(
  async (request, response) => {
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
      await verifyHttpAppCheck(
        request.header("X-Firebase-AppCheck") ?? undefined,
      );
      const bearerToken = bearerTokenFrom(
        request.header("Authorization") ?? undefined,
      );
      if (!bearerToken) {
        throw new HttpsError("unauthenticated", "Authentication required");
      }
      const decodedToken = await admin.auth().verifyIdToken(bearerToken);
      const body = payloadFrom(request.body);
      const data =
        Object.keys(payloadFrom(body.data)).length > 0
          ? payloadFrom(body.data)
          : body;
      await archivePaymentWithQuotaRefundForUser(decodedToken.uid, data);
      response.status(200).json({ result: { ok: true } });
    } catch (error) {
      const handled =
        error instanceof HttpsError
          ? error
          : new HttpsError("internal", "Failed to archive payment");
      response.status(httpStatusFor(handled.code)).json({
        error: {
          code: handled.code,
          status: canonicalCode(handled.code),
          message: handled.message,
          details: handled.details ?? null,
        },
      });
    }
  },
);

async function archiveWorkerEntryWithQuotaRefundForUser(
  uid: string,
  data: Record<string, unknown>,
): Promise<void> {
  const workspaceId = requireString(data, "workspaceId");
  await assertMember(workspaceId, uid);
  const entryId = requireString(data, "entryId");
  const entryRef = db.collection("worker_entries").doc(entryId);
  const counterRef = db
    .collection("usage_counters")
    .doc(`${workspaceId}_${periodKey()}`);

  await db.runTransaction(async (tx) => {
    const entrySnap = await tx.get(entryRef);
    if (!entrySnap.exists) {
      throw new HttpsError("not-found", "Worker entry not found");
    }
    const entry = entrySnap.data() ?? {};
    if (`${entry.workspaceId ?? ""}` !== workspaceId) {
      throw new HttpsError(
        "permission-denied",
        "Worker entry is not available in this workspace",
      );
    }
    if (entry.isArchived === true) {
      return;
    }

    const archivedCost = workerEntryTotalCost(entry);
    const archivedProjectId = `${entry.projectId ?? ""}`;

    tx.update(entryRef, {
      isArchived: true,
      archivedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const counterSnap = await tx.get(counterRef);
    const current = Number(counterSnap.data()?.workerEntriesCount ?? 0);
    tx.set(
      counterRef,
      {
        workspaceId,
        periodKey: periodKey(),
        workerEntriesCount: Math.max(0, current - 1),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    if (archivedProjectId) {
      applyMetricsDeltaInTx(
        tx,
        archivedProjectId,
        workspaceId,
        -archivedCost,
        0,
      );
    }
  });
}

export const archiveWorkerEntryWithQuotaRefund = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }
  await archiveWorkerEntryWithQuotaRefundForUser(
    request.auth.uid,
    request.data as Record<string, unknown>,
  );
});

export const archiveWorkerEntryWithQuotaRefundHttp = onRequest(
  async (request, response) => {
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
      await verifyHttpAppCheck(
        request.header("X-Firebase-AppCheck") ?? undefined,
      );
      const bearerToken = bearerTokenFrom(
        request.header("Authorization") ?? undefined,
      );
      if (!bearerToken) {
        throw new HttpsError("unauthenticated", "Authentication required");
      }
      const decodedToken = await admin.auth().verifyIdToken(bearerToken);
      const body = payloadFrom(request.body);
      const data =
        Object.keys(payloadFrom(body.data)).length > 0
          ? payloadFrom(body.data)
          : body;
      await archiveWorkerEntryWithQuotaRefundForUser(decodedToken.uid, data);
      response.status(200).json({ result: { ok: true } });
    } catch (error) {
      const handled =
        error instanceof HttpsError
          ? error
          : new HttpsError("internal", "Failed to archive worker entry");
      response.status(httpStatusFor(handled.code)).json({
        error: {
          code: handled.code,
          status: canonicalCode(handled.code),
          message: handled.message,
          details: handled.details ?? null,
        },
      });
    }
  },
);

export const updateExpense = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }

  const data = request.data as Record<string, unknown>;
  const workspaceId = requireString(data, "workspaceId");
  await assertMember(workspaceId, request.auth.uid);
  const expenseId = requireString(data, "expenseId");
  const projectId = requireString(data, "projectId");
  const category = requireString(data, "category");
  const amount = requireNumber(data, "amount");
  if (amount <= 0) {
    throw new HttpsError(
      "invalid-argument",
      "Amount must be greater than zero",
    );
  }

  const [expenseSnap, projectSnap] = await Promise.all([
    db.collection("expenses").doc(expenseId).get(),
    db.collection("projects").doc(projectId).get(),
  ]);
  if (!expenseSnap.exists) {
    throw new HttpsError("not-found", "Expense not found");
  }
  const expense = expenseSnap.data() ?? {};
  if (`${expense.workspaceId ?? ""}` !== workspaceId) {
    throw new HttpsError(
      "permission-denied",
      "Expense is not available in this workspace",
    );
  }
  if (expense.isArchived === true) {
    throw new HttpsError(
      "failed-precondition",
      "Archived expenses cannot be edited.",
    );
  }
  if (!projectSnap.exists) {
    throw new HttpsError("invalid-argument", "Project does not exist");
  }
  const project = projectSnap.data() ?? {};
  if (
    `${project.workspaceId ?? ""}` !== workspaceId ||
    project.isArchived === true
  ) {
    throw new HttpsError(
      "permission-denied",
      "Project is not available in this workspace",
    );
  }

  const oldAmount = Number(expense.amount ?? 0);
  const oldProjectId = `${expense.projectId ?? ""}`;
  const batch = db.batch();
  const updateData: Record<string, unknown> = {
    projectId,
    category,
    amount,
    date: parseTimestamp(data.date) ?? admin.firestore.Timestamp.now(),
    notes: `${data.notes ?? ""}`.trim(),
    supplierName: `${data.supplierName ?? ""}`.trim(),
    paymentMethod: `${data.paymentMethod ?? ""}`.trim(),
    clientMutationId: `${data.clientMutationId ?? ""}`.trim(),
    clientUpdatedAt: parseTimestamp(data.clientUpdatedAt),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (data.attachments != null) {
    updateData.attachments = ensureAttachmentItems(data, "attachments");
  }
  batch.update(expenseSnap.ref, updateData);
  if (oldProjectId === projectId) {
    applyMetricsDeltaInBatch(
      batch,
      projectId,
      workspaceId,
      amount - oldAmount,
      0,
    );
  } else {
    if (oldProjectId)
      applyMetricsDeltaInBatch(batch, oldProjectId, workspaceId, -oldAmount, 0);
    applyMetricsDeltaInBatch(batch, projectId, workspaceId, amount, 0);
  }
  await batch.commit();
});

export const updatePayment = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }

  const data = request.data as Record<string, unknown>;
  const workspaceId = requireString(data, "workspaceId");
  await assertMember(workspaceId, request.auth.uid);
  const paymentId = requireString(data, "paymentId");
  const projectId = requireString(data, "projectId");
  const amount = requireNumber(data, "amount");
  if (amount <= 0) {
    throw new HttpsError(
      "invalid-argument",
      "Amount must be greater than zero",
    );
  }

  const [paymentSnap, projectSnap] = await Promise.all([
    db.collection("payments").doc(paymentId).get(),
    db.collection("projects").doc(projectId).get(),
  ]);
  if (!paymentSnap.exists) {
    throw new HttpsError("not-found", "Payment not found");
  }
  const payment = paymentSnap.data() ?? {};
  if (`${payment.workspaceId ?? ""}` !== workspaceId) {
    throw new HttpsError(
      "permission-denied",
      "Payment is not available in this workspace",
    );
  }
  if (payment.isArchived === true) {
    throw new HttpsError(
      "failed-precondition",
      "Archived payments cannot be edited.",
    );
  }
  if (!projectSnap.exists) {
    throw new HttpsError("invalid-argument", "Project does not exist");
  }
  const project = projectSnap.data() ?? {};
  if (
    `${project.workspaceId ?? ""}` !== workspaceId ||
    project.isArchived === true
  ) {
    throw new HttpsError(
      "permission-denied",
      "Project is not available in this workspace",
    );
  }

  const oldAmount = Number(payment.amount ?? 0);
  const oldProjectId = `${payment.projectId ?? ""}`;
  const batch = db.batch();
  const updateData: Record<string, unknown> = {
    projectId,
    amount,
    date: parseTimestamp(data.date) ?? admin.firestore.Timestamp.now(),
    paymentMethod: `${data.paymentMethod ?? "cash"}`.trim(),
    notes: `${data.notes ?? ""}`.trim(),
    clientMutationId: `${data.clientMutationId ?? ""}`.trim(),
    clientUpdatedAt: parseTimestamp(data.clientUpdatedAt),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (data.attachments != null) {
    updateData.attachments = ensureAttachmentItems(data, "attachments");
  }
  batch.update(paymentSnap.ref, updateData);
  if (oldProjectId === projectId) {
    applyMetricsDeltaInBatch(
      batch,
      projectId,
      workspaceId,
      0,
      amount - oldAmount,
    );
  } else {
    if (oldProjectId)
      applyMetricsDeltaInBatch(batch, oldProjectId, workspaceId, 0, -oldAmount);
    applyMetricsDeltaInBatch(batch, projectId, workspaceId, 0, amount);
  }
  await batch.commit();
});

export const createWorker = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }

  const data = request.data as Record<string, unknown>;
  const workspaceId = requireString(data, "workspaceId");
  await assertMember(workspaceId, request.auth.uid);
  const name = requireString(data, "name");
  const billingTypeRaw = `${data.billingType ?? "daily"}`.trim().toLowerCase();
  const billingType = billingTypeRaw === "project" ? "project" : "daily";
  const status = normalizeWorkerStatus(data.status);
  const dailyWage = requireNumber(data, "dailyWage");
  if (billingType === "daily" && dailyWage <= 0) {
    throw new HttpsError(
      "invalid-argument",
      "Daily workers must have daily wage greater than zero",
    );
  }

  const workerRef = db.collection("workers").doc();
  await workerRef.set({
    id: workerRef.id,
    workspaceId,
    name,
    phoneNumber: `${data.phoneNumber ?? ""}`.trim(),
    dailyWage: billingType === "daily" ? dailyWage : 0,
    billingType,
    workerType: `${data.workerType ?? ""}`.trim(),
    notes: `${data.notes ?? ""}`.trim(),
    status,
    clientMutationId: `${data.clientMutationId ?? ""}`.trim(),
    clientCreatedAt: parseTimestamp(data.clientCreatedAt),
    clientUpdatedAt: parseTimestamp(data.clientUpdatedAt),
    createdBy: request.auth.uid,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    isArchived: false,
  });

  return {
    id: workerRef.id,
    clientMutationId: `${data.clientMutationId ?? ""}`.trim(),
  };
});

export const updateWorker = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }

  const data = request.data as Record<string, unknown>;
  const workspaceId = requireString(data, "workspaceId");
  await assertMember(workspaceId, request.auth.uid);
  const workerId = requireString(data, "workerId");
  const name = requireString(data, "name");
  const billingTypeRaw = `${data.billingType ?? "daily"}`.trim().toLowerCase();
  const billingType = billingTypeRaw === "project" ? "project" : "daily";
  const dailyWage = requireNumber(data, "dailyWage");
  if (billingType === "daily" && dailyWage <= 0) {
    throw new HttpsError(
      "invalid-argument",
      "Daily workers must have daily wage greater than zero",
    );
  }

  const workerRef = db.collection("workers").doc(workerId);
  const workerSnap = await workerRef.get();
  if (!workerSnap.exists) {
    throw new HttpsError("not-found", "Worker not found");
  }
  const worker = workerSnap.data() ?? {};
  if (`${worker.workspaceId ?? ""}` !== workspaceId) {
    throw new HttpsError(
      "permission-denied",
      "Worker is not available in this workspace",
    );
  }
  if (worker.isArchived === true) {
    throw new HttpsError(
      "failed-precondition",
      "Archived workers cannot be edited.",
    );
  }
  const status = normalizeWorkerStatus(data.status ?? worker.status ?? "active");

  await workerRef.update({
    name,
    phoneNumber: `${data.phoneNumber ?? ""}`.trim(),
    dailyWage: billingType === "daily" ? dailyWage : 0,
    billingType,
    workerType: `${data.workerType ?? ""}`.trim(),
    notes: `${data.notes ?? ""}`.trim(),
    status,
    clientMutationId: `${data.clientMutationId ?? ""}`.trim(),
    clientUpdatedAt: parseTimestamp(data.clientUpdatedAt),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
});

export const archiveWorker = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }

  const data = request.data as Record<string, unknown>;
  const workspaceId = requireString(data, "workspaceId");
  await assertMember(workspaceId, request.auth.uid);
  const workerId = requireString(data, "workerId");
  const workerRef = db.collection("workers").doc(workerId);
  const workerSnap = await workerRef.get();
  if (!workerSnap.exists) {
    throw new HttpsError("not-found", "Worker not found");
  }
  const worker = workerSnap.data() ?? {};
  if (`${worker.workspaceId ?? ""}` !== workspaceId) {
    throw new HttpsError(
      "permission-denied",
      "Worker is not available in this workspace",
    );
  }
  await workerRef.update({
    isArchived: true,
    clientMutationId: `${data.clientMutationId ?? ""}`.trim(),
    clientUpdatedAt: parseTimestamp(data.clientUpdatedAt),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
});

export const updateWorkerEntry = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }

  const data = request.data as Record<string, unknown>;
  const workspaceId = requireString(data, "workspaceId");
  await assertMember(workspaceId, request.auth.uid);
  const entryId = requireString(data, "entryId");
  const projectId = requireString(data, "projectId");
  const daysWorked = requireNumber(data, "daysWorked");
  const dailyWage = requireNumber(data, "dailyWage");
  if (daysWorked <= 0 || dailyWage <= 0) {
    throw new HttpsError(
      "invalid-argument",
      "Days worked and daily wage must be > 0",
    );
  }

  const [entrySnap, projectSnap] = await Promise.all([
    db.collection("worker_entries").doc(entryId).get(),
    db.collection("projects").doc(projectId).get(),
  ]);
  if (!entrySnap.exists) {
    throw new HttpsError("not-found", "Worker entry not found");
  }
  const entry = entrySnap.data() ?? {};
  if (`${entry.workspaceId ?? ""}` !== workspaceId) {
    throw new HttpsError(
      "permission-denied",
      "Worker entry is not available in this workspace",
    );
  }
  if (entry.isArchived === true) {
    throw new HttpsError(
      "failed-precondition",
      "Archived worker entries cannot be edited.",
    );
  }
  if (!projectSnap.exists) {
    throw new HttpsError("invalid-argument", "Project does not exist");
  }
  const project = projectSnap.data() ?? {};
  if (`${project.workspaceId ?? ""}` !== workspaceId) {
    throw new HttpsError("invalid-argument", "Project does not exist");
  }
  if (project.isArchived === true) {
    throw new HttpsError(
      "permission-denied",
      "Project is archived and can no longer accept worker entries.",
    );
  }

  const newTotalCost = daysWorked * dailyWage;
  const oldTotalCost = workerEntryTotalCost(entry);
  const oldProjectId = `${entry.projectId ?? ""}`;
  const batch = db.batch();
  const updateData: Record<string, unknown> = {
    projectId,
    daysWorked,
    dailyWage,
    totalCost: newTotalCost,
    date: parseTimestamp(data.date) ?? admin.firestore.Timestamp.now(),
    notes: `${data.notes ?? ""}`.trim(),
    clientMutationId: `${data.clientMutationId ?? ""}`.trim(),
    clientUpdatedAt: parseTimestamp(data.clientUpdatedAt),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (data.attachments != null) {
    updateData.attachments = ensureAttachmentItems(data, "attachments");
  }
  batch.update(entrySnap.ref, updateData);
  if (oldProjectId === projectId) {
    applyMetricsDeltaInBatch(
      batch,
      projectId,
      workspaceId,
      newTotalCost - oldTotalCost,
      0,
    );
  } else {
    if (oldProjectId)
      applyMetricsDeltaInBatch(
        batch,
        oldProjectId,
        workspaceId,
        -oldTotalCost,
        0,
      );
    applyMetricsDeltaInBatch(batch, projectId, workspaceId, newTotalCost, 0);
  }
  await batch.commit();
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
    throw new HttpsError(
      "permission-denied",
      "Project is not available in this workspace",
    );
  }

  const [expensesSnap, paymentsSnap, entriesSnap, notificationsSnap] =
    await Promise.all([
      db
        .collection("expenses")
        .where("workspaceId", "==", workspaceId)
        .where("projectId", "==", projectId)
        .get(),
      db
        .collection("payments")
        .where("workspaceId", "==", workspaceId)
        .where("projectId", "==", projectId)
        .get(),
      db
        .collection("worker_entries")
        .where("workspaceId", "==", workspaceId)
        .where("projectId", "==", projectId)
        .get(),
      db
        .collection("notifications")
        .where("workspaceId", "==", workspaceId)
        .where("projectId", "==", projectId)
        .get(),
    ]);

  const expenseRefund = expensesSnap.docs.filter(
    (doc) => doc.data().isArchived !== true,
  ).length;
  const paymentRefund = paymentsSnap.docs.filter(
    (doc) => doc.data().isArchived !== true,
  ).length;
  const entryRefund = entriesSnap.docs.filter(
    (doc) => doc.data().isArchived !== true,
  ).length;
  const counterRef = db
    .collection("usage_counters")
    .doc(`${workspaceId}_${periodKey()}`);

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
  batch.set(
    counterRef,
    {
      workspaceId,
      periodKey: periodKey(),
      expensesCount: Math.max(
        0,
        Number(currentData.expensesCount ?? 0) - expenseRefund,
      ),
      paymentsCount: Math.max(
        0,
        Number(currentData.paymentsCount ?? 0) - paymentRefund,
      ),
      workerEntriesCount: Math.max(
        0,
        Number(currentData.workerEntriesCount ?? 0) - entryRefund,
      ),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

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

  await db
    .collection("users")
    .doc(request.auth.uid)
    .set(
      {
        fullName,
        photoUrl,
        defaultCurrency,
        ...(riskAlertsEnabled == null ? {} : { riskAlertsEnabled }),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
});

export const updateUserSettings = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }

  const data = request.data as Record<string, unknown>;
  const targetUserId = `${data.userId ?? request.auth.uid}`.trim();
  if (targetUserId !== request.auth.uid) {
    throw new HttpsError(
      "permission-denied",
      "Cannot update another user's settings",
    );
  }

  const updates: Record<string, unknown> = {
    clientMutationId: `${data.clientMutationId ?? ""}`.trim(),
    clientUpdatedAt: parseTimestamp(data.clientUpdatedAt),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  const defaultCurrency = currencyCode(data.defaultCurrency);
  if (defaultCurrency) {
    updates.defaultCurrency = defaultCurrency;
  }
  const riskAlertsEnabled = asBooleanOrUndefined(data.riskAlertsEnabled);
  if (riskAlertsEnabled != null) {
    updates.riskAlertsEnabled = riskAlertsEnabled;
  }

  await db
    .collection("users")
    .doc(request.auth.uid)
    .set(updates, { merge: true });
});

export async function bootstrapWorkspaceForUser(input: {
  uid: string;
  email?: string | null;
  fullName?: string | null;
  photoUrl?: string | null;
}): Promise<{
  workspaceId: string;
  created: boolean;
  setupCompleted: boolean;
}> {
  const uid = input.uid.trim();
  if (!uid) {
    throw new HttpsError("invalid-argument", "Missing authenticated user");
  }

  const email = normalizeEmail(`${input.email ?? ""}`);
  const fullName = `${input.fullName ?? ""}`.trim();
  const photoUrl = `${input.photoUrl ?? ""}`.trim();
  const userRef = db.collection("users").doc(uid);
  const userSnap = await userRef.get();
  const existingUser = userSnap.data() ?? {};
  const incomingEmail = nonEmptyStringOrUndefined(email);
  const incomingFullName = nonEmptyStringOrUndefined(fullName);
  const incomingPhotoUrl = nonEmptyStringOrUndefined(photoUrl);
  const existingEmail = nonEmptyStringOrUndefined(
    `${existingUser.email ?? ""}`,
  );
  const existingFullName = nonEmptyStringOrUndefined(
    `${existingUser.fullName ?? ""}`,
  );
  const existingPhotoUrl = nonEmptyStringOrUndefined(
    `${existingUser.photoUrl ?? ""}`,
  );
  const existingDefaultCurrency = nonEmptyStringOrUndefined(
    `${existingUser.defaultCurrency ?? ""}`,
  );
  const existingRiskAlertsEnabled = asBooleanOrUndefined(
    existingUser.riskAlertsEnabled,
  );
  const existingSetupCompleted =
    existingUser.setupCompleted === false ? false : true;

  function existingUserPayload(workspaceId: string): Record<string, unknown> {
    const payload: Record<string, unknown> = {
      id: uid,
      workspaceId,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    assignIfDefined(payload, "email", existingEmail ?? incomingEmail);
    assignIfDefined(payload, "fullName", existingFullName ?? incomingFullName);
    assignIfDefined(payload, "photoUrl", existingPhotoUrl ?? incomingPhotoUrl);
    assignIfDefined(payload, "defaultCurrency", existingDefaultCurrency);
    assignIfDefined(payload, "riskAlertsEnabled", existingRiskAlertsEnabled);
    payload.setupCompleted = existingSetupCompleted;
    return payload;
  }

  function newUserPayload(workspaceId: string): Record<string, unknown> {
    const payload: Record<string, unknown> = {
      id: uid,
      workspaceId,
      defaultCurrency: "EGP",
      riskAlertsEnabled: true,
      setupCompleted: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    assignIfDefined(payload, "email", incomingEmail);
    assignIfDefined(payload, "fullName", incomingFullName);
    assignIfDefined(payload, "photoUrl", incomingPhotoUrl);
    return payload;
  }

  const membershipSnap = await db
    .collection("memberships")
    .where("userId", "==", uid)
    .limit(1)
    .get();
  if (!membershipSnap.empty) {
    const workspaceId =
      `${membershipSnap.docs[0].data().workspaceId ?? ""}`.trim();
    if (workspaceId) {
      await userRef.set(
        userSnap.exists
          ? existingUserPayload(workspaceId)
          : newUserPayload(workspaceId),
        { merge: true },
      );
      return {
        workspaceId,
        created: false,
        setupCompleted: userSnap.exists ? existingSetupCompleted : false,
      };
    }
  }

  const legacyWorkspaceId = `${userSnap.data()?.workspaceId ?? ""}`.trim();
  if (legacyWorkspaceId) {
    const legacyWorkspaceRef = db
      .collection("workspaces")
      .doc(legacyWorkspaceId);
    const legacyWorkspaceSnap = await legacyWorkspaceRef.get();
    const legacyOwnerId = `${legacyWorkspaceSnap.data()?.ownerId ?? ""}`.trim();

    if (!legacyWorkspaceSnap.exists) {
      await legacyWorkspaceRef.set(
        {
          id: legacyWorkspaceId,
          name: userWorkspaceName(fullName),
          ownerId: uid,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }

    if (legacyWorkspaceSnap.exists && legacyOwnerId !== uid) {
      const legacyRole = await roleForUser(legacyWorkspaceId, uid);
      if (!legacyRole) {
        throw new HttpsError(
          "failed-precondition",
          "Legacy workspace points to a workspace owned by another user without a valid membership.",
        );
      }
    } else {
      await membershipRef(legacyWorkspaceId, uid).set(
        {
          workspaceId: legacyWorkspaceId,
          userId: uid,
          role: "owner",
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }

    await userRef.set(
      userSnap.exists
        ? existingUserPayload(legacyWorkspaceId)
        : newUserPayload(legacyWorkspaceId),
      { merge: true },
    );
    return {
      workspaceId: legacyWorkspaceId,
      created: false,
      setupCompleted: userSnap.exists ? existingSetupCompleted : false,
    };
  }

  const workspaceRef = db.collection("workspaces").doc();
  const workspaceId = workspaceRef.id;
  const batch = db.batch();
  batch.set(workspaceRef, {
    id: workspaceId,
    name: userWorkspaceName(fullName),
    ownerId: uid,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  batch.set(membershipRef(workspaceId, uid), {
    workspaceId,
    userId: uid,
    role: "owner",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  batch.set(
    userRef,
    {
      ...newUserPayload(workspaceId),
    },
    { merge: true },
  );
  await batch.commit();
  return { workspaceId, created: true, setupCompleted: false };
}

export const ensureUserWorkspaceBootstrap = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }

  return bootstrapWorkspaceForUser({
    uid: request.auth.uid,
    email: `${request.auth.token.email ?? ""}`,
    fullName: `${request.auth.token.name ?? ""}`,
    photoUrl: `${request.auth.token.picture ?? ""}`,
  });
});

export async function setActiveWorkspaceForUser(input: {
  uid: string;
  workspaceId: string;
}): Promise<{workspaceId: string}> {
  const uid = input.uid.trim();
  const workspaceId = input.workspaceId.trim();
  if (!uid || !workspaceId) {
    throw new HttpsError("invalid-argument", "Missing workspace selection");
  }

  const role = await roleForUser(workspaceId, uid);
  if (!role) {
    const workspaceSnap = await db.collection("workspaces").doc(workspaceId).get();
    if (`${workspaceSnap.data()?.ownerId ?? ""}` !== uid) {
      throw new HttpsError(
        "permission-denied",
        "User is not a member of this workspace",
      );
    }
    await membershipRef(workspaceId, uid).set(
      {
        workspaceId,
        userId: uid,
        role: "owner",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
  }
  await db.collection("users").doc(uid).set(
    {
      id: uid,
      workspaceId,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
  return {workspaceId};
}

export const setActiveWorkspace = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }
  const data = request.data as Record<string, unknown>;
  return setActiveWorkspaceForUser({
    uid: request.auth.uid,
    workspaceId: requireString(data, "workspaceId"),
  });
});

export async function completeInitialWorkspaceSetupForUser(input: {
  uid: string;
  workspaceId: string;
  workspaceName: string;
  defaultCurrency: string;
}): Promise<{workspaceId: string; setupCompleted: boolean}> {
  const uid = input.uid.trim();
  const workspaceId = input.workspaceId.trim();
  const workspaceName = input.workspaceName.trim();
  const defaultCurrency = requireCurrencyCode(input.defaultCurrency);
  if (!uid || !workspaceId) {
    throw new HttpsError("invalid-argument", "Missing workspace setup target");
  }
  if (!workspaceName) {
    throw new HttpsError("invalid-argument", "Missing workspace name");
  }

  const workspaceRef = db.collection("workspaces").doc(workspaceId);
  const workspaceSnap = await workspaceRef.get();
  if (!workspaceSnap.exists) {
    throw new HttpsError("not-found", "Workspace not found");
  }
  if (`${workspaceSnap.data()?.ownerId ?? ""}` !== uid) {
    throw new HttpsError(
      "permission-denied",
      "Only the workspace owner can complete setup",
    );
  }

  await db.runTransaction(async (tx) => {
    tx.set(
      workspaceRef,
      {
        name: workspaceName,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    tx.set(
      db.collection("users").doc(uid),
      {
        id: uid,
        workspaceId,
        defaultCurrency,
        setupCompleted: true,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    tx.set(
      membershipRef(workspaceId, uid),
      {
        workspaceId,
        userId: uid,
        role: "owner",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  });

  return {workspaceId, setupCompleted: true};
}

export const completeInitialWorkspaceSetup = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }
  const data = request.data as Record<string, unknown>;
  return completeInitialWorkspaceSetupForUser({
    uid: request.auth.uid,
    workspaceId: requireString(data, "workspaceId"),
    workspaceName: requireString(data, "workspaceName"),
    defaultCurrency: requireString(data, "defaultCurrency"),
  });
});

function validWorkspaceRole(role: string): boolean {
  return ["owner", "admin", "accountingApproved", "member", "entryOnly"]
    .includes(role);
}

async function ownerCount(workspaceId: string): Promise<number> {
  const snap = await db
    .collection("memberships")
    .where("workspaceId", "==", workspaceId)
    .where("role", "==", "owner")
    .get();
  return snap.size;
}

async function assertWorkspaceOwner(workspaceId: string, userId: string) {
  const role = await assertMember(workspaceId, userId);
  if (role !== "owner") {
    throw new HttpsError("permission-denied", "Only owner can manage members");
  }
}

export async function updateWorkspaceMemberRoleForUser(input: {
  ownerUid: string;
  workspaceId: string;
  targetUserId: string;
  role: string;
}): Promise<{userId: string; workspaceId: string; role: string}> {
  const ownerUid = input.ownerUid.trim();
  const workspaceId = input.workspaceId.trim();
  const targetUserId = input.targetUserId.trim();
  const role = input.role.trim();
  if (!workspaceId || !targetUserId || !role) {
    throw new HttpsError("invalid-argument", "Missing member role update");
  }
  if (!validWorkspaceRole(role)) {
    throw new HttpsError("invalid-argument", "Unsupported workspace role");
  }
  await assertWorkspaceOwner(workspaceId, ownerUid);

  const membership = await membershipRef(workspaceId, targetUserId).get();
  if (!membership.exists) {
    throw new HttpsError("not-found", "Workspace member not found");
  }
  const currentRole = `${membership.data()?.role ?? "member"}`;
  if (currentRole === "owner" && role !== "owner") {
    const count = await ownerCount(workspaceId);
    if (count <= 1) {
      throw new HttpsError(
        "failed-precondition",
        "Workspace must keep at least one owner",
      );
    }
  }

  await membership.ref.set(
    {
      role,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  return {userId: targetUserId, workspaceId, role};
}

export const updateWorkspaceMemberRole = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }
  const data = request.data as Record<string, unknown>;
  return updateWorkspaceMemberRoleForUser({
    ownerUid: request.auth.uid,
    workspaceId: requireString(data, "workspaceId"),
    targetUserId: requireString(data, "userId"),
    role: requireString(data, "role"),
  });
});

export async function removeWorkspaceMemberForUser(input: {
  ownerUid: string;
  workspaceId: string;
  targetUserId: string;
}): Promise<{userId: string; workspaceId: string; removed: boolean}> {
  const ownerUid = input.ownerUid.trim();
  const workspaceId = input.workspaceId.trim();
  const targetUserId = input.targetUserId.trim();
  if (!workspaceId || !targetUserId) {
    throw new HttpsError("invalid-argument", "Missing member removal target");
  }
  await assertWorkspaceOwner(workspaceId, ownerUid);

  const membership = await membershipRef(workspaceId, targetUserId).get();
  if (!membership.exists) {
    throw new HttpsError("not-found", "Workspace member not found");
  }
  const currentRole = `${membership.data()?.role ?? "member"}`;
  if (currentRole === "owner") {
    const count = await ownerCount(workspaceId);
    if (count <= 1) {
      throw new HttpsError(
        "failed-precondition",
        "Workspace must keep at least one owner",
      );
    }
  }

  await membership.ref.delete();
  return {userId: targetUserId, workspaceId, removed: true};
}

export const removeWorkspaceMember = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }
  const data = request.data as Record<string, unknown>;
  return removeWorkspaceMemberForUser({
    ownerUid: request.auth.uid,
    workspaceId: requireString(data, "workspaceId"),
    targetUserId: requireString(data, "userId"),
  });
});

export async function inviteMemberByEmailForUser(input: {
  ownerUid: string;
  workspaceId: string;
  email: string;
  role?: string;
}): Promise<{userId: string; workspaceId: string}> {
  const ownerUid = input.ownerUid.trim();
  const workspaceId = input.workspaceId.trim();
  const ownerRole = await assertMember(workspaceId, ownerUid);
  if (ownerRole !== "owner") {
    throw new HttpsError("permission-denied", "Only owner can invite members");
  }

  const email = normalizeEmail(input.email);
  if (!email) {
    throw new HttpsError("invalid-argument", "Missing required field: email");
  }
  const role = `${input.role ?? "member"}`.trim() || "member";
  if (!validWorkspaceRole(role)) {
    throw new HttpsError("invalid-argument", "Unsupported workspace role");
  }
  const userSnap = await db
    .collection("users")
    .where("email", "==", email)
    .limit(1)
    .get();
  if (userSnap.empty) {
    throw new HttpsError(
      "not-found",
      "No existing user was found with that email",
    );
  }

  const userId = userSnap.docs[0].id;
  const deterministicMembership = await membershipRef(
    workspaceId,
    userId,
  ).get();
  if (deterministicMembership.exists) {
    throw new HttpsError(
      "already-exists",
      "User is already a member of this workspace",
    );
  }

  const existingMembership = await db
    .collection("memberships")
    .where("workspaceId", "==", workspaceId)
    .where("userId", "==", userId)
    .limit(1)
    .get();
  if (!existingMembership.empty) {
    throw new HttpsError(
      "already-exists",
      "User is already a member of this workspace",
    );
  }

  const subscription = await getSubscription(workspaceId);
  if (ENFORCE_TEAM_MEMBER_LIMITS && !hasUnlimitedQuota(subscription)) {
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
    createdBy: ownerUid,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await upsertNotificationForUsers({
    workspaceId,
    userIds: [userId],
    type: "team_invite_added",
    title: "Workspace Access Granted",
    message: "You were added to a workspace team.",
  });

  return {userId, workspaceId};
}

export const inviteMemberByEmail = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }
  const data = request.data as Record<string, unknown>;
  return inviteMemberByEmailForUser({
    ownerUid: request.auth.uid,
    workspaceId: requireString(data, "workspaceId"),
    email: requireString(data, "email"),
    role: `${data.role ?? "member"}`,
  });
});

export async function inviteMemberWithQuotaForUser(input: {
  ownerUid: string;
  workspaceId: string;
  userId: string;
  role?: string;
}): Promise<{userId: string; workspaceId: string}> {
  const ownerUid = input.ownerUid.trim();
  const workspaceId = input.workspaceId.trim();
  const role = await assertMember(workspaceId, ownerUid);
  if (role !== "owner") {
    throw new HttpsError("permission-denied", "Only owner can invite members");
  }

  const newUserId = input.userId.trim();
  if (!newUserId) {
    throw new HttpsError("invalid-argument", "Missing required field: userId");
  }
  const memberRole = `${input.role ?? "member"}`.trim() || "member";
  if (!validWorkspaceRole(memberRole)) {
    throw new HttpsError("invalid-argument", "Unsupported workspace role");
  }
  const deterministicMembership = await membershipRef(
    workspaceId,
    newUserId,
  ).get();
  if (deterministicMembership.exists) {
    throw new HttpsError(
      "already-exists",
      "User is already a member of this workspace",
    );
  }
  const legacyMembership = await db
    .collection("memberships")
    .where("workspaceId", "==", workspaceId)
    .where("userId", "==", newUserId)
    .limit(1)
    .get();
  if (!legacyMembership.empty) {
    throw new HttpsError(
      "already-exists",
      "User is already a member of this workspace",
    );
  }

  const subscription = await getSubscription(workspaceId);
  if (ENFORCE_TEAM_MEMBER_LIMITS && !hasUnlimitedQuota(subscription)) {
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
    createdBy: ownerUid,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await upsertNotificationForUsers({
    workspaceId,
    userIds: [newUserId],
    type: "team_invite_added",
    title: "Workspace Access Granted",
    message: "You were added to a workspace team.",
  });

  return {userId: newUserId, workspaceId};
}

export const inviteMemberWithQuota = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required");
  }
  const data = request.data as Record<string, unknown>;
  return inviteMemberWithQuotaForUser({
    ownerUid: request.auth.uid,
    workspaceId: requireString(data, "workspaceId"),
    userId: requireString(data, "userId"),
    role: `${data.role ?? "member"}`,
  });
});

export const revenuecatWebhook = onRequest(
  { secrets: [revenuecatWebhookSecret] },
  async (req, res) => {
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

    const event = (req.body?.event ?? req.body) as Record<string, unknown>;
    const workspaceId = `${event.app_user_id ?? ""}`.trim();
    if (!workspaceId) {
      res.status(400).json({ error: "missing_workspace" });
      return;
    }

    const eventType = `${event.type ?? "UNKNOWN"}`;
    const periodType = `${event.period_type ?? "UNKNOWN"}`;
    const tier = mapRevenueCatTier(event.entitlement_ids);
    const status = mapRevenueCatStatus(eventType, periodType);
    const periodEndsAt =
      parseTimestamp(event.expiration_at_ms) ??
      parseTimestamp(event.expires_date);
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
      { merge: true },
    );

    const recipients = await notificationRecipients(workspaceId, false);
    await upsertNotificationForUsers({
      workspaceId,
      userIds: recipients,
      type: "subscription_status_changed",
      title: "Subscription Updated",
      message: `Subscription is now ${tier.toUpperCase()} (${status})`,
    });

    res.status(200).json({ ok: true });
  },
);

async function recomputeProjectSummary(
  workspaceId: string,
  projectId: string,
): Promise<void> {
  const projectMetricsRef = db.collection("project_metrics").doc(projectId);
  const [
    projectSnap,
    projectMetricsSnap,
    expensesSnap,
    paymentsSnap,
    workerEntriesSnap,
  ] = await Promise.all([
    db.collection("projects").doc(projectId).get(),
    projectMetricsRef.get(),
    db
      .collection("expenses")
      .where("workspaceId", "==", workspaceId)
      .where("projectId", "==", projectId)
      .where("isArchived", "==", false)
      .get(),
    db
      .collection("payments")
      .where("workspaceId", "==", workspaceId)
      .where("projectId", "==", projectId)
      .where("isArchived", "==", false)
      .get(),
    db
      .collection("worker_entries")
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
  const completionPercentage = Math.max(
    0,
    Number(project.completionPercentage ?? 0),
  );
  const budgetLimit = Number(project.budgetLimit ?? 0) || null;
  const previousMetrics = projectMetricsSnap.data() ?? {};
  const previousRiskLevel = `${previousMetrics.riskLevel ?? "low"}`;
  const previousHealthStatus = `${previousMetrics.healthStatus ?? "healthy"}`;

  const manualExpenses = expensesSnap.docs.reduce(
    (sum, doc) => sum + Number(doc.data().amount ?? 0),
    0,
  );
  const laborExpenses = workerEntriesSnap.docs.reduce(
    (sum, doc) => sum + workerEntryTotalCost(doc.data()),
    0,
  );
  const totalExpenses = manualExpenses + laborExpenses;
  const totalPayments = paymentsSnap.docs.reduce(
    (sum, doc) => sum + Number(doc.data().amount ?? 0),
    0,
  );
  const netProfit = totalPayments - totalExpenses;
  const remainingBalance = contractValue - totalPayments;

  const expectedFinalCost =
    completionPercentage > 0
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

  const categoryTotals = expensesSnap.docs.reduce<Record<string, number>>(
    (map, doc) => {
      const category = `${doc.data().category ?? "other"}`;
      map[category] = (map[category] ?? 0) + Number(doc.data().amount ?? 0);
      return map;
    },
    {},
  );
  if (laborExpenses > 0) {
    categoryTotals.labor = (categoryTotals.labor ?? 0) + laborExpenses;
  }

  const monthlyMap = new Map<string, MonthlyFlowPoint>();
  const pointFor = (date: Date): MonthlyFlowPoint => {
    const monthKey = `${date.getUTCFullYear()}-${`${date.getUTCMonth() + 1}`.padStart(2, "0")}`;
    const existing = monthlyMap.get(monthKey);
    if (existing) {
      return existing;
    }
    const point = { month: monthKey, expenses: 0, income: 0 };
    monthlyMap.set(monthKey, point);
    return point;
  };

  for (const doc of expensesSnap.docs) {
    const date = parseTimestamp(doc.data().date)?.toDate();
    if (!date) {
      continue;
    }
    pointFor(date).expenses += Number(doc.data().amount ?? 0);
  }
  for (const doc of workerEntriesSnap.docs) {
    const date = parseTimestamp(doc.data().date)?.toDate();
    if (!date) {
      continue;
    }
    pointFor(date).expenses += workerEntryTotalCost(doc.data());
  }
  for (const doc of paymentsSnap.docs) {
    const date = parseTimestamp(doc.data().date)?.toDate();
    if (!date) {
      continue;
    }
    pointFor(date).income += Number(doc.data().amount ?? 0);
  }
  const monthlyFlow = Array.from(monthlyMap.values()).sort((a, b) =>
    a.month.localeCompare(b.month),
  );

  const workerIdsInEntries = Array.from(
    new Set(
      workerEntriesSnap.docs
        .map((doc) => `${doc.data().workerId ?? ""}`.trim())
        .filter((id) => id.length > 0),
    ),
  );
  const workerNameMap = await workerNameMapForEntries(
    workspaceId,
    workerIdsInEntries,
  );
  const workerCosts = workerEntriesSnap.docs.reduce<
    Record<string, { name: string; totalCost: number; totalDays: number }>
  >((map, doc) => {
    const workerId = `${doc.data().workerId ?? ""}`;
    const current = map[workerId] ?? {
      name: workerNameMap.get(workerId) ?? workerId,
      totalCost: 0,
      totalDays: 0,
    };
    current.totalCost += workerEntryTotalCost(doc.data());
    current.totalDays += Number(doc.data().daysWorked ?? 0);
    map[workerId] = current;
    return map;
  }, {});
  const topWorkers = Object.entries(workerCosts)
    .map(([workerId, data]) => ({ workerId, ...data }))
    .sort((a, b) => b.totalCost - a.totalCost)
    .slice(0, 5);

  const recentExpenses: Record<string, unknown>[] = expensesSnap.docs
    .map((doc) => ({ id: doc.id, ...(doc.data() as Record<string, unknown>) }))
    .sort((a, b) => {
      const aEntry = a as Record<string, unknown>;
      const bEntry = b as Record<string, unknown>;
      const aDate = parseTimestamp(aEntry["date"])?.toMillis() ?? 0;
      const bDate = parseTimestamp(bEntry["date"])?.toMillis() ?? 0;
      return bDate - aDate;
    })
    .slice(0, 5);
  const recentPayments: Record<string, unknown>[] = paymentsSnap.docs
    .map((doc) => ({ id: doc.id, ...(doc.data() as Record<string, unknown>) }))
    .sort((a, b) => {
      const aEntry = a as Record<string, unknown>;
      const bEntry = b as Record<string, unknown>;
      const aDate = parseTimestamp(aEntry["date"])?.toMillis() ?? 0;
      const bDate = parseTimestamp(bEntry["date"])?.toMillis() ?? 0;
      return bDate - aDate;
    })
    .slice(0, 5);

  const expenseRecords: TriggerDocData[] = expensesSnap.docs.map((doc) => ({
    id: doc.id,
    ...(doc.data() as TriggerDocData),
  }));
  const paymentRecords: TriggerDocData[] = paymentsSnap.docs.map((doc) => ({
    id: doc.id,
    ...(doc.data() as TriggerDocData),
  }));
  const workerEntryRecords: TriggerDocData[] = workerEntriesSnap.docs.map((doc) => ({
    id: doc.id,
    ...(doc.data() as TriggerDocData),
  }));
  const weekStart = new Date();
  weekStart.setUTCHours(0, 0, 0, 0);
  weekStart.setUTCDate(weekStart.getUTCDate() - 6);
  const inCurrentWeek = (record: Record<string, unknown>): boolean => {
    const date = parseTimestamp(record.date)?.toDate();
    return date != null && date >= weekStart;
  };
  const weeklyManualExpenses = expenseRecords
    .filter(inCurrentWeek)
    .reduce((sum, record) => sum + Number(record.amount ?? 0), 0);
  const weeklyLaborExpenses = workerEntryRecords
    .filter(inCurrentWeek)
    .reduce((sum, record) => sum + workerEntryTotalCost(record), 0);
  const weeklyIncome = paymentRecords
    .filter(inCurrentWeek)
    .reduce((sum, record) => sum + Number(record.amount ?? 0), 0);
  const entityTotals: Record<string, number> = {};
  const paymentMethodTotals: Record<string, number> = {};
  for (const record of expenseRecords) {
    const entity = `${record.entityName ?? record.supplierName ?? ""}`.trim();
    if (entity) {
      entityTotals[entity] = (entityTotals[entity] ?? 0) + Number(record.amount ?? 0);
    }
  }
  for (const record of paymentRecords) {
    const entity = `${record.entityName ?? record.clientName ?? ""}`.trim();
    if (entity) {
      entityTotals[entity] = (entityTotals[entity] ?? 0) + Number(record.amount ?? 0);
    }
    const method = `${record.paymentMethod ?? "unknown"}`.trim() || "unknown";
    paymentMethodTotals[method] =
      (paymentMethodTotals[method] ?? 0) + Number(record.amount ?? 0);
  }
  const recentTransactions = [
    ...recentExpenses.map((record) => ({
      id: `${record.id ?? ""}`,
      type: "expense",
      title: `${record.entityName ?? record.supplierName ?? record.category ?? ""}`,
      amount: Number(record.amount ?? 0),
      date: parseTimestamp(record.date)?.toDate().toISOString() ?? "",
    })),
    ...recentPayments.map((record) => ({
      id: `${record.id ?? ""}`,
      type: "payment",
      title: `${record.entityName ?? record.clientName ?? ""}`,
      amount: Number(record.amount ?? 0),
      date: parseTimestamp(record.date)?.toDate().toISOString() ?? "",
    })),
  ]
    .sort((a, b) => Date.parse(b.date) - Date.parse(a.date))
    .slice(0, 10);

  await writeIfChanged(
    projectMetricsRef,
    buildProjectMetricsPayload({
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
      entityTotals,
      paymentMethodTotals,
      weeklyExpenses: weeklyManualExpenses + weeklyLaborExpenses,
      weeklyIncome,
      equipmentExpenses: Number(categoryTotals.equipment ?? 0),
      recentTransactions,
      monthlyFlow,
      topWorkers,
      recentExpenses,
      recentPayments,
    }),
  );
  await writeAccountingSummaries({
    workspaceId,
    projectId,
    expenses: expenseRecords,
    payments: paymentRecords,
    workerEntries: workerEntryRecords,
  });

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

  const riskWorsened =
    compareRisk(riskLevel) > compareRisk(previousRiskLevel) ||
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
    await deleteNotificationForUsers(
      "project_risk_alert",
      projectId,
      memberIds,
    );
  }

  const expectedEndDate = parseTimestamp(project.expectedEndDate)?.toDate();
  if (expectedEndDate) {
    const daysRemaining = Math.ceil(
      (expectedEndDate.getTime() - Date.now()) / (1000 * 60 * 60 * 24),
    );
    if (`${project.status ?? "active"}` === "active" && daysRemaining <= 3) {
      const deadlineMessage =
        daysRemaining < 0
          ? `Project ${project.name ?? "project"} is past its expected end date.`
          : `Project ${project.name ?? "project"} is due in ${daysRemaining} day(s).`;
      await upsertNotificationForUsers({
        workspaceId,
        userIds: riskAlertRecipients,
        type: "project_deadline_alert",
        projectId,
        title: "Project Deadline Reminder",
        message: deadlineMessage,
      });
    } else {
      await deleteNotificationForUsers(
        "project_deadline_alert",
        projectId,
        memberIds,
      );
    }
  }
}

type ExpenseWrittenParams = { expenseId?: string };
type PaymentWrittenParams = { paymentId?: string };
type WorkerEntryWrittenParams = { entryId?: string };
type WorkerAccountingWrittenParams = { recordId?: string };

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
  await Promise.all(
    targets.map(({ workspaceId, projectId }) =>
      recomputeProjectSummary(workspaceId, projectId),
    ),
  );
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
  await Promise.all(
    targets.map(({ workspaceId, projectId }) =>
      recomputeProjectSummary(workspaceId, projectId),
    ),
  );
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
  await Promise.all(
    targets.map(({ workspaceId, projectId }) =>
      recomputeProjectSummary(workspaceId, projectId),
    ),
  );
}

export async function handleWorkerAccountingWriteRecompute(
  event: FirestoreWrittenEventLike<WorkerAccountingWrittenParams>,
): Promise<void> {
  const after = event.data?.after?.data();
  const before = event.data?.before?.data();
  if (
    before &&
    after &&
    !hasRelevantWorkerAccountingFieldsChanged(before, after)
  ) {
    return;
  }
  const targets = workerAccountingTargetsFromChange(before, after);
  if (targets.length === 0) {
    return;
  }
  await Promise.all(
    targets.map(({ workspaceId, workerId }) =>
      recomputeWorkerAccountingSummary(workspaceId, workerId),
    ),
  );
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

export const onWorkerAccountingWriteRecompute = onDocumentWritten(
  "worker_accounting_records/{recordId}",
  handleWorkerAccountingWriteRecompute,
);

type ProjectWrittenParams = { projectId?: string };

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
    await db
      .collection("project_metrics")
      .doc(projectId)
      .delete()
      .catch(() => undefined);
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
