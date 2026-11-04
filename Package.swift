// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BitFi",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "BitFi", targets: ["BitFi"])
    ],
    targets: [
        .executableTarget(
            name: "BitFi",
            path: "BitFi",
            exclude: ["Resources"]
        )
    ]
)
