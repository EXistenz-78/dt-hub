// swift-tools-version: 6.2
import PackageDescription

// The Prompt Master plug-in of DT Hub (docs/superpowers/specs/2026-10-05-plugin-prompt-master-design.md).
let package = Package(
  name: "PromptMaster",
  platforms: [.macOS(.v26)],
  products: [.library(name: "PromptMaster", type: .dynamic, targets: ["PromptMaster"])],
  dependencies: [.package(name: "PluginKit", path: "../../PluginKit")],
  targets: [
    // Like every plug-in it carries its own copy of the kit and of the design system, under names of its own.
    .target(
      name: "PromptMaster",
      dependencies: [
        .product(name: "DTHubPluginKit", package: "PluginKit", moduleAliases: ["DTHubPluginKit": "PromptMasterKit"]),
        .product(name: "DTHubDesign", package: "PluginKit", moduleAliases: ["DTHubDesign": "PromptMasterDesign"]),
      ]),
    .testTarget(name: "PromptMasterTests", dependencies: ["PromptMaster"]),
  ]
)
