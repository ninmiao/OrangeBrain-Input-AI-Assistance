// swift-tools-version:6.0
// SPDX-License-Identifier: GPL-3.0-or-later
import PackageDescription

let package = Package(
    name: "OCCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "OCCore", type: .static, targets: ["OCCore"]),
    ],
    targets: [
        // The shared C++ core (shared/native-core) is compiled in place: shim.cpp
        // includes the original sources, so there is one copy of the protocol
        // code for Android, Windows and iOS.
        .target(
            name: "CNativeCore",
            path: "Sources/CNativeCore",
            publicHeadersPath: "include",
            cxxSettings: [.headerSearchPath("private")]
        ),
        .target(
            name: "OCCore",
            dependencies: ["CNativeCore"],
            path: "Sources/OCCore"
        ),
        .testTarget(
            name: "OCCoreTests",
            dependencies: ["OCCore", "CNativeCore"],
            path: "Tests/OCCoreTests"
        ),
    ],
    swiftLanguageModes: [.v5],
    cxxLanguageStandard: .cxx17
)
