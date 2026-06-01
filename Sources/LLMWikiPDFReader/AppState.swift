#if os(macOS)
import AnnotationCore
import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers
import VaultExporter
import ZoteroResolver

@MainActor
final class AppState: ObservableObject {
    @Published var selectedAnnotationID: HighlightAnnotation.ID?
    @Published var pdfDocument: PDFDocument?
    @Published var pdfView: PDFView?
    @Published var readerDocument: ReaderDocument?
    @Published var vaultURL: URL?
    @Published var status: String = "Open a PDF to begin."
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false

    private var backHistory: [PDFViewLocation] = []
    private var forwardHistory: [PDFViewLocation] = []
    private var lastStableScrollLocation: PDFViewLocation?
    private var lastStableScrollProgress: CGFloat?
    private var lastScrollSampleProgress: CGFloat?
    private var lastScrollSampleTime: TimeInterval?
    private var baselineCaptureTask: Task<Void, Never>?
    private var scrollStopHistoryTask: Task<Void, Never>?
    private var scrollSessionStartLocation: PDFViewLocation?
    private var pendingScrollStopLocation: PDFViewLocation?
    private var pendingScrollStopProgress: CGFloat?
    private var hasQualifiedScrollVelocitySinceCheckpoint = false
    private var suppressViewportHistory = false

    private let store = AnnotationStore()
    private let settings: AppSettings
    private let vaultExporter = VaultMarkdownExporter()
    private let zoteroResolver = ZoteroResolver()
    private let scrollHistoryVelocityThreshold: CGFloat = 0.5
    private let scrollStopHistoryDelayNanoseconds: UInt64 = 1_000_000_000

    init(settings: AppSettings) {
        self.settings = settings
    }

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
        guard let url = choosePDFURL(startingAt: settings.defaultPDFDirectoryURL()) else { return }

        openPDF(at: url)
    }

    private func choosePDFURL(startingAt startURL: URL?) -> URL? {
        var directoryURL = startURL

        while true {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = true
            panel.allowedContentTypes = [.pdf, .folder]
            panel.allowsMultipleSelection = false
            panel.directoryURL = directoryURL
            panel.message = "Choose a PDF, or choose a folder to continue browsing."

            if panel.runModal() != .OK { return nil }
            guard let url = panel.url else {
                status = "Could not open PDF."
                return nil
            }

            if isDirectory(url) {
                directoryURL = url
                continue
            }

            guard isPDF(url) else {
                status = "Choose a PDF file."
                return nil
            }

            return url
        }
    }

    private func openPDF(at url: URL) {
        let directoryURL = url.deletingLastPathComponent()
        let directoryAccessed = directoryURL.startAccessingSecurityScopedResource()

        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
            if directoryAccessed {
                directoryURL.stopAccessingSecurityScopedResource()
            }
        }

        guard let document = PDFDocument(url: url) else {
            status = "Could not open PDF."
            return
        }

        pdfDocument = document
        selectedAnnotationID = nil
        clearHistory()
        let metadata = zoteroResolver.metadata(forPDFAt: url, bookmark: securityScopedBookmark(for: url))
        readerDocument = ReaderDocument(paper: metadata)
        loadSidecarIfAvailable()
        redrawHighlights()
        scheduleInitialViewLocationCapture()
        status = "Opened \(metadata.title)"
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func isPDF(_ url: URL) -> Bool {
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return type.conforms(to: .pdf)
        }
        return url.pathExtension.lowercased() == "pdf"
    }

    func addHighlightFromSelection(color: HighlightColor) {
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
        status = "Added \(color.semanticLevel) highlight."
        saveAfterHighlightChange()
    }

    func select(annotationID: HighlightAnnotation.ID?, navigate: Bool = true) {
        selectedAnnotationID = annotationID
        guard let annotationID, let annotation = annotations.first(where: { $0.id == annotationID }) else { return }
        if navigate {
            jump(to: annotation)
        }
        status = "Selected highlight on page \(annotation.page)."
    }

    func removeSelectedHighlight() {
        guard let selectedAnnotationID else {
            status = "Select a highlight before removing it."
            return
        }

        guard var current = readerDocument else {
            status = "Open a PDF before removing highlights."
            return
        }

        guard current.annotations.contains(where: { $0.id == selectedAnnotationID }) else {
            self.selectedAnnotationID = nil
            status = "Selected highlight was not found."
            return
        }

        removeHighlights(withIDs: [selectedAnnotationID], from: &current)
        status = "Removed highlight."
    }

    func removeSelectedOrSelectionHighlights() {
        if selectedAnnotationID != nil {
            removeSelectedHighlight()
            return
        }

        guard var current = readerDocument, let pdfDocument, let pdfView, let selection = pdfView.currentSelection else {
            status = "Select highlighted text or an existing highlight before removing."
            return
        }

        let selectionRects = selection.selectionsByLine().flatMap { lineSelection in
            lineSelection.pages.compactMap { page -> (page: Int, bounds: CGRect)? in
                let pageIndex = pdfDocument.index(for: page)
                guard pageIndex != NSNotFound else { return nil }
                return (pageIndex + 1, lineSelection.bounds(for: page))
            }
        }

        let ids = current.annotations
            .filter { annotation in
                annotation.boxes.contains { box in
                    selectionRects.contains { selectedRect in
                        selectedRect.page == box.page && selectedRect.bounds.intersects(box.bounds.cgRect)
                    }
                }
            }
            .map(\.id)

        guard !ids.isEmpty else {
            status = "No app highlight found in the selected text."
            return
        }

        removeHighlights(withIDs: ids, from: &current)
        pdfView.clearSelection()
        status = ids.count == 1 ? "Removed highlight." : "Removed \(ids.count) highlights."
    }

    func jump(to annotation: HighlightAnnotation) {
        guard let location = location(for: annotation) else { return }
        recordCurrentLocationForNavigation()
        restore(location)
    }

    func goBack() {
        guard let currentLocation = currentPDFViewLocation() else {
            status = "Open a PDF before navigating."
            return
        }

        guard let destination = backHistory.popLast() else {
            status = "No back history."
            return
        }

        forwardHistory.append(currentLocation)
        updateHistoryAvailability()
        restore(destination)
        status = "Returned to page \(destination.pageNumber)."
    }

    func goForward() {
        guard let currentLocation = currentPDFViewLocation() else {
            status = "Open a PDF before navigating."
            return
        }

        guard let destination = forwardHistory.popLast() else {
            status = "No forward history."
            return
        }

        backHistory.append(currentLocation)
        updateHistoryAvailability()
        restore(destination)
        status = "Moved forward to page \(destination.pageNumber)."
    }

    func noteViewportChanged() {
        guard pdfDocument != nil else { return }
        guard !suppressViewportHistory else { return }
        guard let currentLocation = currentPDFViewLocation() else { return }
        let currentProgress = normalizedProgress(for: currentLocation)
        let currentTime = Date.timeIntervalSinceReferenceDate

        guard let stableLocation = lastStableScrollLocation else {
            lastStableScrollLocation = currentLocation
            lastStableScrollProgress = currentProgress
            resetScrollSample(progress: currentProgress, time: currentTime)
            scheduleScrollStopHistory()
            return
        }

        guard let sampleProgress = lastScrollSampleProgress,
              let sampleTime = lastScrollSampleTime else {
            resetScrollSample(progress: currentProgress, time: currentTime)
            scheduleScrollStopHistory()
            return
        }

        let elapsedTime = currentTime - sampleTime
        guard elapsedTime > 0.001 else {
            resetScrollSample(progress: currentProgress, time: currentTime)
            scheduleScrollStopHistory()
            return
        }

        let velocity = abs(currentProgress - sampleProgress) / CGFloat(elapsedTime)
        resetScrollSample(progress: currentProgress, time: currentTime)

        if velocity >= scrollHistoryVelocityThreshold {
            if !hasQualifiedScrollVelocitySinceCheckpoint {
                scrollSessionStartLocation = stableLocation
            }
            hasQualifiedScrollVelocitySinceCheckpoint = true
        }
        if hasQualifiedScrollVelocitySinceCheckpoint {
            pendingScrollStopLocation = currentLocation
            pendingScrollStopProgress = currentProgress
        }
        scheduleScrollStopHistory()
    }

    func scheduleInitialViewLocationCapture() {
        guard pdfDocument != nil else { return }

        baselineCaptureTask?.cancel()
        baselineCaptureTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            self?.captureInitialViewLocationIfNeeded()
        }
    }

    private func recordCurrentLocationForNavigation() {
        guard let location = currentPDFViewLocation() else { return }
        if backHistory.last != location {
            backHistory.append(location)
        }
        forwardHistory.removeAll()
        resetScrollTracking(to: location)
        updateHistoryAvailability()
    }

    private func captureInitialViewLocationIfNeeded() {
        baselineCaptureTask = nil
        guard lastStableScrollLocation == nil else { return }
        lastStableScrollLocation = currentPDFViewLocation()
        if let lastStableScrollLocation {
            let progress = normalizedProgress(for: lastStableScrollLocation)
            lastStableScrollProgress = progress
            resetScrollSample(progress: progress, time: Date.timeIntervalSinceReferenceDate)
        }
    }

    private func currentPDFViewLocation() -> PDFViewLocation? {
        guard let pdfView, let pdfDocument else { return nil }

        let viewPoint = CGPoint(x: pdfView.bounds.midX, y: pdfView.bounds.midY)
        if let page = pdfView.page(for: viewPoint, nearest: true) {
            let pageIndex = pdfDocument.index(for: page)
            guard pageIndex != NSNotFound else { return nil }
            return PDFViewLocation(pageIndex: pageIndex, point: pdfView.convert(viewPoint, to: page))
        }

        if let destination = pdfView.currentDestination,
           let page = destination.page {
            let pageIndex = pdfDocument.index(for: page)
            guard pageIndex != NSNotFound else { return nil }
            return PDFViewLocation(pageIndex: pageIndex, point: destination.point)
        }

        guard let page = pdfView.currentPage else { return nil }
        let pageIndex = pdfDocument.index(for: page)
        guard pageIndex != NSNotFound else { return nil }
        return PDFViewLocation(pageIndex: pageIndex, point: .zero)
    }

    private func normalizedProgress(for location: PDFViewLocation) -> CGFloat {
        guard let page = pdfDocument?.page(at: location.pageIndex) else {
            return CGFloat(location.pageIndex)
        }

        let bounds = page.bounds(for: .cropBox)
        guard bounds.height > 0 else {
            return CGFloat(location.pageIndex)
        }

        let offsetWithinPage = (bounds.maxY - location.point.y) / bounds.height
        return CGFloat(location.pageIndex) + min(max(offsetWithinPage, 0), 1)
    }

    private func location(for annotation: HighlightAnnotation) -> PDFViewLocation? {
        for box in annotation.boxes {
            let pageIndex = box.page - 1
            guard pdfDocument?.page(at: pageIndex) != nil else { continue }
            return PDFViewLocation(pageIndex: pageIndex, point: box.bounds.cgRect.center)
        }

        guard let page = pdfDocument?.page(at: annotation.page - 1) else { return nil }
        let bounds = page.bounds(for: .cropBox)
        return PDFViewLocation(pageIndex: annotation.page - 1, point: bounds.center)
    }

    private func resetScrollSample(progress: CGFloat, time: TimeInterval) {
        lastScrollSampleProgress = progress
        lastScrollSampleTime = time
    }

    private func resetScrollTracking(to location: PDFViewLocation) {
        let progress = normalizedProgress(for: location)
        lastStableScrollLocation = location
        lastStableScrollProgress = progress
        resetScrollSample(progress: progress, time: Date.timeIntervalSinceReferenceDate)
    }

    private func scheduleScrollStopHistory() {
        scrollStopHistoryTask?.cancel()
        scrollStopHistoryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.scrollStopHistoryDelayNanoseconds ?? 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.recordScrollStopLocation()
        }
    }

    private func recordScrollStopLocation() {
        scrollStopHistoryTask = nil
        guard hasQualifiedScrollVelocitySinceCheckpoint,
              let stoppedLocation = pendingScrollStopLocation,
              let stoppedProgress = pendingScrollStopProgress else {
            clearPendingScrollStopHistory()
            return
        }

        guard let stableLocation = scrollSessionStartLocation ?? lastStableScrollLocation else {
            resetScrollTracking(to: stoppedLocation)
            clearPendingScrollStopHistory()
            return
        }

        let stableProgress = normalizedProgress(for: stableLocation)
        guard abs(stoppedProgress - stableProgress) > 0.001 else {
            clearPendingScrollStopHistory()
            return
        }

        if backHistory.last != stableLocation {
            backHistory.append(stableLocation)
        }
        forwardHistory.removeAll()
        resetScrollTracking(to: stoppedLocation)
        clearPendingScrollStopHistory()
        updateHistoryAvailability()
    }

    private func cancelScrollStopHistory() {
        scrollStopHistoryTask?.cancel()
        scrollStopHistoryTask = nil
        clearPendingScrollStopHistory()
    }

    private func clearPendingScrollStopHistory() {
        scrollSessionStartLocation = nil
        pendingScrollStopLocation = nil
        pendingScrollStopProgress = nil
        hasQualifiedScrollVelocitySinceCheckpoint = false
    }

    private func restore(_ location: PDFViewLocation) {
        guard let page = pdfDocument?.page(at: location.pageIndex) else { return }
        let destination = PDFDestination(page: page, at: destinationPointCentering(location.point, on: page))
        cancelScrollStopHistory()
        suppressViewportHistory = true
        pdfView?.go(to: destination)
        resetScrollTracking(to: location)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            self?.suppressViewportHistory = false
            self?.resetScrollTracking(to: self?.currentPDFViewLocation() ?? location)
        }
    }

    private func destinationPointCentering(_ point: CGPoint, on page: PDFPage) -> CGPoint {
        guard let pdfView else { return point }
        let pageBounds = page.bounds(for: .cropBox)
        guard pageBounds.width > 0, pageBounds.height > 0, pdfView.scaleFactor > 0 else { return point }

        let visibleSize = CGSize(
            width: pdfView.bounds.width / pdfView.scaleFactor,
            height: pdfView.bounds.height / pdfView.scaleFactor
        )
        let destination = CGPoint(
            x: point.x - visibleSize.width / 2,
            y: point.y + visibleSize.height / 2
        )
        return CGPoint(
            x: min(max(destination.x, pageBounds.minX), pageBounds.maxX),
            y: min(max(destination.y, pageBounds.minY), pageBounds.maxY)
        )
    }

    private func clearHistory() {
        baselineCaptureTask?.cancel()
        baselineCaptureTask = nil
        cancelScrollStopHistory()
        backHistory.removeAll()
        forwardHistory.removeAll()
        lastStableScrollLocation = nil
        lastStableScrollProgress = nil
        lastScrollSampleProgress = nil
        lastScrollSampleTime = nil
        updateHistoryAvailability()
    }

    private func updateHistoryAvailability() {
        canGoBack = !backHistory.isEmpty
        canGoForward = !forwardHistory.isEmpty
    }

    func goToPage(at pageIndex: Int) {
        guard let page = pdfDocument?.page(at: pageIndex) else {
            status = "Could not navigate to page \(pageIndex + 1)."
            return
        }
        recordCurrentLocationForNavigation()
        let pageBounds = page.bounds(for: .cropBox)
        restore(PDFViewLocation(pageIndex: pageIndex, point: CGPoint(x: pageBounds.midX, y: pageBounds.maxY)))
        status = "Moved to page \(pageIndex + 1)."
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

    private func saveAfterHighlightChange() {
        if settings.autoSaveAnnotations {
            saveSidecar()
        }
    }

    private func removeHighlights(withIDs ids: [HighlightAnnotation.ID], from document: inout ReaderDocument) {
        let uniqueIDs = Set(ids)
        document.annotations.removeAll { uniqueIDs.contains($0.id) }
        readerDocument = document
        if let pdfDocument {
            for id in uniqueIDs {
                PDFAnnotationBridge.removeAppAnnotations(withID: id, from: pdfDocument)
            }
        }
        selectedAnnotationID = nil
        saveAfterHighlightChange()
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

private struct PDFViewLocation: Equatable {
    let pageIndex: Int
    let point: CGPoint

    var pageNumber: Int {
        pageIndex + 1
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
#endif
