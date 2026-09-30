// swift-tools-version: 6.2
import PackageDescription

// One package, one target per module: the compiler enforces the dependency
// rules of spec §4 (a target can only import what it declares).
let package = Package(
  name: "DTHubPackages",
  defaultLocalization: "en",
  platforms: [.macOS(.v26)],
  products: [
    .library(name: "HubKit", targets: ["HubKit"]),
    .library(name: "HubCore", targets: ["HubCore"]),
  ],
  targets: [
    .target(name: "HubKit"),
    .target(name: "HubCore", dependencies: ["HubKit"]),
    .testTarget(name: "HubKitTests", dependencies: ["HubKit"]),
    .testTarget(name: "HubCoreTests", dependencies: ["HubCore", "HubKit"]),
    // Checks App/Localizable.xcstrings: every string translated in en and it (spec §12).
    .testTarget(name: "CatalogTests"),
  ]
)
