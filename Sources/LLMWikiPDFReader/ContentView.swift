#if os(macOS)
import AnnotationCore
import SwiftUI

struct ContentView: View {
    @Environment(\.openSettings) private var openSettings
    @ObservedObject private var settings: AppSettings
    @StateObject private var appState: AppState

    init(settings: AppSettings) {
        self.settings = settings
        _appState = StateObject(wrappedValue: AppState(settings: settings))
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 420)
        } detail: {
            VStack(spacing: 0) {
                if appState.pdfDocument == nil {
                    ContentUnavailableView("No PDF Open", systemImage: "doc.text.magnifyingglass")
                } else {
                    PDFKitView(
                        pdfDocument: appState.pdfDocument,
                        pdfView: $appState.pdfView,
                        continuousScrolling: settings.continuousScrolling,
                        showPageBreaks: settings.showPageBreaks,
                        onSelectAnnotation: { appState.select(annotationID: $0, navigate: false) },
                        onHighlightSelection: { appState.addHighlightFromSelection(color: $0) },
                        onRemoveHighlight: appState.removeSelectedOrSelectionHighlights,
                        onViewportChanged: appState.noteViewportChanged,
                        onViewReady: appState.scheduleInitialViewLocationCapture
                    )
                }
                Divider()
                Text(appState.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .removeSelectedHighlightShortcut)) { _ in
            appState.removeSelectedHighlight()
        }
        .onReceive(NotificationCenter.default.publisher(for: .backShortcut)) { _ in
            appState.goBack()
        }
        .onReceive(NotificationCenter.default.publisher(for: .forwardShortcut)) { _ in
            appState.goForward()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LLM Wiki Reader")
                .font(.headline)

            Button("Choose Vault", action: appState.chooseVault)
            Button("Open PDF", action: appState.openPDF)
            Button("Settings") {
                openSettings()
            }

            Divider()

            Button("Export Markdown", action: appState.exportMarkdown)
                .keyboardShortcut("e", modifiers: [.command])

            Divider()

            Text("Move")
                .font(.headline)

            moveToolbar

            Divider()

            Text("Highlights")
                .font(.headline)

            highlightToolbar

            List {
                ForEach(appState.annotations) { annotation in
                    Button {
                        appState.select(annotationID: annotation.id, navigate: true)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Page \(annotation.page) · \(annotation.color.rawValue.capitalized)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(annotation.selectedText)
                                .lineLimit(3)
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        appState.selectedAnnotationID == annotation.id
                            ? Color.accentColor.opacity(0.12)
                            : Color.clear
                    )
                }
            }
        }
        .padding()
    }

    private var moveToolbar: some View {
        HStack(spacing: 8) {
            Button {
                appState.goBack()
            } label: {
                Image(systemName: "chevron.left")
            }
            .help("Back")
            .disabled(!appState.canGoBack)

            Button {
                appState.goForward()
            } label: {
                Image(systemName: "chevron.right")
            }
            .help("Forward")
            .disabled(!appState.canGoForward)

            Spacer()
        }
    }

    private var highlightToolbar: some View {
        HStack(spacing: 8) {
            ForEach(HighlightColor.allCases) { color in
                Button {
                    appState.addHighlightFromSelection(color: color)
                } label: {
                    Circle()
                        .fill(swiftUIColor(for: color))
                        .frame(width: 18, height: 18)
                }
                .help(label(for: color))
                .keyboardShortcut(keyEquivalent(for: color), modifiers: [.command])
            }
            Button {
                appState.removeSelectedHighlight()
            } label: {
                Image(systemName: "trash")
            }
            .help("Remove selected highlight")
            .disabled(appState.selectedAnnotationID == nil)

            Spacer()
        }
    }

    private func label(for color: HighlightColor) -> String {
        "\(color.rawValue.capitalized): \(color.semanticLevel)"
    }

    private func swiftUIColor(for color: HighlightColor) -> Color {
        switch color {
        case .red:
            return .red
        case .green:
            return .green
        case .yellow:
            return .yellow
        case .blue:
            return .blue
        }
    }

    private func keyEquivalent(for color: HighlightColor) -> KeyEquivalent {
        switch color {
        case .red:
            return "1"
        case .green:
            return "2"
        case .yellow:
            return "3"
        case .blue:
            return "4"
        }
    }
}
#endif
