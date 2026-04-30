// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "RevenueCatCommerceKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "RevenueCatCommerceKit",
            targets: ["RevenueCatCommerceKit"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/RevenueCat/purchases-ios-spm.git",
            exact: "5.67.0"
        )
    ],
    targets: [
        .target(
            name: "RevenueCatCommerceKit",
            dependencies: [
                .product(name: "RevenueCat", package: "purchases-ios-spm")
            ]
        ),
        .testTarget(
            name: "RevenueCatCommerceKitTests",
            dependencies: [
                "RevenueCatCommerceKit",
                .product(name: "RevenueCat", package: "purchases-ios-spm")
            ]
        )
    ]
)
