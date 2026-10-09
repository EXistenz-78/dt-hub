// swift-tools-version: 6.2
import PackageDescription

// The Batch plus plug-in of DT Hub (docs/superpowers/specs/2026-10-09-plugin-batch-plus-design.md).
let package = Package(
  name: "BatchPlus",
  platforms: [.macOS(.v26)],
  products: [.library(name: "BatchPlus", type: .dynamic, targets: ["BatchPlus"])],
  dependencies: [.package(name: "PluginKit", path: "../../PluginKit")],
  targets: [
    // Every plug-in carries its own copy of the kit and of the design system; `moduleAliases` gives them
    // names of their own, so two plug-ins (and the app) do not define the same classes twice in one process.
    .target(
      name: "BatchPlus",
      dependencies: [
        .product(name: "DTHubPluginKit", package: "PluginKit", moduleAliases: ["DTHubPluginKit": "BatchPlusKit"]),
        .product(name: "DTHubDesign", package: "PluginKit", moduleAliases: ["DTHubDesign": "BatchPlusDesign"]),
      ]),
    .testTarget(name: "BatchPlusTests", dependencies: ["BatchPlus"]),
  ]
)
