// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "Annotator",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "Annotator", targets: ["Annotator"]),
  ],
  targets: [
    .executableTarget(
      name: "Annotator",
      path: "Sources/Annotator"
    ),
  ]
)
