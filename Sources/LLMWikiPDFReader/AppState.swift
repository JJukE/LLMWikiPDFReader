#if os(macOS)
import AnnotationCore
import AppKit
import PDFKit
import SwiftUI
import VaultExporter
import ZoteroResolver

@MainActor
final class AppState: ObservableObject {
    @Published var selectedColor: HighlightColor = .red
    @Published var pdfDocument: PDFDocument?
    @Published var pdfView: PDFView?
    @Published var readerDocument: ReaderDocument?
    @Published var vaultURL: URL?
    @Published var status: String = "Open a PDF to begin."

    private let store = AnnotationStore()
    private let vaultExporter = VaultMarkdownExporter()
    private let zoteroResolver = ZoteroResolver()

    var annotations: [HighlightAnnotation] {
        readerDocument?.annotations.sorted { ($0.page, $0.createdAt) < ($1.page, $1.createdAt) } ?? []
    }

    func chooseVault() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose the root of your LLM Wiki Obsidian vault."
        if panel.runModal() == .OK {
            vaultURL = panel.url
            status = "Vault selected: \(panel.url?.path ?? "")"
        }
    }

    func openPDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        if panel.runModal() != .OK { return }
        guard let url = panel.url else {
            status = "Could not open PDF."
            return
        }

        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let document = PDFDocument(url: url) else {
            status = "Could not open PDF."
            return
        }

        pdfDocument = document
        let metadata = zoteroResolver.metadata(forPDFAt: url, bookmark: securityScopedBookmark(for: url))
        readerDocument = ReaderDocument(paper: metadata)
        loadSidecarIfAvailable()
        redrawHighlights()
        status = "Opened \(metadata.title)"
    }

    func addHighlightFromSelection() {
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
                pdfAnnotation.color = selectedColor.nsColor
                pdfAnnotation.contents = selectedText
                pdfAnnotation.setValue(annotationID.uuidString, forAnnotationKey: PDFAnnotationKey(rawValue: PDFAnnotationBridge.appAnnotationKey))
                page.addAnnotation(pdfAnnotation)
            }
        }

        let annotation = HighlightAnnotation(
            id: annotationID,
            page: firstPageNumber ?? 1,
            color: selectedColor,
            selectedText: selectedText,
            boxes: boxes
        )
        current.annotations.append(annotation)
        readerDocument = current
        pdfView.clearSelection()
        saveSidecar()
        status = "Added \(selectedColor.semanticLevel) highlight."
    }

    func jump(to annotation: HighlightAnnotation) {
        guard let page = pdfDocument?.page(at: annotation.page - 1) else { return }
        pdfView?.go(to: page)
    }

    func saveSidecar() {
        guard let vaultURL, let document = readerDocument else {
            status = "Choose a vault before saving annotations."
            return
        }
        do {
            let url = try store.sidecarURL(for: document, vaultURL: vaultURL)
            try store.save(document, to: url)
            status = "Saved annotations to \(url.path)"
        } catch {
            status = "Failed to save annotations: \(error.localizedDescription)"
        }
    }

    func exportMarkdown() {
        guard let vaultURL, let document = readerDocument else {
            status = "Choose a vault before exporting Markdown."
            return
        }
        do {
            let result = try vaultExporter.export(document, vaultURL: vaultURL)
            readerDocument = result.document
            status = "Exported Markdown to \(result.markdownURL.path)"
        } catch {
            status = "Failed to export Markdown: \(error.localizedDescription)"
        }
    }

    private func loadSidecarIfAvailable() {
        guard let vaultURL, let document = readerDocument else { return }
        do {
            let url = try store.sidecarURL(for: document, vaultURL: vaultURL)
            if FileManager.default.fileExists(atPath: url.path) {
                readerDocument = try store.load(from: url)
            }
        } catch {
            status = "Could not load existing sidecar: \(error.localizedDescription)"
        }
    }

    private func redrawHighlights() {
        guard let pdfDocument, let readerDocument else { return }
        PDFAnnotationBridge.removeAppAnnotations(from: pdfDocument)
        for annotation in readerDocument.annotations {
            PDFAnnotationBridge.apply(annotation, to: pdfDocument)
        }
    }

    private func securityScopedBookmark(for url: URL) -> Data? {
        do {
            return try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            status = "Opened PDF, but could not save its security bookmark: \(error.localizedDescription)"
            return nil
        }
    }
}
#endif
