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
    .library(name: "DTBridge", targets: ["DTBridge"]),
  ],
  dependencies: [
    // Single maintainer, frequent releases: accept patch updates only (spec §5, §16).
    .package(
      url: "https://github.com/euphoriacyberware-ai/DrawThings-Swift.git",
      .upToNextMinor(from: "2.2.0")),
  ],
  targets: [
    .target(name: "HubKit"),
    .target(name: "HubCore", dependencies: ["HubKit"]),
    // The only module that knows DrawThings-Swift and gRPC (spec §4).
    .target(
      name: "DTBridge",
      dependencies: ["HubKit", .product(name: "DrawThingsClient", package: "DrawThings-Swift")]),
    .testTarget(name: "HubKitTests", dependencies: ["HubKit"]),
    .testTarget(name: "HubCoreTests", dependencies: ["HubCore", "HubKit"]),
    .testTarget(name: "DTBridgeTests", dependencies: ["DTBridge", "HubKit"]),
    // Checks App/Localizable.xcstrings: every string translated in en and it (spec §12).
    .testTarget(name: "CatalogTests"),
  ]
)
