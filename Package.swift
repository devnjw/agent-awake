// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentAwake",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "AgentAwake", targets: ["AgentAwake"])],
    targets: [
        .target(name: "AgentAwakeCore"),
        .executableTarget(name: "AgentAwake", dependencies: ["AgentAwakeCore"],
                          linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("ServiceManagement")]),
        .testTarget(name: "AgentAwakeCoreTests", dependencies: ["AgentAwakeCore"]),
        .testTarget(name: "AgentAwakeTests", dependencies: ["AgentAwake"])
    ],
    swiftLanguageModes: [.v5]
)
