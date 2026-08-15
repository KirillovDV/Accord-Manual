// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ManualImporter",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ManualImporter", targets: ["ManualImporter"]),
        .executable(name: "accord-manual-import", targets: ["AccordManualImport"])
    ],
    targets: [
        .target(name: "ManualImporter", linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(name: "AccordManualImport", dependencies: ["ManualImporter"]),
        .testTarget(name: "ManualImporterTests", dependencies: ["ManualImporter"])
    ]
)
