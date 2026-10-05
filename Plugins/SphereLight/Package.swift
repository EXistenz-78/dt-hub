// swift-tools-version: 6.2
import PackageDescription

// The Sphere Light Reference plug-in of DT Hub (docs/superpowers/specs/2026-10-04-plugin-sphere-light-design.md).
let package = Package(
  name: "SphereLight",
  platforms: [.macOS(.v26)],
  products: [.library(name: "SphereLight", type: .dynamic, targets: ["SphereLight"])],
  dependencies: [.package(name: "PluginKit", path: "../../PluginKit")],
  targets: [
    // Every plug-in carries its own copy of the kit and of the design system; `moduleAliases` gives them
    // names of their own, so two plug-ins (and the app) do not define the same classes twice in one process.
    .target(
      name: "SphereLight",
      dependencies: [
        .product(name: "DTHubPluginKit", package: "PluginKit", moduleAliases: ["DTHubPluginKit": "SphereLightKit"]),
        .product(name: "DTHubDesign", package: "PluginKit", moduleAliases: ["DTHubDesign": "SphereLightDesign"]),
      ]),
    .testTarget(name: "SphereLightTests", dependencies: ["SphereLight"]),
  ]
)
