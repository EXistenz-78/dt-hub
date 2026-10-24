// swift-tools-version: 6.2
import PackageDescription

// The Prompt Master F3 plug-in of DT Hub (docs/superpowers/specs/2026-10-20-plugin-prompt-master-f3-design.md).
let package = Package(
  name: "PromptMasterF3",
  platforms: [.macOS(.v26)],
  products: [.library(name: "PromptMasterF3", type: .dynamic, targets: ["PromptMasterF3"])],
  dependencies: [.package(name: "PluginKit", path: "../../PluginKit")],
  targets: [
    // Like every plug-in it carries its own copy of the kit and of the design system, under names of its own.
    .target(
      name: "PromptMasterF3",
      dependencies: [
        .product(name: "DTHubPluginKit", package: "PluginKit", moduleAliases: ["DTHubPluginKit": "PromptMasterF3Kit"]),
        .product(name: "DTHubDesign", package: "PluginKit", moduleAliases: ["DTHubDesign": "PromptMasterF3Design"]),
      ]),
    .testTarget(name: "PromptMasterF3Tests", dependencies: ["PromptMasterF3"], exclude: ["Fixtures"]),
  ]
)
