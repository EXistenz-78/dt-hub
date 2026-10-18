// swift-tools-version: 6.2
import PackageDescription

// The Tiled Upscale Lab plug-in of DT Hub (an experimental fork of Tiled Upscale) (docs/superpowers/specs/2026-10-18-plugin-tiled-upscale-design.md).
let package = Package(
  name: "TiledUpscaleLab",
  platforms: [.macOS(.v26)],
  products: [.library(name: "TiledUpscaleLab", type: .dynamic, targets: ["TiledUpscaleLab"])],
  dependencies: [.package(name: "PluginKit", path: "../../PluginKit")],
  targets: [
    // Every plug-in carries its own copy of the kit and of the design system; `moduleAliases` gives them
    // names of their own, so two plug-ins (and the app) do not define the same classes twice in one process.
    .target(
      name: "TiledUpscaleLab",
      dependencies: [
        .product(name: "DTHubPluginKit", package: "PluginKit", moduleAliases: ["DTHubPluginKit": "TiledUpscaleLabKit"]),
        .product(name: "DTHubDesign", package: "PluginKit", moduleAliases: ["DTHubDesign": "TiledUpscaleLabDesign"]),
      ]),
    .testTarget(name: "TiledUpscaleLabTests", dependencies: ["TiledUpscaleLab"]),
  ]
)
