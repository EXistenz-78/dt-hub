// swift-tools-version: 6.2
import PackageDescription

// The Prompt Master MOSS plug-in of DT Hub (docs/superpowers/specs/2026-10-23-plugin-prompt-master-moss-design.md).
let package = Package(
  name: "PromptMasterMOSS",
  platforms: [.macOS(.v26)],
  products: [.library(name: "PromptMasterMOSS", type: .dynamic, targets: ["PromptMasterMOSS"])],
  dependencies: [.package(name: "PluginKit", path: "../../PluginKit")],
  targets: [
    // Like every plug-in it carries its own copy of the kit and of the design system, under names of its own.
    .target(
      name: "PromptMasterMOSS",
      dependencies: [
        .product(name: "DTHubPluginKit", package: "PluginKit", moduleAliases: ["DTHubPluginKit": "PromptMasterMOSSKit"]),
        .product(name: "DTHubDesign", package: "PluginKit", moduleAliases: ["DTHubDesign": "PromptMasterMOSSDesign"]),
      ]),
    .testTarget(name: "PromptMasterMOSSTests", dependencies: ["PromptMasterMOSS"], resources: [.copy("Fixtures")]),
  ]
)
