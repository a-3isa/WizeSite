import type { FastifyInstance } from "fastify";

import type { Sql } from "../db/pool";
import { withTransaction } from "../db/tx";
import { parseTimestamp } from "../domain/accounting";
import {
  authorizationHeaderMatches,
  mapRevenueCatEvent,
  mapRevenueCatTier,
  revenueCatEventId,
} from "../domain/revenuecat_status";
import { upsertNotificationForUsers } from "../rpc/notify";

/**
 * POST /v1/webhooks/revenuecat (contracts/webhooks.md), ported from revenuecatWebhook in
 * functions/src/index.ts: constant-time secret check, dedupe on event id in webhook_events,
 * subscription upsert, then a notification to every member. `app_user_id` is the workspace id.
 *
 * One difference: subscriptions reference workspaces here, so an event for an unknown workspace
 * (e.g. an anonymous RevenueCat id) is recorded and acknowledged instead of failing and being
 * retried forever; Firestore stored a subscription doc for it.
 */
export function registerRevenueCatWebhook(app: FastifyInstance, deps: { sql: Sql; secret: string }): void {
  app.all("/v1/webhooks/revenuecat", async (request, reply) => {
    if (request.method !== "POST") {
      return reply.status(405).send({ error: "method_not_allowed" });
    }
    if (!deps.secret) {
      return reply.status(500).send({ error: "missing_server_secret" });
    }
    if (!authorizationHeaderMatches(request.headers.authorization, deps.secret)) {
      return reply.status(401).send({ error: "unauthorized" });
    }
    const body = (request.body ?? {}) as Record<string, unknown>;
    const event = ((body.event ?? body) as Record<string, unknown>) ?? {};
    const workspaceId = `${event.app_user_id ?? ""}`.trim();
    if (!workspaceId) {
      return reply.status(400).send({ error: "missing_workspace" });
    }
    const eventType = `${event.type ?? "UNKNOWN"}`;
    const periodType = `${event.period_type ?? "UNKNOWN"}`;
    const eventId = revenueCatEventId(event);

    const outcome = await withTransaction(deps.sql, async (tx) => {
      if (eventId) {
        const inserted = await tx`
          INSERT INTO webhook_events (id, type, workspace_id, payload)
          VALUES (${eventId}, ${eventType}, ${workspaceId}, ${tx.json(event as never)})
          ON CONFLICT (id) DO NOTHING
          RETURNING id`;
        if (inserted.length === 0) {
          return "duplicate" as const;
        }
      }
      const [workspace] = await tx`SELECT id FROM workspaces WHERE id = ${workspaceId}`;
      if (!workspace) {
        return "unknown_workspace" as const;
      }
      const [current] = await tx<{ status: string }[]>`
        SELECT status FROM subscriptions WHERE workspace_id = ${workspaceId} FOR UPDATE`;
      const mapped = mapRevenueCatEvent({
        eventType,
        periodType,
        currentStatus: current?.status ?? "",
        entitlements: event.entitlement_ids,
      });
      const periodEndsAt =
        (parseTimestamp(event.expiration_at_ms) ?? parseTimestamp(event.expires_date))?.toDate() ?? null;
      const trialEndsAt = periodType === "TRIAL" ? periodEndsAt : null;
      await tx`
        INSERT INTO subscriptions (workspace_id, tier, status, store, is_auto_renewing, trial_ends_at, period_ends_at,
                                   last_synced_at)
        VALUES (${workspaceId}, ${mapRevenueCatTier(event.entitlement_ids)}, ${mapped.status},
                ${`${event.store ?? "unknown"}`}, ${mapped.isAutoRenewing}, ${trialEndsAt}, ${periodEndsAt}, now())
        ON CONFLICT (workspace_id) DO UPDATE SET
          tier = EXCLUDED.tier, status = EXCLUDED.status, store = EXCLUDED.store,
          is_auto_renewing = EXCLUDED.is_auto_renewing, trial_ends_at = EXCLUDED.trial_ends_at,
          period_ends_at = EXCLUDED.period_ends_at, last_synced_at = now(), updated_at = now()`;

      // Same message as today, which maps the status without the current one.
      const tier = mapRevenueCatTier(event.entitlement_ids);
      const announced = mapRevenueCatEvent({ eventType, periodType, entitlements: event.entitlement_ids });
      const members = await tx<{ user_uid: string }[]>`
        SELECT user_uid FROM memberships WHERE workspace_id = ${workspaceId}`;
      await upsertNotificationForUsers(tx, {
        workspaceId,
        userIds: members.map((m) => m.user_uid).filter((id) => id.trim().length > 0),
        type: "subscription_status_changed",
        title: "Subscription Updated",
        message: `Subscription is now ${tier.toUpperCase()} (${announced.status})`,
      });
      return "applied" as const;
    });

    if (outcome === "duplicate") {
      return reply.status(200).send({ ok: true, duplicate: true });
    }
    if (outcome === "unknown_workspace") {
      request.log.warn({ workspaceId, eventId }, "RevenueCat event for an unknown workspace");
      return reply.status(200).send({ ok: true, ignored: "unknown_workspace" });
    }
    return reply.status(200).send({ ok: true });
  });
}
