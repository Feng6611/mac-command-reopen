# RevenueCatCommerceKit

`RevenueCatCommerceKit` is the reusable purchase boundary for apps that use a fixed Pro entitlement with yearly and lifetime products.

The kit directly depends on the RevenueCat SDK. Host apps should depend on this kit instead of importing RevenueCat in product state, views, or feature code.

This is intentionally not a general-purpose commerce framework. It fits apps with:

- one semantic Pro entitlement
- one yearly subscription product
- one lifetime non-consumable product
- host-owned trial, paywall copy, and feature locking

If an app needs monthly plans, team tiers, consumables, multiple entitlements, or account-based server authorization, treat this package as a starting point rather than a drop-in abstraction.

## What This Kit Owns

- RevenueCat SDK configuration
- current/default offering loading
- yearly and lifetime package lookup
- entitlement refresh
- purchase
- restore purchases
- RevenueCat delegate updates
- RevenueCat error mapping
- request timeouts
- invalid receipt recovery by refreshing entitlement, then restoring purchases

## What Host Apps Still Own

- trial policy
- onboarding
- feature locking
- paywall presentation
- "expired" prompting
- grandfathering from a paid download app to IAP
- direct vs App Store build behavior
- pricing copy, badges, and app-specific text

RevenueCat is the purchase and entitlement source of truth. The host app decides how that entitlement affects the product.

## Install

Add this package to the app target:

```swift
.package(path: "Packages/RevenueCatCommerceKit")
```

Or reference it from another repository once extracted:

```swift
.package(url: "https://github.com/your-org/RevenueCatCommerceKit.git", from: "1.0.0")
```

The package pulls RevenueCat through Swift Package Manager:

```swift
.package(url: "https://github.com/RevenueCat/purchases-ios-spm.git", exact: "5.67.0")
```

## Recommended RevenueCat Shape

Use the same semantic model across apps:

- entitlement: `pro`
- offering: `default`
- yearly product: `{bundleIdentifier}.pro.yearly`
- lifetime product: `{bundleIdentifier}.pro.lifetime`

RevenueCat entitlement IDs can be shared semantically across apps, but Apple IAP product IDs usually need to be unique per App Store app. Prefer a fixed naming rule over literally sharing one SKU.

## SKU And Entitlement Strategy

The kit treats RevenueCat entitlement state as the source of truth. Products, packages, and prices are purchase entry points; the entitlement decides whether the user has access.

This keeps simple setups easy to manage:

- one Pro entitlement can be granted by yearly, lifetime, promotional, or migrated products
- a lifetime purchase can have multiple price points or packages in RevenueCat
- host apps do not need to ship a new build just to change the current price package

By default, `CommerceConfiguration` uses `.allowAnyActiveEntitlement`. That means if the configured entitlement id or configured product ids drift, any active RevenueCat entitlement can still unlock access. This is useful when a project intentionally models access as "any active RevenueCat entitlement means Pro."

For stricter apps, use `.configuredEntitlementOrProductOnly`:

```swift
let commerce = RevenueCatCommerceClient(
    configuration: CommerceConfiguration(
        apiKey: revenueCatAPIKey,
        entitlementIdentifier: "pro",
        productIdentifiers: [
            .yearly: "com.example.myapp.pro.yearly",
            .lifetime: "com.example.myapp.pro.lifetime"
        ],
        entitlementMatchingPolicy: .configuredEntitlementOrProductOnly
    )
)
```

Use the strict policy when one RevenueCat project contains unrelated entitlements and the app must only trust its configured entitlement or configured product ids.

## Offering Strategy

The kit prefers RevenueCat's current offering when that offering contains at least one configured product identifier. If the current offering does not contain this app's yearly or lifetime product, the kit falls back to `offeringIdentifier`.

This matches the recommended operational flow: manage active packages, price tests, and limited-time price points in RevenueCat, while keeping the app focused on semantic plans and entitlement access.

For example, a project can offer two lifetime prices by configuring both packages in RevenueCat and making the desired package part of the current offering. Both products should grant the same Pro entitlement, so entitlement refresh and restore stay simple.

The configured-offering fallback is important when a shared RevenueCat project has a global current offering that belongs to another app or experiment. In that case, this kit will still try the host app's configured offering before reporting no products.

## Configure

Read the public RevenueCat SDK key from the app Info.plist or build settings:

```swift
import RevenueCatCommerceKit

let commerce = RevenueCatCommerceClient(
    configuration: .standardProFromInfoDictionary(
        apiKeyInfoDictionaryKey: "MyAppRevenueCatAPIKey",
        entitlementIdentifier: "pro"
    )
)
```

`standardProFromInfoDictionary` uses `Bundle.main.bundleIdentifier` to infer product IDs:

```text
{bundleIdentifier}.pro.yearly
{bundleIdentifier}.pro.lifetime
```

For apps that need explicit SKU values:

```swift
let commerce = RevenueCatCommerceClient(
    configuration: CommerceConfiguration(
        apiKey: revenueCatAPIKey,
        entitlementIdentifier: "pro",
        offeringIdentifier: "default",
        productIdentifiers: [
            .yearly: "com.example.myapp.pro.yearly",
            .lifetime: "com.example.myapp.pro.lifetime"
        ]
    )
)
```

Advanced configuration is centralized in `CommerceConfiguration`:

- `entitlementMatchingPolicy`
- `requestTimeoutNanoseconds`
- `invalidReceiptRecoveryDelayNanoseconds`
- `allowsTestAPIKeyInRelease`
- `showStoreMessagesAutomatically`
- `logSubsystem`
- `logCategory`

## Host App Checklist

Before reusing the package in another app:

- Create the yearly and lifetime in-app purchase products in App Store Connect.
- Create or reuse the RevenueCat entitlement, usually `pro`.
- Add both products to RevenueCat and make sure both grant the Pro entitlement.
- Create an offering, usually `default`, containing the packages the app should sell.
- Decide whether the app trusts any active entitlement with `.allowAnyActiveEntitlement` or only configured identifiers with `.configuredEntitlementOrProductOnly`.
- Add the public RevenueCat SDK key to the host app's Info.plist or build settings.
- Call `configureIfNeeded()` during purchase-state startup before reading cached entitlement state.
- Call `refreshEntitlement()` on app activation or purchase-state refresh.
- Load offerings only when presenting purchase UI; feature access should be based on entitlement, not product availability.
- Keep trial policy, expired prompts, onboarding, and paywall text in the host app.

For local sandbox testing, use a non-empty RevenueCat SDK key, a sandbox App Store account, and products that are approved or available for StoreKit testing. Verify purchase, cancellation, restore, no-purchase restore, offline refresh behavior, and the first-launch trial path in the host app.

## Minimal Host App Usage

```swift
@MainActor
final class AppPurchaseState: ObservableObject {
    enum AccessState {
        case trial
        case expired
        case pro
    }

    @Published private(set) var accessState: AccessState = .trial
    @Published private(set) var products: [CommerceProduct] = []

    private let commerce: CommerceClient
    private let trialStore: TrialStore

    init(commerce: CommerceClient, trialStore: TrialStore) {
        self.commerce = commerce
        self.trialStore = trialStore

        self.commerce.entitlementDidChange = { [weak self] entitlement in
            self?.apply(entitlement: entitlement)
        }
    }

    func configure() {
        commerce.configureIfNeeded()
        apply(entitlement: commerce.cachedEntitlement)
    }

    func refresh() async {
        do {
            let entitlement = try await commerce.refreshEntitlement()
            apply(entitlement: entitlement)
        } catch {
            // Decide host behavior. For example, keep trial open on network errors.
        }
    }

    func loadProducts() async {
        products = (try? await commerce.loadOffering()?.products) ?? []
    }

    func purchase(_ plan: CommercePlan) async throws {
        let entitlement = try await commerce.purchase(plan)
        apply(entitlement: entitlement)
    }

    func restorePurchases() async throws {
        let entitlement = try await commerce.restorePurchases()
        apply(entitlement: entitlement)
    }

    private func apply(entitlement: CommerceEntitlement?) {
        if entitlement != nil {
            accessState = .pro
        } else if trialStore.isTrialActive {
            accessState = .trial
        } else {
            accessState = .expired
        }
    }
}
```

## ComTab Integration Pattern

ComTab should keep its product-specific layer:

- `ProStatusManager`
- local two-day trial
- paid-download grandfathering
- onboarding behavior
- expired prompt routing

Only the RevenueCat SDK adapter should move behind `CommerceClient`.

The intended dependency direction is:

```text
ComTab product state -> CommerceClient protocol -> RevenueCatCommerceKit -> RevenueCat SDK
```

Views and feature code should not import RevenueCat.

## Testing Boundary

`CommerceClient` is the public boundary for host app tests. Inside this package, `RevenueCatCommerceClient` also routes SDK calls through an internal adapter so package tests can inject fake offerings, customer info, purchases, and restores without touching `Purchases.shared`.
