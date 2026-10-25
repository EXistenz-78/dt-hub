// swift-tools-version: 6.2
import PackageDescription

// The Panorama 360 plug-in of DT Hub (docs/superpowers/specs/2026-10-25-plugin-panorama-360-design.md).
let package = Package(
  name: "Panorama360",
  platforms: [.macOS(.v26)],
  products: [.library(name: "Panorama360", type: .dynamic, targets: ["Panorama360"])],
  dependencies: [.package(name: "PluginKit", path: "../../PluginKit")],
  targets: [
    // Like every plug-in it carries its own copy of the kit and of the design system, under names of its own.
    .target(
      name: "Panorama360",
      dependencies: [
        .product(name: "DTHubPluginKit", package: "PluginKit", moduleAliases: ["DTHubPluginKit": "Panorama360Kit"]),
        .product(name: "DTHubDesign", package: "PluginKit", moduleAliases: ["DTHubDesign": "Panorama360Design"]),
      ]),
    .testTarget(name: "Panorama360Tests", dependencies: ["Panorama360"], exclude: ["Fixtures"]),
  ]
)
