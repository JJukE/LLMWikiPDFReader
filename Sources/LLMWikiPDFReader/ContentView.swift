#if os(macOS)
import AnnotationCore
import SwiftUI

struct ContentView: View {
    @StateObject private var appState = AppState()

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 420)
        } detail: {
            VStack(spacing: 0) {
                toolbar
                Divider()
                if appState.pdfDocument == nil {
                    ContentUnavailableView("No PDF Open", systemImage: "doc.text.magnifyingglass")
                } else {
                    PDFKitView(pdfDocument: appState.pdfDocument, pdfView: $appState.pdfView)
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
        .onReceive(NotificationCenter.default.publisher(for: .highlightSelectionShortcut)) { _ in
            appState.addHighlightFromSelection()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LLM Wiki Reader")
                .font(.headline)

            Button("Choose Vault", action: appState.chooseVault)
            Button("Open PDF", action: appState.openPDF)

            Divider()

            Picker("Highlight", selection: $appState.selectedColor) {
                ForEach(HighlightColor.allCases) { color in
                    Text(label(for: color)).tag(color)
                }
            }
            .pickerStyle(.radioGroup)

            Button("Highlight Selection", action: appState.addHighlightFromSelection)
                .keyboardShortcut("h", modifiers: [.command])

            Button("Export Markdown", action: appState.exportMarkdown)
                .keyboardShortcut("e", modifiers: [.command])

            Divider()

            Text("Highlights")
                .font(.headline)

            List(appState.annotations) { annotation in
                Button {
                    appState.jump(to: annotation)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Page \(annotation.page) · \(annotation.color.rawValue.capitalized)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(annotation.selectedText)
                            .lineLimit(3)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            ForEach(HighlightColor.allCases) { color in
                Button {
                    appState.selectedColor = color
                    appState.addHighlightFromSelection()
                } label: {
                    Circle()
                        .fill(swiftUIColor(for: color))
                        .frame(width: 18, height: 18)
                }
                .help(label(for: color))
                .keyboardShortcut(keyEquivalent(for: color), modifiers: [.command])
            }
            Spacer()
        }
        .padding(8)
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
