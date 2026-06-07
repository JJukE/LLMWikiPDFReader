import Foundation

public struct MarkdownExporter {
    public init() {}

    public func markdown(for document: ReaderDocument, annotationJSONPath: String? = nil) -> String {
        var lines: [String] = []
        lines.append("---")
        lines.append("title: \(yaml(document.paper.title))")
        lines.append("authors: \(yamlArray(document.paper.authors))")
        if let year = document.paper.year { lines.append("year: \(yaml(year))") }
        if let citekey = document.paper.citekey { lines.append("citekey: \(yaml(citekey))") }
        if let itemKey = document.paper.zoteroItemKey { lines.append("zotero_item_key: \(yaml(itemKey))") }
        if let zoteroURI = document.paper.zoteroSelectURI { lines.append("zotero_select_uri: \(yaml(zoteroURI))") }
        lines.append("pdf_path: \(yaml(document.paper.pdfPath))")
        if let pdfRelativePath = document.paper.pdfRelativePath {
            lines.append("pdf_relative_path: \(yaml(pdfRelativePath))")
        }
        if let annotationJSONPath { lines.append("annotation_json_path: \(yaml(annotationJSONPath))") }
        lines.append("---")
        lines.append("")
        lines.append("# Concept Hierarchy from Highlights")
        lines.append("")

        for color in HighlightColor.allCases {
            lines.append("## \(color.markdownHeading)")
            let items = document.annotations
                .filter { $0.color == color }
                .sorted { ($0.page, $0.createdAt) < ($1.page, $1.createdAt) }
            if items.isEmpty {
                lines.append("")
                lines.append("_No highlights yet._")
            } else {
                for item in items {
                    lines.append("")
                    lines.append("- Page \(item.page): \(item.selectedText.normalizedForMarkdownList())")
                    if !item.comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        lines.append("  - Note: \(item.comment.normalizedForMarkdownList())")
                    }
                }
            }
            lines.append("")
        }

        lines.append("# Highlights by Page")
        lines.append("")
        let groupedPages = Dictionary(grouping: document.annotations, by: \.page)
        for page in groupedPages.keys.sorted() {
            lines.append("## Page \(page)")
            for item in groupedPages[page, default: []].sorted(by: { $0.createdAt < $1.createdAt }) {
                lines.append("- \(item.color.rawValue.capitalized) / \(item.semanticLevel): \(item.selectedText.normalizedForMarkdownList())")
            }
            lines.append("")
        }

        lines.append("# My Reading Notes")
        lines.append("")
        lines.append("To be filled after personal reading.")
        lines.append("")
        lines.append("# Open Questions")
        lines.append("")
        lines.append("- ")
        lines.append("")

        return lines.joined(separator: "\n")
    }

    private func yaml(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private func yamlArray(_ values: [String]) -> String {
        "[\(values.map(yaml).joined(separator: ", "))]"
    }
}

private extension String {
    func normalizedForMarkdownList() -> String {
        replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
