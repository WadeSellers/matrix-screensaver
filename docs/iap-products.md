# In-App Purchases — Tip Jar

Falling Code ships three Consumable IAPs that appear in **Preferences →
Support**. They are pure "support the developer" tips — nothing in the app
unlocks. Users can purchase each tier as many times as they like.

## Product Catalog

| Product ID | Display Name | Price | Type |
| --- | --- | --- | --- |
| `com.wadesellers.cipherfall.tip.coffee` | Buy me a coffee | $2.99 | Consumable |
| `com.wadesellers.cipherfall.tip.lunch` | Buy me lunch | $9.99 | Consumable |
| `com.wadesellers.cipherfall.tip.awesome` | You're awesome | $19.99 | Consumable |

The bundle ID is `com.wadesellers.cipherfall` (legacy from the Cipherfall
rebrand) — all product IDs inherit that prefix. Apple binds App Store
records permanently to the Bundle ID, so even though the app's user-facing
name is "Falling Code", the IDs cannot change.

## Why Consumable, not Non-Consumable

- Users can re-tip the same tier as many times as they want. Non-Consumables
  can only be purchased once per Apple ID.
- Apple only mandates a "Restore Purchases" button for Non-Consumables and
  Auto-Renewable Subscriptions. Skipping it keeps the Support tab visually
  clean.
- The tip jar gates no functionality. There's nothing to "own."

## Configuration

### App Store Connect

For each product:
- **Reference name** (internal, never shown): `Tip — Coffee`, `Tip — Lunch`,
  `Tip — Awesome`
- **Display Name** (shown in purchase sheet): the column above
- **Description** (shown in purchase sheet): "A small tip to support Falling
  Code's development. Nothing in the app changes — just gratitude." (adjust
  "small" / "larger" / "generous" per tier as desired)
- **Price**: the column above. Apple sets equivalent prices in other
  currencies automatically.
- **Cleared for Sale**: Yes
- **Review screenshot**: a screenshot of the Support tab with the three
  cards visible

### Local Dev / Xcode

A `Configuration.storekit` file lives at the repo root. To test the full
purchase flow inside Xcode without needing a sandbox Apple ID:

1. Open the project in Xcode.
2. Edit Scheme → Run → Options → **StoreKit Configuration** → select
   `Configuration.storekit`.
3. Build & run. Tapping any tip card now opens a synthetic Apple purchase
   sheet you can complete instantly. No real money is moved.

The file's product IDs are kept in lockstep with this doc and with
`TipJarManager.productIDs` in code. If you change one, change all three.

## Code references

- `MatrixApp/TipJarManager.swift` — the `productIDs` array is the source of
  truth in code.
- `MatrixApp/SupportView.swift` — UI; per-tier emoji is assigned by index
  (`☕`, `🍕`, `❤️`), so the display order is determined by ascending price
  order from `Product.products(for:)`.

## Apple's cut

Default: **30%**. Under the Small Business Program (Wade applied for it on
launch day): **15%**. Verify the SBP enrollment in App Store Connect →
Business → Agreements before each fiscal year.
