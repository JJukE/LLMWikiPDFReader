import AnnotationCore
import Foundation

public struct VaultExportResult: Equatable {
    public var document: ReaderDocument
    public var markdownURL: URL
    public var sidecarURL: URL

    public init(document: ReaderDocument, markdownURL: URL, sidecarURL: URL) {
        self.document = document
        self.markdownURL = markdownURL
        self.sidecarURL = sidecarURL
    }
}

public struct VaultMarkdownExporter {
    public var fileManager: FileManager
    public var store: AnnotationStore
    public var markdownExporter: MarkdownExporter

    public init(
        fileManager: FileManager = .default,
        store: AnnotationStore = AnnotationStore(),
        markdownExporter: MarkdownExporter = MarkdownExporter()
    ) {
        self.fileManager = fileManager
        self.store = store
        self.markdownExporter = markdownExporter
    }

    public func export(_ document: ReaderDocument, vaultURL: URL) throws -> VaultExportResult {
        var exportedDocument = document
        let sidecarURL = try store.sidecarURL(for: document, vaultURL: vaultURL)
        let papersURL = vaultURL.appendingPathComponent("raw/papers", isDirectory: true)
        try fileManager.createDirectory(at: papersURL, withIntermediateDirectories: true)

        let markdownURL = papersURL.appendingPathComponent(markdownFileName(for: document))
        let relativeSidecar = relativePath(for: sidecarURL, in: vaultURL)
        let markdown = markdownExporter.markdown(for: exportedDocument, annotationJSONPath: relativeSidecar)
        try markdown.write(to: markdownURL, atomically: true, encoding: .utf8)

        exportedDocument.exports.obsidianNotePath = relativePath(for: markdownURL, in: vaultURL)
        try store.save(exportedDocument, to: sidecarURL)

        return VaultExportResult(document: exportedDocument, markdownURL: markdownURL, sidecarURL: sidecarURL)
    }

    public func relativePath(for fileURL: URL, in vaultURL: URL) -> String {
        let vaultPath = vaultURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(vaultPath + "/") else {
            return filePath
        }
        return String(filePath.dropFirst(vaultPath.count + 1))
    }

    public func markdownFileName(for document: ReaderDocument) -> String {
        let yearPrefix = document.paper.year.map { "\($0) - " } ?? ""
        let title = document.paper.title.replacingOccurrences(of: "/", with: "-")
        return "\(yearPrefix)\(title) - Reader Highlights.md"
    }
}
