// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Nyanyi",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "NyanyiCore", targets: ["NyanyiCore"]),
        .executable(name: "Nyanyi", targets: ["Nyanyi"])
    ],
    targets: [
        .target(
            name: "NyanyiCore",
            path: "Sources/NyanyiCore"
        ),
        .executableTarget(
            name: "Nyanyi",
            dependencies: ["NyanyiCore"],
            path: "Sources/Nyanyi"
        ),
        .testTarget(
            name: "NyanyiTests",
            dependencies: ["NyanyiCore"],
            path: "Tests/NyanyiTests"
        )
    ]
)

