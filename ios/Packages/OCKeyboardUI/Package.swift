// swift-tools-version:6.0
// SPDX-License-Identifier: GPL-3.0-or-later
import PackageDescription

// The keyboard's views and input logic. Shared by the keyboard extension and by the
// simulator test host, which embeds the same view as the input view of a text field
// (so UI tests can drive it without the system keyboard and without coordinates).
// UIKit only: built through Xcode for iOS, not by `swift test`.
let package = Package(
    name: "OCKeyboardUI",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "OCKeyboardUI", type: .static, targets: ["OCKeyboardUI"]),
    ],
    dependencies: [
        .package(path: "../OCCore"),
        .package(path: "../OCRime"),
    ],
    targets: [
        .target(
            name: "OCKeyboardUI",
            dependencies: [
                .product(name: "OCCore", package: "OCCore"),
                .product(name: "OCRime", package: "OCRime"),
            ],
            path: "Sources/OCKeyboardUI"
        ),
    ],
    swiftLanguageModes: [.v5]
)
