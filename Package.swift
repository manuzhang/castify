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
  dependencies: [
    .package(url: "https://github.com/getsentry/sentry-cocoa.git", from: "9.14.0")
  ],
  targets: [
    .target(
      name: "Podcasts",
      dependencies: ["Sentry"],
      path: "Podcasts"
    )
  ]
)
