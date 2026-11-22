// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DrawThingsSwift",
    platforms: [
        .macOS(.v15),
        .iOS(.v18)
    ],
    products: [
        .library(
            name: "DrawThingsClient",
            targets: ["DrawThingsClient"]
        ),
        .library(
            name: "DrawThingsQueue",
            targets: ["DrawThingsQueue"]
        ),
        .library(
            name: "DrawThingsVideoKit",
            targets: ["DrawThingsVideoKit"]
        ),
        .library(
            name: "DrawThingsKit",
            targets: ["DrawThingsKit"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/grpc/grpc-swift-2.git", from: "2.4.0"),
        .package(url: "https://github.com/grpc/grpc-swift-nio-transport.git", from: "2.10.0"),
        .package(url: "https://github.com/grpc/grpc-swift-protobuf.git", from: "2.4.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.38.0"),
        .package(url: "https://github.com/google/flatbuffers.git", exact: "25.9.23"),
    ],
    targets: [
        .target(
            name: "CFpzip",
            path: "Sources/CFpzip",
            exclude: [
                "LICENSE",
                "src/fpe.inl",
                "src/pccodec.inl",
                "src/pcdecoder.inl",
                "src/pcencoder.inl",
                "src/pcmap.inl",
                "src/rcdecoder.inl",
                "src/rcencoder.inl",
                "src/rcqsmodel.inl",
            ],
            sources: ["src"],
            publicHeadersPath: "include",
            cxxSettings: [
                .define("FPZIP_FP", to: "FPZIP_FP_FAST"),
                .define("FPZIP_BLOCK_SIZE", to: "0x1000"),
                .headerSearchPath("src"),
                .headerSearchPath("include"),
            ]
        ),
        .target(
            name: "DrawThingsClient",
            dependencies: [
                .product(name: "GRPCCore", package: "grpc-swift-2"),
                .product(name: "GRPCNIOTransportHTTP2", package: "grpc-swift-nio-transport"),
                .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "FlatBuffers", package: "flatbuffers"),
                "CFpzip",
            ],
            resources: [
                .copy("Resources/models.json"),
            ]
        ),
        .target(
            name: "DrawThingsQueue",
            dependencies: [
                "DrawThingsClient",
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ]
        ),
        .target(
            name: "DrawThingsVideoKit",
            dependencies: ["DrawThingsClient"]
        ),
        .target(
            name: "DrawThingsKit",
            dependencies: ["DrawThingsClient"],
            resources: [
                .copy("Resources/official_models.json"),
                .copy("Resources/community_models.json"),
            ]
        ),
        .testTarget(
            name: "DrawThingsClientTests",
            dependencies: [
                "DrawThingsClient",
                "DrawThingsQueue",
                "DrawThingsVideoKit",
                "DrawThingsKit",
                "CFpzip",
                .product(name: "GRPCCore", package: "grpc-swift-2"),
                .product(name: "GRPCNIOTransportHTTP2", package: "grpc-swift-nio-transport"),
                .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
            ],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6],
    cxxLanguageStandard: .cxx11
)
