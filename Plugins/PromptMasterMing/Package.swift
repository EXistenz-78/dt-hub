// swift-tools-version: 6.2
import PackageDescription

// The Prompt Master Ming plug-in of DT Hub (docs/superpowers/specs/2026-11-24-plugin-prompt-master-ming-design.md).
let package = Package(
  name: "PromptMasterMing",
  platforms: [.macOS(.v26)],
  products: [.library(name: "PromptMasterMing", type: .dynamic, targets: ["PromptMasterMing"])],
  dependencies: [.package(name: "PluginKit", path: "../../PluginKit")],
  targets: [
    // Like every plug-in it carries its own copy of the kit and of the design system, under names of its own.
    .target(
      name: "PromptMasterMing",
      dependencies: [
        .product(name: "DTHubPluginKit", package: "PluginKit", moduleAliases: ["DTHubPluginKit": "PromptMasterMingKit"]),
        .product(name: "DTHubDesign", package: "PluginKit", moduleAliases: ["DTHubDesign": "PromptMasterMingDesign"]),
      ]),
    .testTarget(name: "PromptMasterMingTests", dependencies: ["PromptMasterMing"]),
  ]
)
