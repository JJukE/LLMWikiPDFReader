import Foundation

public struct MetadataGuessing {
    public init() {}

    public func paperMetadata(forPDFAt url: URL) -> PaperMetadata {
        let fileName = url.deletingPathExtension().lastPathComponent
        let year = firstYear(in: fileName)
        let title = fileName
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return PaperMetadata(title: title.isEmpty ? "Untitled PDF" : title, year: year, pdfPath: url.path)
    }

    private func firstYear(in value: String) -> String? {
        let pattern = #"(19|20)\d{2}"#
        guard let range = value.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        return String(value[range])
    }
}
