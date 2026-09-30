import {
  buildAccountingSummaryPayloads,
  buildProjectMetricsPayload,
  classifyProjectRisk,
  parseTimestamp,
  workerEntryTotalCost,
  type MonthlyFlowPoint,
  type TriggerDocData,
} from "../domain/accounting";
import { cashCollectedAmount, normalizeExpenseCategory } from "../domain/money";

export interface ProjectDerivedInput {
  workspaceId: string;
  projectId: string;
  project: TriggerDocData;
  /** Non-archived records of the project, as Firestore-shaped documents (see rowToDoc). */
  expenses: TriggerDocData[];
  payments: TriggerDocData[];
  workerEntries: TriggerDocData[];
  /** workerId → display name (workerNameMapForEntries in functions). */
  workerNames: Map<string, string>;
  now: Date;
}

/**
 * Pure port of the computation in `recomputeProjectSummary` (functions/src/index.ts),
 * without I/O and without the notification side effects (those run in the mutating RPCs).
 * Snapshot iteration is replaced by document arrays; the arithmetic is unchanged.
 */
export function computeProjectDerived(input: ProjectDerivedInput) {
  const { workspaceId, projectId, project } = input;
  const contractValue =
    project.contractValue === null || project.contractValue === undefined
      ? null
      : Number(project.contractValue) || null;
  const completionPercentage = Math.max(0, Number(project.completionPercentage ?? 0));
  const budgetLimit = Number(project.budgetLimit ?? 0) || null;

  const manualExpenses = input.expenses.reduce((sum, doc) => sum + Number(doc.amount ?? 0), 0);
  const laborExpenses = input.workerEntries.reduce(
    (sum, doc) => sum + workerEntryTotalCost(doc),
    0,
  );
  const totalExpenses = manualExpenses + laborExpenses;
  const totalPayments = input.payments.reduce((sum, doc) => sum + cashCollectedAmount(doc), 0);
  const netProfit = totalPayments - totalExpenses;
  // Contract-derived: meaningless without a contract to invoice against.
  const remainingBalance = contractValue === null ? null : contractValue - totalPayments;
  const expectedFinalCost =
    completionPercentage > 0 ? totalExpenses / (completionPercentage / 100) : totalExpenses;

  const { riskLevel, healthStatus } = classifyProjectRisk({
    contractValue,
    netProfit,
    expectedFinalCost,
  });
  const budgetExceeded = budgetLimit != null && totalExpenses > budgetLimit;

  const categoryTotals = input.expenses.reduce<Record<string, number>>((map, doc) => {
    const category = normalizeExpenseCategory(`${doc.category ?? "other"}`);
    map[category] = (map[category] ?? 0) + Number(doc.amount ?? 0);
    return map;
  }, {});
  if (laborExpenses > 0) {
    categoryTotals.worker = (categoryTotals.worker ?? 0) + laborExpenses;
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
  for (const doc of input.expenses) {
    const date = parseTimestamp(doc.date)?.toDate();
    if (date) pointFor(date).expenses += Number(doc.amount ?? 0);
  }
  for (const doc of input.workerEntries) {
    const date = parseTimestamp(doc.date)?.toDate();
    if (date) pointFor(date).expenses += workerEntryTotalCost(doc);
  }
  for (const doc of input.payments) {
    const date = parseTimestamp(doc.date)?.toDate();
    if (date) pointFor(date).income += cashCollectedAmount(doc);
  }
  const monthlyFlow = Array.from(monthlyMap.values()).sort((a, b) =>
    a.month.localeCompare(b.month),
  );

  const workerCosts = input.workerEntries.reduce<
    Record<string, { name: string; totalCost: number; totalDays: number }>
  >((map, doc) => {
    const workerId = `${doc.workerId ?? ""}`;
    const current = map[workerId] ?? {
      name: input.workerNames.get(workerId) ?? workerId,
      totalCost: 0,
      totalDays: 0,
    };
    current.totalCost += workerEntryTotalCost(doc);
    current.totalDays += Number(doc.daysWorked ?? 0);
    map[workerId] = current;
    return map;
  }, {});
  const topWorkers = Object.entries(workerCosts)
    .map(([workerId, data]) => ({ workerId, ...data }))
    .sort((a, b) => b.totalCost - a.totalCost)
    .slice(0, 5);

  const byDateDesc = (a: TriggerDocData, b: TriggerDocData) =>
    (parseTimestamp(b.date)?.toMillis() ?? 0) - (parseTimestamp(a.date)?.toMillis() ?? 0);
  const recentExpenses = [...input.expenses].sort(byDateDesc).slice(0, 5);
  const recentPayments = [...input.payments].sort(byDateDesc).slice(0, 5);

  const weekStart = new Date(input.now);
  weekStart.setUTCHours(0, 0, 0, 0);
  weekStart.setUTCDate(weekStart.getUTCDate() - 6);
  const inCurrentWeek = (record: TriggerDocData): boolean => {
    const date = parseTimestamp(record.date)?.toDate();
    return date != null && date >= weekStart;
  };
  const weeklyManualExpenses = input.expenses
    .filter(inCurrentWeek)
    .reduce((sum, record) => sum + Number(record.amount ?? 0), 0);
  const weeklyLaborExpenses = input.workerEntries
    .filter(inCurrentWeek)
    .reduce((sum, record) => sum + workerEntryTotalCost(record), 0);
  const weeklyIncome = input.payments
    .filter(inCurrentWeek)
    .reduce((sum, record) => sum + cashCollectedAmount(record), 0);

  const entityTotals: Record<string, number> = {};
  const paymentMethodTotals: Record<string, number> = {};
  for (const record of input.expenses) {
    const entity = `${record.entityName ?? record.supplierName ?? ""}`.trim();
    if (entity) {
      entityTotals[entity] = (entityTotals[entity] ?? 0) + Number(record.amount ?? 0);
    }
  }
  for (const record of input.payments) {
    const entity = `${record.entityName ?? record.clientName ?? ""}`.trim();
    if (entity) {
      entityTotals[entity] = (entityTotals[entity] ?? 0) + cashCollectedAmount(record);
    }
    const method = `${record.paymentMethod ?? "unknown"}`.trim() || "unknown";
    paymentMethodTotals[method] = (paymentMethodTotals[method] ?? 0) + cashCollectedAmount(record);
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

  const projectMetrics = buildProjectMetricsPayload({
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
  });

  const summaries = buildAccountingSummaryPayloads({
    workspaceId,
    projectId,
    expenses: input.expenses,
    payments: input.payments,
    workerEntries: input.workerEntries,
    now: input.now,
  });

  return { projectMetrics, summaries, riskLevel, healthStatus, budgetExceeded };
}
