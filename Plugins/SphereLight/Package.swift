// swift-tools-version: 6.2
import PackageDescription

// The Sphere Light Reference plug-in of DT Hub (docs/superpowers/specs/2026-10-04-plugin-sphere-light-design.md).
let package = Package(
  name: "SphereLight",
  platforms: [.macOS(.v26)],
  products: [.library(name: "SphereLight", type: .dynamic, targets: ["SphereLight"])],
  dependencies: [.package(name: "PluginKit", path: "../../PluginKit")],
  targets: [
    // Every plug-in carries its own copy of the kit; `moduleAliases` gives it a name of its own, so two plug-ins
    // do not define the same Objective-C classes twice in one process.
    .target(
      name: "SphereLight",
      dependencies: [.product(name: "DTHubPluginKit", package: "PluginKit", moduleAliases: ["DTHubPluginKit": "SphereLightKit"])]),
    .testTarget(name: "SphereLightTests", dependencies: ["SphereLight"]),
  ]
)
