// swift-tools-version:5.9
import PackageDescription

let package = Package(
  name: "quant4",
  platforms: [.macOS(.v13)],
  dependencies: [
    .package(
      url: "https://github.com/liuliu/s4nnc.git",
      revision: "01d743a210b3f032393aeae51e00a41417ed4201")
  ],
  targets: [
    .executableTarget(
      name: "quant4",
      dependencies: [.product(name: "NNC", package: "s4nnc")])
  ])
