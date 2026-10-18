// swift-tools-version: 6.2
import PackageDescription

// The Tiled Upscale plug-in of DT Hub (docs/superpowers/specs/2026-10-18-plugin-tiled-upscale-design.md).
let package = Package(
  name: "TiledUpscale",
  platforms: [.macOS(.v26)],
  products: [.library(name: "TiledUpscale", type: .dynamic, targets: ["TiledUpscale"])],
  dependencies: [.package(name: "PluginKit", path: "../../PluginKit")],
  targets: [
    // Every plug-in carries its own copy of the kit and of the design system; `moduleAliases` gives them
    // names of their own, so two plug-ins (and the app) do not define the same classes twice in one process.
    .target(
      name: "TiledUpscale",
      dependencies: [
        .product(name: "DTHubPluginKit", package: "PluginKit", moduleAliases: ["DTHubPluginKit": "TiledUpscaleKit"]),
        .product(name: "DTHubDesign", package: "PluginKit", moduleAliases: ["DTHubDesign": "TiledUpscaleDesign"]),
      ]),
    .testTarget(name: "TiledUpscaleTests", dependencies: ["TiledUpscale"]),
  ]
)
