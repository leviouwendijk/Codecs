// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "Codecs",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "Codecs", targets: ["Codecs"]),
        .library(name: "CodecsLAME", targets: ["CodecsLAME"]),
        .executable(name: "codecs", targets: ["CodecsCLI"]),
        .executable(name: "codecstest", targets: ["CodecsTestFlows"]),
    ],
    dependencies: [
        .package(path: "../Media"),
        .package(url: "https://github.com/leviouwendijk/Arguments.git", branch: "master"),
        .package(url: "https://github.com/leviouwendijk/TestFlows.git", branch: "master"),
    ],
    targets: [
        .systemLibrary(name: "CLAME", pkgConfig: "lame", providers: [.brew(["lame"])]),
        .target(name: "CodecsLAMEBridge", dependencies: ["CLAME"], publicHeadersPath: "include"),
        .target(
            name: "CodecsLAME",
            dependencies: [
                .product(name: "MediaCore", package: "Media"),
                .product(name: "MediaTranscoding", package: "Media"),
                "CodecsLAMEBridge",
            ]
        ),
        .target(name: "Codecs", dependencies: ["CodecsLAME"]),
        .executableTarget(
            name: "CodecsCLI",
            dependencies: [
                "CodecsLAME",
                .product(name: "MediaTranscoding", package: "Media"),
                .product(name: "Arguments", package: "Arguments"),
            ]
        ),
        .executableTarget(
            name: "CodecsTestFlows",
            dependencies: [
                "CodecsLAME",
                .product(name: "MediaTranscoding", package: "Media"),
                .product(name: "MediaCore", package: "Media"),
                .product(name: "MediaAV", package: "Media"),
                .product(name: "TestFlows", package: "TestFlows"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
