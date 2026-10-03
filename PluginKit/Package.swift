// swift-tools-version: 6.2
import PackageDescription

// The package a DT Hub plug-in is written with. It does not depend on DT Hub: the app and the plug-in
// only talk through selectors and JSON messages (plug-in design §3).
let package = Package(
  name: "DTHubPluginKit",
  platforms: [.macOS(.v26)],
  products: [.library(name: "DTHubPluginKit", targets: ["DTHubPluginKit"])],
  targets: [.target(name: "DTHubPluginKit")]
)
