// swift-tools-version:5.1
import PackageDescription

let package = Package(
        name: "Podcasts",
        products: [
            .library(name: "Podcasts", targets: ["Podcasts"])
        ],
        dependencies: [
            .package(url: "https://github.com/Moya/Moya.git", .upToNextMajor(from: "13.0.0")),
            .package(url: "https://github.com/onevcat/Kingfisher.git", .upToNextMajor(from: "5.12.0")),
            .package(url: "https://github.com/nmdias/FeedKit", .upToNextMajor(from: "9.0.0"))
        ],
        targets: [
            .target(
                    name: "Podcasts",
                    dependencies: [
                        "Moya",
                        "Kingfisher",
                        "FeedKit"
                    ],
                    path: "Podcasts"
            )
        ]
)
