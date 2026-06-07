import Foundation

public enum AnnotationStoreError: Error {
    case invalidVault(URL)
}

public struct AnnotationStore {
    public var fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func sidecarURL(for document: ReaderDocument, vaultURL: URL) throws -> URL {
        let root = vaultURL.appendingPathComponent("raw/reader-annotations", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent("\(documentIdentifier(for: document)).json")
    }

    public func load(from url: URL) throws -> ReaderDocument {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ReaderDocument.self, from: data)
    }

    public func save(_ document: ReaderDocument, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(document)
        try data.write(to: url, options: [.atomic])
    }

    public func mergedDocument(_ document: ReaderDocument, withExistingDocumentAt url: URL) throws -> ReaderDocument {
        guard fileManager.fileExists(atPath: url.path) else {
            return document
        }

        let existingDocument = try load(from: url)
        return ReaderDocumentMerger().merged(local: document, remote: existingDocument)
    }

    public func documentIdentifier(for document: ReaderDocument) -> String {
        if let citekey = document.paper.citekey, !citekey.isEmpty {
            return slug(citekey)
        }
        if let key = document.paper.zoteroItemKey, !key.isEmpty {
            return slug(key)
        }
        let yearPrefix = document.paper.year.map { "\($0)-" } ?? ""
        return slug("\(yearPrefix)\(document.paper.title)")
    }

    public func slug(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let collapsed = String(scalars).replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-")).lowercased()
    }

    public func relativePath(for fileURL: URL, in vaultURL: URL) -> String? {
        let vaultPath = vaultURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(vaultPath + "/") else {
            return nil
        }
        return String(filePath.dropFirst(vaultPath.count + 1))
    }

    public func fileURL(forVaultRelativePath relativePath: String, in vaultURL: URL) -> URL {
        relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .reduce(vaultURL) { url, component in
                url.appendingPathComponent(String(component))
            }
    }
}
