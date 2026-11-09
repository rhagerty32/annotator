// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "Annotator",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "Annotator", targets: ["Annotator"]),
    .executable(name: "Capture", targets: ["Capture"]),
  ],
  dependencies: [
    // Keep in sync with packaging/sparkle-version.
    .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
  ],
  targets: [
    .target(
      name: "CaptureKit",
      path: "Sources/CaptureKit"
    ),
    .executableTarget(
      name: "Capture",
      dependencies: ["CaptureKit"],
      path: "Sources/Capture"
    ),
    .executableTarget(
      name: "Annotator",
      dependencies: [
        "CaptureKit",
        .product(name: "Sparkle", package: "Sparkle"),
      ],
      path: "Sources/Annotator"
    ),
  ]
)
