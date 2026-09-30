# Contract: Sync (PowerSync, `wss://sync.<domain>`)

Read-only replication of server rows to each device's local SQLite for offline browsing (FR-006)
and live updates (FR-005). **Writes never go through sync** — they use the RPC API via the offline queue.

## Authentication

- Client passes its Firebase ID token as the PowerSync credential (`fetchCredentials` returns
  `{endpoint: 'https://sync.<domain>', token: <idToken>}`); refreshed on expiry.
- PowerSync config:
  ```yaml
  client_auth:
    jwks_uri: https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com
    audience: [wize-site]
  ```
  `token_parameters.user_id` = Firebase `uid` (`sub`).

## Buckets

> **Authoritative file: `server/powersync/sync_rules.yaml`** (verified by `server/test/sync/sync_rules.test.ts`).
> The listing below is explanatory. Implementation notes: parameter queries do not accept `IN (...)`
> lists, so the financial bucket uses one equality query per role; tables keyed by something other
> than `id` alias their key (`SELECT uid AS id, ...`) because generated columns are not replicated.
> A sync-rules version that fails to load is persisted and replayed by the service, so fix it with a
> clean redeploy.

```yaml
bucket_definitions:
  user_self:
    parameters: SELECT request.user_id() AS uid
    data:
      - SELECT * FROM user_profiles WHERE uid = bucket.uid
      - SELECT * FROM memberships WHERE user_uid = bucket.uid
      - SELECT * FROM notifications WHERE recipient_uid = bucket.uid

  # --- every workspace member (firestore.rules read condition: inWorkspace) ---
  workspace_member:
    # membership OR workspace owner (inWorkspace = hasMembership || isWorkspaceOwner)
    parameters:
      - SELECT workspace_id FROM memberships
        WHERE user_uid = request.user_id() AND status = 'active'
      - SELECT id AS workspace_id FROM workspaces WHERE owner_uid = request.user_id()
    data:
      - SELECT * FROM workspaces WHERE id = bucket.workspace_id
      - SELECT * FROM memberships WHERE workspace_id = bucket.workspace_id
      - SELECT * FROM projects WHERE workspace_id = bucket.workspace_id
      - SELECT * FROM expenses WHERE workspace_id = bucket.workspace_id
      - SELECT * FROM worker_entries WHERE workspace_id = bucket.workspace_id
      - SELECT * FROM workers WHERE workspace_id = bucket.workspace_id
      - SELECT * FROM entities WHERE workspace_id = bucket.workspace_id
      - SELECT * FROM subscriptions WHERE workspace_id = bucket.workspace_id
      - SELECT * FROM usage_counters WHERE workspace_id = bucket.workspace_id

  # --- financial roles only (firestore.rules read condition: canAccessAccounting) ---
  workspace_financial:
    # canAccessAccounting = isWorkspaceOwner || role in [owner, admin, accountingApproved]
    parameters:
      - SELECT workspace_id FROM memberships
        WHERE user_uid = request.user_id() AND status = 'active'
          AND role IN ('owner', 'admin', 'accountingApproved')
      - SELECT id AS workspace_id FROM workspaces WHERE owner_uid = request.user_id()
    data:
      - SELECT * FROM payments WHERE workspace_id = bucket.workspace_id
      - SELECT * FROM attachments WHERE workspace_id = bucket.workspace_id
      - SELECT * FROM worker_accounting_records WHERE workspace_id = bucket.workspace_id
      - SELECT * FROM contractor_accounting_records WHERE workspace_id = bucket.workspace_id
      - SELECT * FROM equipment_accounting_records WHERE workspace_id = bucket.workspace_id
      - SELECT * FROM transport_provider_accounting_records WHERE workspace_id = bucket.workspace_id
      - SELECT * FROM project_metrics WHERE workspace_id = bucket.workspace_id
      - SELECT * FROM workspace_metrics WHERE workspace_id = bucket.workspace_id
      - SELECT * FROM project_summaries WHERE workspace_id = bucket.workspace_id
      - SELECT * FROM weekly_summaries WHERE workspace_id = bucket.workspace_id
      - SELECT * FROM entity_summaries WHERE workspace_id = bucket.workspace_id
      - SELECT * FROM category_summaries WHERE workspace_id = bucket.workspace_id
      - SELECT * FROM worker_accounting_summaries WHERE workspace_id = bucket.workspace_id
      - SELECT * FROM reports WHERE workspace_id = bucket.workspace_id
      - SELECT * FROM report_exports WHERE workspace_id = bucket.workspace_id
```

Not synced (server-only, `allow read: if false` today): `idempotency_keys`, `webhook_events`,
`drafts`, `deleted_rows`.

Note: if a synced PowerSync release does not accept multiple parameter queries per bucket, use two
buckets per tier (`*_by_membership`, `*_by_ownership`) with identical data queries; rows are
de-duplicated on the device.

## Role-restricted financial data (Constitution IV)

The split above is copied table by table from the read conditions in `firestore.rules`
(`inWorkspace` → `workspace_member`; `canAccessAccounting` → `workspace_financial`). `attachments` is
financial because its rule uses `canAccessAccounting`. File downloads apply the same check server-side
in `getAttachmentDownloadUrl`. Sync-rule tests verify that a device whose role is not in
(`owner`, `admin`, `accountingApproved`) and who does not own the workspace receives zero rows from
any `workspace_financial` table.

## Guarantees tested

1. A user never receives rows of a workspace they are not an active member of.
2. Removing a membership removes that workspace's rows from the device on next sync.
3. Change committed by the API is visible on another member's device in ≤ 5 s (p95, SC-006).
4. Deletes (cascade, account deletion) propagate.
