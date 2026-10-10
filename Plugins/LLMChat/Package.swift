// swift-tools-version: 6.2
import PackageDescription

// The LLM Chat plug-in of DT Hub (docs/superpowers/specs/2026-10-10-plugin-llm-chat-design.md).
let package = Package(
  name: "LLMChat",
  platforms: [.macOS(.v26)],
  products: [.library(name: "LLMChat", type: .dynamic, targets: ["LLMChat"])],
  dependencies: [.package(name: "PluginKit", path: "../../PluginKit")],
  targets: [
    // Every plug-in carries its own copy of the kit and of the design system; `moduleAliases` gives them
    // names of their own, so two plug-ins (and the app) do not define the same classes twice in one process.
    .target(
      name: "LLMChat",
      dependencies: [
        .product(name: "DTHubPluginKit", package: "PluginKit", moduleAliases: ["DTHubPluginKit": "LLMChatKit"]),
        .product(name: "DTHubDesign", package: "PluginKit", moduleAliases: ["DTHubDesign": "LLMChatDesign"]),
      ]),
    .testTarget(name: "LLMChatTests", dependencies: ["LLMChat"]),
  ]
)
