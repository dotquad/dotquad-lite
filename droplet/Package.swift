// swift-tools-version: 6.0
//
//  Dotquad Lite, a Droplet for Droppy.
//
//  Build the .droplet bundle with DroppyKit's `droppykit build`, not a bare
//  `swift build`: a bare build folds a second copy of DroppyKit in, and
//  Droppy's loader refuses the bundle.
//

import PackageDescription

let package = Package(
    name: "DotquadLite",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DotquadLite", type: .dynamic, targets: ["DotquadLite"])
    ],
    dependencies: [
        .package(url: "https://gitlab.com/droppyformac1/droppykit.git", from: "1.23.0")
    ],
    targets: [
        .target(
            name: "DotquadLite",
            dependencies: [.product(name: "DroppyKit", package: "droppykit")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "DotquadLiteHarness",
            dependencies: [
                "DotquadLite",
                .product(name: "DroppyKitHarness", package: "droppykit")
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
