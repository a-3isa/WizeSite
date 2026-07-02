# Buildozer v2 Design System — Implementation Design

**Date:** 2026-07-02
**Branch:** 001-review-improvement-pack
**Source:** `Buildozer Design System.zip` → `ui_kits/redesign/` (theme.css, primitives.jsx, index.html, strings.jsx) + README.

## Goal

Adopt the "v2" redesign of the Buildozer (buildtrack_app) Flutter app: a calmer,
more spacious visual system with **dark mode**, a shifted brand palette, a
token-driven theme, a **5-tab bottom nav with a raised center FAB**, and
restyled screens matching the redesign UI-kit — implemented in one pass.

## Locked decisions

- **Scope:** Full v2 including new information architecture (not just a reskin).
- **Palette:** Adopt v2 values (see Tokens).
- **Delivery:** One-shot (single large commit at the end).
- **Bottom nav:** Custom raised-FAB nav (pixel-match the kit), not Material `NavigationBar`.
- **Dark mode default:** `ThemeMode.system` (user overrides in More).

## Tokens (v2 values)

Light theme (default):
- accent `#FF6D00`, accent-press `#E76100`, accent-soft `#FFF1E7`, on-accent `#FFFFFF`
- income `#12A150` / soft `#E7F6EE`; expense `#E5484D` / soft `#FDECEC`;
  warning `#F59E0B` / soft `#FEF3E2`
- bg `#F4F5F7`, surface `#FFFFFF`, surface-2 `#F1F3F6`, surface-3 `#E9ECF1`
- border `#E7EAEF`, border-strong `#D7DCE3`
- text `#141922`, text-muted `#67717F`, text-faint `#99A2AE`
- shadow-sm `0 1px 2px rgba(20,25,34,.05), 0 2px 6px rgba(20,25,34,.04)`
- shadow-md `0 4px 12px rgba(20,25,34,.07), 0 12px 28px rgba(20,25,34,.05)`
- shadow-nav `0 -4px 20px rgba(20,25,34,.06)`; scrim `rgba(20,25,34,.42)`

Dark theme:
- accent `#FF7D1F`, accent-press `#FF6D00`, accent-soft `rgba(255,125,31,.16)`, on-accent `#16130F`
- income `#35D08A` / soft `rgba(53,208,138,.15)`; expense `#FF6B6B` / soft `rgba(255,107,107,.15)`;
  warning `#FBBF24` / soft `rgba(251,191,36,.15)`
- bg `#0E1116`, surface `#171C23`, surface-2 `#1E242D`, surface-3 `#262D38`
- border `#262D38`, border-strong `#333C49`
- text `#EDF0F4`, text-muted `#949FAD`, text-faint `#6A7482`
- shadow-sm/md/nav dark variants; scrim `rgba(0,0,0,.6)`

Radii: `rSm 10 · rMd 14 · rLg 20 · rXl 26 · pill 999`.
Spacing rhythm: `gap 14 · cardPad 18 · sectionGap 22`.
Type: Inter (Latin) / Cairo (Arabic); heavy weights carry brand (values 800,
titles 700, login headline 900); tight negative letter-spacing on display.

## Architecture

### 1. Token layer — `lib/app/theme/build_tokens.dart`
`@immutable class BuildTokens extends ThemeExtension<BuildTokens>` with all
semantic color/shadow/spacing/radius fields above. Two consts: `BuildTokens.light`,
`BuildTokens.dark`. `lerp` implemented. Convenience getter
`context.tokens` via extension on `BuildContext`.

### 2. Colors — `lib/core/constants/app_colors.dart`
Update the static consts to v2 values in place (keeps ~40 direct references
working, they shift automatically). Keep legacy aliases. These remain the
*light* brand values; dark-specific values live only in `BuildTokens.dark`.

### 3. Theme — `lib/app/theme/app_theme.dart`
- Refresh `light(locale)` to v2 and register `extensions: [BuildTokens.light]`.
- Add `dark(locale)` mirroring it with `ColorScheme.dark` + `BuildTokens.dark`.
- Both keep Inter/Cairo via google_fonts, input focus = 2px accent, card radius `rLg`.

### 4. Theme controller — `lib/core/providers/theme_provider.dart`
Riverpod `StateNotifier<ThemeMode>` persisted in `SharedPreferences`
(key `theme_mode`), default `system`. Wire in `app.dart`:
`theme: AppTheme.light`, `darkTheme: AppTheme.dark`, `themeMode: watch`.

### 5. Primitives — `lib/core/widgets/ds/`
Token-driven: `BuildCard`, `BuildButton` (primary/soft/outline/ghost/danger ×
sm40/md50/lg56), `SegmentedToggle`, `BuildChip`, `MoneyRow`, `SelectField`,
`BuildTextField`, `Avatar`, `HeroNetCard`, `StatTile`. Restyle existing
`metric_card`, `usage_card`, `attachment_tile`, `app_search_field`,
`section_header` to tokens (dark-aware).

### 6. Navigation — `lib/core/widgets/app_bottom_nav_shell.dart` + `router.dart`
- Extend `StatefulShellRoute.indexedStack` from 2 → **4 branches**:
  Home (dashboard), Projects, **Activity** (new), **More** (new).
- Custom `BuildBottomNav` widget: 5 slots `home · projects · (+) · activity · more`,
  center raised orange FAB opens the Add sheet, active icons fill + accent color,
  upward nav shadow, `EdgeInsetsDirectional` for RTL. Preserve offline banner + `PopScope`.
- Add sheet restyled to v2: expense card (money out) + payment card (money in) +
  "record by voice" CTA. Reuse existing routes.

### 7. New screens
- **Activity** `lib/features/activity/presentation/screens/activity_screen.dart`:
  title, search field (reuse `app_search_field`), All/Income/Expenses filter chips,
  `MoneyRow` list fed by existing transaction/aggregation providers.
- **More** — a dedicated new screen `lib/features/settings/presentation/screens/more_screen.dart`
  used as the 4th nav branch (the existing full Settings screen stays reachable via a row here):
  profile header (Avatar + name/role), Upgrade-to-Pro accent card, Resources row,
  Appearance card (dark-mode toggle → ThemeController, EN/ع segmented → LocaleController),
  Account/Team/Plan rows. Links to existing settings/profile routes.

### 8. Screen restyle mapping (existing screens)
- **Dashboard → Home**: greeting + workspace switcher sheet, scope pill,
  `HeroNetCard`, two `StatTile`s, Recent `MoneyRow`s, Quick-add chips.
- **Projects / ProjectDetail**: card list w/ budget `Progress` + net; detail
  hero + funds-in/spent split + budget bar + recent.
- **Add Expense / Add Payment**: big centered amount, `SelectField`s
  (project/category/method), supplier/notes, 56px Save.
- **Voice**: idle → listening (pulsing mic) → review (transcript + parsed fields
  + Confirm). Restyle existing voice screen to 3-stage layout.
- **Login**: orange rounded-square logo, 900-weight headline, Google outline button.
- **Notifications / Profile / Resources / Workspace settings**: token cards + rows.

### 9. i18n — `lib/app/localization/app_localizations.dart`
Add EN + AR keys introduced by v2 (from strings.jsx): `activity`, `more`,
`netThisMonth`, `week`, `month`, `quickAdd`, `switchWorkspace`, `budgetUsed`,
`ofContract`, `appearance`, `darkMode`, `language`, `allProjects`, `fundsIn`,
`spent`, `budgetHealth`, `activeProjects`, `good`, `whatToAdd`, `expenseDesc`,
`paymentDesc`, `startVoice`, `markRead`, `thisWeek`, `earlier`, `memberSince`,
`role`, `upgradePro`, `proSub`, `seeAll`, `searchActivity`, etc. Only add keys
not already present.

## Data flow

No backend/model changes. All screens keep existing Riverpod providers and
Firestore repositories; this is a presentation-layer redesign. Activity screen
reuses existing transaction/aggregation providers; workspace switcher reuses
`workspaceProvider`; dark toggle + language use new/existing controllers.

## Error handling

Preserve existing error/empty/loading states (`async_content`, `app_async_state`,
`EmptyState`). Restyle them to tokens; no behavior change. Offline banner and
sync states preserved.

## Testing

- `BuildTokens.light`/`.dark` resolve + `lerp` unit test.
- `ThemeController` persistence test (default system, set dark, reload).
- Dark-mode smoke: pump app in dark, key screens render without exception.
- 5-tab nav renders; center FAB opens Add sheet; Activity filter chips switch.
- Update existing theme-dependent widget tests (`test/widget/*`) for new colors/nav.
- Gate: `flutter analyze` clean + `flutter test` green.

## Risks / non-goals

- **Long tail:** hardcoded `Colors.white` / `AppColors.textDark` inside deep detail
  screens won't auto-adapt to dark. High-traffic screens (home, projects, activity,
  more, add forms, voice, login, project detail) will be fully dark-correct; deep
  secondary screens get theme wiring and will be flagged if left partial.
- **Non-goals:** no data model, routing-contract, or Firebase changes; no new
  business features; no gradient/photography (kit forbids them).

## Success criteria

1. App builds; `flutter analyze` + `flutter test` green.
2. Dark/light both render; toggle in More persists across restart; defaults to system.
3. 5-tab nav with raised center FAB matches the kit; Add sheet + Activity + More work.
4. Primary screens visually match the redesign (colors, spacing, radii, primitives).
5. EN + AR both correct incl. RTL.
