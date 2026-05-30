# Research: Complete Accounting Scope

## Decision: Stabilize current regressions before feature expansion

**Rationale**: The verified state has three failing Flutter tests and a broad dirty worktree. Accounting work must begin from a trustworthy regression baseline so later failures point to the new scope rather than existing drift.

**Alternatives considered**:

- Continue with visible feature work first: rejected because it risks masking save, attachment, and prefill regressions.
- Disable failing tests temporarily: rejected because the spec requires preserving existing behavior and full verification.

## Decision: Keep the existing Flutter/Riverpod/Firebase architecture

**Rationale**: The app already has feature folders, repositories, providers, offline queue services, Firebase Storage upload, Cloud Functions, and PDF exporters. Extending those systems minimizes migration risk and preserves working flows.

**Alternatives considered**:

- Rebuild accounting as a separate module: rejected because the user explicitly requires working inside the existing app.
- Move all logic to backend-only aggregation immediately: rejected because some UI/offline behavior depends on local pending state.

## Decision: Use maintained summary records for normal dashboards and entity aggregation

**Rationale**: Current aggregation/dashboard risks include unbounded reads. Maintained summaries allow normal screens to load quickly and predictably as history grows.

**Alternatives considered**:

- Always calculate live from transaction collections: rejected for cost and latency on large workspaces.
- Use summaries for every report: rejected because date-scoped reports may need exact bounded recalculation for audit confidence.

## Decision: Use bounded exact recalculation for date-scoped reports

**Rationale**: Reports are user-initiated and naturally scoped by date/filter, so exact recalculation over the selected range preserves accounting accuracy without making normal screens expensive.

**Alternatives considered**:

- Only export precomputed summaries: rejected because filtered/daily/weekly reports need traceable transaction detail.
- Allow unbounded all-history exports by default: rejected for performance and cost.

## Decision: Save transactions and local attachment references offline

**Rationale**: Field users need to finish data entry without connectivity. The offline queue should preserve the transaction and attachment references with pending upload state, then upload/sync automatically after reconnecting.

**Alternatives considered**:

- Block all attachment transactions while offline: rejected by clarification.
- Save transaction only and ask users to reattach later: rejected because it loses field context and increases error risk.

## Decision: Store attachment metadata in records and files outside Firestore

**Rationale**: Metadata-only records keep Firestore documents small and searchable while file bytes remain in file storage/local pending storage until uploaded.

**Alternatives considered**:

- Base64 or binary in Firestore: rejected by product rules and scalability constraints.
- Embed images in list rows: rejected because list rows need only counts/indicators.

## Decision: Restrict financial reports, exports, balances, and attachments by role

**Rationale**: Accounting documents and balances are sensitive. Owners, admins, and accounting-approved roles should be able to view/export them; non-approved field users can still perform permitted entry workflows.

**Alternatives considered**:

- Any workspace member can view all accounting data: rejected for privacy and financial exposure.
- Creator-only visibility: rejected because owners/accountants need cross-team reconciliation.

## Decision: Offline conflicts use last-saved-change-wins

**Rationale**: The user selected automatic last-saved behavior. Implementation must preserve internal consistency and audit-relevant timestamps while avoiding manual conflict review flows.

**Alternatives considered**:

- Require manual conflict resolution: rejected by clarification.
- Keep both versions as duplicates: rejected because it risks double-counted financial records.

## Decision: Add missing accounting domains where absent

**Rationale**: The clarified scope requires contractors, equipment, workers, transport providers, and related accounting sections even if base screens or models need to be added.

**Alternatives considered**:

- Defer absent domains until later: rejected by clarification.
- Model everything as generic notes only: rejected because filtering, aggregation, and reports require typed entities.

## Decision: Preserve and extend tests around each feature slice

**Rationale**: The scope touches financial totals, offline state, permissions, file handling, and exports. Each slice needs repository/provider/widget/export tests where practical, with manual QA only for behaviors that cannot be reliably automated.

**Alternatives considered**:

- Rely on manual QA for broad UI scope: rejected because current verification already found missing coverage.
- Add only golden/widget tests: rejected because repository, provider, offline, and functions logic also need coverage.
