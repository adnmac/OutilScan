// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OutilScan",
    platforms: [.macOS(.v14)],
    targets: [
        // Logique métier (pilote SANE, traitement d'images, PDF) — testable sans interface.
        .target(name: "OutilScanCore"),
        // Application SwiftUI.
        .executableTarget(name: "OutilScan", dependencies: ["OutilScanCore"]),
        // Tests : `swift run OutilScanSelfTest` (XCTest / Swift Testing indisponibles sans Xcode).
        .executableTarget(name: "OutilScanSelfTest", dependencies: ["OutilScanCore"]),
    ]
)
