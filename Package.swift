// swift-tools-version:5.10
import Foundation
import PackageDescription

// Command Line Tools ships Testing.framework outside the default search paths.
let cltDev = "/Library/Developer/CommandLineTools/Library/Developer"
let hasCLT = FileManager.default.fileExists(atPath: cltDev + "/Frameworks")
let cltSwift: [SwiftSetting] = hasCLT ? [.unsafeFlags(["-F", cltDev + "/Frameworks"])] : []
let cltLink: [LinkerSetting] = hasCLT ? [.unsafeFlags([
    "-F", cltDev + "/Frameworks",
    "-Xlinker", "-rpath", "-Xlinker", cltDev + "/Frameworks",
    "-Xlinker", "-rpath", "-Xlinker", cltDev + "/usr/lib",
])] : []

let package = Package(
    name: "Pulse",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "PulseCore", path: "Sources/PulseCore"),
        .target(name: "PulseSystem", dependencies: ["PulseCore"], path: "Sources/PulseSystem"),
        .target(name: "PulseActions", dependencies: ["PulseCore"], path: "Sources/PulseActions"),
        .executableTarget(name: "pulse-probe", dependencies: ["PulseCore", "PulseSystem"], path: "Sources/PulseProbe"),
        .executableTarget(
            name: "Pulse",
            dependencies: ["PulseCore", "PulseSystem", "PulseActions"],
            path: "Sources/Pulse",
            resources: [.copy("Resources/Fonts")]),
        .testTarget(name: "PulseCoreTests", dependencies: ["PulseCore", "PulseActions"], path: "Tests/PulseCoreTests",
            swiftSettings: cltSwift, linkerSettings: cltLink),
    ]
)
