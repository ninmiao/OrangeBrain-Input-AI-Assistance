// swift-tools-version:6.0
// SPDX-License-Identifier: GPL-3.0-or-later
import PackageDescription

// Swift wrapper over the librime C API. The static libraries themselves
// (librime.a and its dependencies from fcitx5-prebuilder, see ios/deps.lock.json)
// are linked by the app and keyboard targets, not by this package, so the
// package builds anywhere and the link line stays in one place (ios/project.yml).
let package = Package(
    name: "OCRime",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "OCRime", type: .static, targets: ["OCRime"]),
    ],
    targets: [
        .target(
            name: "CRime",
            path: "Sources/CRime",
            exclude: ["LICENSE-librime.txt"],
            publicHeadersPath: "include"
        ),
        .target(
            name: "OCRime",
            dependencies: ["CRime"],
            path: "Sources/OCRime"
        ),
    ],
    swiftLanguageModes: [.v5]
)
