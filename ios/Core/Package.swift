// swift-tools-version:6.0
//
// KCNA26Core: the iOS app's platform-independent code (data, schedule rules, routing, sync,
// reminders planning, view models). Foundation and Observation only, so it builds and its
// tests run on macOS and on Linux:
//
//     cd ios/Core && swift test
//
// The Xcode app target compiles these same sources (Sources/KCNA26Core) straight into the app
// module, so nothing here needs to be `public`; the tests use `@testable import KCNA26Core`.
import PackageDescription

let package = Package(
    name: "KCNA26Core",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "KCNA26Core", targets: ["KCNA26Core"]),
    ],
    targets: [
        .target(name: "KCNA26Core"),
        .testTarget(name: "KCNA26CoreTests", dependencies: ["KCNA26Core"]),
    ]
)
