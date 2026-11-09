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
    // Sparkle is the one third-party Swift dependency. It downloads a signed
    // update and relaunches the app. See CONTRIBUTING.md.
    .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.7.1"),
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
    .target(
      name: "AppKitShims",
      path: "Sources/AppKitShims",
      publicHeadersPath: "include",
      linkerSettings: [
        .linkedFramework("Foundation"),
      ]
    ),
    .executableTarget(
      name: "Annotator",
      dependencies: [
        "AppKitShims",
        "CaptureKit",
        .product(name: "Sparkle", package: "Sparkle"),
      ],
      path: "Sources/Annotator",
      linkerSettings: [
        .unsafeFlags([
          "-Xlinker", "-rpath",
          "-Xlinker", "@executable_path/../Frameworks",
        ]),
      ]
    ),
  ]
)
