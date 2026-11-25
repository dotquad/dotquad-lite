// swift-tools-version: 6.0
//
// Tests for Dotquad Lite's logic. The Droplet itself is the package in
// droplet/, which is what goes to the Droppy Store. The Store refuses a
// Tests/ folder in a submission, so the tests live out here and build the
// DroppyKit-free files in droplet/Sources/DotquadLite/Core on their own.
//
//     swift test
//

import PackageDescription

let package = Package(
    name: "DotquadLiteTests",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "LiteCore",
            path: "droplet/Sources/DotquadLite/Core"
        ),
        .testTarget(
            name: "LiteCoreTests",
            dependencies: ["LiteCore"],
            path: "Tests/LiteCoreTests"
        ),
    ]
)
