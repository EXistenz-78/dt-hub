// swift-tools-version: 6.2
import PackageDescription

// The Character Sheet plug-in of DT Hub (docs/superpowers/specs/2026-10-07-plugin-character-sheet-design.md).
let package = Package(
  name: "CharacterSheet",
  platforms: [.macOS(.v26)],
  products: [.library(name: "CharacterSheet", type: .dynamic, targets: ["CharacterSheet"])],
  dependencies: [.package(name: "PluginKit", path: "../../PluginKit")],
  targets: [
    // Every plug-in carries its own copy of the kit and of the design system; `moduleAliases` gives them
    // names of their own, so two plug-ins (and the app) do not define the same classes twice in one process.
    .target(
      name: "CharacterSheet",
      dependencies: [
        .product(name: "DTHubPluginKit", package: "PluginKit", moduleAliases: ["DTHubPluginKit": "CharacterSheetKit"]),
        .product(name: "DTHubDesign", package: "PluginKit", moduleAliases: ["DTHubDesign": "CharacterSheetDesign"]),
      ]),
    .testTarget(name: "CharacterSheetTests", dependencies: ["CharacterSheet"]),
  ]
)
