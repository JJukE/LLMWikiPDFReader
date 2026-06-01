#if os(macOS)
import SwiftUI

@main
struct LLMWikiPDFReaderApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1000, minHeight: 700)
        }
        .commands {
            CommandMenu("Reader") {
                Button("Highlight Selection") {
                    NotificationCenter.default.post(name: .highlightSelectionShortcut, object: nil)
                }
                .keyboardShortcut("h", modifiers: [.command])
            }
        }
    }
}

extension Notification.Name {
    static let highlightSelectionShortcut = Notification.Name("highlightSelectionShortcut")
}
#else
@main
struct LLMWikiPDFReaderApp {
    static func main() {
        fatalError("The app target is implemented for macOS first. AnnotationCore is shared for future iOS/iPadOS targets.")
    }
}
#endif
