#if os(macOS)
import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                settingsSection("Annotations") {
                    Toggle("Save annotations after highlight changes", isOn: $settings.autoSaveAnnotations)
                }

                settingsSection("PDF View") {
                    Toggle("Use continuous scrolling", isOn: $settings.continuousScrolling)
                    Toggle("Show page breaks", isOn: $settings.showPageBreaks)
                }

                settingsSection("Navigation") {
                    settingRow("Back") {
                        shortcutField(text: $settings.previousPageShortcutKey)
                    }

                    settingRow("Forward") {
                        shortcutField(text: $settings.nextPageShortcutKey)
                    }

                    Text("Shortcuts use the Command modifier. Enter one key for each action.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                settingsSection("Open PDF") {
                    settingRow("Default folder") {
                        Text(settings.defaultPDFDirectoryPath ?? "None")
                            .foregroundStyle(settings.defaultPDFDirectoryPath == nil ? .secondary : .primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Button("Choose Default PDF Folder", action: chooseDefaultPDFFolder)
                        Button("Clear", action: settings.clearDefaultPDFDirectory)
                            .disabled(settings.defaultPDFDirectoryPath == nil)
                    }
                }
            }
            .padding(20)
        }
        .frame(width: 460, height: 420)
    }

    private func chooseDefaultPDFFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose the folder where Open PDF should start."
        if let url = settings.defaultPDFDirectoryURL() {
            panel.directoryURL = url
        }

        if panel.runModal() == .OK, let url = panel.url {
            settings.setDefaultPDFDirectory(url)
        }
    }

    private func shortcutField(text: Binding<String>) -> some View {
        HStack(spacing: 4) {
            Text("Command")
                .foregroundStyle(.secondary)
            Text("+")
                .foregroundStyle(.secondary)
            TextField("", text: text)
                .multilineTextAlignment(.center)
                .frame(width: 40)
        }
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func settingRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            content()
        }
    }
}
#endif
