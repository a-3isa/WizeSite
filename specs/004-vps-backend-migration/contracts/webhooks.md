# Contract: RevenueCat Webhook

```
POST https://api.<domain>/v1/webhooks/revenuecat
Authorization: <REVENUECAT_WEBHOOK_SECRET>
Content-Type: application/json
```

Behavior is ported unchanged from `revenuecatWebhook` in `functions/src/index.ts` and
`functions/src/revenuecat_status.ts`:

| Case | Response |
|---|---|
| Method ≠ POST | `405 {"error":"method_not_allowed"}` |
| Secret not configured | `500 {"error":"missing_server_secret"}` |
| Authorization mismatch (constant-time compare) | `401 {"error":"unauthorized"}` |
| Event already in `webhook_events` | `200` (no-op, dedupe) |
| Valid event | apply entitlement → `subscriptions`, adjust `usage_counters` limits, record event; `200` |

`app_user_id` = workspace id (unchanged).

**Cutover step**: change the webhook URL in the RevenueCat dashboard from the Cloud Functions URL to the
URL above during the maintenance window. Events that arrived at the old endpoint before it was disabled are
included in the final migration via `webhook_events`/`subscriptions`; RevenueCat retries failed deliveries,
so events sent during the switch land on whichever endpoint is live and are deduped by `event_id`.
