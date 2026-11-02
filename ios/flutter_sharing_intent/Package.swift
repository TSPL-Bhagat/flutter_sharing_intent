// swift-tools-version: 5.9
// Flutter looks for the manifest at ios/<plugin_name>/Package.swift.

import PackageDescription

let package = Package(
    name: "flutter_sharing_intent",
    platforms: [
        .iOS("12.0"),
    ],
    products: [
        .library(name: "flutter-sharing-intent", targets: ["flutter_sharing_intent"]),
    ],
    targets: [
        .target(
            name: "flutter_sharing_intent",
            // Tools version 5.9 builds in Swift 5 language mode, so no Swift 6 strict concurrency.
            resources: [
                .process("PrivacyInfo.xcprivacy"),
            ]
        ),
    ]
)
