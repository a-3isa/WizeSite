import {timingSafeEqual} from "node:crypto";

export type SubscriptionStatus =
  | "trial"
  | "active"
  | "grace"
  | "expired"
  | "canceled"
  | "unknown";

export type SubscriptionTier = "free" | "pro";

const GOOD_STATUSES: SubscriptionStatus[] = [
  "trial",
  "active",
  "grace",
  "expired",
  "canceled",
];

function asStatus(input: string | undefined): SubscriptionStatus | undefined {
  if (!input) {
    return undefined;
  }
  if (GOOD_STATUSES.includes(input as SubscriptionStatus)) {
    return input as SubscriptionStatus;
  }
  return undefined;
}

export function mapRevenueCatTier(entitlements: unknown): SubscriptionTier {
  if (!Array.isArray(entitlements)) {
    return "free";
  }
  const hasPro = entitlements.some((item) =>
    `${item}`.toLowerCase().includes("pro"),
  );
  return hasPro ? "pro" : "free";
}

export function hasProEntitlement(entitlements: unknown): boolean {
  return mapRevenueCatTier(entitlements) === "pro";
}

/**
 * Maps a RevenueCat webhook event to a subscription status.
 * CANCELLATION keeps access until EXPIRATION (`isAutoRenewing: false`).
 * Unknown events with a Pro entitlement never overwrite a good status with
 * `unknown`.
 */
export function mapRevenueCatEvent(input: {
  eventType: string;
  periodType: string;
  currentStatus?: string;
  entitlements?: unknown;
}): {status: SubscriptionStatus; isAutoRenewing: boolean} {
  const eventType = input.eventType;
  const periodType = input.periodType;
  const current = asStatus(input.currentStatus);
  const pro = hasProEntitlement(input.entitlements);

  if (eventType === "BILLING_ISSUE") {
    return {status: "grace", isAutoRenewing: true};
  }
  if (eventType === "EXPIRATION") {
    return {status: "expired", isAutoRenewing: false};
  }
  if (eventType === "CANCELLATION") {
    const status = current && current !== "expired" ? current : "active";
    return {status, isAutoRenewing: false};
  }
  if (
    eventType === "INITIAL_PURCHASE" ||
    eventType === "RENEWAL" ||
    eventType === "UNCANCELLATION"
  ) {
    const status: SubscriptionStatus =
      periodType === "TRIAL" ? "trial" : "active";
    return {status, isAutoRenewing: true};
  }
  if (pro) {
    if (current) {
      return {
        status: current,
        isAutoRenewing:
          current === "active" || current === "trial" || current === "grace",
      };
    }
    return {status: "active", isAutoRenewing: true};
  }
  return {status: current ?? "unknown", isAutoRenewing: false};
}

export function authorizationHeaderMatches(
  header: string | string[] | undefined,
  secret: string,
): boolean {
  const incoming = Array.isArray(header) ? header[0] : (header ?? "");
  const expected = `Bearer ${secret}`;
  const left = Buffer.from(incoming);
  const right = Buffer.from(expected);
  if (left.length !== right.length) {
    return false;
  }
  return timingSafeEqual(left, right);
}

export function revenueCatEventId(event: Record<string, unknown>): string {
  return `${event.id ?? event.event_id ?? ""}`.trim();
}
