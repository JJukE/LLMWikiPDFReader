#if os(macOS)
import AnnotationCore
import AppKit
import PDFKit
import SwiftUI
import ZoteroResolver

struct ContentView: View {
    @State private var annotationsDirectoryURL: URL?
    @State private var pdfDocument: PDFDocument?
    @State private var pdfView: PDFView?
    @State private var readerDocument: ReaderDocument?
    @State private var selectedAnnotationID: HighlightAnnotation.ID?
    @State private var status = "Choose an Annotations Folder to begin."

    private let store = AnnotationStore()
    private let zoteroResolver = ZoteroResolver()

    var body: some View {
        Group {
            if annotationsDirectoryURL == nil {
                requiredAnnotationsFolderView
            } else {
                NavigationSplitView {
                    sidebar
                        .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 380)
                } detail: {
                    VStack(spacing: 0) {
                        if pdfDocument == nil {
                            ContentUnavailableView("No PDF Open", systemImage: "doc.text.magnifyingglass")
                        } else {
                            PDFKitView(
                                pdfDocument: pdfDocument,
                                pdfView: $pdfView,
                                continuousScrolling: true,
                                showPageBreaks: true,
                                onSelectAnnotation: { selectedAnnotationID = $0 },
                                onHighlightSelection: addHighlightFromSelection,
                                onRemoveHighlight: removeSelectedHighlight,
                                onViewportChanged: {},
                                onViewReady: {}
                            )
                        }
                        Divider()
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                }
            }
        }
        .onAppear(perform: restoreAnnotationsFolder)
        .frame(minWidth: 1000, minHeight: 700)
    }

    private var requiredAnnotationsFolderView: some View {
        VStack(spacing: 16) {
            ContentUnavailableView(
                "Annotations Folder Required",
                systemImage: "folder.badge.plus",
                description: Text("Choose the folder where highlight JSON files will be saved.")
            )
            Button("Choose Annotations Folder", action: chooseAnnotationsFolder)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LLM Wiki Reader")
                .font(.headline)

            Button("Open PDF", action: openPDF)

            Divider()

            Text("Highlights")
                .font(.headline)

            HStack(spacing: 8) {
                ForEach(HighlightColor.allCases) { color in
                    Button {
                        addHighlightFromSelection(color)
                    } label: {
                        Circle()
                            .fill(swiftUIColor(for: color))
                            .frame(width: 18, height: 18)
                    }
                    .help(color.semanticLevel)
                }

                Button {
                    removeSelectedHighlight()
                } label: {
                    Image(systemName: "trash")
                }
                .help("Remove selected highlight")
                .disabled(selectedAnnotationID == nil)

                Spacer()
            }

            List {
                ForEach(annotations) { annotation in
                    Button {
                        selectedAnnotationID = annotation.id
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
                        selectedAnnotationID == annotation.id
                            ? Color.accentColor.opacity(0.12)
                            : Color.clear
                    )
                }
            }
        }
        .padding()
    }

    private var annotations: [HighlightAnnotation] {
        readerDocument?.annotations.sorted { ($0.page, $0.createdAt) < ($1.page, $1.createdAt) } ?? []
    }

    private func chooseAnnotationsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose the folder where highlight JSON files should be saved."
        panel.directoryURL = annotationsDirectoryURL

        if panel.runModal() == .OK, let url = panel.url {
            persistAnnotationsFolder(url)
            annotationsDirectoryURL = url
            loadSidecarIfAvailable()
            redrawHighlights()
            status = "Annotations Folder selected: \(url.path)"
        }
    }

    private func openPDF() {
        guard annotationsDirectoryURL != nil else {
            status = "Choose an Annotations Folder before opening PDFs."
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a PDF."

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let document = PDFDocument(url: url) else {
            status = "Could not open PDF."
            return
        }

        var metadata = zoteroResolver.metadata(forPDFAt: url, bookmark: securityScopedBookmark(for: url))
        if let annotationsDirectoryURL, let relativePath = store.relativePath(for: url, in: annotationsDirectoryURL) {
            metadata.pdfRelativePath = relativePath
        }

        pdfDocument = document
        selectedAnnotationID = nil
        readerDocument = ReaderDocument(paper: metadata)
        loadSidecarIfAvailable()
        redrawHighlights()
        status = "Opened \(metadata.title)"
    }

    private func addHighlightFromSelection(_ color: HighlightColor) {
        guard var current = readerDocument, let pdfView, let selection = pdfView.currentSelection else {
            status = "Select text before highlighting."
            return
        }

        let selectedText = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !selectedText.isEmpty else {
            status = "Selection has no extractable text."
            return
        }

        let lineSelections = selection.selectionsByLine()
        let annotationID = UUID()
        var boxes: [HighlightBox] = []
        var firstPageNumber: Int?

        for line in lineSelections {
            for page in line.pages {
                let pageIndex = pdfDocument?.index(for: page) ?? 0
                let pageNumber = pageIndex + 1
                if firstPageNumber == nil { firstPageNumber = pageNumber }
                let bounds = line.bounds(for: page)
                boxes.append(HighlightBox(page: pageNumber, bounds: RectValue(bounds)))

                let pdfAnnotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                pdfAnnotation.color = color.nsColor
                pdfAnnotation.contents = selectedText
                pdfAnnotation.setValue(annotationID.uuidString, forAnnotationKey: PDFAnnotationKey(rawValue: PDFAnnotationBridge.appAnnotationKey))
                page.addAnnotation(pdfAnnotation)
            }
        }

        let annotation = HighlightAnnotation(
            id: annotationID,
            page: firstPageNumber ?? 1,
            color: color,
            selectedText: selectedText,
            boxes: boxes
        )
        current.annotations.append(annotation)
        readerDocument = current
        selectedAnnotationID = annotation.id
        pdfView.clearSelection()
        saveAnnotations()
    }

    private func removeSelectedHighlight() {
        guard let selectedAnnotationID, var current = readerDocument else { return }
        current.markAnnotationsDeleted(withIDs: [selectedAnnotationID])
        readerDocument = current
        if let pdfDocument {
            PDFAnnotationBridge.removeAppAnnotations(withID: selectedAnnotationID, from: pdfDocument)
        }
        self.selectedAnnotationID = nil
        saveAnnotations()
    }

    private func saveAnnotations() {
        guard let annotationsDirectoryURL, let document = readerDocument else { return }
        let accessed = annotationsDirectoryURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                annotationsDirectoryURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let sidecarURL = try store.sidecarURL(for: document, annotationsDirectoryURL: annotationsDirectoryURL)
            let mergedDocument = try store.mergedDocument(document, withExistingDocumentAt: sidecarURL)
            try store.save(mergedDocument, to: sidecarURL)
            readerDocument = mergedDocument
            redrawHighlights()
            status = "Saved annotations to \(sidecarURL.path)"
        } catch {
            status = "Failed to save annotations: \(error.localizedDescription)"
        }
    }

    private func loadSidecarIfAvailable() {
        guard let annotationsDirectoryURL, let document = readerDocument else { return }
        let accessed = annotationsDirectoryURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                annotationsDirectoryURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let sidecarURL = try store.sidecarURL(for: document, annotationsDirectoryURL: annotationsDirectoryURL)
            guard FileManager.default.fileExists(atPath: sidecarURL.path) else { return }
            readerDocument = try store.mergedDocument(document, withExistingDocumentAt: sidecarURL)
        } catch {
            status = "Could not load synced annotations: \(error.localizedDescription)"
        }
    }

    private func redrawHighlights() {
        guard let pdfDocument, let readerDocument else { return }
        PDFAnnotationBridge.removeAppAnnotations(from: pdfDocument)
        for annotation in readerDocument.annotations {
            PDFAnnotationBridge.apply(annotation, to: pdfDocument)
        }
    }

    private func restoreAnnotationsFolder() {
        guard annotationsDirectoryURL == nil else { return }
        guard let url = Self.savedAnnotationsFolderURL() else {
            status = "Choose an Annotations Folder to begin."
            return
        }
        annotationsDirectoryURL = url
        status = "Annotations Folder selected: \(url.path)"
    }

    private func persistAnnotationsFolder(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: Self.annotationsFolderPathKey)
        do {
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: Self.annotationsFolderBookmarkKey)
        } catch {
            UserDefaults.standard.removeObject(forKey: Self.annotationsFolderBookmarkKey)
        }
    }

    private static func savedAnnotationsFolderURL() -> URL? {
        if let data = UserDefaults.standard.data(forKey: annotationsFolderBookmarkKey) {
            do {
                var isStale = false
                let url = try URL(
                    resolvingBookmarkData: data,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                if isStale {
                    UserDefaults.standard.removeObject(forKey: annotationsFolderBookmarkKey)
                }
                return url
            } catch {
                UserDefaults.standard.removeObject(forKey: annotationsFolderBookmarkKey)
            }
        }

        guard let path = UserDefaults.standard.string(forKey: annotationsFolderPathKey), !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func securityScopedBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
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

    private static let annotationsFolderBookmarkKey = "annotationsFolderBookmark"
    private static let annotationsFolderPathKey = "annotationsFolderPath"
}
#else
import SwiftUI

struct ContentView: View {
    var body: some View {
        ContentUnavailableView("Unsupported Platform", systemImage: "xmark.circle")
    }
}
#endif
