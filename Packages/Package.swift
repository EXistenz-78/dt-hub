// swift-tools-version: 6.2
import PackageDescription

// One package, one target per module: the compiler enforces the dependency
// rules of spec §4 (a target can only import what it declares).
let package = Package(
  name: "DTHubPackages",
  defaultLocalization: "en",
  platforms: [.macOS(.v26)],
  products: [
    .library(name: "HubKit", targets: ["HubKit"]),
    .library(name: "HubCore", targets: ["HubCore"]),
    .library(name: "DTBridge", targets: ["DTBridge"]),
    .library(name: "LLMBridge", targets: ["LLMBridge"]),
    .library(name: "PluginHost", targets: ["PluginHost"]),
  ],
  dependencies: [
    // Single maintainer, frequent releases: accept patch updates only (spec §5, §16).
    .package(
      url: "https://github.com/euphoriacyberware-ai/DrawThings-Swift.git",
      .upToNextMinor(from: "2.2.0")),
    // The language-model engine (spec §9). 3.x asks for a downloader and a tokenizer package.
    .package(url: "https://github.com/ml-explore/mlx-swift-lm", .upToNextMajor(from: "3.31.3")),
    .package(url: "https://github.com/ml-explore/mlx-swift", .upToNextMinor(from: "0.32.3")),
    .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0"),
    .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
    // The design system (cards, buttons, colours) is shared with the plug-ins: it lives in the plug-in kit package.
    .package(name: "PluginKit", path: "../PluginKit"),
  ],
  targets: [
    .target(name: "HubKit", dependencies: [.product(name: "DTHubDesign", package: "PluginKit")]),
    .target(name: "HubCore", dependencies: ["HubKit"]),
    // The only module that knows DrawThings-Swift and gRPC (spec §4).
    .target(
      name: "DTBridge",
      dependencies: ["HubKit", .product(name: "DrawThingsClient", package: "DrawThings-Swift")]),
    // The only module that knows MLX (spec §4).
    .target(
      name: "LLMBridge",
      dependencies: [
        "HubKit",
        .product(name: "MLXLLM", package: "mlx-swift-lm"),
        .product(name: "MLXVLM", package: "mlx-swift-lm"),
        .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
        .product(name: "MLX", package: "mlx-swift"),
        .product(name: "HuggingFace", package: "swift-huggingface"),
        .product(name: "Tokenizers", package: "swift-transformers"),
      ]),
    // Loads downloaded plug-in bundles (AppKit, Bundle, selectors); knows HubCore, never DT or MLX.
    .target(name: "PluginHost", dependencies: ["HubKit", "HubCore"]),
    // Live tests: need a model on disk or the network, and the Metal library, so they run with
    // `xcodebuild test` (`swift test` skips them: spec §13, "LLMBridge: test a mano").
    .testTarget(name: "LLMBridgeTests", dependencies: ["LLMBridge", "HubKit"]),
    .testTarget(name: "HubKitTests", dependencies: ["HubKit"]),
    .testTarget(name: "HubCoreTests", dependencies: ["HubCore", "HubKit"]),
    .testTarget(name: "DTBridgeTests", dependencies: ["DTBridge", "HubKit", "HubCore"]),
    .testTarget(name: "PluginHostTests", dependencies: ["PluginHost", "HubCore", "HubKit"]),
    // Checks App/Localizable.xcstrings: every string translated in en and it (spec §12).
    .testTarget(name: "CatalogTests"),
  ]
)
