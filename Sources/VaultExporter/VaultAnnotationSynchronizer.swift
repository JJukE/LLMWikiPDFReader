import AnnotationCore
import Foundation

public struct VaultAnnotationSyncResult: Equatable {
    public var document: ReaderDocument
    public var sidecarURL: URL
    public var markdownURL: URL
    public var mergedExistingSidecar: Bool

    public init(document: ReaderDocument, sidecarURL: URL, markdownURL: URL, mergedExistingSidecar: Bool) {
        self.document = document
        self.sidecarURL = sidecarURL
        self.markdownURL = markdownURL
        self.mergedExistingSidecar = mergedExistingSidecar
    }
}

public struct VaultAnnotationSynchronizer {
    public var fileManager: FileManager
    public var store: AnnotationStore
    public var exporter: VaultMarkdownExporter

    public init(
        fileManager: FileManager = .default,
        store: AnnotationStore = AnnotationStore(),
        exporter: VaultMarkdownExporter = VaultMarkdownExporter()
    ) {
        self.fileManager = fileManager
        self.store = store
        self.exporter = exporter
    }

    public func saveAndExport(_ document: ReaderDocument, vaultURL: URL) throws -> VaultAnnotationSyncResult {
        let sidecarURL = try store.sidecarURL(for: document, vaultURL: vaultURL)
        let hadExistingSidecar = fileManager.fileExists(atPath: sidecarURL.path)
        let mergedDocument = try store.mergedDocument(document, withExistingDocumentAt: sidecarURL)
        let exportResult = try exporter.export(mergedDocument, vaultURL: vaultURL)

        return VaultAnnotationSyncResult(
            document: exportResult.document,
            sidecarURL: exportResult.sidecarURL,
            markdownURL: exportResult.markdownURL,
            mergedExistingSidecar: hadExistingSidecar
        )
    }

    public func loadMergedSidecar(for document: ReaderDocument, vaultURL: URL) throws -> ReaderDocument {
        let sidecarURL = try store.sidecarURL(for: document, vaultURL: vaultURL)
        return try store.mergedDocument(document, withExistingDocumentAt: sidecarURL)
    }
}
