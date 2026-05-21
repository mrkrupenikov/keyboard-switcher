// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KeyboardSwitcher",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "KeyboardSwitcher",
            dependencies: [],
            path: "Sources/PuntoSwitcher",
            resources: [
                .copy("../../Resources/english_words.txt"),
                .copy("../../Resources/ukrainian_words.txt")
            ],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("AppKit")
            ]
        )
    ]
)
