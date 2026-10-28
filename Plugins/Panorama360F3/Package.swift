// swift-tools-version: 6.2
import PackageDescription

// The Pano 360 F3 plug-in of DT Hub (docs/superpowers/specs/2026-10-28-plugin-pano-360-f3-design.md).
let package = Package(
  name: "Panorama360F3",
  platforms: [.macOS(.v26)],
  products: [.library(name: "Panorama360F3", type: .dynamic, targets: ["Panorama360F3"])],
  dependencies: [.package(name: "PluginKit", path: "../../PluginKit")],
  targets: [
    // Like every plug-in it carries its own copy of the kit and of the design system, under names of its own.
    .target(
      name: "Panorama360F3",
      dependencies: [
        .product(name: "DTHubPluginKit", package: "PluginKit", moduleAliases: ["DTHubPluginKit": "Panorama360F3Kit"]),
        .product(name: "DTHubDesign", package: "PluginKit", moduleAliases: ["DTHubDesign": "Panorama360F3Design"]),
      ]),
    .testTarget(name: "Panorama360F3Tests", dependencies: ["Panorama360F3"]),
  ]
)
