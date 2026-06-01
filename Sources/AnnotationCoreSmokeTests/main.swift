import AnnotationCore
import Foundation
import VaultExporter
import ZoteroResolver

@main
struct AnnotationCoreSmokeTests {
    static func main() throws {
        try testHighlightColorSemanticsAreStable()
        try testSidecarJSONUsesSnakeCasePlanSchema()
        try testLegacyCamelCaseSidecarStillDecodes()
        try testMarkdownExporterCreatesRequiredSections()
        try testVaultExporterWritesMarkdownAndSidecarWithRelativePaths()
        try testZoteroResolverInfersItemKeyOnlyInsideConfiguredRoot()
        print("AnnotationCoreSmokeTests passed")
    }

    private static func testHighlightColorSemanticsAreStable() throws {
        try expect(HighlightColor.red.semanticLevel == "highest-level concept")
        try expect(HighlightColor.green.semanticLevel == "secondary high-level concept")
        try expect(HighlightColor.yellow.semanticLevel == "detailed-level concept")
        try expect(HighlightColor.blue.semanticLevel == "limitations/problems")
    }

    private static func testSidecarJSONUsesSnakeCasePlanSchema() throws {
        let document = sampleDocument()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(document)
        let json = try require(String(data: data, encoding: .utf8))

        try expect(json.contains(#""schema_version""#))
        try expect(json.contains(#""zotero_item_key""#))
        try expect(json.contains(#""pdf_path""#))
        try expect(json.contains(#""semantic_level""#))
        try expect(json.contains(#""selected_text""#))
        try expect(json.contains(#""created_at""#))
        try expect(json.contains(#""updated_at""#))
        try expect(json.contains(#""bbox""#))
        try expect(json.contains(#""obsidian_note_path""#))
        try expect(!json.contains(#""schemaVersion""#))
        try expect(!json.contains(#""selectedText""#))
    }

    private static func testLegacyCamelCaseSidecarStillDecodes() throws {
        let json = """
        {
          "schemaVersion": 1,
          "paper": {
            "title": "Legacy Paper",
            "authors": [],
            "zoteroItemKey": "ABCDEFGH",
            "pdfPath": "/tmp/legacy.pdf"
          },
          "annotations": [
            {
              "id": "00000000-0000-0000-0000-000000000001",
              "page": 3,
              "color": "blue",
              "semanticLevel": "limitations/problems",
              "selectedText": "legacy selected text",
              "comment": "",
              "createdAt": "2026-06-01T00:00:00Z",
              "updatedAt": "2026-06-01T00:00:00Z",
              "boxes": []
            }
          ],
          "exports": {
            "obsidianNotePath": "raw/papers/legacy.md"
          }
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let document = try decoder.decode(ReaderDocument.self, from: Data(json.utf8))

        try expect(document.schemaVersion == 1)
        try expect(document.paper.zoteroItemKey == "ABCDEFGH")
        try expect(document.paper.pdfPath == "/tmp/legacy.pdf")
        try expect(document.annotations.first?.selectedText == "legacy selected text")
        try expect(document.exports.obsidianNotePath == "raw/papers/legacy.md")
    }

    private static func testMarkdownExporterCreatesRequiredSections() throws {
        let markdown = MarkdownExporter().markdown(
            for: sampleDocument(),
            annotationJSONPath: "raw/reader-annotations/sample.json"
        )

        try expect(markdown.contains("# Concept Hierarchy from Highlights"))
        try expect(markdown.contains("## Highest-Level Concepts"))
        try expect(markdown.contains("## Secondary High-Level Concepts"))
        try expect(markdown.contains("## Detailed Concepts"))
        try expect(markdown.contains("## Limitations and Problems"))
        try expect(markdown.contains("# Highlights by Page"))
        try expect(markdown.contains("# My Reading Notes"))
        try expect(markdown.contains("# Open Questions"))
        try expect(markdown.contains("annotation_json_path: \"raw/reader-annotations/sample.json\""))
    }

    private static func testVaultExporterWritesMarkdownAndSidecarWithRelativePaths() throws {
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LLMWikiPDFReaderTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        let result = try VaultMarkdownExporter().export(sampleDocument(), vaultURL: vaultURL)

        try expect(FileManager.default.fileExists(atPath: result.markdownURL.path))
        try expect(FileManager.default.fileExists(atPath: result.sidecarURL.path))
        try expect(result.document.exports.obsidianNotePath == "raw/papers/2026 - Sample Paper - Reader Highlights.md")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let savedDocument = try decoder.decode(ReaderDocument.self, from: Data(contentsOf: result.sidecarURL))
        try expect(savedDocument.exports.obsidianNotePath == "raw/papers/2026 - Sample Paper - Reader Highlights.md")
    }

    private static func testZoteroResolverInfersItemKeyOnlyInsideConfiguredRoot() throws {
        let root = URL(fileURLWithPath: "/tmp/Zotero", isDirectory: true)
        let resolver = ZoteroResolver(root: ZoteroPDFRoot(url: root))
        let zoteroPDF = URL(fileURLWithPath: "/tmp/Zotero/Human/ABCDEFGH/Sample.pdf")
        let otherPDF = URL(fileURLWithPath: "/tmp/Other/ABCDEFGH/Sample.pdf")

        let metadata = resolver.metadata(forPDFAt: zoteroPDF)
        let otherMetadata = resolver.metadata(forPDFAt: otherPDF)

        try expect(metadata.zoteroItemKey == "ABCDEFGH")
        try expect(metadata.zoteroSelectURI == "zotero://select/library/items/ABCDEFGH")
        try expect(otherMetadata.zoteroItemKey == nil)
        try expect(otherMetadata.zoteroSelectURI == nil)
    }

    private static func sampleDocument() -> ReaderDocument {
        ReaderDocument(
            paper: PaperMetadata(
                title: "Sample Paper",
                authors: ["A. Researcher"],
                year: "2026",
                citekey: "Researcher2026Sample",
                zoteroItemKey: "ABCDEFGH",
                zoteroSelectURI: "zotero://select/library/items/ABCDEFGH",
                pdfPath: "/tmp/Sample Paper.pdf"
            ),
            annotations: [
                HighlightAnnotation(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                    page: 2,
                    color: .red,
                    selectedText: "A core idea.",
                    createdAt: Date(timeIntervalSince1970: 1_780_000_000),
                    updatedAt: Date(timeIntervalSince1970: 1_780_000_001),
                    boxes: [
                        HighlightBox(page: 2, bounds: RectValue(x: 1, y: 2, width: 3, height: 4))
                    ]
                )
            ],
            exports: ExportMetadata(obsidianNotePath: "raw/papers/sample.md")
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, file: StaticString = #file, line: UInt = #line) throws {
        if !condition() {
            throw SmokeTestError.expectationFailed(file: "\(file)", line: line)
        }
    }

    private static func require<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) throws -> T {
        guard let value else {
            throw SmokeTestError.requiredValueMissing(file: "\(file)", line: line)
        }
        return value
    }
}

enum SmokeTestError: Error, CustomStringConvertible {
    case expectationFailed(file: String, line: UInt)
    case requiredValueMissing(file: String, line: UInt)

    var description: String {
        switch self {
        case let .expectationFailed(file, line):
            return "Expectation failed at \(file):\(line)"
        case let .requiredValueMissing(file, line):
            return "Required value missing at \(file):\(line)"
        }
    }
}
