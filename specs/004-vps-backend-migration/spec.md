# Feature Specification: Migrate Backend from Firebase to Self-Hosted VPS

**Feature Branch**: `004-vps-backend-migration`

**Created**: 2026-09-30

**Status**: Draft

**Input**: User description: "i want to migrate the backend from firebase to my vps"

## Context

WizeSite currently depends on a managed cloud platform (Firebase) for every backend concern:
user sign-in (email/password and Google), the primary database, file attachments (receipts,
photos, voice notes), all server-side business rules (quota-enforced creation of projects,
expenses, payments and worker entries; archiving with quota refunds; project cascade delete;
workspace bootstrap and switching; account deletion), automatic recomputation of project
metrics and accounting summaries whenever financial records change, the voice-to-expense
pipeline, the subscription-status webhook from the in-app purchase provider, remote
configuration flags, device-integrity checks, and crash reporting.

The owner wants to run the data-holding and business-logic parts of this backend on their own
virtual private server (VPS) instead, to gain control over cost, data location and vendor
dependence. Sign-in and crash reporting stay on Firebase. Users of the mobile app should not
notice the change except, at most, a single planned transition.

## Clarifications

### Session 2026-09-30

- Q: What capacity does the target VPS have? → A: 4 GB RAM, 2 vCPU
- Q: Which responsibilities move off Firebase? → A: Database, attachment files and server logic
  move to the VPS; Firebase sign-in and crash reporting stay (revised from the earlier "move
  everything" answer). Remote configuration and device-integrity checks also stay on Firebase,
  since the Firebase project remains active for sign-in.
- Q: How much recent data may be lost if the VPS fails permanently? → A: At most 15 minutes
  (continuous off-server backup plus a daily full backup)
- Q: How long is Firebase's data kept as a rollback fallback after cutover? → A: 7 days
  read-only, then deleted
- Q: How does the app address the VPS? → A: A subdomain of a domain the owner already owns
- Q: What must work offline? → A: Full parity with today — browse all workspace data and record
  new entries offline, syncing on reconnect

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Existing users keep working without losing anything (Priority: P1)

A site manager who has used WizeSite for months opens the app after the migration. They are
still signed in with the same account, and every project, expense, payment,
worker, worker entry, attachment, workspace membership and setting they had before is present
and identical. Totals, balances and project risk indicators show the same values as before.

**Why this priority**: The app stores financial records. Any loss, duplication or silent change
of a figure destroys trust and may have real monetary consequences. Nothing else matters if this
fails.

**Independent Test**: Take a snapshot of a set of real accounts' figures before migration
(record counts per type, per-project totals, balances, attachment counts), perform migration,
sign in as those users on the new backend, and compare. Can be run against a staging copy
without affecting production.

**Acceptance Scenarios**:

1. **Given** a user with data on the old backend, **When** they open the app after migration,
   **Then** they are still signed in with the same account (no re-login or password reset) and
   land in the same workspace with the same role, seeing all their records.
2. **Given** a project with expenses, payments and worker entries, **When** it is viewed after
   migration, **Then** every per-project total, balance and risk indicator equals the
   pre-migration value to the smallest currency unit.
3. **Given** an expense with an attached receipt image, **When** the user opens the attachment
   after migration, **Then** the same file opens.
4. **Given** a user who has an active paid subscription, **When** they open the app after
   migration, **Then** their paid entitlements and quota limits are unchanged.

---

### User Story 2 - Day-to-day recording works exactly as before (Priority: P1)

A foreman on a site with weak signal records an expense with a photo and a voice note, adds a
worker entry, and archives a mistaken payment. Some of this happens offline. When signal
returns, everything syncs once, quotas are enforced, project totals update automatically, and
other members of the same workspace see the changes without having to restart the app.

**Why this priority**: This is the core daily loop of the product. Parity with current behaviour
(offline capture, idempotent sync, quota enforcement, automatic recalculation, live updates for
teammates) is mandatory.

**Independent Test**: Run the existing end-to-end recording scenarios (create/edit/archive each
record type, offline then reconnect, two devices in the same workspace) against the new backend
and verify identical outcomes to the current backend.

**Acceptance Scenarios**:

1. **Given** a device offline, **When** the user creates an expense with an attachment and later
   reconnects, **Then** exactly one expense and one attachment exist on the server.
2. **Given** a free-tier user at their quota limit, **When** they attempt to create another
   record, **Then** the server rejects it with the same user-facing message as today.
3. **Given** two members viewing the same project, **When** one adds a payment, **Then** the
   other sees the updated project balance within a few seconds without manual refresh.
4. **Given** an archived expense, **When** it is archived, **Then** the quota is refunded and
   project totals are recomputed.
5. **Given** a recorded voice note, **When** it is submitted, **Then** a draft expense is extracted
   and matched to a project as it is today.

---

### User Story 3 - Owner can operate the backend on their own server (Priority: P2)

The owner (acting as operator) can deploy, update, back up, restore and monitor the backend on
their VPS without needing Firebase's database, storage or functions consoles. They are alerted when the service is down or
errors spike, and they can restore data from a backup if the server fails.

**Why this priority**: Moving off a managed platform transfers operational responsibility to the
owner. Without backups, monitoring and a repeatable deployment, a single server failure could
lose all customer data.

**Independent Test**: On a fresh server, perform a documented deployment from scratch, run a
backup, destroy the data, restore from backup, and confirm the app works with restored data.

**Acceptance Scenarios**:

1. **Given** a fresh server, **When** the operator follows the deployment procedure, **Then** a
   working backend is running and reachable by the app over an encrypted connection.
2. **Given** a running backend, **When** a scheduled backup runs, **Then** a restorable copy of the
   database and all attachments is stored off the server.
3. **Given** the backend becomes unreachable, **When** the outage exceeds a short threshold,
   **Then** the operator is notified.
4. **Given** a new backend version, **When** the operator deploys it, **Then** the app keeps working
   during the update or experiences at most a brief, recoverable interruption.

---

### User Story 4 - Firebase data services are decommissioned (Priority: P3)

Seven days after cutover (the rollback window, FR-016), the owner turns off Firebase's database, file storage
and server functions. The Firebase project stays active only for sign-in, crash reporting, remote
configuration and device-integrity checks, and no business data or attachments remain in it.

**Why this priority**: Realises the cost and independence goals, but only safe after P1–P3 are
proven.

**Independent Test**: Disable Firebase's database, file storage and server functions in a staging
environment and verify every app flow still works.

**Acceptance Scenarios**:

1. **Given** Firebase's database, storage and functions are disabled, **When** any app feature is
   used, **Then** it works normally.
2. **Given** decommissioning is complete, **When** the Firebase database and storage are inspected,
   **Then** they hold no business records or attachments.

### Edge Cases

- A user still has un-synced offline actions queued on the old app version when the switch
  happens (mitigated by syncing before cutover; must be detectable, not silently dropped).
- A user is mid-upload of an attachment during the cutover window.
- The in-app purchase provider sends a subscription event while the backend is switching.
- A sign-in identity exists but has no matching data on the new backend (e.g. a brand-new sign-up
  after cutover) — the workspace must be bootstrapped as today.
- A user requested account deletion shortly before migration — their data must not reappear.
- Duplicate or conflicting records arise if both backends accept writes during a transition.
- The VPS disk fills up, or the server reboots unexpectedly.
- Attachments whose files are missing or corrupt in the source.
- Clock or time-zone differences affecting record timestamps and ordering.
- Arabic / right-to-left text and non-ASCII file names survive the data transfer unchanged.
- The app is opened for the first time after cutover with no connection — it has no local copy of
  the new backend's data yet and must show a clear "connect to load your data" state rather than
  an empty workspace.

## Requirements *(mandatory)*

### Functional Requirements

**Scope & parity**

- **FR-001**: The new backend MUST take over the database, attachment storage, and all server-side
  business logic including automatic recalculation, the voice pipeline and the subscription
  webhook. Sign-in (email/password and Google), crash reporting, remote configuration and
  device-integrity checks MUST remain on Firebase unchanged. After migration the app MUST have no
  runtime dependency on Firebase's database, file storage or server functions.
- **FR-002**: Every server-side business rule that exists today MUST behave identically on the new
  backend: quota enforcement on create, quota refund on archive, project cascade delete, workspace
  bootstrap/switch/initial setup, profile and settings updates, worker management, account deletion,
  attachment access, and the voice-to-expense pipeline.
- **FR-003**: Derived figures (project metrics, accounting summaries, worker accounting summaries,
  risk classification) MUST be recomputed automatically whenever the underlying records change,
  producing the same values as today.
- **FR-004**: The system MUST enforce the same access rules as today: users can only read or change
  data in workspaces they belong to, according to their role, and financial figures remain hidden
  from roles that cannot see them today.
- **FR-005**: The system MUST deliver changes to other signed-in members of a workspace in near
  real time, as today.
- **FR-006**: The app MUST keep a local copy of the user's active workspace data so that all
  projects, records, totals and previously opened attachments can be browsed with no connection,
  as today. Records created, edited or archived offline MUST sync once on reconnect via an
  idempotent process; a retried request MUST never create a duplicate record. After reconnect the
  local copy MUST converge to the server state.
- **FR-007**: The system MUST receive and process subscription status events from the in-app
  purchase provider and apply entitlement and quota changes as today.
- **FR-008**: Remotely changeable feature flags/configuration MUST keep working exactly as today
  (they remain on Firebase).
- **FR-009**: The new backend MUST accept only requests carrying a valid Firebase sign-in
  credential and a valid device-integrity token, giving at least the same protection as today, and
  MUST identify the user by their existing Firebase user identity.

**Data migration**

- **FR-010**: User accounts are not migrated; they stay in Firebase sign-in. Every migrated record
  MUST remain linked to the same user identity it has today. The app is live with real financial
  data; the current user base is two accounts (the owner and one other user), and all of their
  data MUST be migrated.
- **FR-011**: All existing records and attachments MUST be migrated with no loss, no duplication and
  no change in value, including Arabic text and non-ASCII file names.
- **FR-012**: Migration MUST produce a verification report comparing source and destination (counts
  per record type, per-project totals, attachment counts and checksums) and MUST flag any mismatch.
- **FR-013**: Migration MUST be repeatable against a staging copy before running on production.
- **FR-014**: Data belonging to users whose accounts were deleted before migration MUST NOT be
  migrated. Account deletion after migration MUST remove the user's sign-in identity on Firebase and
  all of their data and attachments on the new backend.

**Cutover**

- **FR-015**: The switch MUST be a single coordinated cutover: both users sync any pending offline
  actions, the old backend stops accepting writes, final data is migrated and verified, and both
  users install the new app version. No write accepted by the old backend may be lost. Running both
  backends in parallel and supporting old app versions are out of scope.
- **FR-016**: Firebase's database and attachments MUST be kept read-only for 7 days after cutover
  as a rollback fallback, then deleted. A documented rollback procedure MUST exist for use within
  that window, and it MUST carry back any records written to the new backend since cutover so no
  data is lost by rolling back.
- **FR-017**: After cutover the old backend MUST reject writes, so a stray old app install cannot
  silently record data that never reaches the new backend.

**Operations**

- **FR-018**: All traffic between app and backend MUST be encrypted with a publicly trusted,
  automatically renewed certificate. The app MUST reach the backend through a subdomain of the
  owner's existing domain, never a raw IP address, so the server can be moved by changing DNS
  without an app release.
- **FR-019**: Database changes MUST be copied continuously to a location separate from the VPS so
  that no more than 15 minutes of accepted writes can be lost on permanent server failure.
  Attachments MUST be copied off-server within the same 15-minute window. A full backup of
  database and attachments MUST also run daily. Backups MUST be retained for at least 30 days and
  allow restoring to any point within that period.
- **FR-020**: A documented restore procedure MUST exist and MUST be tested before cutover.
- **FR-021**: The operator MUST be notified of downtime, high error rates and low disk space.
- **FR-022**: Deployment of new backend versions MUST be repeatable from the repository without
  manual server edits.
- **FR-023**: App crash reporting stays on the existing Firebase service; the new backend MUST
  additionally record its own server errors in logs the operator can inspect.
- **FR-024**: Secrets (third-party API keys, signing keys, webhook secrets) MUST NOT be stored in
  the repository or the app bundle.

### Key Entities

- **User account**: identity and sign-in methods (password, Google) remain on Firebase; profile,
  settings and active workspace move to the new backend, keyed by the existing user identity.
- **Workspace & membership**: a team space with members and roles controlling visibility and
  permissions.
- **Project**: name, optional contract value, budget limit, status, archived flag; parent of
  financial records.
- **Expense / Payment / Worker entry**: dated financial records attached to a project, may carry
  attachments, may be archived.
- **Worker**: a person paid through worker entries; has an accounting summary.
- **Attachment**: a stored file (image, document, audio) linked to a record.
- **Derived summaries**: project metrics, accounting summaries, worker accounting summaries,
  workspace metrics — computed from the records above.
- **Subscription & quota**: a user's entitlement level and remaining allowance of records.
- **Idempotency record**: marker ensuring a retried request is applied once.
- **Remote configuration**: flags and values the owner can change without an app release (stays
  on Firebase).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of migrated records match the source in count and value; 100% of attachments
  match by checksum; zero unresolved mismatches in the verification report.
- **SC-002**: 100% of existing users remain signed in after migration with no re-login, password
  reset or re-registration.
- **SC-003**: Every existing automated backend and app test suite is either ported to the new
  backend or replaced by equivalent coverage (API authorization tests and sync-rule tests for the
  old security-rules tests; recorded parity golden files for the old server-function tests), and
  all of them pass.
- **SC-004**: Planned user-facing downtime for the cutover is under 1 hour, announced in advance.
- **SC-005**: 95% of user actions (open project, save record) complete in under 2 seconds on a
  normal mobile connection — no slower than today.
- **SC-006**: Teammates see another member's change within 5 seconds in 95% of cases.
- **SC-007**: Monthly backend running cost is lower than the current cloud bill at today's usage.
- **SC-008**: A full restore from backup to a fresh server completes in under 4 hours and loses no
  more than the last 15 minutes of accepted writes.
- **SC-009**: Backend availability of at least 99.5% per month after cutover.
- **SC-010**: Zero user-reported data-loss incidents in the 30 days after cutover.

## Assumptions

- The app has exactly two installs (owner and one friend); both will be updated manually at
  cutover, so no forced-update mechanism, store staged rollout or backward compatibility is needed.
- "My VPS" is a single Linux virtual server with 4 GB RAM and 2 vCPU; all backend components
  (including backup and monitoring agents) must fit within this capacity. It is a single server the owner already controls; high-availability
  multi-server setups are out of scope for this feature, compensated by backups and a tested
  restore procedure.
- The owner acts as the operator and accepts responsibility for server updates and security
  patching.
- The Flutter app will be updated to talk to the new backend; a new app release is part of this
  feature.
- The in-app purchase provider and the speech/LLM services used by the voice pipeline remain the
  same third-party providers; only the component that calls them moves.
- Current role model, quotas, localization (English/Arabic) and offline behaviour are kept as-is;
  no new product features are added in this migration.
- Data residency follows the VPS location chosen by the owner; no specific compliance regime
  (e.g. GDPR certification) is required beyond current practice.
- Existing automated tests (functions tests, rules tests, Flutter tests) are the parity baseline.
  They are ported where possible; tests tied to removed Firebase services are replaced by
  equivalent coverage before they are deleted, never dropped without a replacement.
