// swift-tools-version: 6.3.3
import PackageDescription

let package = Package(
    name: "SwiftImageMagick",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "SwiftImageMagick",
            targets: ["SwiftImageMagick"]
        )
    ],
    dependencies: [],
    targets: [
        .systemLibrary(
            name: "imagemagick",
            pkgConfig: "MagickWand-7.Q16HDRI",
            providers: [.apt(["libmagickwand-dev"]), .brew(["imagemagick"])]
        ),
        .target(
            name: "SwiftImageMagick",
            dependencies: ["imagemagick"]
        ),
        .testTarget(
            name: "SwiftImageMagickTests",
            dependencies: ["SwiftImageMagick"]
        )
    ],
    swiftLanguageModes: [.v6]
)
