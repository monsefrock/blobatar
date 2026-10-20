// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Blobatar",
    platforms: [.iOS(.v15), .macOS(.v12), .tvOS(.v15), .watchOS(.v8), .visionOS(.v1)],
    products: [
        .library(name: "Blobatar", targets: ["Blobatar"]),
    ],
    targets: [
        .target(name: "Blobatar"),
        .testTarget(name: "BlobatarTests", dependencies: ["Blobatar"]),
    ]
)
