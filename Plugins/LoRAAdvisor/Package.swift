// swift-tools-version: 6.2
import PackageDescription

// The LoRA Advisor plug-in of DT Hub (docs/superpowers/specs/2026-10-13-plugin-lora-advisor-design.md).
let package = Package(
  name: "LoRAAdvisor",
  platforms: [.macOS(.v26)],
  products: [.library(name: "LoRAAdvisor", type: .dynamic, targets: ["LoRAAdvisor"])],
  dependencies: [.package(name: "PluginKit", path: "../../PluginKit")],
  targets: [
    // Every plug-in carries its own copy of the kit and of the design system; `moduleAliases` gives them
    // names of their own, so two plug-ins (and the app) do not define the same classes twice in one process.
    .target(
      name: "LoRAAdvisor",
      dependencies: [
        .product(name: "DTHubPluginKit", package: "PluginKit", moduleAliases: ["DTHubPluginKit": "LoRAAdvisorKit"]),
        .product(name: "DTHubDesign", package: "PluginKit", moduleAliases: ["DTHubDesign": "LoRAAdvisorDesign"]),
      ]),
    .testTarget(name: "LoRAAdvisorTests", dependencies: ["LoRAAdvisor"]),
  ]
)
