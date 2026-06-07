#if os(iOS)
import AnnotationCore
import PDFKit
import SwiftUI
import UniformTypeIdentifiers
import VaultExporter
import ZoteroResolver

struct MobileContentView: View {
    @State private var pdfDocument: PDFDocument?
    @State private var pdfView: PDFView?
    @State private var readerDocument: ReaderDocument?
    @State private var vaultURL: URL?
    @State private var status = "Choose an iCloud Drive vault and PDF."
    @State private var isChoosingVault = false
    @State private var isChoosingPDF = false

    private let store = AnnotationStore()
    private let synchronizer = VaultAnnotationSynchronizer()
    private let zoteroResolver = ZoteroResolver()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if pdfDocument == nil {
                    ContentUnavailableView("No PDF Open", systemImage: "doc.text.magnifyingglass")
                } else {
                    PDFKitView(
                        pdfDocument: pdfDocument,
                        pdfView: $pdfView,
                        continuousScrolling: true,
                        showPageBreaks: true,
                        onSelectAnnotation: { _ in },
                        onHighlightSelection: { _ in },
                        onRemoveHighlight: {},
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
            .navigationTitle("LLM Wiki Reader")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Vault") {
                        isChoosingVault = true
                    }
                    Button("PDF") {
                        isChoosingPDF = true
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $isChoosingVault,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleVaultImport(result)
        }
        .fileImporter(
            isPresented: $isChoosingPDF,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            handlePDFImport(result)
        }
    }

    private func handleVaultImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            vaultURL = url
            status = "Vault selected: \(url.lastPathComponent)"
            loadSidecarIfAvailable()
            redrawHighlights()
        } catch {
            status = "Could not choose vault: \(error.localizedDescription)"
        }
    }

    private func handlePDFImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            openPDF(at: url)
        } catch {
            status = "Could not open PDF: \(error.localizedDescription)"
        }
    }

    private func openPDF(at url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let document = PDFDocument(url: url) else {
            status = "Could not read PDF."
            return
        }

        var metadata = zoteroResolver.metadata(forPDFAt: url)
        if let vaultURL, let relativePath = store.relativePath(for: url, in: vaultURL) {
            metadata.pdfRelativePath = relativePath
        }

        pdfDocument = document
        readerDocument = ReaderDocument(paper: metadata)
        loadSidecarIfAvailable()
        redrawHighlights()
        status = "Opened \(metadata.title)"
    }

    private func loadSidecarIfAvailable() {
        guard let vaultURL, let document = readerDocument else { return }
        do {
            let sidecarURL = try store.sidecarURL(for: document, vaultURL: vaultURL)
            guard FileManager.default.fileExists(atPath: sidecarURL.path) else { return }
            readerDocument = try synchronizer.loadMergedSidecar(for: document, vaultURL: vaultURL)
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
}
#endif
