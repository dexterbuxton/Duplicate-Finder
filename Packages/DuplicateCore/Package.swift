// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "DuplicateCore",
  platforms: [.macOS(.v26)],
  products: [
    .library(name: "DuplicateCore", targets: ["DuplicateCore"]),
  ],
  targets: [
    .target(name: "DuplicateCore"),
    .testTarget(name: "DuplicateCoreTests", dependencies: ["DuplicateCore"]),
  ]
)
