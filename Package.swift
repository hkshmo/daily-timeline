// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Dayline",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Dayline", targets: ["Dayline"])
    ],
    targets: [
        .executableTarget(name: "Dayline", path: "Sources/Dayline"),
        .testTarget(name: "DaylineTests", dependencies: ["Dayline"], path: "Tests/DaylineTests")
    ]
)
