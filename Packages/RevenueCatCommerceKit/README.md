# RevenueCatCommerceKit

`RevenueCatCommerceKit` is the reusable purchase boundary for apps that use a fixed Pro entitlement with yearly and lifetime products.

The kit directly depends on the RevenueCat SDK. Host apps should depend on this kit instead of importing RevenueCat in product state, views, or feature code.

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

- `requestTimeoutNanoseconds`
- `invalidReceiptRecoveryDelayNanoseconds`
- `allowsTestAPIKeyInRelease`
- `showStoreMessagesAutomatically`
- `logSubsystem`
- `logCategory`

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
