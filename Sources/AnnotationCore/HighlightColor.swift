import Foundation

public enum HighlightColor: String, Codable, CaseIterable, Identifiable {
    case red
    case green
    case yellow
    case blue

    public var id: String { rawValue }

    public var semanticLevel: String {
        switch self {
        case .red:
            return "highest-level concept"
        case .green:
            return "secondary high-level concept"
        case .yellow:
            return "detailed-level concept"
        case .blue:
            return "limitations/problems"
        }
    }

    public var markdownHeading: String {
        switch self {
        case .red:
            return "Highest-Level Concepts"
        case .green:
            return "Secondary High-Level Concepts"
        case .yellow:
            return "Detailed Concepts"
        case .blue:
            return "Limitations and Problems"
        }
    }
}
