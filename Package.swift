// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "JevNotch",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "JevNotch", targets: ["JevNotch"])],
    targets: [
        .executableTarget(
            name: "JevNotch",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Speech"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Contacts"),
                .linkedFramework("EventKit"),
                .linkedFramework("Security"),
                .linkedFramework("Network"),
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Config/EmbeddedInfo.plist",
                ]),
            ]
        ),
        .testTarget(name: "JevNotchTests", dependencies: ["JevNotch"]),
    ]
)
