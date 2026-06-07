import Foundation

public struct PaperMetadata: Codable, Equatable {
    public var title: String
    public var authors: [String]
    public var year: String?
    public var citekey: String?
    public var zoteroItemKey: String?
    public var zoteroSelectURI: String?
    public var pdfPath: String
    public var pdfRelativePath: String?
    public var pdfBookmark: Data?

    public init(
        title: String,
        authors: [String] = [],
        year: String? = nil,
        citekey: String? = nil,
        zoteroItemKey: String? = nil,
        zoteroSelectURI: String? = nil,
        pdfPath: String,
        pdfRelativePath: String? = nil,
        pdfBookmark: Data? = nil
    ) {
        self.title = title
        self.authors = authors
        self.year = year
        self.citekey = citekey
        self.zoteroItemKey = zoteroItemKey
        self.zoteroSelectURI = zoteroSelectURI
        self.pdfPath = pdfPath
        self.pdfRelativePath = pdfRelativePath
        self.pdfBookmark = pdfBookmark
    }

    enum CodingKeys: String, CodingKey {
        case title
        case authors
        case year
        case citekey
        case zoteroItemKey = "zotero_item_key"
        case zoteroSelectURI = "zotero_select_uri"
        case pdfPath = "pdf_path"
        case pdfRelativePath = "pdf_relative_path"
        case pdfBookmark = "pdf_bookmark"
    }

    enum LegacyCodingKeys: String, CodingKey {
        case zoteroItemKey
        case zoteroSelectURI
        case pdfPath
        case pdfRelativePath
        case pdfBookmark
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)

        title = try container.decode(String.self, forKey: .title)
        authors = try container.decodeIfPresent([String].self, forKey: .authors) ?? []
        year = try container.decodeIfPresent(String.self, forKey: .year)
        citekey = try container.decodeIfPresent(String.self, forKey: .citekey)
        zoteroItemKey = try container.decodeIfPresent(String.self, forKey: .zoteroItemKey)
            ?? legacy.decodeIfPresent(String.self, forKey: .zoteroItemKey)
        zoteroSelectURI = try container.decodeIfPresent(String.self, forKey: .zoteroSelectURI)
            ?? legacy.decodeIfPresent(String.self, forKey: .zoteroSelectURI)
        pdfPath = try container.decodeIfPresent(String.self, forKey: .pdfPath)
            ?? legacy.decode(String.self, forKey: .pdfPath)
        pdfRelativePath = try container.decodeIfPresent(String.self, forKey: .pdfRelativePath)
            ?? legacy.decodeIfPresent(String.self, forKey: .pdfRelativePath)
        pdfBookmark = try container.decodeIfPresent(Data.self, forKey: .pdfBookmark)
            ?? legacy.decodeIfPresent(Data.self, forKey: .pdfBookmark)
    }
}

public struct RectValue: Codable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct HighlightBox: Codable, Equatable {
    public var page: Int
    public var bounds: RectValue

    public init(page: Int, bounds: RectValue) {
        self.page = page
        self.bounds = bounds
    }
}

public struct HighlightAnnotation: Codable, Identifiable, Equatable {
    public var id: UUID
    public var page: Int
    public var color: HighlightColor
    public var semanticLevel: String
    public var selectedText: String
    public var comment: String
    public var createdAt: Date
    public var updatedAt: Date
    public var boxes: [HighlightBox]

    public init(
        id: UUID = UUID(),
        page: Int,
        color: HighlightColor,
        selectedText: String,
        comment: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        boxes: [HighlightBox] = []
    ) {
        self.id = id
        self.page = page
        self.color = color
        self.semanticLevel = color.semanticLevel
        self.selectedText = selectedText
        self.comment = comment
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.boxes = boxes
    }

    enum CodingKeys: String, CodingKey {
        case id
        case page
        case color
        case semanticLevel = "semantic_level"
        case selectedText = "selected_text"
        case comment
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case boxes = "bbox"
    }

    enum LegacyCodingKeys: String, CodingKey {
        case semanticLevel
        case selectedText
        case createdAt
        case updatedAt
        case boxes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        page = try container.decode(Int.self, forKey: .page)
        color = try container.decode(HighlightColor.self, forKey: .color)
        semanticLevel = try container.decodeIfPresent(String.self, forKey: .semanticLevel)
            ?? legacy.decodeIfPresent(String.self, forKey: .semanticLevel)
            ?? color.semanticLevel
        selectedText = try container.decodeIfPresent(String.self, forKey: .selectedText)
            ?? legacy.decode(String.self, forKey: .selectedText)
        comment = try container.decodeIfPresent(String.self, forKey: .comment) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
            ?? legacy.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
            ?? legacy.decode(Date.self, forKey: .updatedAt)
        boxes = try container.decodeIfPresent([HighlightBox].self, forKey: .boxes)
            ?? legacy.decodeIfPresent([HighlightBox].self, forKey: .boxes)
            ?? []
    }
}

public struct ExportMetadata: Codable, Equatable {
    public var obsidianNotePath: String?
    public var wikiPagePath: String?

    public init(obsidianNotePath: String? = nil, wikiPagePath: String? = nil) {
        self.obsidianNotePath = obsidianNotePath
        self.wikiPagePath = wikiPagePath
    }

    enum CodingKeys: String, CodingKey {
        case obsidianNotePath = "obsidian_note_path"
        case wikiPagePath = "wiki_page_path"
    }

    enum LegacyCodingKeys: String, CodingKey {
        case obsidianNotePath
        case wikiPagePath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        obsidianNotePath = try container.decodeIfPresent(String.self, forKey: .obsidianNotePath)
            ?? legacy.decodeIfPresent(String.self, forKey: .obsidianNotePath)
        wikiPagePath = try container.decodeIfPresent(String.self, forKey: .wikiPagePath)
            ?? legacy.decodeIfPresent(String.self, forKey: .wikiPagePath)
    }
}

public struct DeletedAnnotation: Codable, Identifiable, Equatable {
    public var id: UUID
    public var deletedAt: Date

    public init(id: UUID, deletedAt: Date = Date()) {
        self.id = id
        self.deletedAt = deletedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case deletedAt = "deleted_at"
    }

    enum LegacyCodingKeys: String, CodingKey {
        case deletedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
            ?? legacy.decode(Date.self, forKey: .deletedAt)
    }
}

public struct ReaderDocument: Codable, Equatable {
    public var schemaVersion: Int
    public var paper: PaperMetadata
    public var annotations: [HighlightAnnotation]
    public var deletedAnnotations: [DeletedAnnotation]
    public var exports: ExportMetadata

    public init(
        schemaVersion: Int = 2,
        paper: PaperMetadata,
        annotations: [HighlightAnnotation] = [],
        deletedAnnotations: [DeletedAnnotation] = [],
        exports: ExportMetadata = ExportMetadata()
    ) {
        self.schemaVersion = schemaVersion
        self.paper = paper
        self.annotations = annotations
        self.deletedAnnotations = deletedAnnotations
        self.exports = exports
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case paper
        case annotations
        case deletedAnnotations = "deleted_annotations"
        case exports
    }

    enum LegacyCodingKeys: String, CodingKey {
        case schemaVersion
        case deletedAnnotations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? legacy.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? 1
        paper = try container.decode(PaperMetadata.self, forKey: .paper)
        annotations = try container.decodeIfPresent([HighlightAnnotation].self, forKey: .annotations) ?? []
        deletedAnnotations = try container.decodeIfPresent([DeletedAnnotation].self, forKey: .deletedAnnotations)
            ?? legacy.decodeIfPresent([DeletedAnnotation].self, forKey: .deletedAnnotations)
            ?? []
        exports = try container.decodeIfPresent(ExportMetadata.self, forKey: .exports) ?? ExportMetadata()
    }

    public mutating func markAnnotationsDeleted(withIDs ids: some Sequence<HighlightAnnotation.ID>, at date: Date = Date()) {
        let uniqueIDs = Set(ids)
        annotations.removeAll { uniqueIDs.contains($0.id) }

        for id in uniqueIDs {
            if let index = deletedAnnotations.firstIndex(where: { $0.id == id }) {
                if date > deletedAnnotations[index].deletedAt {
                    deletedAnnotations[index].deletedAt = date
                }
            } else {
                deletedAnnotations.append(DeletedAnnotation(id: id, deletedAt: date))
            }
        }
    }
}
