// swift-tools-version: 6.2
import PackageDescription

// The AI Assistant plug-in of DT Hub (docs/superpowers/specs/2026-10-10-plugin-llm-chat-design.md).
let package = Package(
  name: "AIAssistant",
  platforms: [.macOS(.v26)],
  products: [.library(name: "AIAssistant", type: .dynamic, targets: ["AIAssistant"])],
  dependencies: [.package(name: "PluginKit", path: "../../PluginKit")],
  targets: [
    // Every plug-in carries its own copy of the kit and of the design system; `moduleAliases` gives them
    // names of their own, so two plug-ins (and the app) do not define the same classes twice in one process.
    .target(
      name: "AIAssistant",
      dependencies: [
        .product(name: "DTHubPluginKit", package: "PluginKit", moduleAliases: ["DTHubPluginKit": "AIAssistantKit"]),
        .product(name: "DTHubDesign", package: "PluginKit", moduleAliases: ["DTHubDesign": "AIAssistantDesign"]),
      ]),
    .testTarget(name: "AIAssistantTests", dependencies: ["AIAssistant"]),
  ]
)
