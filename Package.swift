// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "TaskNotebook", platforms: [.macOS(.v14)], products: [
    .executable(name: "TaskNotebook", targets: ["TaskNotebook"]),
    .executable(name: "tasknote", targets: ["TaskNoteCLI"])
], targets: [
    .target(name: "TaskCore"),
    .executableTarget(name: "TaskNotebook", dependencies: ["TaskCore"]),
    .executableTarget(name: "TaskNoteCLI", dependencies: ["TaskCore"]),
    .testTarget(name: "TaskCoreTests", dependencies: ["TaskCore"])
])
