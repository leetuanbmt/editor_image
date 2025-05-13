// swift-tools-version:5.6
import PackageDescription

let package = Package(
    name: "ImageProcessor",
    platforms: [
        .iOS(.v12)
    ],
    products: [
        .library(
            name: "ImageProcessor",
            targets: ["ImageProcessor"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "ImageProcessor",
            path: "xcframeworks/image_processor.xcframework"
        ),
    ]
)
