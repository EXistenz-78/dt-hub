// swift-tools-version: 6.2
import PackageDescription

// The Flux3 Editing plug-in of DT Hub (docs/superpowers/specs/2026-10-22-plugin-flux3-editing-design.md).
let package = Package(
  name: "Flux3Editing",
  platforms: [.macOS(.v26)],
  products: [.library(name: "Flux3Editing", type: .dynamic, targets: ["Flux3Editing"])],
  dependencies: [.package(name: "PluginKit", path: "../../PluginKit")],
  targets: [
    // Like every plug-in it carries its own copy of the kit and of the design system, under names of its own.
    .target(
      name: "Flux3Editing",
      dependencies: [
        .product(name: "DTHubPluginKit", package: "PluginKit", moduleAliases: ["DTHubPluginKit": "Flux3EditingKit"]),
        .product(name: "DTHubDesign", package: "PluginKit", moduleAliases: ["DTHubDesign": "Flux3EditingDesign"]),
      ]),
    .testTarget(name: "Flux3EditingTests", dependencies: ["Flux3Editing"], exclude: ["Fixtures"]),
  ]
)
