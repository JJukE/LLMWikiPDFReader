#if os(iOS)
import AnnotationCore
import Combine
import PDFKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import ZoteroResolver

struct MobileContentView: View {
    @StateObject private var settings = MobileAppSettings()
    @State private var pdfDocument: PDFDocument?
    @State private var pdfView: PDFView?
    @State private var readerDocument: ReaderDocument?
    @State private var selectedAnnotationID: HighlightAnnotation.ID?
    @State private var annotationsDirectoryURL: URL?
    @State private var status = "Choose an Annotations Folder and PDF."
    @State private var isShowingSettings = false
    @State private var isChoosingAnnotationsFolder = false
    @State private var isChoosingDefaultPDFFolder = false
    @State private var isChoosingPDF = false
    @State private var isFindPresented = false
    @State private var findQuery = ""
    @State private var findMatches: [PDFSelection] = []
    @State private var currentFindMatchNumber = 0
    @State private var backHistory: [MobilePDFViewLocation] = []
    @State private var forwardHistory: [MobilePDFViewLocation] = []
    @State private var lastStableScrollLocation: MobilePDFViewLocation?
    @State private var lastStableScrollProgress: CGFloat?
    @State private var lastScrollSampleProgress: CGFloat?
    @State private var lastScrollSampleTime: TimeInterval?
    @State private var baselineCaptureTask: Task<Void, Never>?
    @State private var scrollStopHistoryTask: Task<Void, Never>?
    @State private var scrollSessionStartLocation: MobilePDFViewLocation?
    @State private var pendingScrollStopLocation: MobilePDFViewLocation?
    @State private var pendingScrollStopProgress: CGFloat?
    @State private var hasQualifiedScrollVelocitySinceCheckpoint = false
    @State private var suppressViewportHistory = false
    @FocusState private var isFindFieldFocused: Bool

    private let store = AnnotationStore()
    private let zoteroResolver = ZoteroResolver()
    private let scrollHistoryVelocityThreshold: CGFloat = 0.5
    private let scrollStopHistoryDelayNanoseconds: UInt64 = 1_000_000_000

    private var canGoBack: Bool {
        !backHistory.isEmpty
    }

    private var canGoForward: Bool {
        !forwardHistory.isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if annotationsDirectoryURL == nil {
                    requiredAnnotationsFolderView
                } else {
                    VStack(spacing: 0) {
                        if pdfDocument == nil {
                            ContentUnavailableView("No PDF Open", systemImage: "doc.text.magnifyingglass")
                        } else {
                            if isFindPresented {
                                findBar
                            }
                            PDFKitView(
                                pdfDocument: pdfDocument,
                                pdfView: $pdfView,
                                continuousScrolling: settings.continuousScrolling,
                                showPageBreaks: settings.showPageBreaks,
                                onSelectAnnotation: { selectedAnnotationID = $0 },
                                onHighlightSelection: addHighlightFromSelection,
                                onRemoveHighlight: removeSelectedHighlight,
                                onViewportChanged: noteViewportChanged,
                                onViewReady: scheduleInitialViewLocationCapture
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
            .navigationTitle("LLM Wiki Reader")
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")

                    Button {
                        goBack()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Back")
                    .disabled(!canGoBack)

                    Button {
                        goForward()
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .accessibilityLabel("Forward")
                    .disabled(!canGoForward)
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showFind()
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("Find")
                    .keyboardShortcut("f", modifiers: [.command])
                    .disabled(pdfDocument == nil)

                    Button("Open PDF") {
                        isChoosingPDF = true
                    }
                    .disabled(annotationsDirectoryURL == nil)
                }
            }
        }
        .onAppear(perform: restoreAnnotationsFolderFromSettings)
        .onChange(of: isFindPresented) { _, isPresented in
            if isPresented {
                focusFindField()
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            MobileSettingsView(
                settings: settings,
                chooseAnnotationsFolder: beginChoosingAnnotationsFolderFromSettings,
                clearAnnotationsFolder: clearAnnotationsFolderFromSettings,
                chooseDefaultPDFFolder: beginChoosingDefaultPDFFolderFromSettings
            )
        }
        .sheet(isPresented: $isChoosingAnnotationsFolder) {
            FolderPicker(
                isPresented: $isChoosingAnnotationsFolder,
                onSelect: handleAnnotationsFolderSelection,
                onCancel: {
                    status = "Annotations Folder selection cancelled."
                }
            )
        }
        .sheet(isPresented: $isChoosingDefaultPDFFolder) {
            FolderPicker(
                isPresented: $isChoosingDefaultPDFFolder,
                onSelect: handleDefaultPDFFolderSelection,
                onCancel: {
                    status = "Default PDF Folder selection cancelled."
                }
            )
        }
        .fileImporter(
            isPresented: $isChoosingPDF,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            handlePDFImport(result)
        }
    }

    private var requiredAnnotationsFolderView: some View {
        VStack(spacing: 16) {
            ContentUnavailableView(
                "Annotations Folder Required",
                systemImage: "folder.badge.plus",
                description: Text("Choose the folder where highlight JSON files will be saved.")
            )
            Button("Choose Annotations Folder") {
                isChoosingAnnotationsFolder = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var findBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Find in PDF", text: Binding(get: {
                findQuery
            }, set: {
                updateFindQuery($0)
            }))
            .textFieldStyle(.roundedBorder)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .focused($isFindFieldFocused)
            .onSubmit {
                findNext()
            }

            Text(findCountLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 52, alignment: .trailing)

            Button {
                findPrevious()
            } label: {
                Image(systemName: "chevron.up")
            }
            .accessibilityLabel("Previous match")
            .disabled(findMatches.isEmpty)

            Button {
                findNext()
            } label: {
                Image(systemName: "chevron.down")
            }
            .accessibilityLabel("Next match")
            .disabled(findMatches.isEmpty)

            Button {
                hideFind()
            } label: {
                Image(systemName: "xmark")
            }
            .accessibilityLabel("Close Find")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial)
    }

    private func handleAnnotationsFolderSelection(_ url: URL) {
        settings.setAnnotationsFolder(url)
        annotationsDirectoryURL = settings.annotationsFolderURL() ?? url
        updateCurrentDocumentAnnotationsRelativePath()
        loadSidecarIfAvailable()
        redrawHighlights()
        status = "Annotations Folder selected: \(url.lastPathComponent)"
    }

    private func handleDefaultPDFFolderSelection(_ url: URL) {
        settings.setDefaultPDFDirectory(url)
        status = "Default PDF Folder selected: \(url.lastPathComponent)"
    }

    private func beginChoosingAnnotationsFolderFromSettings() {
        isShowingSettings = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            isChoosingAnnotationsFolder = true
        }
    }

    private func beginChoosingDefaultPDFFolderFromSettings() {
        isShowingSettings = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            isChoosingDefaultPDFFolder = true
        }
    }

    private func clearAnnotationsFolderFromSettings() {
        settings.clearAnnotationsFolder()
        annotationsDirectoryURL = nil
        selectedAnnotationID = nil
        status = "Choose an Annotations Folder to begin."
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
        guard annotationsDirectoryURL != nil else {
            status = "Choose an Annotations Folder before opening PDFs."
            return
        }
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
        if let annotationsDirectoryURL, let relativePath = store.relativePath(for: url, in: annotationsDirectoryURL) {
            metadata.pdfRelativePath = relativePath
        }

        pdfDocument = document
        readerDocument = ReaderDocument(paper: metadata)
        selectedAnnotationID = nil
        clearFindResults()
        findQuery = ""
        isFindPresented = false
        clearHistory()
        loadSidecarIfAvailable()
        redrawHighlights()
        scheduleInitialViewLocationCapture()
        status = "Opened \(metadata.title)"
    }

    private func goBack() {
        guard let currentLocation = currentPDFViewLocation() else {
            status = "Open a PDF before navigating."
            return
        }

        guard let destination = backHistory.popLast() else {
            status = "No back history."
            return
        }

        forwardHistory.append(currentLocation)
        restore(destination)
        status = "Returned to page \(destination.pageNumber)."
    }

    private func goForward() {
        guard let currentLocation = currentPDFViewLocation() else {
            status = "Open a PDF before navigating."
            return
        }

        guard let destination = forwardHistory.popLast() else {
            status = "No forward history."
            return
        }

        backHistory.append(currentLocation)
        restore(destination)
        status = "Moved forward to page \(destination.pageNumber)."
    }

    private func noteViewportChanged() {
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

    private func scheduleInitialViewLocationCapture() {
        guard pdfDocument != nil else { return }

        baselineCaptureTask?.cancel()
        baselineCaptureTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            captureInitialViewLocationIfNeeded()
        }
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

    private func currentPDFViewLocation() -> MobilePDFViewLocation? {
        guard let pdfView, let pdfDocument else { return nil }

        let viewPoint = CGPoint(x: pdfView.bounds.midX, y: pdfView.bounds.midY)
        if let page = pdfView.page(for: viewPoint, nearest: true) {
            let pageIndex = pdfDocument.index(for: page)
            guard pageIndex != NSNotFound else { return nil }
            return MobilePDFViewLocation(pageIndex: pageIndex, point: pdfView.convert(viewPoint, to: page))
        }

        if let destination = pdfView.currentDestination,
           let page = destination.page {
            let pageIndex = pdfDocument.index(for: page)
            guard pageIndex != NSNotFound else { return nil }
            return MobilePDFViewLocation(pageIndex: pageIndex, point: destination.point)
        }

        guard let page = pdfView.currentPage else { return nil }
        let pageIndex = pdfDocument.index(for: page)
        guard pageIndex != NSNotFound else { return nil }
        return MobilePDFViewLocation(pageIndex: pageIndex, point: .zero)
    }

    private func normalizedProgress(for location: MobilePDFViewLocation) -> CGFloat {
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

    private func resetScrollSample(progress: CGFloat, time: TimeInterval) {
        lastScrollSampleProgress = progress
        lastScrollSampleTime = time
    }

    private func resetScrollTracking(to location: MobilePDFViewLocation) {
        let progress = normalizedProgress(for: location)
        lastStableScrollLocation = location
        lastStableScrollProgress = progress
        resetScrollSample(progress: progress, time: Date.timeIntervalSinceReferenceDate)
    }

    private func scheduleScrollStopHistory() {
        scrollStopHistoryTask?.cancel()
        scrollStopHistoryTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: scrollStopHistoryDelayNanoseconds)
            guard !Task.isCancelled else { return }
            recordScrollStopLocation()
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

    private func restore(_ location: MobilePDFViewLocation) {
        guard let page = pdfDocument?.page(at: location.pageIndex) else { return }
        let destination = PDFDestination(page: page, at: destinationPointCentering(location.point, on: page))
        cancelScrollStopHistory()
        suppressViewportHistory = true
        pdfView?.go(to: destination)
        resetScrollTracking(to: location)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            suppressViewportHistory = false
            resetScrollTracking(to: currentPDFViewLocation() ?? location)
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
    }

    private func showFind() {
        guard pdfDocument != nil else {
            status = "Open a PDF before finding text."
            return
        }
        isFindPresented = true
    }

    private func hideFind() {
        isFindPresented = false
        findQuery = ""
        clearFindResults()
    }

    private func updateFindQuery(_ query: String) {
        findQuery = query
        rebuildFindResults()
    }

    private func findNext() {
        guard !findMatches.isEmpty else {
            rebuildFindResults()
            return
        }
        let nextIndex = (currentFindMatchNumber % findMatches.count)
        showFindMatch(at: nextIndex)
    }

    private func findPrevious() {
        guard !findMatches.isEmpty else {
            rebuildFindResults()
            return
        }
        let currentIndex = max(currentFindMatchNumber - 1, 0)
        let previousIndex = (currentIndex - 1 + findMatches.count) % findMatches.count
        showFindMatch(at: previousIndex)
    }

    private func rebuildFindResults() {
        let query = findQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            clearFindResults()
            return
        }

        guard let pdfDocument else {
            clearFindResults()
            status = "Open a PDF before finding text."
            return
        }

        findMatches = pdfDocument.findString(query, withOptions: [.caseInsensitive])
        pdfView?.highlightedSelections = findMatches

        guard !findMatches.isEmpty else {
            currentFindMatchNumber = 0
            pdfView?.showSearchSelection(nil)
            status = "No matches for \"\(query)\"."
            return
        }

        showFindMatch(at: 0)
        status = findMatches.count == 1 ? "Found 1 match." : "Found \(findMatches.count) matches."
    }

    private func showFindMatch(at index: Int) {
        guard findMatches.indices.contains(index) else { return }
        currentFindMatchNumber = index + 1
        pdfView?.highlightedSelections = findMatches
        pdfView?.showSearchSelection(findMatches[index])
    }

    private func clearFindResults() {
        findMatches.removeAll()
        currentFindMatchNumber = 0
        pdfView?.highlightedSelections = []
        pdfView?.showSearchSelection(nil)
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
                pdfAnnotation.color = color.uiColor
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
        saveAnnotations()
    }

    private func removeSelectedHighlight() {
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

        current.markAnnotationsDeleted(withIDs: [selectedAnnotationID])
        readerDocument = current
        if let pdfDocument {
            PDFAnnotationBridge.removeAppAnnotations(withID: selectedAnnotationID, from: pdfDocument)
        }
        self.selectedAnnotationID = nil
        if saveAnnotations() {
            status = "Removed highlight."
        }
    }

    @discardableResult
    private func saveAnnotations() -> Bool {
        guard let annotationsDirectoryURL, let document = readerDocument else {
            status = "Choose an Annotations Folder before saving annotations."
            return false
        }

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
            status = "Saved annotations to \(sidecarURL.lastPathComponent)"
            return true
        } catch {
            status = "Failed to save annotations: \(error.localizedDescription)"
            return false
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

    private func restoreAnnotationsFolderFromSettings() {
        guard annotationsDirectoryURL == nil else { return }
        guard let url = settings.annotationsFolderURL() else {
            status = "Choose an Annotations Folder to begin."
            return
        }
        annotationsDirectoryURL = url
        selectedAnnotationID = nil
    }

    private func updateCurrentDocumentAnnotationsRelativePath() {
        guard let annotationsDirectoryURL, var document = readerDocument else { return }
        let pdfURL = URL(fileURLWithPath: document.paper.pdfPath)
        guard let relativePath = store.relativePath(for: pdfURL, in: annotationsDirectoryURL) else { return }
        document.paper.pdfRelativePath = relativePath
        readerDocument = document
    }

    private var findCountLabel: String {
        guard !findQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "0 / 0"
        }
        return "\(currentFindMatchNumber) / \(findMatches.count)"
    }

    private func focusFindField() {
        DispatchQueue.main.async {
            isFindFieldFocused = true
        }
    }
}

private struct MobilePDFViewLocation: Equatable {
    let pageIndex: Int
    let point: CGPoint

    var pageNumber: Int {
        pageIndex + 1
    }
}

@MainActor
private final class MobileAppSettings: ObservableObject {
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

    @Published private(set) var defaultPDFDirectoryPath: String?
    @Published private(set) var annotationsFolderPath: String?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        continuousScrolling = defaults.object(forKey: Keys.continuousScrolling) as? Bool ?? true
        showPageBreaks = defaults.object(forKey: Keys.showPageBreaks) as? Bool ?? true
        defaultPDFDirectoryPath = defaults.string(forKey: Keys.defaultPDFDirectoryPath)
        annotationsFolderPath = defaults.string(forKey: Keys.annotationsFolderPath)
    }

    func setAnnotationsFolder(_ url: URL) {
        annotationsFolderPath = url.path
        defaults.set(url.path, forKey: Keys.annotationsFolderPath)

        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            defaults.set(bookmark, forKey: Keys.annotationsFolderBookmark)
        } catch {
            defaults.removeObject(forKey: Keys.annotationsFolderBookmark)
        }
    }

    func clearAnnotationsFolder() {
        annotationsFolderPath = nil
        defaults.removeObject(forKey: Keys.annotationsFolderPath)
        defaults.removeObject(forKey: Keys.annotationsFolderBookmark)
    }

    func annotationsFolderURL() -> URL? {
        if let data = defaults.data(forKey: Keys.annotationsFolderBookmark) {
            do {
                var isStale = false
                let url = try URL(
                    resolvingBookmarkData: data,
                    options: [],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                if isStale {
                    setAnnotationsFolder(url)
                }
                return url
            } catch {
                clearAnnotationsFolder()
                return nil
            }
        }

        guard let path = annotationsFolderPath, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    func setDefaultPDFDirectory(_ url: URL) {
        defaultPDFDirectoryPath = url.path
        defaults.set(url.path, forKey: Keys.defaultPDFDirectoryPath)

        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
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
}

private enum Keys {
    static let continuousScrolling = "continuousScrolling"
    static let showPageBreaks = "showPageBreaks"
    static let annotationsFolderBookmark = "annotationsFolderBookmark"
    static let annotationsFolderPath = "annotationsFolderPath"
    static let defaultPDFDirectoryBookmark = "defaultPDFDirectoryBookmark"
    static let defaultPDFDirectoryPath = "defaultPDFDirectoryPath"
}

private struct MobileSettingsView: View {
    @ObservedObject var settings: MobileAppSettings
    let chooseAnnotationsFolder: () -> Void
    let clearAnnotationsFolder: () -> Void
    let chooseDefaultPDFFolder: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Annotations") {
                    LabeledContent("Folder") {
                        Text(settings.annotationsFolderPath ?? "None")
                            .foregroundStyle(settings.annotationsFolderPath == nil ? .secondary : .primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }
                    Button("Choose Annotations Folder", action: chooseAnnotationsFolder)
                    Button("Clear", action: clearAnnotationsFolder)
                        .disabled(settings.annotationsFolderPath == nil)
                }

                Section("PDF View") {
                    Toggle("Use continuous scrolling", isOn: $settings.continuousScrolling)
                    Toggle("Show page breaks", isOn: $settings.showPageBreaks)
                }

                Section("Open PDF") {
                    LabeledContent("Default Folder") {
                        Text(settings.defaultPDFDirectoryPath ?? "None")
                            .foregroundStyle(settings.defaultPDFDirectoryPath == nil ? .secondary : .primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }
                    Button("Choose Default PDF Folder", action: chooseDefaultPDFFolder)
                    Button("Clear", action: settings.clearDefaultPDFDirectory)
                        .disabled(settings.defaultPDFDirectoryPath == nil)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

private struct FolderPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool

    let onSelect: (URL) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private var parent: FolderPicker

        init(parent: FolderPicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                parent.isPresented = false
                return
            }

            parent.onSelect(url)
            parent.isPresented = false
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onCancel()
            parent.isPresented = false
        }
    }
}
#endif
