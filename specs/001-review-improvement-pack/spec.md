# Feature Specification: Buildozer Review Improvement Pack

**Feature Branch**: `001-review-improvement-pack`

**Created**: 2026-06-15

**Status**: Draft

**Input**: User description: "Translate the attached Buildozer project review into a prioritized product improvement specification covering navigation, dashboard, voice expense, expenses and payments, projects, reports, subscription, settings, authentication, offline sync, entity management, code quality, performance, accessibility, and internationalization."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Reach Core Actions Faster (Priority: P1)

As an active workspace member, I want the app's primary destinations and high-frequency actions to stay easy to find so I can move from opening the app to taking action without hunting through multiple screens.

**Why this priority**: Discoverability and navigation friction affect nearly every session. Improving access to core destinations, quick actions, notifications, and empty-state calls to action creates value for all user types immediately.

**Independent Test**: Can be fully tested by opening the app from a signed-in state, navigating between primary destinations, opening key actions, and confirming that no essential workflow is hidden behind unrelated screens.

**Acceptance Scenarios**:

1. **Given** a signed-in user on the main shell, **When** they look for Home, Add, Reports, and Projects, **Then** each destination is visibly reachable from the primary navigation without requiring a workaround.
2. **Given** a signed-in user with unread notifications, **When** they view the main shell, **Then** they can reach notifications from a clearly visible entry point and can tell that unread items exist.
3. **Given** a user opens the home experience, **When** the screen loads, **Then** high-frequency actions appear before lower-priority summaries and the user can refresh the page explicitly.
4. **Given** a list or chart has no available data, **When** the user reaches that state, **Then** the app explains what is missing and offers the most relevant next action instead of showing a blank or confusing surface.
5. **Given** a home summary cannot identify a meaningful top category or top entity, **When** the user views that summary, **Then** the app explains the state in plain language instead of exposing an unexplained fallback label.
6. **Given** a user is eligible to upgrade, **When** they review the home experience, **Then** the upgrade path is discoverable without requiring them to scroll through multiple unrelated summary sections first.
7. **Given** dashboard or report content is still loading, **When** the user opens the screen, **Then** they see visible placeholders that indicate content is loading instead of unexplained blank space.
8. **Given** a signed-in user without accounting access opens Home or Projects, **When** restricted financial summaries or financial sort options would normally appear, **Then** the app keeps navigation and non-financial actions available while replacing the restricted financial content with a friendly denied state.

---

### User Story 2 - Capture and Manage Financial Activity Confidently (Priority: P2)

As a construction operator or accountant, I want expense, payment, and voice-entry workflows to give me clear feedback and preserve context so I can record transactions accurately and recover easily from mistakes.

**Why this priority**: Financial capture is the app's core operational job. Improvements here reduce data-entry friction, prevent context loss, and improve trust in day-to-day accounting work.

**Independent Test**: Can be fully tested by creating voice-based drafts, reviewing recordings, applying transaction filters, clearing individual filters, exporting results, and moving between project-scoped payment flows.

**Acceptance Scenarios**:

1. **Given** a user starts a voice-based expense capture, **When** they are recording, **Then** they can see that recording is in progress, understand how much time remains, and review the audio before submission.
2. **Given** a user has a preferred currency, **When** they create a voice-based draft, **Then** the draft uses that preference by default instead of forcing a generic fallback value.
3. **Given** a user is viewing expenses or payments with multiple filters applied, **When** they remove one filter, **Then** only that filter is cleared and the other active filters remain in place.
4. **Given** a user entered a payment from a project-specific workflow, **When** they open payment detail or edit that payment, **Then** returning from those screens keeps them inside the project-specific payment flow.
5. **Given** a user exports a transaction list or report artifact, **When** the export completes, **Then** they can keep, share, or print the exported document through a user-facing save/share path.
6. **Given** a user needs to clean up several expenses or payments at once, **When** they select multiple matching records, **Then** they can apply a supported bulk action with a confirmation step before records are changed.
7. **Given** a user is recording a voice expense, **When** they speak into the microphone, **Then** they receive live visual feedback that the app is capturing audio rather than only a static recording control.
8. **Given** a user opens transaction filtering on a small screen, **When** they adjust common filters, **Then** the filtering experience remains manageable without excessive scrolling or hidden primary controls.

---

### User Story 3 - Understand Projects, Reports, and Operational Health (Priority: P3)

As an owner, manager, or accountant, I want project, report, and entity views to be scoped, understandable, and actionable so I can monitor performance without misreading incomplete or misleading data.

**Why this priority**: Decision-making depends on trusted summaries. Users need scoped reporting, understandable charts, project summaries, and cross-project entity visibility to act on the data confidently.

**Independent Test**: Can be fully tested by filtering projects, opening reports for a selected project and date range, generating custom report exports, and reviewing worker or vendor information across projects.

**Acceptance Scenarios**:

1. **Given** a user is reviewing projects, **When** they filter by status or change the sort/view controls, **Then** the list updates to reflect the selected project subset and the requested ordering across the complete matching result set, not only the currently loaded page.
2. **Given** a user opens reports for a selected project, **When** they choose a date range, **Then** charts, tables, and exports reflect that project and that period consistently.
3. **Given** a user requests a custom export, **When** the export is generated, **Then** it includes only the selected project's data for the chosen time window and excludes unrelated projects.
4. **Given** a user opens the top-level Add destination, **When** they need an organization-wide resource view, **Then** a visible Resources section lets them browse workers, contractors, equipment, and transport records across projects.
5. **Given** a chart or summary has no meaningful data for the chosen period, **When** the user views it, **Then** the app explains the empty state instead of rendering an unlabeled or ambiguous visualization.
6. **Given** a workspace contains many projects or records, **When** a user changes project scope, report scope, or export scope, **Then** the app remains understandable by either responding promptly or clearly showing that work is still in progress.
7. **Given** a user switches between supported languages, **When** financial amounts and counts are shown, **Then** the values remain readable, appropriately localized, and free of ambiguous formatting.
8. **Given** a workspace contains many active projects, **When** a user browses or filters the project list, **Then** the list remains understandable and responsive instead of behaving like an unbounded live feed.
9. **Given** a user wants to share one report visualization instead of a full report package, **When** they act from an individual chart, **Then** the app provides a direct way to export or share that single visualization.
10. **Given** a user needs to report on older or archived work, **When** they choose a project for reporting, **Then** the selector includes the relevant historical projects instead of only the currently active subset.
11. **Given** worker accounting contains paid, unpaid, or partial records, **When** the user views its summary, **Then** total cost, confirmed paid amount, and confirmed remaining balance follow explicit payment rules and any unresolved legacy partial records are identified instead of estimated.
12. **Given** an accounting user creates or updates a domain accounting record, **When** the save is in progress or fails recoverably, **Then** the screen shows visible pending or failure feedback instead of silently writing or exposing a raw error.

---

### User Story 4 - Trust Account, Subscription, and Sync Feedback (Priority: P4)

As a user managing my account and subscription, I want authentication, settings, pricing, and sync recovery flows to be explicit and trustworthy so I know what the system is doing and what to do next.

**Why this priority**: Clear account, pricing, and recovery feedback reduces support burden and increases user trust, especially when the app is offline, pricing is unavailable, or settings updates fail.

**Independent Test**: Can be fully tested by signing in, viewing plan options, changing settings, forcing recoverable sync failures, and reviewing pending or failed sync items.

**Acceptance Scenarios**:

1. **Given** a user signs in with email and password, **When** they interact with the login form, **Then** they see inline guidance, can reveal the password temporarily, and the sign-in screen uses branded local assets consistently.
2. **Given** subscription offers cannot be loaded, **When** the user opens plan selection, **Then** the app shows an honest unavailable state with a retry path instead of displaying placeholder prices as if they were real.
3. **Given** subscription offers are available, **When** the user compares plans, **Then** they can understand the differences in value, recommendation, and trial terms without outside explanation.
4. **Given** a settings change fails, **When** the user attempts to save it, **Then** the app tells them that the update failed and leaves them with a clear next step.
5. **Given** sync items are pending or failed, **When** the user opens sync status, **Then** they can see which items need attention, understand the failure reason, and retry the affected item without retrying everything.
6. **Given** a user can trigger a deliberate diagnostic action from settings that would terminate the app, **When** they invoke it, **Then** the app asks for explicit confirmation before continuing.
7. **Given** a user reaches a gated usage limit, **When** the app blocks the action, **Then** the user can understand which limit was reached and can move directly to the relevant upgrade path.
8. **Given** the system resolves a sync conflict automatically, **When** the user reviews sync status, **Then** they can understand that a conflict occurred and which version of the data was kept.
9. **Given** sign-in options depend on capability checks, **When** the login experience first loads, **Then** major sign-in choices appear stably and do not flicker in a way that undermines user confidence.
10. **Given** a returning user has already established a trusted sign-in path, **When** they come back to the app, **Then** the app avoids unnecessary credential-entry friction while still respecting the product's security rules.

### Edge Cases

- A user opens a major screen while data is still loading, partially unavailable, or temporarily stale.
- A user has permission to use the app but not to view restricted financial summaries or exports.
- A user chooses a date range, project, or chart context that produces no matching data.
- A user sees a fallback summary term, status label, or number format that could be misunderstood in Arabic or English.
- A voice capture is interrupted by cancellation, timeout, or playback failure before submission.
- Subscription offers are temporarily unavailable or incomplete for the user's region.
- The app goes offline or comes back online while the user is on a content-heavy screen.
- The app resolves conflicting offline changes automatically and the user still needs a trustworthy explanation of what happened.
- Two pending offline actions are created nearly simultaneously and must retain a stable user-visible order.
- A workspace contains enough projects, records, or entities that users need filters, summaries, and progress feedback to stay oriented.
- A major sign-in option becomes temporarily unavailable or appears late while capability checks are still resolving.
- A user taps a primary quick action repeatedly while preloading is still underway and the app must avoid duplicate or unstable launch behavior.
- A signed-in member or entry-only user opens dashboard, projects, or worker accounting and must not trigger restricted financial reads.
- A legacy worker accounting record is marked partial but does not contain an explicit paid amount.
- A legacy entity record does not contain `lastUsedAt` when the paged cross-project directories are introduced.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST provide persistent access to the primary destinations for home overview, adding new records, reports, and projects from the main in-app navigation.
- **FR-002**: The system MUST expose a visible notifications entry point from the main shell and indicate when unread notifications exist.
- **FR-003**: The system MUST place high-frequency quick actions ahead of lower-priority informational content on the home experience.
- **FR-003A**: The system MUST keep Home navigation, sync visibility, and non-financial quick actions available for all signed-in members while replacing restricted financial dashboard summaries with a friendly denied state and preventing restricted financial providers from loading for denied roles.
- **FR-004**: The system MUST provide an explicit refresh action for the home experience so users can re-request current information on demand.
- **FR-005**: The system MUST replace blank loading and raw error states on key operational screens with user-friendly loading, empty, and recovery messaging.
- **FR-005A**: The system MUST use visible loading placeholders on the targeted dashboard and reporting surfaces rather than leaving unexplained blank space while data is loading.
- **FR-006**: The system MUST allow users to start voice-based expense capture with enough time to describe typical real-world construction expenses in one attempt.
- **FR-007**: The system MUST show recording progress and remaining recording time during voice-based expense capture.
- **FR-008**: The system MUST allow users to play back and review a recorded voice entry before they submit it for processing.
- **FR-008A**: The system MUST provide live visual feedback during voice recording so users can tell that the app is actively capturing speech.
- **FR-009**: The system MUST apply the user's current preferred currency to newly created voice-based expense drafts unless the user changes it intentionally.
- **FR-010**: The system MUST let users remove individual active expense and payment filters without clearing the rest of the filter set.
- **FR-011**: The system MUST make grouping controls and filtering controls visually distinct so users can tell whether they are changing organization or narrowing results.
- **FR-012**: The system MUST provide a clear call to action when an expense or payment list is empty and no records exist yet.
- **FR-012A**: The system MUST keep expense and payment filtering usable on small screens without requiring excessive scrolling to reach the most common filter controls.
- **FR-013**: The system MUST let users keep, share, or print exported transaction and report documents after generation.
- **FR-014**: The system MUST preserve project context when users move from a project-scoped payment list into payment detail and payment editing flows and then return.
- **FR-015**: The system MUST allow users to filter projects by status and change the visible ordering of project lists, with each selected ordering applied consistently across the complete matching paged result set rather than independently within each loaded page. Financial sort options that depend on restricted metrics MUST be available only to accounting-authorized roles, while denied roles retain non-financial ordering options.
- **FR-016**: The system MUST show enough project-level financial summary information in the project list for accounting-authorized roles to compare expense, income, and net outcome without opening each project individually. Users without that access MUST still be able to browse projects through non-financial status and recent/name options and receive a friendly restricted state instead of hidden breakage.
- **FR-017**: The system MUST ask for confirmation before archiving a project so users do not hide active work accidentally.
- **FR-018**: The system MUST allow users to choose a date range that scopes the main report view for a selected project.
- **FR-019**: The system MUST ensure that custom report exports include only the selected project's data for the selected reporting period.
- **FR-019A**: The system MUST let users choose from the full relevant project set for reporting purposes, including historical or archived projects when those projects remain reportable.
- **FR-020**: The system MUST present report export choices in a discoverable way that does not rely on users horizontally scrolling to find hidden actions.
- **FR-021**: The system MUST provide friendly empty states for charts, tables, and summaries when the chosen report scope has no data.
- **FR-021A**: The system MUST let users export or share an individual report visualization when they need a chart artifact without the rest of the report package.
- **FR-022**: The system MUST provide a visible Resources section in the top-level Add destination with direct cross-project browse access for workers, contractors, equipment providers, and transport providers, not only project-specific routes.
- **FR-023**: The system MUST allow users to search the worker directory and distinguish worker status when browsing worker records.
- **FR-024**: The system MUST show worker accounting total cost, confirmed paid amount, and confirmed remaining balance from an exact full-worker summary rather than only the currently visible page of records. Paid records contribute their full amount; unpaid records contribute zero paid; partial records use an explicit paid amount between zero and the record amount; legacy partial records without that value are excluded from confirmed paid and confirmed remaining totals and trigger a visible incomplete-data explanation rather than an estimate; and worker-only partial-payment controls MUST not appear on contractor, equipment, or transport accounting flows.
- **FR-025**: The system MUST show live subscription offers using the user's actual available pricing, or present an explicit unavailable state with retry guidance when live pricing cannot be loaded.
- **FR-026**: The system MUST identify the recommended or best-value subscription offer clearly when multiple plans are available.
- **FR-027**: The system MUST show trial terms using the actual offer details available to the user instead of a generic placeholder description.
- **FR-028**: The system MUST present enough plan comparison information for users to understand why one offer is recommended over another.
- **FR-029**: The system MUST let users know when settings updates fail and preserve a clear recovery path after failure.
- **FR-030**: The system MUST show the app version and provide access to product information such as policy or help links from settings.
- **FR-031**: The system MUST support a broader set of commonly used regional currencies in account preferences.
- **FR-032**: The system MUST use branded local assets for sign-in surfaces instead of depending on third-party image hosting at sign-in time.
- **FR-033**: The system MUST let users temporarily reveal their password while signing in.
- **FR-034**: The system MUST provide inline validation and guidance on the sign-in form before final submission.
- **FR-034A**: The system MUST keep major sign-in options visually stable while capability checks are loading so they do not flicker in and out unexpectedly.
- **FR-034B**: The system MUST provide a supported low-friction return path for previously authenticated users so they do not need to re-enter credentials unnecessarily on normal return flows.
- **FR-035**: The system MUST provide a sync status view that lists pending and failed sync items with their type, time, and latest failure reason.
- **FR-036**: The system MUST let users retry an individual failed sync item without requiring a full global retry.
- **FR-037**: The system MUST surface offline and reconnecting state changes without creating jarring layout shifts in primary screens.
- **FR-037A**: The system MUST inform users when an automatic sync conflict resolution has occurred and explain which version of the data was retained.
- **FR-038**: The system MUST communicate profit and loss using more than color alone.
- **FR-039**: The system MUST provide meaningful spoken labels for quick-action items so assistive technologies can identify them reliably.
- **FR-040**: The system MUST preserve correct visual behavior for left-to-right and right-to-left layouts in the primary action launcher.
- **FR-041**: The system MUST keep large data and export flows understandable by showing progress or waiting feedback when users request longer-running report generation.
- **FR-042**: The feature scope MUST prioritize behavior, clarity, and recoverability improvements described in the attached review; purely internal cleanup work is only in scope when it directly supports those user-facing outcomes.
- **FR-043**: The system MUST allow users to apply supported bulk actions to multiple selected expenses or payments in one step, with confirmation before destructive changes are committed.
- **FR-044**: The system MUST replace unexplained fallback summary labels with user-understandable messaging when a top entity, top category, or comparable summary cannot be determined meaningfully.
- **FR-045**: The system MUST keep subscription upgrade paths discoverable from the home experience for users who are eligible to upgrade.
- **FR-046**: The system MUST keep project browsing, project selection, report scoping, and export scoping understandable in large workspaces by either responding within normal interaction expectations or showing clear progress feedback while work continues.
- **FR-047**: The system MUST display currency amounts and numeric values consistently across supported languages so that Arabic and English users can read the values without ambiguity.
- **FR-048**: The system MUST require explicit confirmation before any settings-based diagnostic action that intentionally terminates the app is executed.
- **FR-049**: The system MUST present user-facing labels, actions, and error messages consistently in each supported language across the targeted screens in this improvement pack.
- **FR-050**: The system MUST ensure that each primary shell destination defined by the product navigation model remains directly reachable and is not left orphaned or inaccessible.
- **FR-051**: The system MUST provide a direct upgrade path from any limit-reached state and clearly explain the blocked limit in user terms.
- **FR-052**: The system MUST keep project-list browsing understandable in large workspaces by avoiding overload from continuously changing full-workspace project lists from the user's perspective.
- **FR-053**: The system MUST keep dashboard summary content coherent during refresh so users do not see fragmented or contradictory summary states while the home experience is updating.
- **FR-054**: Supporting engineering cleanup from the attached review, including removal of accidental artifacts, cleanup of abandoned or unreachable UI paths, and consistency of shared presentation patterns, MUST remain in scope when required to deliver the targeted user-visible improvements safely.
- **FR-055**: The system MUST avoid exposing leftover debug-only or hardcoded production labels on the targeted user-facing screens.
- **FR-056**: The system MUST keep repeated taps on primary quick actions from causing duplicate loading states, duplicate launches, or unstable entry behavior.

### Key Entities *(include if feature involves data)*

- **Primary Navigation Destination**: A top-level area a signed-in user can reach directly from the main shell, including its label, iconography, badge state, and expected destination behavior.
- **Quick Action**: A high-frequency entry point used to start core work such as creating records, opening reports, or reviewing notifications.
- **Voice Expense Draft**: A temporary expense record created from recorded speech, including recording state, playback readiness, default currency, and review status.
- **Transaction Filter Set**: The active combination of search, grouping, date, status, entity, and project filters that shapes visible expense or payment results.
- **Project Summary View**: A condensed representation of a project's status, financial outcome, and visibility state used in lists and previews.
- **Report Request**: A user-selected reporting scope that includes project context, date range, export choice, and included content sections.
- **Subscription Offer**: A purchasable plan presented to a user, including its price, trial details, eligibility, and recommendation priority.
- **Sync Queue Item**: A pending or failed background action that includes its business type, creation time, latest status, retry state, and any user-facing error reason.
- **Managed Resource Directory Entry**: A worker, contractor, equipment provider, or transport provider record that users can browse across projects and summarize financially.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In a moderated usability study with at least 20 returning users, at least 90% can reach Home, Add, Reports, Projects, and Notifications within 10 seconds from the signed-in shell without assistance.
- **SC-002**: In a moderated study with at least 20 participants, at least 90% can complete voice recording, playback review, and draft submission on their first attempt.
- **SC-003**: Across an automated sample containing at least 20 project/date combinations, 100% of custom report exports match the selected project and reporting period with no unrelated records.
- **SC-004**: In a release-candidate audit of every targeted empty, loading, offline, and recoverable failure state, at least 95% provide both a visible explanation and a next-step action.
- **SC-005**: In a moderated study with at least 20 participants, at least 85% can identify project financial status, worker balance status, and sync failure status without opening secondary help content.
- **SC-006**: Categorized support requests per 1,000 monthly active users for hidden navigation, unclear export options, missing pricing context, or silent settings/sync failures decrease by at least 30% when comparing the first full release cycle after launch with the preceding release cycle of equal duration.
- **SC-007**: Across at least 100 timed project/report scope changes using the defined large-workspace dataset, at least 95% display updated content or explicit in-progress feedback within 3 seconds.
- **SC-008**: In release-candidate review of every targeted financial screen in Arabic and English, 100% show readable localized amounts and no unexplained fallback summary labels.
- **SC-009**: In a first-session moderated study with at least 20 upgrade-eligible users, at least 80% can identify where to upgrade from the home experience without moderator help.
- **SC-010**: In a moderated plan-comparison study with at least 20 participants, at least 85% can correctly identify the recommended plan and its main value differences without moderator explanation.
- **SC-011**: In recording-flow testing with at least 20 participants, at least 95% can tell within 2 seconds that voice capture is active from on-screen feedback alone.
- **SC-012**: Across at least 100 browse/filter/re-open cycles on the defined 50-project dataset, at least 95% complete without visible overload or confusing live reordering.
- **SC-013**: Across at least 20 seeded auto-resolved conflict cases, 100% present a user-visible explanation of the resolution outcome in sync status.
- **SC-014**: In a phone-sized-device study with at least 20 participants, at least 90% can apply a common transaction filter without scrolling past more than one screenful of controls.
- **SC-015**: In a moderated sharing study with at least 20 participants, at least 90% can share a single report visualization without exporting the full report package first.
- **SC-016**: Across at least 20 returning sessions with an established trusted sign-in path, at least 85% re-enter without manual credential entry during normal return flows.

## Assumptions

- The improvement pack covers the recommendations in the attached review as one prioritized product initiative rather than a single isolated screen change.
- Existing role-based financial access rules remain in place; this feature improves clarity, discoverability, and scoped behavior without broadening who can see restricted financial data.
- Existing business concepts for projects, workers, contractors, equipment providers, transport providers, reports, subscriptions, and offline actions remain the source of truth.
- The app continues to support both Arabic and English, and all new or revised user-facing content must behave appropriately in both language directions.
- Users may work in inconsistent connectivity conditions, so recoverability and clear feedback are treated as first-class outcomes across the feature.
- Internal refactors, duplicate widget cleanup, and artifact removal are acceptable only when they are necessary to deliver the user-visible improvements defined in this specification.
- Bulk transaction actions are limited to actions the product already considers safe for multi-select workflows, and they must not bypass normal confirmation safeguards.
