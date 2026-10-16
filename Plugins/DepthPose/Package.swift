// swift-tools-version: 6.2
import PackageDescription

// The Depth & Pose plug-in of DT Hub (docs/superpowers/specs/2026-10-16-plugin-depth-pose-design.md).
let package = Package(
  name: "DepthPose",
  platforms: [.macOS(.v26)],
  products: [.library(name: "DepthPose", type: .dynamic, targets: ["DepthPose"])],
  dependencies: [.package(name: "PluginKit", path: "../../PluginKit")],
  targets: [
    // Every plug-in carries its own copy of the kit and of the design system; `moduleAliases` gives them
    // names of their own, so two plug-ins (and the app) do not define the same classes twice in one process.
    .target(
      name: "DepthPose",
      dependencies: [
        .product(name: "DTHubPluginKit", package: "PluginKit", moduleAliases: ["DTHubPluginKit": "DepthPoseKit"]),
        .product(name: "DTHubDesign", package: "PluginKit", moduleAliases: ["DTHubDesign": "DepthPoseDesign"]),
      ]),
    .testTarget(name: "DepthPoseTests", dependencies: ["DepthPose"]),
  ]
)
