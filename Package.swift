// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "DisplayFocus",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "displayfocus", targets: ["displayfocus"]),
        .executable(name: "DisplayFocusApp", targets: ["DisplayFocusApp"]),
    ],
    targets: [
        .target(name: "DisplayCore", linkerSettings: [.linkedFramework("CoreGraphics"), .linkedFramework("AppKit"), .linkedFramework("ColorSync")]),
        .executableTarget(name: "displayfocus", dependencies: ["DisplayCore"]),
        .executableTarget(name: "DisplayFocusApp", dependencies: ["DisplayCore"]),
    ]
)
