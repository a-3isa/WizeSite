# Buildozer v2 Design System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adopt the v2 redesign of the Buildozer Flutter app — token-driven theme, dark mode, shifted palette, custom raised-FAB 5-tab nav, and restyled screens matching the redesign UI-kit.

**Architecture:** Presentation-layer only. Introduce a `BuildTokens` `ThemeExtension` (light+dark), refresh `AppTheme`, add a Hive-backed `ThemeController`, build token-driven DS primitives in `lib/core/widgets/ds/`, extend the `StatefulShellRoute` to 4 branches with a custom bottom nav, add Activity + More screens, and restyle existing screens. No model/routing-contract/Firebase changes.

**Tech Stack:** Flutter, Material 3, Riverpod, go_router, google_fonts (Inter/Cairo), Hive (prefs), flutter_test.

## Global Constraints

- Brand accent orange `#FF6D00` (dark `#FF7D1F`). No gradients, no photography, Material Symbols/Icons outlined only, no emoji.
- Money semantics: income/funds-in green `#12A150`; expense/funds-out red `#E5484D`; workers/pending amber `#F59E0B`. Trailing currency code, default `EGP`, live thousands separators.
- Title Case buttons/titles; sentence case body. Radii `8/12/16/20/28`→v2 `10/14/20/26/pill`. Primary CTA 56px full-width.
- Persistence via Hive box `app_prefs` (matches `LocaleController`).
- Bilingual EN/AR, RTL via `EdgeInsetsDirectional`/`Directionality`. Only add i18n keys not already present.
- Gate every phase: `flutter analyze` clean, `flutter test` green.

---

### Task 1: BuildTokens ThemeExtension

**Files:**
- Create: `lib/app/theme/build_tokens.dart`
- Test: `test/app/theme/build_tokens_test.dart`

**Interfaces:**
- Produces: `class BuildTokens extends ThemeExtension<BuildTokens>` with `Color` fields `accent, accentPress, accentSoft, onAccent, income, incomeSoft, expense, expenseSoft, warning, warningSoft, bg, surface, surface2, surface3, border, borderStrong, text, textMuted, textFaint, scrim`; `List<BoxShadow> shadowSm, shadowMd, shadowNav`; `double gap, cardPad, sectionGap, rSm, rMd, rLg, rXl`. Static consts `BuildTokens.light`, `BuildTokens.dark`. Extension `BuildTokensX on BuildContext { BuildTokens get tokens }`.

- [ ] Step 1: Write `build_tokens_test.dart` asserting `BuildTokens.light.income == const Color(0xFF12A150)`, `BuildTokens.dark.bg == const Color(0xFF0E1116)`, and `BuildTokens.light.lerp(BuildTokens.dark, 0).income == BuildTokens.light.income`.
- [ ] Step 2: Run `flutter test test/app/theme/build_tokens_test.dart` — expect FAIL (file missing).
- [ ] Step 3: Implement `build_tokens.dart` with all fields, `.light`/`.dark` consts using the exact hex from the spec, `copyWith`, `lerp` (use `Color.lerp`/`lerpDouble`, snap shadows/spacing at t<0.5).
- [ ] Step 4: Run the test — expect PASS.
- [ ] Step 5: `flutter analyze lib/app/theme/build_tokens.dart` clean. Commit `feat(theme): add BuildTokens theme extension (light+dark)`.

---

### Task 2: v2 palette in AppColors + refreshed AppTheme with dark

**Files:**
- Modify: `lib/core/constants/app_colors.dart`
- Modify: `lib/app/theme/app_theme.dart`
- Test: `test/app/theme/app_theme_test.dart`

**Interfaces:**
- Consumes: `BuildTokens.light`, `BuildTokens.dark` (Task 1).
- Produces: `AppTheme.light(Locale)`, `AppTheme.dark(Locale)` both registering `extensions: [BuildTokens.*]`. `AppColors` values shifted to v2.

- [ ] Step 1: Write `app_theme_test.dart`: `AppTheme.light(Locale('en')).extension<BuildTokens>()` is `BuildTokens.light`; `AppTheme.dark(Locale('en')).brightness == Brightness.dark` and its extension is `BuildTokens.dark`.
- [ ] Step 2: Run test — expect FAIL (`dark` undefined).
- [ ] Step 3: Update `AppColors`: `surfaceGrey`→`0xFFF4F5F7`, `borderGrey`→`0xFFE7EAEF`, `textDark`→`0xFF141922`, `textBody`→`0xFF67717F`, `success`→`0xFF12A150`, `danger`→`0xFFE5484D`, `constructionOrangeLight`→`0xFFFFF1E7`. Keep legacy aliases.
- [ ] Step 4: In `app_theme.dart`, register `extensions: [BuildTokens.light]` in `light`; add `static ThemeData dark(Locale)` mirroring `light` with `ColorScheme.dark(primary: accent, surface: bg, ...)`, dark card/appbar/input colors from `BuildTokens.dark`, and `extensions: [BuildTokens.dark]`. Bump card radius to `rLg=20`, input radius `rMd=14`.
- [ ] Step 5: Run test — PASS. `flutter analyze` clean. Commit `feat(theme): v2 palette + dark theme`.

---

### Task 3: ThemeController (Hive-persisted ThemeMode)

**Files:**
- Create: `lib/core/providers/theme_provider.dart`
- Modify: `lib/app/app.dart`
- Test: `test/core/providers/theme_provider_test.dart`

**Interfaces:**
- Produces: `class ThemeController extends StateNotifier<ThemeMode>` (default `ThemeMode.system`, persists to Hive `app_prefs` key `theme_mode` as `system|light|dark`); `void setThemeMode(ThemeMode)`; `themeControllerProvider`.

- [ ] Step 1: Write test: construct `ThemeController(prefsBox: null)` → state `ThemeMode.system`; `setThemeMode(ThemeMode.dark)` → state dark.
- [ ] Step 2: Run — FAIL.
- [ ] Step 3: Implement controller mirroring `LocaleController` (optional injected `Box<String>?`, `_tryOpenPrefsBox`, resolve initial from key). Provider via `flutter_riverpod/legacy.dart` `StateNotifierProvider`.
- [ ] Step 4: Wire `app.dart`: `final themeMode = ref.watch(themeControllerProvider);` set `theme: AppTheme.light(locale)`, `darkTheme: AppTheme.dark(locale)`, `themeMode: themeMode`.
- [ ] Step 5: Run test — PASS. `flutter analyze` clean. Commit `feat(theme): Hive-persisted ThemeController wired into app`.

---

### Task 4: i18n keys for v2

**Files:**
- Modify: `lib/app/localization/app_localizations.dart`
- Test: `test/app/localization/app_localizations_test.dart` (or existing localization test)

**Interfaces:**
- Produces: new EN+AR keys: `activity, more, netThisMonth, week, month, quickAdd, switchWorkspace, budgetUsed, ofContract, appearance, darkMode, language, allProjects, fundsIn, spent, budgetHealth, good, whatToAdd, expenseDesc, paymentDesc, startVoice, markRead, thisWeek, earlier, memberSince, seeAll, searchActivity, recordExpense, tapToSpeak, listening, transcript, detected, onSite, upgradePro, proSub, themeSystem, themeLight, themeDark, siteEngineer, welcomeSub` (skip any already present). Values from strings.jsx.

- [ ] Step 1: Add keys to `_en` and `_ar` maps (verify absence first; `requiredKeys` parity is enforced by existing test).
- [ ] Step 2: Run existing localization parity test (`flutter test test/ -k localization` or the file) — expect PASS (EN/AR key sets equal).
- [ ] Step 3: `flutter analyze` clean. Commit `feat(i18n): add v2 redesign string keys (en+ar)`.

---

### Task 5: DS primitives library

**Files:**
- Create: `lib/core/widgets/ds/build_card.dart`, `build_button.dart`, `segmented_toggle.dart`, `build_chip.dart`, `money_row.dart`, `select_field.dart`, `avatar.dart`, `hero_net_card.dart`, `stat_tile.dart`, `ds.dart` (barrel)
- Test: `test/core/widgets/ds/ds_primitives_test.dart`

**Interfaces:**
- Consumes: `context.tokens` (Task 1).
- Produces: `BuildCard({child, pad, elevated, onClick})`; `BuildButton({label, variant: BuildButtonVariant, size: BuildButtonSize, icon, onPressed, full})` heights sm40/md50/lg56; `SegmentedToggle<T>({options: List<({T value, String label})>, value, onChanged})`; `BuildChip({label, icon, active, onTap})`; `MoneyRow({title, sub, amount, kind: MoneyKind, icon, last, onTap, currency='EGP'})`; `SelectField({label, valueLabel, icon, onTap})`; `Avatar({label, size})`; `HeroNetCard({net, income, expense, period, onPeriodChanged})`; `StatTile({icon, iconColor, label, value})`.

- [ ] Step 1: Write widget test: pump `MaterialApp(theme: AppTheme.light(Locale('en')))` with a `BuildButton(label:'Save', onPressed:(){})` inside a `Builder`; `expect(find.text('Save'), findsOneWidget)`. Pump `MoneyRow(kind: MoneyKind.income, amount:'120,000', title:'x')` → finds `+120,000`.
- [ ] Step 2: Run — FAIL.
- [ ] Step 3: Implement each primitive token-driven (colors/radii/shadows from `context.tokens`), matching primitives.jsx geometry. Barrel `ds.dart` exports all.
- [ ] Step 4: Run test — PASS.
- [ ] Step 5: `flutter analyze lib/core/widgets/ds` clean. Commit `feat(ds): token-driven v2 primitive widgets`.

---

### Task 6: Restyle existing shared widgets to tokens

**Files:**
- Modify: `lib/core/widgets/metric_card.dart`, `usage_card.dart`, `attachment_tile.dart`, `app_search_field.dart`, `section_header.dart`, `active_filter_bar.dart`
- Test: reuse existing widget tests touching these.

- [ ] Step 1: Replace hardcoded `Colors.white`/`AppColors.textDark`/literal greys in each with `context.tokens.*` (surface, text, border, textMuted). Keep public APIs unchanged.
- [ ] Step 2: Run `flutter test test/widget` — fix any snapshot/color assertions that changed.
- [ ] Step 3: `flutter analyze` clean. Commit `refactor(widgets): route shared widgets through BuildTokens (dark-aware)`.

---

### Task 7: Custom raised-FAB 5-tab bottom nav + 4-branch shell

**Files:**
- Create: `lib/core/widgets/build_bottom_nav.dart`
- Modify: `lib/core/widgets/app_bottom_nav_shell.dart`, `lib/app/router.dart`, `lib/core/constants/app_routes.dart`
- Test: `test/widget/bottom_nav_test.dart`

**Interfaces:**
- Consumes: `context.tokens`, existing `_showAddMenu` (restyled), `AppRoutes.activity`, `AppRoutes.more`.
- Produces: `BuildBottomNav({currentIndex, onSelect(int), onAdd()})` with 5 slots `home·projects·(+)·activity·more`, center raised FAB (index 2 = add), fill-on-active icons, upward shadow; `AppRoutes.activity='/activity'`, `AppRoutes.more='/more'`.

- [ ] Step 1: Write test: pump shell, `expect(find.byKey(Key('qa_nav_activity')), findsOneWidget)`; tap center FAB key `qa_nav_add` → Add sheet (`find.text` expense) appears.
- [ ] Step 2: Run — FAIL.
- [ ] Step 3: Add routes `activity`, `more`. Extend `StatefulShellRoute.indexedStack` branches to `[dashboard, projects, activity, more]`. Build `BuildBottomNav`; map branch index↔nav slot (skip center). Restyle `_showAddMenu` to v2 sheet (expense/payment cards + voice CTA) using DS primitives. Preserve offline banner + `PopScope`.
- [ ] Step 4: Run test — PASS.
- [ ] Step 5: `flutter analyze` clean. Commit `feat(nav): custom raised-FAB 5-tab shell + Activity/More branches`.

---

### Task 8: Activity screen

**Files:**
- Create: `lib/features/activity/presentation/screens/activity_screen.dart`
- Modify: `lib/app/router.dart` (wire branch builder)
- Test: `test/widget/activity_screen_test.dart`

**Interfaces:**
- Consumes: existing transaction/aggregation providers (reuse whatever feeds dashboard "recent"; if none list-wide, aggregate expenses+payments providers), DS `MoneyRow`, `BuildChip`, `app_search_field`.
- Produces: `ActivityScreen` — title, search field, All/Income/Expenses filter chips, filtered `MoneyRow` list, empty state.

- [ ] Step 1: Write test: pump `ActivityScreen` with overridden providers returning 1 income + 1 expense; default shows both; tap `Income` chip → only income row.
- [ ] Step 2: Run — FAIL.
- [ ] Step 3: Implement screen; wire into the Activity branch in `router.dart`.
- [ ] Step 4: Run test — PASS.
- [ ] Step 5: `flutter analyze` clean. Commit `feat(activity): searchable/filterable Activity screen`.

---

### Task 9: More screen

**Files:**
- Create: `lib/features/settings/presentation/screens/more_screen.dart`
- Modify: `lib/app/router.dart` (More branch)
- Test: `test/widget/more_screen_test.dart`

**Interfaces:**
- Consumes: `themeControllerProvider`, `localeControllerProvider`, DS primitives, existing settings/profile/resources routes.
- Produces: `MoreScreen` — profile header, Upgrade-to-Pro accent card, Resources row, Appearance card (dark toggle + EN/ع segmented), Account/Team/Plan/Settings rows.

- [ ] Step 1: Write test: pump `MoreScreen`; toggling dark switch calls `setThemeMode(dark)` (verify state via container read); EN/ع segmented calls `setLocale`.
- [ ] Step 2: Run — FAIL.
- [ ] Step 3: Implement; wire More branch.
- [ ] Step 4: Run test — PASS.
- [ ] Step 5: `flutter analyze` clean. Commit `feat(more): More screen with appearance + language controls`.

---

### Task 10: Home (dashboard) restyle

**Files:**
- Modify: `lib/features/dashboard/presentation/screens/dashboard_screen.dart`
- Test: existing `test/widget/dashboard_screen_test.dart`

**Interfaces:**
- Consumes: DS `HeroNetCard`, `StatTile`, `MoneyRow`, `BuildChip`, `Avatar`; existing dashboard providers; workspace switcher sheet (new inline widget or `WorkspaceSheet`).

- [ ] Step 1: Restyle to: greeting + workspace switcher button, scope pill, `HeroNetCard` (net + income/expense split + week/month segmented), two `StatTile`s (active projects, budget health), Recent `MoneyRow`s w/ See all → Activity, Quick-add chips → Add flows. Keep data providers.
- [ ] Step 2: Update `dashboard_screen_test.dart` for new structure; run — PASS.
- [ ] Step 3: `flutter analyze` clean. Commit `feat(home): v2 dashboard restyle`.

---

### Task 11: Projects + ProjectDetail restyle

**Files:**
- Modify: `lib/features/projects/presentation/screens/projects_screen.dart`, `project_detail_screen.dart`
- Test: existing project widget/data tests.

- [ ] Step 1: Projects → card list: icon badge, name, workers·on-site, net (+/−), budget `Progress` (over→expense color). Detail → hero net card + funds-in/spent split + budget bar + recent `MoneyRow`s. Reuse DS primitives; keep providers/actions.
- [ ] Step 2: Run related tests — fix/pass.
- [ ] Step 3: `flutter analyze` clean. Commit `feat(projects): v2 projects + detail restyle`.

---

### Task 12: Add Expense / Add Payment restyle

**Files:**
- Modify: `lib/features/expenses/presentation/screens/add_expense_screen.dart`, `lib/features/payments/presentation/screens/add_payment_screen.dart`
- Test: existing add-flow widget tests if present.

- [ ] Step 1: Restyle to: big centered amount (income green for payment), `SelectField`s (project/category/method), supplier/notes `BuildTextField`, 56px primary Save. Keep form controllers, validation, thousands formatter, submit logic.
- [ ] Step 2: Run tests — pass.
- [ ] Step 3: `flutter analyze` clean. Commit `feat(entry): v2 add expense/payment restyle`.

---

### Task 13: Voice flow restyle

**Files:**
- Modify: `lib/features/expenses/presentation/screens/voice_expense_screen.dart` and/or `lib/features/voice_expense/presentation/screens/voice_review_screen.dart`
- Test: existing voice tests.

- [ ] Step 1: Restyle to 3-stage layout: idle (record prompt + big mic), listening (pulsing mic ring via `AnimatedContainer`/box-shadow), review (transcript card + parsed fields list + Confirm & save). Keep controller/state machine + pipeline logic.
- [ ] Step 2: Run voice tests — pass.
- [ ] Step 3: `flutter analyze` clean. Commit `feat(voice): v2 voice capture/review restyle`.

---

### Task 14: Login + Notifications + Profile + Workspace/Resources restyle

**Files:**
- Modify: `lib/features/auth/presentation/screens/login_screen.dart`, `lib/features/notifications/presentation/screens/notifications_screen.dart`, `lib/features/settings/presentation/screens/profile_edit_screen.dart`, `workspace_settings_screen.dart`, `lib/features/entities/presentation/screens/resource_directory_screen.dart`
- Test: existing widget tests (`settings_screen_test.dart`, etc.).

- [ ] Step 1: Login → orange rounded-square logo, 900-weight headline, `welcomeSub`, Google outline button. Notifications → grouped (This week/Earlier) token cards + unread dot + Mark all read. Profile/Workspace/Resources → token cards + rows/avatars. Keep all logic/providers.
- [ ] Step 2: Run tests — pass.
- [ ] Step 3: `flutter analyze` clean. Commit `feat(screens): v2 restyle login/notifications/profile/workspace/resources`.

---

### Task 15: Dark-mode sweep + full suite gate

**Files:**
- Modify: any high-traffic screen still using hardcoded `Colors.white`/`AppColors.textDark` (from Tasks 10–14 scope).
- Test: `test/widget/dark_mode_smoke_test.dart` (new) + full suite.

- [ ] Step 1: Add smoke test: pump `MaterialApp(theme: AppTheme.light, darkTheme: AppTheme.dark, themeMode: dark)` wrapping Home, Projects, Activity, More, Add, Login — each renders without exception.
- [ ] Step 2: Grep primary screens for `Colors.white`, `Color(0xFF0F172A)`, literal greys; replace with `context.tokens.*`. Flag (in commit body) any deep secondary screen intentionally left theme-inherited.
- [ ] Step 3: Run `flutter analyze` (clean) + `flutter test` (green).
- [ ] Step 4: Commit `feat(theme): dark-mode sweep of primary screens + smoke test`.

---

## Self-Review

- **Spec coverage:** Tokens(T1) · palette+dark theme(T2) · ThemeController(T3) · i18n(T4) · primitives(T5) · shared-widget restyle(T6) · nav IA(T7) · Activity(T8) · More(T9) · Home(T10) · Projects(T11) · Add(T12) · Voice(T13) · Login/Notif/Profile/Workspace/Resources(T14) · dark sweep+testing(T15). All spec §1–9 mapped.
- **Placeholders:** none — each task names exact files, interfaces, commits.
- **Type consistency:** `context.tokens`, `BuildTokens`, `MoneyKind`, `BuildButtonVariant/Size`, `themeControllerProvider`, `AppRoutes.activity/more` used consistently across tasks.
- **Persistence:** Hive `app_prefs` (not SharedPreferences) — consistent with LocaleController.
