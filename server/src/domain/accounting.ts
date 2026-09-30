/**
 * Pure accounting logic ported verbatim from functions/src/index.ts (tasks.md T014).
 * Keep behaviour identical: parity with the Cloud Functions implementation is tested.
 */
import {Timestamp} from "firebase-admin/firestore";
import {RpcError as HttpsError} from "./errors";
import {cashCollectedAmount} from "./money";

export function parseTimestamp(input: unknown): Timestamp | null {
  if (input == null) {
    return null;
  }
  if (input instanceof Timestamp) {
    return input;
  }
  if (input instanceof Date) {
    return Timestamp.fromDate(input);
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
        return Timestamp.fromDate(converted);
      }
    }

    const seconds = Number(candidate.seconds ?? candidate._seconds);
    const nanoseconds = Number(
      candidate.nanoseconds ?? candidate._nanoseconds ?? 0,
    );
    if (Number.isFinite(seconds) && Number.isFinite(nanoseconds)) {
      return new Timestamp(seconds, nanoseconds);
    }
  }
  if (typeof input === "string") {
    const parsed = Date.parse(input);
    if (Number.isNaN(parsed)) {
      return null;
    }
    return Timestamp.fromMillis(parsed);
  }
  if (typeof input === "number") {
    return Timestamp.fromMillis(input);
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

export interface ProjectRiskVerdict {
  riskLevel: string | null;
  healthStatus: string | null;
}

/**
 * Classifies a project's financial risk.
 *
 * Returns a null verdict when there is no contract amount to measure against.
 * BOTH rules are skipped in that case, not just the contract comparison:
 * `netProfit < 0` holds for any expense-only project, so suppressing one rule
 * alone would flag every such project as "losing" on its very first expense.
 *
 * Exported so the rule can be unit-tested without a Firestore emulator — it is
 * the highest-consequence branch in this file, since a wrong verdict pushes a
 * notification to every member with risk alerts enabled.
 */
export function classifyProjectRisk(input: {
  contractValue: number | null;
  netProfit: number;
  expectedFinalCost: number;
}): ProjectRiskVerdict {
  const { contractValue, netProfit, expectedFinalCost } = input;
  if (contractValue === null) {
    return { riskLevel: null, healthStatus: null };
  }
  if (netProfit < 0 || expectedFinalCost > contractValue) {
    return { riskLevel: "high", healthStatus: "losing" };
  }
  if (expectedFinalCost >= contractValue * 0.9) {
    return { riskLevel: "medium", healthStatus: "warning" };
  }
  return { riskLevel: "low", healthStatus: "healthy" };
}

export type TriggerDocData = Record<string, unknown>;

function isRecord(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === "object" && !Array.isArray(value);
}

function asComparable(value: unknown): unknown {
  if (value instanceof Timestamp) {
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

export function compareRisk(current: string): number {
  switch (current) {
    case "high":
      return 3;
    case "medium":
      return 2;
    default:
      return 1;
  }
}

export type MonthlyFlowPoint = {
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
      (sum, payment) => sum + cashCollectedAmount(payment),
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
      weekStart: Timestamp.fromDate(start),
      weekEnd: Timestamp.fromDate(endOfUtcWeek(start)),
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
      latestTransactionDate: Timestamp.fromMillis(0),
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
      latestTransactionDate: Timestamp.fromMillis(0),
    };
    categoryMap.set(key, summary);
    return summary;
  };

  const rememberLatest = (summary: AccountingSummaryRecord, date: Date): void => {
    const current =
      parseTimestamp(summary.latestTransactionDate)?.toMillis() ?? 0;
    if (date.getTime() > current) {
      summary.latestTransactionDate = Timestamp.fromDate(date);
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
    const amount = cashCollectedAmount(payment);
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

export function buildProjectMetricsPayload(input: {
  workspaceId: string;
  projectId: string;
  project: TriggerDocData;
  contractValue: number | null;
  completionPercentage: number;
  budgetLimit: number | null;
  budgetExceeded: boolean;
  totalExpenses: number;
  laborExpenses: number;
  totalPayments: number;
  netProfit: number;
  remainingBalance: number | null;
  expectedFinalCost: number;
  riskLevel: string | null;
  healthStatus: string | null;
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
