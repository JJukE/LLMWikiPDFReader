// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "LLMWikiPDFReader",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "AnnotationCore", targets: ["AnnotationCore"]),
        .library(name: "VaultExporter", targets: ["VaultExporter"]),
        .library(name: "ZoteroResolver", targets: ["ZoteroResolver"]),
        .executable(name: "LLMWikiPDFReaderMac", targets: ["LLMWikiPDFReaderMac"]),
        .executable(name: "AnnotationCoreSmokeTests", targets: ["AnnotationCoreSmokeTests"])
    ],
    targets: [
        .target(name: "AnnotationCore"),
        .target(
            name: "VaultExporter",
            dependencies: ["AnnotationCore"]
        ),
        .target(
            name: "ZoteroResolver",
            dependencies: ["AnnotationCore"]
        ),
        .executableTarget(
            name: "LLMWikiPDFReaderMac",
            dependencies: ["AnnotationCore", "VaultExporter", "ZoteroResolver"],
            path: "Sources/LLMWikiPDFReader"
        ),
        .executableTarget(
            name: "AnnotationCoreSmokeTests",
            dependencies: ["AnnotationCore", "VaultExporter", "ZoteroResolver"]
        )
    ]
)
