#if os(macOS)
import SwiftUI

@main
struct LLMWikiPDFReaderApp: App {
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            ContentView(settings: settings)
                .frame(minWidth: 1000, minHeight: 700)
        }
        .commands {
            CommandMenu("Reader") {
                Button("Remove Selected Highlight") {
                    NotificationCenter.default.post(name: .removeSelectedHighlightShortcut, object: nil)
                }
                .keyboardShortcut(.delete, modifiers: [])

                Divider()

                Button("Back") {
                    NotificationCenter.default.post(name: .backShortcut, object: nil)
                }
                .keyboardShortcut(keyEquivalent(for: settings.previousPageShortcutKey), modifiers: [.command])

                Button("Forward") {
                    NotificationCenter.default.post(name: .forwardShortcut, object: nil)
                }
                .keyboardShortcut(keyEquivalent(for: settings.nextPageShortcutKey), modifiers: [.command])
            }
        }

        Settings {
            SettingsView(settings: settings)
        }
    }

    private func keyEquivalent(for value: String) -> KeyEquivalent {
        KeyEquivalent(value.first ?? " ")
    }
}

extension Notification.Name {
    static let removeSelectedHighlightShortcut = Notification.Name("removeSelectedHighlightShortcut")
    static let backShortcut = Notification.Name("backShortcut")
    static let forwardShortcut = Notification.Name("forwardShortcut")
}
#elseif os(iOS)
import SwiftUI

@main
struct LLMWikiPDFReaderApp: App {
    var body: some Scene {
        WindowGroup {
            MobileContentView()
        }
    }
}
#else
@main
struct LLMWikiPDFReaderApp {
    static func main() {
        fatalError("LLMWikiPDFReaderApp is implemented for macOS and iOS/iPadOS.")
    }
}
#endif
