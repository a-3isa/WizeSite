# RevenueCat Setup (Flutter + WizeSite)

This project now includes a live RevenueCat integration with:
- SDK init and app user linking
- offering/package loading
- purchase + restore
- entitlement check for `WizeSite Pro`
- paywall presentation
- customer center presentation
- customer info retrieval in app

## 1) Pub dependencies

Already added in `pubspec.yaml`:

- `purchases_flutter`
- `purchases_ui_flutter`

If needed:

```bash
flutter pub add purchases_flutter purchases_ui_flutter
```

## 2) Configure SDK key

Current code uses:

- `REVENUECAT_API_KEY` from `--dart-define`
- fallback key: `test_xrxXJcTowFByLKxcgDhWpeEmBir`

Recommended run command:

```bash
flutter run --dart-define=REVENUECAT_API_KEY=test_xrxXJcTowFByLKxcgDhWpeEmBir --dart-define=REVENUECAT_ENTITLEMENT_ID=wizesite_pro
```

## 3) RevenueCat dashboard configuration

Create these in RevenueCat:

1. Entitlement:
- ID: `wizesite_pro`
- Display name: `WizeSite Pro`

2. Products (linked to App Store / Play Console):
- `monthly`
- `yearly`
- `lifetime`

3. Offering:
- Create `default` offering.
- Add packages:
  - Monthly package -> product `monthly` (`$rc_monthly` or custom package)
  - Annual package -> product `yearly` (`$rc_annual` or custom package)
  - Lifetime package -> product `lifetime` (`$rc_lifetime` or custom package)

4. Paywall:
- Attach paywall to the `default` offering.
- Publish it.

5. Customer Center:
- Enable Customer Center in RevenueCat dashboard.
- Configure support links and actions.

## 4) Where implementation lives

- `lib/features/subscription/data/revenuecat_purchase_coordinator.dart`
  - `configure()` links user/workspace and sets attributes.
  - `getPackages()` fetches offerings.
  - `purchase()` / `restore()` handle transactions with error mapping.
  - `getCustomerInfo()` and `watchCustomerInfo()` expose customer state.
  - `presentPaywallIfNeeded()` uses RevenueCat paywall UI.
  - `presentCustomerCenter()` opens Customer Center.

- `lib/features/subscription/presentation/screens/plans_screen.dart`
  - Added RevenueCat paywall CTA.
  - Added monthly/yearly/lifetime plan rendering.

- `lib/features/subscription/presentation/screens/manage_subscription_screen.dart`
  - Shows customer info.
  - Adds Customer Center button.
  - Keeps restore action.

- `lib/features/subscription/presentation/screens/limit_reached_screen.dart`
  - Upgrade flow now attempts paywall directly.
  - Falls back to plans route if paywall is unsupported.

## 5) Entitlement check used in app

`WizeSite Pro` entitlement check is done in coordinator by:

- exact entitlement ID (`wizesite_pro` by default),
- safe normalization fallback (`wizesitepro`, keys containing `pro`).

## 6) Error handling behavior

- Purchase cancelled -> treated as non-fatal user cancellation.
- Purchase/restore platform errors -> raised with explicit reason.
- Paywall errors -> handled and surfaced as UI message.
- Unsupported platform -> returns `notSupported` and uses route fallback.

## 7) Best-practice notes

- Keep RevenueCat key in `--dart-define` for release builds.
- Keep entitlement ID stable: `wizesite_pro`.
- Keep all purchase/restore/paywall logic centralized in coordinator.
- Do not gate UI modules directly; use entitlement + quota checks at action level.
- Keep webhook/backend entitlements as server source of truth for quota enforcement.

