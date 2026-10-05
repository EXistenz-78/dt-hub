// swift-tools-version: 6.2
import PackageDescription

// The package a DT Hub plug-in is written with. It does not depend on DT Hub: the app and the plug-in
// only talk through selectors and JSON messages (plug-in design §3).
//
// `DTHubDesign` is the look of the app (cards, buttons, colours: SwiftUI only, no Objective-C classes). The app's
// HubKit uses it from here and a plug-in takes the same product next to the kit. A plug-in gives each module a name of
// its own with `moduleAliases` (see Plugins/SphereLight/Package.swift).
let package = Package(
  name: "DTHubPluginKit",
  platforms: [.macOS(.v26)],
  products: [
    .library(name: "DTHubPluginKit", targets: ["DTHubPluginKit"]),
    .library(name: "DTHubDesign", targets: ["DTHubDesign"]),
  ],
  targets: [
    .target(name: "DTHubDesign"),
    .target(name: "DTHubPluginKit"),
    .testTarget(name: "DTHubPluginKitTests", dependencies: ["DTHubPluginKit"]),
    .testTarget(name: "DTHubDesignTests", dependencies: ["DTHubDesign"]),
  ]
)
