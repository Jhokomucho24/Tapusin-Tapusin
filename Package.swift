// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "TapusinTapusin",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "TapusinTapusin", path: "Sources/TapusinTapusin")
    ]
)
