// swift-tools-version: 6.2
import PackageDescription

// A complete plug-in to copy: a tab that shows the model the app tells it about, and buttons that send
// contributions to the Generation tab (the plug-in design, §7). Setting SAMPLE_B builds a second plug-in
// from the same sources (other identifier, other module, other values) to try two plug-ins contributing
// the same field: `Scripts/build-sample.sh`.
let variantB = Context.environment["SAMPLE_B"] != nil
let name = variantB ? "SamplePluginB" : "SamplePlugin"
// Every plug-in carries its own copy of the kit. Two copies with the same module name would define the same
// Objective-C classes twice in one process, so each plug-in gives its copy a name of its own with
// `moduleAliases`. The sources still `import DTHubPluginKit`; only the names in the binary change.
let kitAlias = variantB ? "SampleBKit" : "SampleKit"
let package = Package(
  name: name,
  platforms: [.macOS(.v26)],
  products: [.library(name: name, type: .dynamic, targets: [name])],
  dependencies: [.package(name: "PluginKit", path: "../..")],
  targets: [
    .target(
      name: name, dependencies: [.product(name: "DTHubPluginKit", package: "PluginKit", moduleAliases: ["DTHubPluginKit": kitAlias])], path: "Sources/SamplePlugin",
      swiftSettings: variantB ? [.define("SAMPLE_B")] : [])
  ]
)
