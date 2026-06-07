import Foundation

public struct ReaderDocumentMerger {
    public init() {}

    public func merged(local: ReaderDocument, remote: ReaderDocument) -> ReaderDocument {
        var result = local
        result.schemaVersion = max(2, local.schemaVersion, remote.schemaVersion)
        result.paper = mergedPaper(local.paper, remote.paper)
        result.annotations = mergedAnnotations(local: local, remote: remote)
        result.deletedAnnotations = mergedTombstones(local: local, remote: remote, annotations: result.annotations)
        result.exports = mergedExports(local.exports, remote.exports)
        return result
    }

    private func mergedPaper(_ local: PaperMetadata, _ remote: PaperMetadata) -> PaperMetadata {
        var paper = local
        if paper.title.isEmpty { paper.title = remote.title }
        if paper.authors.isEmpty { paper.authors = remote.authors }
        if paper.year == nil { paper.year = remote.year }
        if paper.citekey == nil { paper.citekey = remote.citekey }
        if paper.zoteroItemKey == nil { paper.zoteroItemKey = remote.zoteroItemKey }
        if paper.zoteroSelectURI == nil { paper.zoteroSelectURI = remote.zoteroSelectURI }
        if paper.pdfPath.isEmpty { paper.pdfPath = remote.pdfPath }
        if paper.pdfRelativePath == nil { paper.pdfRelativePath = remote.pdfRelativePath }
        if paper.pdfBookmark == nil { paper.pdfBookmark = remote.pdfBookmark }
        return paper
    }

    private func mergedAnnotations(local: ReaderDocument, remote: ReaderDocument) -> [HighlightAnnotation] {
        var annotationsByID: [HighlightAnnotation.ID: HighlightAnnotation] = [:]

        for annotation in local.annotations + remote.annotations {
            if let existing = annotationsByID[annotation.id] {
                if annotation.updatedAt > existing.updatedAt {
                    annotationsByID[annotation.id] = annotation
                }
            } else {
                annotationsByID[annotation.id] = annotation
            }
        }

        let tombstones = newestTombstones(local.deletedAnnotations + remote.deletedAnnotations)
        for (id, tombstone) in tombstones {
            guard let annotation = annotationsByID[id] else { continue }
            if tombstone.deletedAt >= annotation.updatedAt {
                annotationsByID[id] = nil
            }
        }

        return annotationsByID.values.sorted { lhs, rhs in
            if lhs.page != rhs.page { return lhs.page < rhs.page }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func mergedTombstones(
        local: ReaderDocument,
        remote: ReaderDocument,
        annotations: [HighlightAnnotation]
    ) -> [DeletedAnnotation] {
        let annotationsByID = Dictionary(uniqueKeysWithValues: annotations.map { ($0.id, $0) })
        let tombstones = newestTombstones(local.deletedAnnotations + remote.deletedAnnotations)
            .filter { id, tombstone in
                guard let annotation = annotationsByID[id] else { return true }
                return tombstone.deletedAt >= annotation.updatedAt
            }

        return tombstones.values.sorted { lhs, rhs in
            if lhs.deletedAt != rhs.deletedAt { return lhs.deletedAt < rhs.deletedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func newestTombstones(_ tombstones: [DeletedAnnotation]) -> [DeletedAnnotation.ID: DeletedAnnotation] {
        var newestByID: [DeletedAnnotation.ID: DeletedAnnotation] = [:]
        for tombstone in tombstones {
            if let existing = newestByID[tombstone.id] {
                if tombstone.deletedAt > existing.deletedAt {
                    newestByID[tombstone.id] = tombstone
                }
            } else {
                newestByID[tombstone.id] = tombstone
            }
        }
        return newestByID
    }

    private func mergedExports(_ local: ExportMetadata, _ remote: ExportMetadata) -> ExportMetadata {
        ExportMetadata(
            obsidianNotePath: local.obsidianNotePath ?? remote.obsidianNotePath,
            wikiPagePath: local.wikiPagePath ?? remote.wikiPagePath
        )
    }
}
