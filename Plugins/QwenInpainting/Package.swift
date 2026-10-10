// swift-tools-version: 6.2
import PackageDescription

// The Qwen 2.1 Inpainting plug-in of DT Hub (docs/superpowers/specs/2026-10-10-plugin-qwen-inpainting-design.md).
let package = Package(
  name: "QwenInpainting",
  platforms: [.macOS(.v26)],
  products: [.library(name: "QwenInpainting", type: .dynamic, targets: ["QwenInpainting"])],
  dependencies: [.package(name: "PluginKit", path: "../../PluginKit")],
  targets: [
    // Every plug-in carries its own copy of the kit and of the design system; `moduleAliases` gives them
    // names of their own, so two plug-ins (and the app) do not define the same classes twice in one process.
    .target(
      name: "QwenInpainting",
      dependencies: [
        .product(name: "DTHubPluginKit", package: "PluginKit", moduleAliases: ["DTHubPluginKit": "QwenInpaintingKit"]),
        .product(name: "DTHubDesign", package: "PluginKit", moduleAliases: ["DTHubDesign": "QwenInpaintingDesign"]),
      ]),
    .testTarget(name: "QwenInpaintingTests", dependencies: ["QwenInpainting"]),
  ]
)
