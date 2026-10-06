// swift-tools-version: 6.2
import PackageDescription

// The Prompt Master I4 plug-in of DT Hub (docs/superpowers/specs/2026-10-06-plugin-prompt-master-i4-design.md).
let package = Package(
  name: "PromptMasterI4",
  platforms: [.macOS(.v26)],
  products: [.library(name: "PromptMasterI4", type: .dynamic, targets: ["PromptMasterI4"])],
  dependencies: [.package(name: "PluginKit", path: "../../PluginKit")],
  targets: [
    // Like every plug-in it carries its own copy of the kit and of the design system, under names of its own.
    .target(
      name: "PromptMasterI4",
      dependencies: [
        .product(name: "DTHubPluginKit", package: "PluginKit", moduleAliases: ["DTHubPluginKit": "PromptMasterI4Kit"]),
        .product(name: "DTHubDesign", package: "PluginKit", moduleAliases: ["DTHubDesign": "PromptMasterI4Design"]),
      ]),
    .testTarget(name: "PromptMasterI4Tests", dependencies: ["PromptMasterI4"]),
  ]
)
