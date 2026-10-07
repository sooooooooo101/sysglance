// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SysGlanceCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SysGlanceCore", targets: ["SysGlanceCore"]),
    ],
    targets: [
        .target(
            name: "SysGlanceCore",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .testTarget(
            name: "SysGlanceCoreTests",
            dependencies: ["SysGlanceCore"]
        ),
    ]
)
