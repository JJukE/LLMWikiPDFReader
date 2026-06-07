import AnnotationCore
import Foundation

public struct ZoteroPDFRoot {
    public static var defaultURL: URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return (documentsURL ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true))
            .appendingPathComponent("Zotero", isDirectory: true)
    }

    public static var defaultPath: String {
        defaultURL.path
    }

    public var url: URL

    public init(url: URL = Self.defaultURL) {
        self.url = url
    }
}

public struct ZoteroResolver {
    public var root: ZoteroPDFRoot
    public var metadataGuessing: MetadataGuessing

    public init(
        root: ZoteroPDFRoot = ZoteroPDFRoot(),
        metadataGuessing: MetadataGuessing = MetadataGuessing()
    ) {
        self.root = root
        self.metadataGuessing = metadataGuessing
    }

    public func metadata(forPDFAt url: URL, bookmark: Data? = nil) -> PaperMetadata {
        var metadata = metadataGuessing.paperMetadata(forPDFAt: url)
        metadata.pdfBookmark = bookmark

        if isInsideZoteroRoot(url) {
            metadata.zoteroItemKey = inferredZoteroItemKey(from: url)
            if let key = metadata.zoteroItemKey {
                metadata.zoteroSelectURI = "zotero://select/library/items/\(key)"
            }
        }

        return metadata
    }

    public func isInsideZoteroRoot(_ url: URL) -> Bool {
        let rootPath = root.url.standardizedFileURL.path
        let pdfPath = url.standardizedFileURL.path
        return pdfPath == rootPath || pdfPath.hasPrefix(rootPath + "/")
    }

    public func inferredZoteroItemKey(from url: URL) -> String? {
        let candidates = url.deletingLastPathComponent().pathComponents.reversed()
        for component in candidates {
            if component.range(of: #"^[A-Z0-9]{8}$"#, options: .regularExpression) != nil {
                return component
            }
        }
        return nil
    }
}
