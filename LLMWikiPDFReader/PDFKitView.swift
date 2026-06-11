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

    fileprivate func performSearchSelection(_ selection: PDFSelection?) {
        hideSelectionToolbar()
        guard let selection else {
            clearSelection()
            return
        }
        setCurrentSelection(selection, animate: true)
        go(to: selection)
    }
}

extension PDFView {
    func showSearchSelection(_ selection: PDFSelection?) {
        if let selectablePDFView = self as? SelectablePDFView {
            selectablePDFView.performSearchSelection(selection)
            return
        }

        guard let selection else {
            clearSelection()
            return
        }
        setCurrentSelection(selection, animate: true)
        go(to: selection)
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
            view.configureSelectionObservation()
            view.configureAnnotationTapRecognition()
            view.configureViewportObservation()
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
        if let selectablePDFView = uiView as? SelectablePDFView {
            selectablePDFView.onSelectAnnotation = onSelectAnnotation
            selectablePDFView.onHighlightSelection = onHighlightSelection
            selectablePDFView.onRemoveHighlight = onRemoveHighlight
            selectablePDFView.onViewportChanged = onViewportChanged
        }

        DispatchQueue.main.async {
            if pdfView !== uiView {
                pdfView = uiView
            }
            (uiView as? SelectablePDFView)?.configureSelectionObservation()
            (uiView as? SelectablePDFView)?.configureAnnotationTapRecognition()
            (uiView as? SelectablePDFView)?.configureViewportObservation()
            onViewReady()
        }
    }
}

private final class SelectablePDFView: PDFView {
    var onSelectAnnotation: ((HighlightAnnotation.ID) -> Void)?
    var onHighlightSelection: ((HighlightColor) -> Void)?
    var onRemoveHighlight: (() -> Void)?
    var onViewportChanged: (() -> Void)?

    private var selectionToolbar: UIVisualEffectView?
    private var selectionObserver: NSObjectProtocol?
    private var viewportObservation: NSKeyValueObservation?
    private var annotationTapRecognizer: UITapGestureRecognizer?
    private var separatorView: UIView?
    private var removeButton: UIButton?
    private var showsRemoveButton = false
    private var suppressSelectionToolbar = false

    deinit {
        if let selectionObserver {
            NotificationCenter.default.removeObserver(selectionObserver)
        }
        viewportObservation?.invalidate()
    }

    func configureSelectionObservation() {
        guard selectionObserver == nil else { return }
        selectionObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.PDFViewSelectionChanged,
            object: self,
            queue: .main
        ) { [weak self] _ in
            self?.selectionDidChange()
        }
    }

    func configureAnnotationTapRecognition() {
        guard annotationTapRecognizer == nil else { return }
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleAnnotationTap(_:)))
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        addGestureRecognizer(recognizer)
        annotationTapRecognizer = recognizer
    }

    func configureViewportObservation() {
        guard viewportObservation == nil else { return }
        guard let scrollView = firstScrollView(in: self) else { return }
        viewportObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.onViewportChanged?()
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let selectionToolbar, !selectionToolbar.isHidden {
            selectionToolbar.frame = toolbarFrame()
        }
    }

    private func firstScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView {
            return scrollView
        }
        for subview in view.subviews {
            if let scrollView = firstScrollView(in: subview) {
                return scrollView
            }
        }
        return nil
    }

    private func selectionDidChange() {
        guard !suppressSelectionToolbar else {
            hideSelectionToolbar()
            return
        }

        if hasCurrentTextSelection {
            showSelectionToolbar(includeRemoveButton: false)
        } else if !showsRemoveButton {
            hideSelectionToolbar()
        }
    }

    private var hasCurrentTextSelection: Bool {
        let text = currentSelection?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !text.isEmpty
    }

    @objc private func handleAnnotationTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        let viewPoint = recognizer.location(in: self)
        guard let annotationID = appAnnotationID(at: viewPoint) else {
            if !hasCurrentTextSelection {
                hideSelectionToolbar()
            }
            return
        }

        clearSelection()
        onSelectAnnotation?(annotationID)
        showSelectionToolbar(includeRemoveButton: true)
    }

    override func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    private func appAnnotationID(at viewPoint: CGPoint) -> HighlightAnnotation.ID? {
        guard let page = page(for: viewPoint, nearest: true) else { return nil }
        let pagePoint = convert(viewPoint, to: page)
        guard let annotation = page.annotation(at: pagePoint),
              let rawID = annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: PDFAnnotationBridge.appAnnotationKey)) as? String,
              let id = UUID(uuidString: rawID) else {
            return nil
        }

        return id
    }

    private func showSelectionToolbar(includeRemoveButton: Bool) {
        showsRemoveButton = includeRemoveButton
        let toolbar = selectionToolbar ?? makeSelectionToolbar()
        if toolbar.superview == nil {
            addSubview(toolbar)
        }
        separatorView?.isHidden = !includeRemoveButton
        removeButton?.isHidden = !includeRemoveButton
        toolbar.frame = toolbarFrame()
        toolbar.isHidden = false
    }

    private func hideSelectionToolbar() {
        selectionToolbar?.isHidden = true
        showsRemoveButton = false
    }

    private func toolbarFrame() -> CGRect {
        let preferredWidth: CGFloat = showsRemoveButton ? 268 : 220
        let size = CGSize(width: min(bounds.width - 32, preferredWidth), height: 44)
        return CGRect(
            x: max(16, (bounds.width - size.width) / 2),
            y: max(16, safeAreaInsets.top + 12),
            width: size.width,
            height: size.height
        )
    }

    private func makeSelectionToolbar() -> UIVisualEffectView {
        let container = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        container.layer.cornerRadius = 10
        container.layer.masksToBounds = true

        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .equalSpacing
        stackView.spacing = 10
        stackView.translatesAutoresizingMaskIntoConstraints = false

        for color in HighlightColor.allCases {
            stackView.addArrangedSubview(highlightButton(for: color))
        }

        let separator = UIView()
        separator.backgroundColor = UIColor.separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.widthAnchor.constraint(equalToConstant: 1).isActive = true
        separator.heightAnchor.constraint(equalToConstant: 24).isActive = true
        separator.isHidden = true
        stackView.addArrangedSubview(separator)
        separatorView = separator

        let removeButton = removeHighlightButton()
        removeButton.isHidden = true
        stackView.addArrangedSubview(removeButton)
        self.removeButton = removeButton

        container.contentView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: container.contentView.leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: container.contentView.trailingAnchor, constant: -12),
            stackView.topAnchor.constraint(equalTo: container.contentView.topAnchor, constant: 6),
            stackView.bottomAnchor.constraint(equalTo: container.contentView.bottomAnchor, constant: -6)
        ])

        selectionToolbar = container
        return container
    }

    private func highlightButton(for color: HighlightColor) -> UIButton {
        let button = UIButton(type: .system)
        button.accessibilityLabel = "\(color.rawValue.capitalized): \(color.semanticLevel)"
        button.backgroundColor = color.solidUIColor
        button.layer.cornerRadius = 14
        button.layer.borderColor = UIColor.label.withAlphaComponent(0.2).cgColor
        button.layer.borderWidth = 1
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        button.addAction(UIAction { [weak self] _ in
            self?.hideSelectionToolbar()
            self?.onHighlightSelection?(color)
        }, for: .touchUpInside)
        return button
    }

    private func removeHighlightButton() -> UIButton {
        let button = UIButton(type: .system)
        button.accessibilityLabel = "Remove highlight"
        button.setImage(UIImage(systemName: "trash"), for: .normal)
        button.tintColor = .systemRed
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 32).isActive = true
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        button.addAction(UIAction { [weak self] _ in
            self?.hideSelectionToolbar()
            self?.onRemoveHighlight?()
        }, for: .touchUpInside)
        return button
    }

    fileprivate func performSearchSelection(_ selection: PDFSelection?) {
        suppressSelectionToolbar = true
        defer {
            DispatchQueue.main.async { [weak self] in
                self?.suppressSelectionToolbar = false
            }
        }

        hideSelectionToolbar()
        guard let selection else {
            clearSelection()
            return
        }
        setCurrentSelection(selection, animate: true)
        go(to: selection)
    }
}

extension PDFView {
    func showSearchSelection(_ selection: PDFSelection?) {
        if let selectablePDFView = self as? SelectablePDFView {
            selectablePDFView.performSearchSelection(selection)
            return
        }

        guard let selection else {
            clearSelection()
            return
        }
        setCurrentSelection(selection, animate: true)
        go(to: selection)
    }
}

private extension HighlightColor {
    var solidUIColor: UIColor {
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
#endif
