# UI Behavior Contract: Buildozer Review Improvement Pack

This contract defines observable behavior for implementation and widget/integration tests. It intentionally avoids prescribing visual pixel values.

## Main Shell

- The signed-in shell exposes Home, Add, Reports, and Projects as persistent destinations.
- Add opens the canonical add hub containing expense, payment, worker entry, and voice expense actions.
- No configured shell branch is unreachable.
- Repeated taps do not create duplicate routes or duplicate loading overlays.
- Notifications are reachable from the dashboard app bar and show an unread badge when the bounded feed contains unread items.

## Dashboard

- Offline/sync status and quick actions appear before long-form metrics and insights.
- Pull-to-refresh refreshes the dashboard snapshot, subscription/usage state, and notification badge as one visible action.
- Loading sections show stable placeholders; failures show localized recovery copy and retry actions.
- Missing top entity/category values show explanatory no-data copy.
- Profit/loss uses text or iconography in addition to color.
- Eligible users can find the upgrade path without traversing all insights.
- Users without accounting access still see notifications, sync visibility, and non-financial quick actions, but dashboard financial summaries are replaced with a localized restricted-financial state.

## Voice Expense

- A recording can run for up to 60 seconds.
- Recording state exposes elapsed or remaining time and live visual audio feedback.
- A completed recording can be played, paused, rerecorded, cancelled, or processed in production builds.
- Processing uses the current user currency and presents localized recoverable errors.

## Expenses and Payments

- Each active filter token removes only its corresponding filter.
- Grouping controls are visually and semantically distinct from filters.
- Common filters remain reachable within one screenful on target phone sizes.
- Empty datasets offer the relevant add action; empty filtered results offer filter recovery.
- Selection mode supports confirmed bulk archive through existing mutations and reports partial failures.
- Generated PDFs expose print and share/save actions.
- Project-scoped payment list, detail, add, and edit flows preserve project context on return.

## Projects

- Users can filter All, Active, Completed, and On Hold projects and choose a supported sort.
- Project cards expose expenses, income, net result, and non-color profit/loss meaning.
- Archive requires confirmation.
- The project screen paginates; the warm active-project stream does not become the complete browse source.
- Users without accounting access still browse projects by status and recent/name ordering, while financial sort controls and project-card financial metrics are hidden or replaced with localized access copy.

## Reports

- Report access is denied before financial providers render for unauthorized roles.
- One project/date scope drives all charts, tables, totals, and export actions.
- The default date scope is month-to-date.
- Report project selection can page through active and reportable archived projects.
- Export actions are available from one discoverable menu.
- Empty charts explain the empty scope.
- A single chart can be shared without generating the full report package.
- Long exports show progress and remain cancellable before the share/print handoff.
- Custom exports contain only the selected project/date data and continue beyond 500 records.

## Resource Directories

- The top-level Add destination contains a visible Resources section with direct cross-project browse entries for workers, contractors, equipment providers, and transport providers.
- Worker search covers name, phone, and worker type; worker status is visible and filterable.
- Worker accounting shows total cost, confirmed paid, and confirmed remaining. Legacy partial records without explicit paid amounts trigger an incomplete-data explanation and are never estimated.
- Worker accounting reads its summary from an exact maintained full-worker total, not from the currently visible ledger page.
- Worker-only partial-payment controls appear only in worker accounting flows; contractor, equipment, and transport accounting remain on the generic accounting-entry model.
- Domain accounting screens show a friendly denied state before records or add actions render for unauthorized roles.
- Authorized accounting-entry saves show visible pending progress and localized recoverable failure feedback instead of raw exception text.
- Contractor/equipment/transport directories page typed entities and open existing accounting detail flows.

## Subscription, Settings, and Authentication

- Plans display only store-returned prices; missing offers show retryable unavailable state.
- Recommended plans, feature differences, savings/value context, and actual trial metadata are understandable without external help.
- Limit-reached screens explain the blocked limit and open the upgrade path directly.
- Settings failures show localized feedback and retain the previous confirmed value.
- Settings show app version and help/legal destinations and include the expanded currency set.
- Diagnostic termination requires confirmation.
- Login uses local app/Google assets, supports password visibility, shows inline validation, and reserves stable space while Google support resolves.
- Existing authenticated sessions continue through the current deterministic restore flow without unnecessary credential entry.

## Sync and Connectivity

- The offline banner enters and exits without abrupt layout jumps.
- Sync status lists pending, failed, dead-letter, and recently resolved items with type, time, and reason/outcome.
- A failed item can be retried individually.
- A skipped stale update states that the newer saved version was retained.

## Accessibility and Localization

- Interactive icons and quick actions expose localized semantic labels.
- Core layouts remain usable in English LTR and Arabic RTL.
- Amounts and counts use consistent locale-aware formatting and retain unambiguous currency codes.
- No targeted screen exposes raw exception text, debug-only production labels, or untranslated user-facing strings.
