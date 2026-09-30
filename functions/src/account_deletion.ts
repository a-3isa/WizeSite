export const ACCOUNT_DELETION_REAUTH_SECONDS = 5 * 60;

export const WORKSPACE_SCOPED_COLLECTIONS = [
  "attachments",
  "category_summaries",
  "contractor_accounting_records",
  "drafts",
  "entities",
  "entity_summaries",
  "equipment_accounting_records",
  "expenses",
  "idempotency_keys",
  "memberships",
  "notifications",
  "payments",
  "project_metrics",
  "project_summaries",
  "projects",
  "report_exports",
  "reports",
  "transport_provider_accounting_records",
  "usage_counters",
  "weekly_summaries",
  "worker_accounting_records",
  "worker_accounting_summaries",
  "worker_entries",
  "workers",
] as const;

export function isRecentLogin(
  authTimeSeconds: unknown,
  nowSeconds = Date.now() / 1000,
): boolean {
  if (typeof authTimeSeconds !== "number" || !Number.isFinite(authTimeSeconds)) {
    return false;
  }
  return nowSeconds - authTimeSeconds <= ACCOUNT_DELETION_REAUTH_SECONDS;
}

export function ownerDeletionBlocked(otherMemberCount: number): boolean {
  return otherMemberCount > 0;
}

export function userStoragePrefixes(uid: string): string[] {
  const safe = uid.trim();
  if (!safe) {
    return [];
  }
  return [
    `attachments/${safe}/`,
    `receipts/${safe}/`,
    `voice-expenses/${safe}/`,
    `profile-photos/${safe}/`,
  ];
}
