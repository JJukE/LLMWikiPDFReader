#if os(macOS)
import AnnotationCore
import AppKit
import PDFKit

extension RectValue {
    init(_ rect: CGRect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

extension HighlightColor {
    var nsColor: NSColor {
        switch self {
        case .red:
            return NSColor.systemRed.withAlphaComponent(0.35)
        case .green:
            return NSColor.systemGreen.withAlphaComponent(0.35)
        case .yellow:
            return NSColor.systemYellow.withAlphaComponent(0.45)
        case .blue:
            return NSColor.systemBlue.withAlphaComponent(0.35)
        }
    }
}

enum PDFAnnotationBridge {
    static let appAnnotationKey = "llmWikiAnnotationID"

    static func apply(_ annotation: HighlightAnnotation, to document: PDFDocument) {
        for box in annotation.boxes {
            guard let page = document.page(at: box.page - 1) else { continue }
            let pdfAnnotation = PDFAnnotation(bounds: box.bounds.cgRect, forType: .highlight, withProperties: nil)
            pdfAnnotation.color = annotation.color.nsColor
            pdfAnnotation.contents = annotation.selectedText
            pdfAnnotation.setValue(annotation.id.uuidString, forAnnotationKey: PDFAnnotationKey(rawValue: appAnnotationKey))
            page.addAnnotation(pdfAnnotation)
        }
    }

    static func removeAppAnnotations(from document: PDFDocument) {
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            for annotation in page.annotations {
                if annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: appAnnotationKey)) != nil {
                    page.removeAnnotation(annotation)
                }
            }
        }
    }
}
#endif
