// swift-tools-version: 6.2
import PackageDescription

// A complete plug-in to copy: a tab that shows the model the app tells it about, and a notice at start.
let package = Package(
  name: "SamplePlugin",
  platforms: [.macOS(.v26)],
  products: [.library(name: "SamplePlugin", type: .dynamic, targets: ["SamplePlugin"])],
  dependencies: [.package(name: "PluginKit", path: "../..")],
  targets: [.target(name: "SamplePlugin", dependencies: [.product(name: "DTHubPluginKit", package: "PluginKit")])]
)
