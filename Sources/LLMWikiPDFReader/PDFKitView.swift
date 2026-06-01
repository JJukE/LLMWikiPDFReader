#if os(macOS)
import AnnotationCore
import PDFKit
import SwiftUI

struct PDFKitView: NSViewRepresentable {
    let pdfDocument: PDFDocument?
    @Binding var pdfView: PDFView?

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.document = pdfDocument
        DispatchQueue.main.async {
            pdfView = view
        }
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document !== pdfDocument {
            nsView.document = pdfDocument
        }
    }
}
#endif
