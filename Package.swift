// swift-tools-version:5.1
import PackageDescription

let package = Package(
  name: "Podcasts",
  platforms: [
    .iOS(.v13)
  ],
  products: [
    .library(name: "Podcasts", targets: ["Podcasts"])
  ],
  dependencies: [],
  targets: [
    .target(
      name: "Podcasts",
      dependencies: [],
      path: "Podcasts"
    )
  ]
)
