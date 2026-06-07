#if os(macOS)
import AnnotationCore
import AppKit
import PDFKit
import SwiftUI

struct PDFKitView: NSViewRepresentable {
    let pdfDocument: PDFDocument?
    @Binding var pdfView: PDFView?
    var continuousScrolling: Bool
    var showPageBreaks: Bool
    var onSelectAnnotation: (HighlightAnnotation.ID) -> Void
    var onHighlightSelection: (HighlightColor) -> Void
    var onRemoveHighlight: () -> Void
    var onViewportChanged: () -> Void
    var onViewReady: () -> Void

    func makeNSView(context: Context) -> PDFView {
        let view = SelectablePDFView()
        view.onSelectAnnotation = onSelectAnnotation
        view.onHighlightSelection = onHighlightSelection
        view.onRemoveHighlight = onRemoveHighlight
        view.onViewportChanged = onViewportChanged
        view.autoScales = true
        view.displayMode = continuousScrolling ? .singlePageContinuous : .singlePage
        view.displayDirection = .vertical
        view.displaysPageBreaks = showPageBreaks
        view.document = pdfDocument
        DispatchQueue.main.async {
            pdfView = view
            view.configureViewportObservation()
            onViewReady()
        }
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document !== pdfDocument {
            nsView.document = pdfDocument
        }
        nsView.displayMode = continuousScrolling ? .singlePageContinuous : .singlePage
        nsView.displaysPageBreaks = showPageBreaks
        if let selectablePDFView = nsView as? SelectablePDFView {
            selectablePDFView.onSelectAnnotation = onSelectAnnotation
            selectablePDFView.onHighlightSelection = onHighlightSelection
            selectablePDFView.onRemoveHighlight = onRemoveHighlight
            selectablePDFView.onViewportChanged = onViewportChanged
            DispatchQueue.main.async {
                selectablePDFView.configureViewportObservation()
                onViewReady()
            }
        }
    }
}

private final class SelectablePDFView: PDFView {
    var onSelectAnnotation: ((HighlightAnnotation.ID) -> Void)?
    var onHighlightSelection: ((HighlightColor) -> Void)?
    var onRemoveHighlight: (() -> Void)?
    var onViewportChanged: (() -> Void)?

    private var pendingAnnotationID: HighlightAnnotation.ID?
    private var selectionToolbar: NSVisualEffectView?
    private weak var observedClipView: NSClipView?
    private var boundsObserver: NSObjectProtocol?

    deinit {
        removeViewportObservation()
    }

    func configureViewportObservation() {
        guard let clipView = enclosingScrollView?.contentView ?? firstScrollView(in: self)?.contentView else {
            return
        }
        guard observedClipView !== clipView else { return }

        removeViewportObservation()
        observedClipView = clipView
        clipView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clipView,
            queue: .main
        ) { [weak self] _ in
            self?.onViewportChanged?()
        }
    }

    override func mouseDown(with event: NSEvent) {
        pendingAnnotationID = appAnnotationID(at: event)
        hideSelectionToolbar()
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)

        if let pendingAnnotationID {
            onSelectAnnotation?(pendingAnnotationID)
            showSelectionToolbar(near: convert(event.locationInWindow, from: nil))
        } else if hasCurrentTextSelection {
            showSelectionToolbar(near: selectionToolbarPoint())
        } else {
            hideSelectionToolbar()
        }

        self.pendingAnnotationID = nil
    }

    override func scrollWheel(with event: NSEvent) {
        hideSelectionToolbar()
        super.scrollWheel(with: event)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            hideSelectionToolbar()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            self?.configureViewportObservation()
        }
    }

    private func removeViewportObservation() {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
        boundsObserver = nil
        observedClipView = nil
    }

    private func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView {
            return scrollView
        }
        for subview in view.subviews {
            if let scrollView = firstScrollView(in: subview) {
                return scrollView
            }
        }
        return nil
    }

    private var hasCurrentTextSelection: Bool {
        let text = currentSelection?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !text.isEmpty
    }

    private func appAnnotationID(at event: NSEvent) -> HighlightAnnotation.ID? {
        let viewPoint = convert(event.locationInWindow, from: nil)
        guard let page = page(for: viewPoint, nearest: true) else { return nil }

        let pagePoint = convert(viewPoint, to: page)
        guard let annotation = page.annotation(at: pagePoint),
              let rawID = annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: PDFAnnotationBridge.appAnnotationKey)) as? String,
              let id = UUID(uuidString: rawID) else {
            return nil
        }

        return id
    }

    private func selectionToolbarPoint() -> CGPoint {
        guard let selection = currentSelection,
              let page = selection.pages.first else {
            return CGPoint(x: bounds.midX, y: bounds.midY)
        }

        let selectionBounds = selection.bounds(for: page)
        let viewBounds = convert(selectionBounds, from: page)
        return CGPoint(x: viewBounds.midX, y: viewBounds.maxY + 10)
    }

    private func showSelectionToolbar(near point: CGPoint) {
        let toolbar = selectionToolbar ?? makeSelectionToolbar()
        if toolbar.superview == nil {
            addSubview(toolbar)
        }

        let size = toolbar.fittingSize
        let x = min(max(point.x - size.width / 2, 8), bounds.width - size.width - 8)
        let y = min(max(point.y, 8), bounds.height - size.height - 8)
        toolbar.frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
        toolbar.isHidden = false
    }

    private func hideSelectionToolbar() {
        selectionToolbar?.isHidden = true
    }

    private func makeSelectionToolbar() -> NSVisualEffectView {
        let container = NSVisualEffectView()
        container.material = .hudWindow
        container.blendingMode = .withinWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.masksToBounds = true

        let stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 6
        stackView.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        for color in HighlightColor.allCases {
            stackView.addArrangedSubview(highlightButton(for: color))
        }

        let separator = NSBox()
        separator.boxType = .separator
        stackView.addArrangedSubview(separator)

        let removeButton = NSButton(image: NSImage(systemSymbolName: "trash", accessibilityDescription: "Remove highlight") ?? NSImage(), target: self, action: #selector(removeHighlight))
        removeButton.bezelStyle = .texturedRounded
        removeButton.isBordered = false
        removeButton.toolTip = "Remove highlight"
        stackView.addArrangedSubview(removeButton)

        container.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: container.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        selectionToolbar = container
        return container
    }

    private func highlightButton(for color: HighlightColor) -> NSButton {
        let button = NSButton(title: "", target: self, action: #selector(applyHighlight(_:)))
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.toolTip = "\(color.rawValue.capitalized): \(color.semanticLevel)"
        button.identifier = NSUserInterfaceItemIdentifier(color.rawValue)
        button.attributedTitle = NSAttributedString(
            string: "●",
            attributes: [
                .foregroundColor: color.toolbarColor,
                .font: NSFont.systemFont(ofSize: 18)
            ]
        )
        button.frame.size = CGSize(width: 24, height: 24)
        return button
    }

    @objc private func applyHighlight(_ sender: NSButton) {
        guard let rawValue = sender.identifier?.rawValue,
              let color = HighlightColor(rawValue: rawValue) else { return }
        hideSelectionToolbar()
        onHighlightSelection?(color)
    }

    @objc private func removeHighlight() {
        hideSelectionToolbar()
        onRemoveHighlight?()
    }
}

private extension HighlightColor {
    var toolbarColor: NSColor {
        switch self {
        case .red:
            return .systemRed
        case .green:
            return .systemGreen
        case .yellow:
            return .systemYellow
        case .blue:
            return .systemBlue
        }
    }
}
#elseif os(iOS)
import AnnotationCore
import PDFKit
import SwiftUI
import UIKit

struct PDFKitView: UIViewRepresentable {
    let pdfDocument: PDFDocument?
    @Binding var pdfView: PDFView?
    var continuousScrolling: Bool
    var showPageBreaks: Bool
    var onSelectAnnotation: (HighlightAnnotation.ID) -> Void
    var onHighlightSelection: (HighlightColor) -> Void
    var onRemoveHighlight: () -> Void
    var onViewportChanged: () -> Void
    var onViewReady: () -> Void

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = continuousScrolling ? .singlePageContinuous : .singlePage
        view.displayDirection = .vertical
        view.displaysPageBreaks = showPageBreaks
        view.document = pdfDocument

        DispatchQueue.main.async {
            pdfView = view
            onViewReady()
        }

        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document !== pdfDocument {
            uiView.document = pdfDocument
        }
        uiView.displayMode = continuousScrolling ? .singlePageContinuous : .singlePage
        uiView.displaysPageBreaks = showPageBreaks

        DispatchQueue.main.async {
            if pdfView !== uiView {
                pdfView = uiView
            }
            onViewReady()
        }
    }
}
#endif
