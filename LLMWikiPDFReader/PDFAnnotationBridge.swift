#if os(macOS) || os(iOS)
import AnnotationCore
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif
import PDFKit

extension RectValue {
    init(_ rect: CGRect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

#if os(macOS)
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
#elseif os(iOS)
extension HighlightColor {
    var uiColor: UIColor {
        switch self {
        case .red:
            return UIColor.systemRed.withAlphaComponent(0.35)
        case .green:
            return UIColor.systemGreen.withAlphaComponent(0.35)
        case .yellow:
            return UIColor.systemYellow.withAlphaComponent(0.45)
        case .blue:
            return UIColor.systemBlue.withAlphaComponent(0.35)
        }
    }
}
#endif

enum PDFAnnotationBridge {
    static let appAnnotationKey = "llmWikiAnnotationID"

    static func apply(_ annotation: HighlightAnnotation, to document: PDFDocument) {
        for box in annotation.boxes {
            guard let page = document.page(at: box.page - 1) else { continue }
            let pdfAnnotation = PDFAnnotation(bounds: box.bounds.cgRect, forType: .highlight, withProperties: nil)
            #if os(macOS)
            pdfAnnotation.color = annotation.color.nsColor
            #elseif os(iOS)
            pdfAnnotation.color = annotation.color.uiColor
            #endif
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

    static func removeAppAnnotations(withID id: UUID, from document: PDFDocument) {
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            for annotation in page.annotations {
                let annotationID = annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: appAnnotationKey)) as? String
                if annotationID == id.uuidString {
                    page.removeAnnotation(annotation)
                }
            }
        }
    }
}
#endif
