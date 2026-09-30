export const PAYMENT_STATUSES = [
  "unpaid",
  "partial",
  "paid",
  "refunded",
  "cancelled",
] as const;

export const EXPENSE_CATEGORIES = [
  "labor",
  "worker",
  "materials",
  "equipment",
  "transport",
  "contractor",
  "storage",
  "rentals",
  "payments",
  "other",
] as const;

export function parsePaymentStatus(
  input: unknown,
  fallback: "paid" | "unpaid",
): string {
  const raw = `${input ?? fallback}`.trim().toLowerCase();
  if ((PAYMENT_STATUSES as readonly string[]).includes(raw)) {
    return raw;
  }
  return fallback;
}

export function normalizeExpenseCategory(category: string): string {
  const raw = category.trim().toLowerCase();
  if (raw === "labor") {
    return "worker";
  }
  if ((EXPENSE_CATEGORIES as readonly string[]).includes(raw)) {
    return raw;
  }
  return "other";
}

export function isAllowedExpenseCategory(category: string): boolean {
  return (EXPENSE_CATEGORIES as readonly string[]).includes(
    category.trim().toLowerCase(),
  );
}

/**
 * Cash actually received. Unpaid/refunded/cancelled contribute 0.
 * Partial uses `paidAmount` when present, otherwise the full amount
 * (legacy partial docs without a paid split). Missing status is paid.
 */
export function roundMoney(value: number): number {
  if (!Number.isFinite(value)) {
    return 0;
  }
  return Math.round(value * 100) / 100;
}

/**
 * Metrics delta when a payment is archived. Unpaid/refunded/cancelled
 * contribute 0, matching create-path cash collected.
 */
export function archivePaymentCashDelta(
  payment: Record<string, unknown>,
): number {
  const delta = roundMoney(-cashCollectedAmount(payment));
  return delta === 0 ? 0 : delta;
}

export function cashCollectedAmount(data: Record<string, unknown>): number {
  const amount = Number(data.amount ?? 0);
  if (!Number.isFinite(amount) || amount <= 0) {
    return 0;
  }
  const status = parsePaymentStatus(data.paymentStatus, "paid");
  if (
    status === "unpaid" ||
    status === "refunded" ||
    status === "cancelled"
  ) {
    return 0;
  }
  if (status === "partial") {
    const paid = Number(data.paidAmount);
    if (Number.isFinite(paid) && paid > 0) {
      return roundMoney(Math.min(paid, amount));
    }
    return roundMoney(amount);
  }
  return roundMoney(amount);
}

export function canCreateProject(role: string): boolean {
  return (
    role === "owner" ||
    role === "admin" ||
    role === "accountingApproved" ||
    role === "member"
  );
}

export function canUpdateProject(role: string): boolean {
  return canCreateProject(role);
}

export function canDeleteProjectCascade(role: string): boolean {
  return role === "owner" || role === "admin";
}

export function canMutateMoneyViaCallable(role: string): boolean {
  return role !== "entryOnly";
}
