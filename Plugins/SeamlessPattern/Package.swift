// swift-tools-version: 6.2
import PackageDescription

// The Seamless Pattern plug-in of DT Hub (docs/superpowers/specs/2026-11-25-plugin-seamless-pattern-design.md).
let package = Package(
  name: "SeamlessPattern",
  platforms: [.macOS(.v26)],
  products: [.library(name: "SeamlessPattern", type: .dynamic, targets: ["SeamlessPattern"])],
  dependencies: [.package(name: "PluginKit", path: "../../PluginKit")],
  targets: [
    // Every plug-in carries its own copy of the kit and of the design system; `moduleAliases` gives them
    // names of their own, so two plug-ins (and the app) do not define the same classes twice in one process.
    .target(
      name: "SeamlessPattern",
      dependencies: [
        .product(name: "DTHubPluginKit", package: "PluginKit", moduleAliases: ["DTHubPluginKit": "SeamlessPatternKit"]),
        .product(name: "DTHubDesign", package: "PluginKit", moduleAliases: ["DTHubDesign": "SeamlessPatternDesign"]),
      ]),
    .testTarget(name: "SeamlessPatternTests", dependencies: ["SeamlessPattern"]),
  ]
)
