// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "Annotator",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "Annotator", targets: ["Annotator"]),
    .executable(name: "Capture", targets: ["Capture"]),
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
      dependencies: ["CaptureKit"],
      path: "Sources/Annotator"
    ),
  ]
)
