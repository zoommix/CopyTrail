// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CopyTrail",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CopyTrail", targets: ["CopyTrail"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "CopyTrail",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            exclude: [
                "Resources/Info.plist",
                "Resources/AppIcon.icns",
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/CopyTrail/Resources/Info.plist",
                ])
            ]
        ),
    ]
)
