// swift-tools-version: 6.2
import PackageDescription

// The Sphere Light Reference plug-in of DT Hub (docs/superpowers/specs/2026-10-04-plugin-sphere-light-design.md).
let package = Package(
  name: "SphereLight",
  platforms: [.macOS(.v26)],
  products: [.library(name: "SphereLight", type: .dynamic, targets: ["SphereLight"])],
  targets: [
    .target(name: "SphereLight"),
    .testTarget(name: "SphereLightTests", dependencies: ["SphereLight"]),
  ]
)
