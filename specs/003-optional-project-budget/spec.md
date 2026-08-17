# Feature Specification: Optional Project Budget

**Feature Branch**: `003-optional-project-budget`

**Created**: 2026-08-17

**Status**: Draft

**Input**: User description: "i want to make assign budget to a project when it is created is optional, so a user can create a project without specifig the budget because h may want to only reord the expenses and other things and dont have a budget, take in mind that i want all the widgets and other things to be dynamically with this change like dont show the payment widget and so, dive deeep and analyze other conditions"

## Context

Today a project cannot be created without a **Contract Value**. It is a required field on the create-project form, it is rejected by the server if missing or zero, and it silently powers a chain of derived numbers and widgets across the app: budget progress bars, remaining-balance figures, project risk/health classification, and risk notifications.

A second, already-optional field — **Budget Limit** — overrides Contract Value as the spending baseline when it is set.

This feature removes the hard requirement so a user can create a project purely to record expenses (and optionally payments), and makes every budget-derived surface adapt honestly rather than displaying zeroes, empty progress bars, or false alarms.

**Terminology used in this spec:**

- **Contract Value** — the agreed amount the client pays for the project. Basis for revenue-side and risk calculations.
- **Budget Limit** — a spending ceiling for the project. Basis for budget-usage progress. Already optional today.
- **Budget baseline** — whichever of the two the app currently uses to measure spending against (Budget Limit when set, otherwise Contract Value).
- **Budget-less project** — a project with neither a Contract Value nor a Budget Limit.
- **Expense-ledger mode** — the presentation mode a project is in whenever it has no Contract Value. The project reads as a pure cost tracker: revenue-side widgets and actions are hidden. The mode is derived, never stored, and the project leaves it the moment a Contract Value is entered.

**The two switches are independent.** Budget-usage widgets are governed by the budget baseline; revenue-side widgets are governed by the Contract Value. A project with a Budget Limit but no Contract Value therefore shows budget progress while hiding the revenue side — a spending budget with no income expected, which is a coherent and intended combination.

**Core invariant**: a project with no Contract Value cannot have payments. This is enforced at both ends — payments cannot be recorded against a contract-less project, and a Contract Value cannot be cleared while payments exist — so the app never reaches a state where recorded payments are hidden behind expense-ledger mode.

## Clarifications

### Session 2026-08-17

- Q: When a project has no Contract Value, should risk/health classification be suppressed entirely, or should the negative-net rule still apply? → A: Suppressed entirely — a project without a Contract Value never receives a risk verdict, regardless of payments. Risk requires a contract to be measured against.
- Q: Does the absence of a Contract Value alone put a project in expense-ledger mode, or must it also have no payments? → A: Contract Value alone decides, and the rule is enforced as an invariant: a project with no Contract Value cannot have payments. Clearing a Contract Value is blocked while payments exist, and payments cannot be recorded against a project that has no Contract Value.
- Q: What counts as "has payments" for the purpose of blocking a Contract Value from being cleared? → A: The existence of any payment record, whatever its amount — not the payment total. A zero-amount or fully-refunded payment still blocks clearing, since the record would otherwise be orphaned.
- Q: How does a user know why the revenue widgets are missing and how to get them back? → A: A short empty-state on the project detail screen, placed where the revenue section would otherwise be, naming the reason and offering to set a Contract Value. No badge in project lists.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Create a project without a budget (Priority: P1)

A user starts a new project to track costs on a job where no contract amount has been agreed yet, or where they simply want an expense ledger. They fill in the project name and other details, leave the money fields empty, and save. The project is created successfully and appears in their project list.

**Why this priority**: This is the core ask. Without it nothing else in the feature is reachable.

**Independent Test**: Open the create-project form, enter only a name, save, and confirm the project is created and openable — both online and while offline.

**Acceptance Scenarios**:

1. **Given** the create-project form is open, **When** the user enters a project name and leaves both Contract Value and Budget Limit empty, **Then** the project is created without a validation error.
2. **Given** the create-project form is open, **When** the user leaves the money fields empty, **Then** neither money field is presented as required to the user.
3. **Given** the user is offline, **When** they create a project without any budget values, **Then** the project is queued and shown optimistically with no fabricated zero amounts, and it syncs successfully when connectivity returns.
4. **Given** a project is created without a budget, **When** the user reopens it, **Then** no money field shows a placeholder `0` that could be mistaken for a real agreed amount.
5. **Given** the create-project form is open, **When** the user enters a negative amount in either money field, **Then** the entry is rejected with a clear message.

---

### User Story 2 - Budget-dependent widgets adapt automatically (Priority: P1)

A user opens a budget-less project. Every surface that would otherwise compare spend against a baseline, or display a contract amount, either disappears or is replaced with something meaningful. Nothing shows a zero-value amount, an empty progress bar, a `0%` used indicator, or an "over budget" state derived from an absent number.

**Why this priority**: Shipping US1 alone would leave the app displaying misleading zeroes and permanently "over budget" states on every budget-less project. This is inseparable from the core value.

**Independent Test**: Create a budget-less project, add a few expenses, then inspect the project detail screen, the project list card, and the project-scoped dashboard — confirm no budget-derived widget renders and no zero amounts appear.

**Acceptance Scenarios**:

1. **Given** a project with no Contract Value and no Budget Limit, **When** the user views the project detail screen, **Then** the budget-usage card (spend vs. baseline, percentage used, remaining, "over budget") is not rendered.
2. **Given** a project with no Contract Value, **When** the user views the project detail screen, **Then** the Contract Value row and the Contract Value metric card are not rendered.
3. **Given** a project with no Contract Value, **When** the user views that project in the project list, **Then** the card shows no budget bar and no contract figure, and the layout has no leftover gap where they used to be.
4. **Given** a project with no Contract Value, **When** the user views the dashboard scoped to that project, **Then** the budget-usage card and Contract Value row are not rendered.
5. **Given** a project with a Budget Limit but no Contract Value, **When** the user views any of the above screens, **Then** budget-usage widgets render normally against the Budget Limit, while Contract Value displays and the revenue side are omitted (see User Story 3).
6. **Given** a project with a Contract Value but no Budget Limit, **When** the user views any of the above screens, **Then** behaviour is unchanged from today.
7. **Given** a budget-less project, **When** the user records expenses totalling any amount, **Then** the project is never labelled "over budget".
8. **Given** a budget-less project, **When** the user views expense totals, **Then** they render correctly and are not suppressed by the absence of a budget.
9. **Given** a project with a Contract Value but no Budget Limit, **When** the user views income totals, net figures, and profit margin, **Then** all of them render — the absence of a Budget Limit suppresses nothing on the revenue side. (Revenue-side behaviour for projects with *no Contract Value* is governed by User Story 3.)

---

### User Story 3 - Expense-ledger mode hides the revenue side (Priority: P1)

A user who created a project only to record expenses does not want revenue-side UI cluttering it. On any project with no Contract Value, the whole profit-and-loss side — Add Payment, Total Income, Net Profit, Profit Margin, payment lists — is hidden, and the project reads as a cost tracker. Entering a Contract Value brings the revenue side back.

**Why this priority**: Explicitly called out in the request ("dont show the payment widget and so"). It is what makes a contract-less project feel intentional rather than broken.

**Independent Test**: Create a project with no Contract Value, confirm every revenue-side widget and action is absent while expense-side ones work fully, then add a Contract Value and confirm the revenue side reappears.

**Acceptance Scenarios**:

1. **Given** a project with no Contract Value, **When** the user opens the project detail screen, **Then** the Add Payment action, the View Payments action, the Total Income figure, and the Profit Margin stat are all absent.
2. **Given** the same project, **When** the user views the headline financial card, **Then** it presents total expenses rather than a net-profit figure built from zero income.
3. **Given** the same project, **When** the user views it in the project list, **Then** the card shows a total-expenses figure and never the words "profit" or "loss".
4. **Given** the same project, **When** the user views the dashboard scoped to it, **Then** the same revenue-side widgets are absent there too.
5. **Given** the same project, **When** the user views expense lists, worker entries, timeline, and completion, **Then** all of them render and function exactly as on any other project.
6. **Given** a project with a Budget Limit but no Contract Value, **When** the user opens it, **Then** budget-usage widgets render against the Budget Limit while the revenue side stays hidden — the two switches act independently.
7. **Given** a project in expense-ledger mode, **When** the user opens the project detail screen, **Then** a short empty-state appears where the revenue section would be, stating the project has no Contract Value and offering an action to set one.
7a. **Given** that empty-state, **When** the user takes its action and saves a Contract Value, **Then** the project leaves expense-ledger mode and its revenue-side widgets appear with no further action.
7b. **Given** a project in expense-ledger mode, **When** the user views the project list, **Then** no badge or marker distinguishes it — the list card simply shows expenses instead of profit.
8. **Given** the workspace-level payments screen, **When** the user opens its project picker, **Then** projects with no Contract Value are not offered as targets.
9. **Given** a user attempts by any route to record a payment against a project with no Contract Value, **When** the attempt is submitted, **Then** it is rejected with a message explaining that the project needs a Contract Value first.
10. **Given** a mix of expense-ledger and ordinary projects in a workspace, **When** the user views the workspace-level dashboard, **Then** workspace-wide payment figures (cash collected, outstanding payments) remain correct — they simply contain no contribution from expense-ledger projects, which by definition have none.

---

### User Story 4 - No false risk alerts or misleading health status (Priority: P1)

A user records expenses on a project with no Contract Value. They are not told the project is "high risk" or "losing", and they receive no risk notifications, because there is no agreed contract amount to be losing against. This applies to any project lacking a Contract Value, whether or not it has a Budget Limit.

**Why this priority**: Without this, the very first expense on every contract-less project flips it to high risk and pushes a notification to every member with risk alerts enabled. It converts the feature from useful to actively harmful.

**Independent Test**: Create a project with no Contract Value, record an expense, and confirm no risk notification is generated and the project is not surfaced in any risk or warning list.

**Acceptance Scenarios**:

1. **Given** a project with no Contract Value, **When** any expense is recorded, **Then** no project risk alert notification is created for any workspace member.
2. **Given** a project with no Contract Value, **When** the system evaluates project health, **Then** the project receives no risk verdict at all — not at-risk, not warning, not losing, not healthy-by-default.
2a. **Given** a project with no Contract Value that nonetheless has payments recorded and spends more than it received, **When** the system evaluates project health, **Then** it still receives no risk verdict, because risk requires a contract amount to measure against.
3. **Given** a project with a Budget Limit but no Contract Value, **When** expenses exceed the Budget Limit, **Then** the budget-exceeded notification still fires as it does today.
4. **Given** a project with no Contract Value, **When** the user views any dashboard warnings or risk summary, **Then** the project does not appear there on risk grounds. A Budget-Limit-only project MAY still appear there for exceeding its Budget Limit, which is a separate signal.
5. **Given** a project that previously had a risk alert and later has its Contract Value removed, **When** metrics are next recalculated, **Then** the stale risk alert is cleared.
6. **Given** a project with no Contract Value, **When** derived balance figures are calculated, **Then** no negative "remaining balance" is produced or displayed from an absent contract amount.

---

### User Story 5 - Add or remove a budget later (Priority: P2)

A user who created an expense-only project later agrees a contract amount, opens the project, and enters it. Every budget-dependent widget appears and reflects the expenses already recorded. The reverse also works: a user can clear the amount on an existing project.

**Why this priority**: Budget-less is a starting state, not a permanent one. Without a transition path, users must delete and recreate projects.

**Independent Test**: Create a budget-less project, record expenses, then edit it to add a Contract Value — confirm budget widgets appear and are calculated against the existing expense history.

**Acceptance Scenarios**:

1. **Given** a budget-less project with recorded expenses, **When** the user adds a Contract Value and saves, **Then** budget-usage widgets, contract displays, and health classification appear and are computed against the full existing expense history.
2. **Given** a project with a Contract Value and no payments, **When** the user clears the field and saves, **Then** the project enters expense-ledger mode and all contract-derived widgets are removed accordingly.
3. **Given** a project with recorded payments, **When** the user attempts to clear its Contract Value, **Then** the save is blocked with a message explaining that the project's payments must be removed first, and no data is altered.
3a. **Given** a project with a payment still queued for sync, **When** the user attempts to clear its Contract Value, **Then** the save is blocked on the same grounds as a synced payment.
4. **Given** the user edits a project while offline, **When** they add or clear a budget value, **Then** the change is queued, reflected optimistically, and applied on sync.
5. **Given** a user without permission to view financial data, **When** they view any project, **Then** the presence or absence of a budget does not expose financial figures they are not entitled to see.

---

### User Story 6 - Reports and exports handle contract-less projects (Priority: P3)

A user generates a report for a project in expense-ledger mode. The report reads as an expense document: revenue sections are omitted rather than printed as zeroes.

**Why this priority**: Lower frequency than day-to-day screens, but a zero-filled export is a document the user may send to a client.

**Note on scope**: report output does not currently display Contract Value or Budget Limit anywhere, so there are no contract or budget lines to remove. The real work in this story is the revenue side and the workspace aggregates.

**Independent Test**: Generate a project report for a project in expense-ledger mode and confirm no income, net-profit, or profit-margin section appears.

**Acceptance Scenarios**:

1. **Given** a project in expense-ledger mode, **When** the user generates a report, **Then** the report omits income, net-profit, and profit-margin sections and presents an expense summary instead.
2. **Given** a workspace containing both contract-bearing and contract-less projects, **When** the user generates a workspace-level report, **Then** aggregate expense and payment totals remain correct and contract-less projects are not counted as zero-value contracts in any average or ratio.
3. **Given** any report that comes to display a contract or budget figure, **When** the underlying amount is absent, **Then** the figure is omitted rather than printed as zero.

---

### Edge Cases

- **Zero versus absent**: A user who deliberately enters `0` must be treated identically to a user who left the field empty — there is no meaningful "zero-value contract".
- **Budget Limit set, Contract Value absent**: Budget-usage widgets must work off the Budget Limit; only contract-specific displays disappear.
- **Contract Value set, Budget Limit absent**: Current behaviour must be preserved exactly — the Contract Value continues to serve as the budget baseline.
- **Budget removed while over budget**: A project currently flagged over-budget must clear that state, and any related notification, when its baseline is removed.
- **Budget added retroactively when already overspent**: Adding a Contract Value below the already-recorded expense total must immediately show the correct over-budget state, not a fresh 0%.
- **Payment attempted on an expense-ledger project**: Unreachable through the interface, since contract-less projects are absent from payment project pickers, and rejected if attempted by any other route.
- **Last payment deleted**: Once a project's final payment record is removed, its Contract Value becomes clearable again with no further action.
- **Zero-amount payment**: A payment recorded as zero, or refunded to zero, still counts as a payment record and still blocks the Contract Value from being cleared — the project total reading zero is not sufficient grounds to allow it.
- **Budget Limit cleared on a project that has payments**: Always allowed. Only the Contract Value is bound by the invariant; the Budget Limit is free to come and go.
- **Queued payment not yet synced**: Counts as a payment for the blocking rule, so a user cannot clear a Contract Value while a payment sits unsynced in the queue.
- **Two offline edits racing**: A queued payment and a queued Contract Value clear must not both apply. Server-side enforcement decides, and the losing edit surfaces to the user rather than failing silently.
- **Contract cleared, then re-added**: A project may move in and out of expense-ledger mode repeatedly. Each transition must be clean, with no residue from the previous state.
- **Existing projects created before this change**: Every project already in the system has a Contract Value greater than zero and must be entirely unaffected.
- **Offline creation then sync rejection**: A queued budget-less project must not be rejected by server-side validation on sync and stranded in the queue.
- **Optimistic placeholder rows**: The temporary project shown while a queued creation syncs must not display a fabricated zero contract amount.
- **Sorting and filtering**: Project list sorts (by income, by net, by expense) must order contract-less projects by their true values — zero income, zero net — with no special-casing, and must page and filter them without error.
- **Percentage and ratio calculations**: Any calculation that divides by the budget baseline must not produce a not-a-number, infinite, or negative percentage when the baseline is absent.
- **Currency display**: No screen should render a bare currency symbol with no number, or a formatted `0.00`, in place of an absent amount.
- **Right-to-left and localisation**: Both English and Arabic must have wording for any new empty-state or "no budget set" text; no screen may fall back to an untranslated string.
- **Layout integrity**: Removing widgets must not leave orphaned section headers, double dividers, or collapsed cards.
- **Test surface**: Existing automated coverage that assumes a contract value is always present must be updated rather than deleted.

## Requirements *(mandatory)*

### Functional Requirements

**Creation and editing**

- **FR-001**: Users MUST be able to create a project without supplying a Contract Value or a Budget Limit.
- **FR-002**: The create-project form MUST NOT present Contract Value as a required field, and MUST NOT block submission when it is empty.
- **FR-003**: The system MUST treat an empty money field and a zero-value money field as equivalent — both mean "not set".
- **FR-004**: The system MUST continue to reject negative amounts in either money field with a clear, localised message.
- **FR-005**: Users MUST be able to add a Contract Value or Budget Limit to an existing project at any time, and MUST be able to clear either one.
- **FR-006**: Clearing a budget value MUST NOT delete, hide, or alter any expense, payment, or worker entry already recorded against the project.
- **FR-007**: Server-side validation MUST accept project creation and update requests with no Contract Value, while continuing to reject malformed or negative values.
- **FR-008**: Projects created or edited while offline without budget values MUST queue, display optimistically without fabricated zero amounts, and sync successfully.

**Dynamic presentation**

- **FR-009**: The system MUST determine, per project, whether a budget baseline exists (Budget Limit if set, otherwise Contract Value) and drive all budget-dependent presentation from that single determination, so that every surface agrees.
- **FR-010**: When no budget baseline exists, the budget-usage widget (spend versus baseline, percentage used, amount remaining, over-budget state) MUST NOT be rendered on the project detail screen, the project list card, or the project-scoped dashboard.
- **FR-011**: When no Contract Value is set, every Contract Value display MUST be omitted rather than rendered as zero — this includes the project detail contract row, the project detail metric card, and the project-scoped dashboard contract row.
- **FR-012**: Removing a widget MUST leave no visual artefact — no empty card, orphaned heading, stray divider, or double spacing.
- **FR-013**: Expense totals MUST continue to render for every project, since they never depend on a budget baseline. Income totals, net figures, and profit margin are governed by expense-ledger mode (FR-031), not by the budget baseline — a project with a Contract Value but no Budget Limit MUST continue to show all four.
- **FR-014**: A project MUST be presented in expense-ledger mode when, and only when, it has no Contract Value. The Budget Limit and the payment count MUST NOT affect this determination. The mode MUST be derived on demand from the Contract Value and never stored as a setting, so it can never disagree with the underlying data.
- **FR-015**: The system MUST NOT reach a state in which a project has recorded payments and no Contract Value; because that state is unreachable, no payment is ever hidden by expense-ledger mode.
- **FR-016**: The project detail screen MUST present a short empty-state where the revenue section would otherwise appear, stating that the project has no Contract Value set and offering an action to set one. This is the sole indicator of expense-ledger mode; project list cards MUST NOT carry a badge or other marker.
- **FR-017**: A project with a Budget Limit but no Contract Value MUST show budget-usage widgets computed against the Budget Limit while hiding the revenue side, demonstrating that the two switches operate independently.
- **FR-018**: Projects with a Contract Value MUST behave exactly as they do today, with no visual or numeric change.

**Derived metrics and alerts**

- **FR-019**: Project risk level and health status MUST NOT be computed for any project without a Contract Value. Neither the contract-comparison rule nor the negative-net rule may classify such a project, regardless of whether payments exist. The project carries no risk verdict at all.
- **FR-020**: Project risk alert notifications MUST NOT be generated for any project without a Contract Value.
- **FR-021**: When a project's Contract Value is removed, any previously generated risk alert for that project MUST be cleared on the next metrics recalculation.
- **FR-022**: Budget-exceeded detection and its notification MUST continue to operate for projects with a Budget Limit, independent of whether a Contract Value is set.
- **FR-023**: The system MUST NOT produce or display the project's contract-derived remaining balance (contract amount less payments received) when no Contract Value is set. This applies only to that contract-derived figure — the separate per-supplier and per-client balances in accounting summaries, which compare expenses against payments for an entity, are unrelated and MUST be left untouched.
- **FR-024**: No derived percentage or ratio may evaluate to a not-a-number, infinite, or negative-percentage value when the budget baseline is absent. Where a baseline is absent the calculation MUST be skipped entirely rather than guarded after the fact.
- **FR-025**: Workspace-level aggregates MUST exclude projects with no budget baseline from budget-based averages, ratios, and warning lists, while continuing to include their expenses and payments in absolute totals.

**Reporting and consistency**

- **FR-026**: Generated reports and exports MUST omit income, net-profit, and profit-margin sections for projects in expense-ledger mode, presenting an expense summary instead. Where a report displays contract or budget figures, those MUST be omitted rather than printed as zero when the corresponding amount is absent.
- **FR-027**: All new or changed user-facing text MUST be available in both English and Arabic, with correct right-to-left rendering.
- **FR-028**: Financial-access permissions MUST continue to govern visibility of all money figures; the absence of a Contract Value MUST NOT become a path to seeing restricted financial data.
- **FR-029**: Project list sorting and filtering MUST order projects with no budget baseline, and projects in expense-ledger mode, by their actual values with no special-casing. An expense-ledger project sorts as zero income and zero net because those are its true values, and it MUST be sorted, paged, and filtered without error alongside every other project.

**Expense-ledger mode**

- **FR-030**: *(merged into FR-014 — expense-ledger mode is derived, never stored)*
- **FR-031**: In expense-ledger mode the system MUST hide, on the project detail screen and the project-scoped dashboard: the Add Payment action, the View Payments action, the Total Income display, and the Profit Margin display.
- **FR-032**: In expense-ledger mode the headline financial card MUST present total expenses instead of a net-profit figure derived from zero income.
- **FR-033**: In expense-ledger mode the project list card MUST present a total-expenses figure and MUST NOT label the project with profit or loss wording.
- **FR-034**: A project MUST leave expense-ledger mode automatically, with no user action beyond entering a Contract Value.
- **FR-035**: Expense-ledger mode MUST NOT hide, restrict, or alter expense entry, worker entries, expense lists, timeline, completion, archiving, or report generation.
- **FR-036**: *(merged into FR-017 — Budget-Limit-only projects show budget widgets and hide the revenue side)*

**Contract-and-payment invariant**

- **FR-037**: The system MUST reject any attempt to record a payment against a project that has no Contract Value, with a message telling the user to set a Contract Value first.
- **FR-038**: Project pickers in payment flows MUST exclude projects that have no Contract Value, so the invalid combination is unreachable rather than merely rejected on submit.
- **FR-039**: The system MUST block clearing a project's Contract Value while any payment record exists against that project, including payments still queued for sync, and MUST explain that the payments have to be removed first.
- **FR-039a**: "Has payments" MUST be determined by the existence of a payment record, not by the payment total. A payment recorded with a zero amount, or one whose amount nets to zero, MUST still block clearing.
- **FR-040**: When a save is blocked by FR-039, the system MUST leave the project and all its records completely unaltered.
- **FR-041**: The invariant MUST be enforced on the server as well as in the interface, so that a queued offline edit cannot produce a project holding both payments and no Contract Value.
- **FR-042**: Removing the last payment record from a project MUST make its Contract Value clearable again, with no further action required.

### Key Entities

- **Project**: A unit of work being tracked. Holds an optional Contract Value (agreed client amount), an optional Budget Limit (spending ceiling), plus name, client, dates, location, description, status, and completion. After this change, a project's *financial mode* is derived from which of these two amounts, if any, are present.
- **Budget baseline**: A derived, per-project value — the Budget Limit when set, otherwise the Contract Value — used to measure spend against. Absent when neither is set. Its presence or absence is the single switch controlling every budget-dependent widget and calculation.
- **Expense-ledger mode**: A derived, per-project presentation state — active whenever the project has no Contract Value. It is the second switch, independent of the budget baseline, governing whether the revenue side is shown. Computed fresh from the Contract Value rather than stored. Because of the core invariant, a project in this mode can never hold payments.
- **Project metrics**: The recalculated financial summary for a project (expense totals, payment totals, net, expected final cost, budget-exceeded flag, risk level, health status, remaining balance). Several of its fields are only meaningful when a budget baseline or Contract Value exists.
- **Notification**: Alerts raised for budget-exceeded and project-risk conditions. Both must respect the absence of a baseline.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can create a usable project entering only a project name, in under 30 seconds, with no validation error.
- **SC-002**: Across every screen that displays a budget-less project, zero misleading money figures are shown — no `0` contract amounts, no empty progress bars, no `0%` used indicators.
- **SC-003**: Recording expenses on a project with no Contract Value generates zero risk-alert notifications, measured over a project's full lifecycle.
- **SC-004**: 100% of projects that have a Contract Value render identically to their pre-change appearance, verified against existing visual and widget coverage.
- **SC-005**: Adding a Contract Value to an existing budget-less project makes budget widgets appear, correctly computed against pre-existing expenses, on the first screen refresh with no further user action.
- **SC-006**: A budget-less project created offline reaches a fully synced state with no queue rejection, in 100% of sync attempts.
- **SC-007**: Every new or changed user-facing string renders in both English and Arabic with no untranslated fallback.
- **SC-008**: No budget-dependent screen produces a layout defect (orphaned heading, empty card, collapsed section) when its widgets are hidden.
- **SC-009**: A project in expense-ledger mode displays no revenue figure anywhere in the app, and no screen labels it with profit or loss wording.
- **SC-010**: Adding a Contract Value to an expense-ledger project restores every revenue-side widget on the next screen refresh, with no user action beyond the save.
- **SC-011**: Zero projects in the system can be found holding both recorded payments and no Contract Value, verified across interface routes, offline sync, and direct server calls.
- **SC-012**: Every attempt to violate the invariant — recording a payment on a contract-less project, or clearing a Contract Value from a project with payments — is refused with a message that names the required corrective action, and leaves all data unchanged.

## Assumptions

- **Two distinct fields, one behaviour**: The user's phrase "budget" covers both money fields. Contract Value is the field that is currently mandatory and therefore the primary target; Budget Limit is already optional and its existing behaviour is preserved.
- **Existing baseline precedence is kept**: When both are set, Budget Limit continues to override Contract Value as the spending baseline, exactly as today.
- **Zero means absent**: Entering `0` is interpreted as "no budget", matching the existing server behaviour that already converts a zero Budget Limit to absent.
- **Removal is conditional**: Users may clear a Contract Value only on a project with no payments. The invariant is enforced rather than assumed, which is what keeps "never hide data the user entered" from colliding with "hide the revenue side" — the conflicting state simply cannot exist.
- **The mode is derived, not chosen**: No new toggle, setting, or project type is introduced. The user gets expense-ledger mode by leaving Contract Value empty and leaves it by filling it in. This keeps the create form as short as it is today.
- **Budget Limit is unconstrained**: Only the Contract Value participates in the invariant. A Budget Limit may be added or cleared at any time regardless of payments.
- **No migration required**: Every existing project has a Contract Value above zero, so this change is purely additive to the data model and no backfill is needed.
- **Risk classification is suppressed, not redefined**: For projects with no Contract Value the system withholds a risk verdict rather than inventing an alternative formula. A future feature could introduce expense-trend-based risk signals; that is out of scope here.
- **Workspace-level payment widgets stay**: Cash-collected and outstanding-payment figures are workspace-scoped and continue to reflect all projects regardless of any individual project's budget state.
- **Hiding, not disabling**: Where a widget is removed, it is omitted from the layout rather than shown greyed out — with one deliberate exception, the revenue-section empty-state on project detail (FR-016), which exists to explain the absence and offer the way out.
- **Workspace payments flow gains a filter**: The existing add-payment flow accepts any project today; under the invariant it must exclude contract-less ones from its project picker. This is a constraint on an existing screen, not new navigation.
- **Permissions unchanged**: The existing financial-access role model continues to govern who sees money figures; this feature adds no new permission concept.
- **Reports follow the same rule**: Report content is derived from the same budget-baseline determination as the on-screen widgets, so the two can never disagree.

## Out of Scope

- Introducing a new risk or health model based on expense trends, burn rate, or schedule for budget-less projects.
- Multi-tier budgets, phased budgets, or per-category budget allocations.
- Budget forecasting, variance analysis, or earned-value reporting.
- Changing the financial-access permission model.
- Any change to how expenses or worker entries are themselves recorded.
- Any change to the fields, amounts, or workflow of a payment itself. Payment *recording* gains exactly one precondition from the invariant — the target project must have a Contract Value (FR-037, FR-038) — and nothing else about payments changes.
