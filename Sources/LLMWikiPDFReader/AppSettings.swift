#if os(macOS)
import AppKit
import Combine
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    @Published var autoSaveAnnotations: Bool {
        didSet {
            defaults.set(autoSaveAnnotations, forKey: Keys.autoSaveAnnotations)
        }
    }

    @Published var continuousScrolling: Bool {
        didSet {
            defaults.set(continuousScrolling, forKey: Keys.continuousScrolling)
        }
    }

    @Published var showPageBreaks: Bool {
        didSet {
            defaults.set(showPageBreaks, forKey: Keys.showPageBreaks)
        }
    }

    @Published var previousPageShortcutKey: String {
        didSet {
            let normalized = Self.normalizedShortcutKey(previousPageShortcutKey, fallback: oldValue)
            guard previousPageShortcutKey == normalized else {
                previousPageShortcutKey = normalized
                return
            }
            defaults.set(previousPageShortcutKey, forKey: Keys.previousPageShortcutKey)
        }
    }

    @Published var nextPageShortcutKey: String {
        didSet {
            let normalized = Self.normalizedShortcutKey(nextPageShortcutKey, fallback: oldValue)
            guard nextPageShortcutKey == normalized else {
                nextPageShortcutKey = normalized
                return
            }
            defaults.set(nextPageShortcutKey, forKey: Keys.nextPageShortcutKey)
        }
    }

    @Published private(set) var defaultPDFDirectoryPath: String?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        autoSaveAnnotations = defaults.object(forKey: Keys.autoSaveAnnotations) as? Bool ?? true
        continuousScrolling = defaults.object(forKey: Keys.continuousScrolling) as? Bool ?? true
        showPageBreaks = defaults.object(forKey: Keys.showPageBreaks) as? Bool ?? true
        previousPageShortcutKey = Self.normalizedShortcutKey(
            defaults.string(forKey: Keys.previousPageShortcutKey) ?? "[",
            fallback: "["
        )
        nextPageShortcutKey = Self.normalizedShortcutKey(
            defaults.string(forKey: Keys.nextPageShortcutKey) ?? "]",
            fallback: "]"
        )
        defaultPDFDirectoryPath = defaults.string(forKey: Keys.defaultPDFDirectoryPath)
    }

    func setDefaultPDFDirectory(_ url: URL) {
        defaultPDFDirectoryPath = url.path
        defaults.set(url.path, forKey: Keys.defaultPDFDirectoryPath)

        do {
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            defaults.set(bookmark, forKey: Keys.defaultPDFDirectoryBookmark)
        } catch {
            defaults.removeObject(forKey: Keys.defaultPDFDirectoryBookmark)
        }
    }

    func clearDefaultPDFDirectory() {
        defaultPDFDirectoryPath = nil
        defaults.removeObject(forKey: Keys.defaultPDFDirectoryPath)
        defaults.removeObject(forKey: Keys.defaultPDFDirectoryBookmark)
    }

    func defaultPDFDirectoryURL() -> URL? {
        if let data = defaults.data(forKey: Keys.defaultPDFDirectoryBookmark) {
            do {
                var isStale = false
                let url = try URL(
                    resolvingBookmarkData: data,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                if isStale {
                    setDefaultPDFDirectory(url)
                }
                return url
            } catch {
                defaults.removeObject(forKey: Keys.defaultPDFDirectoryBookmark)
            }
        }

        guard let path = defaultPDFDirectoryPath, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private static func normalizedShortcutKey(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return fallback }
        return String(first)
    }
}

private enum Keys {
    static let autoSaveAnnotations = "autoSaveAnnotations"
    static let continuousScrolling = "continuousScrolling"
    static let showPageBreaks = "showPageBreaks"
    static let previousPageShortcutKey = "previousPageShortcutKey"
    static let nextPageShortcutKey = "nextPageShortcutKey"
    static let defaultPDFDirectoryBookmark = "defaultPDFDirectoryBookmark"
    static let defaultPDFDirectoryPath = "defaultPDFDirectoryPath"
}
#endif
