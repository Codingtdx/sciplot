import PDFKit
import SwiftUI

struct PDFPreviewView: NSViewRepresentable {
    private let url: URL?
    private let data: Data?

    init(url: URL) {
        self.url = url
        self.data = nil
    }

    init(data: Data) {
        self.url = nil
        self.data = data
    }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.backgroundColor = .clear
        return view
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        if let url {
            if pdfView.document?.documentURL != url {
                pdfView.document = PDFDocument(url: url)
            }
            return
        }

        if let data {
            pdfView.document = PDFDocument(data: data)
        }
    }
}

struct Base64PDFPreviewView: View {
    let base64PDF: String

    var body: some View {
        if let data = Data(base64Encoded: base64PDF),
           PDFDocument(data: data) != nil
        {
            PDFPreviewView(data: data)
                .background(.black.opacity(0.02), in: RoundedRectangle(cornerRadius: 18))
        } else {
            EmptyStateCard(
                title: "Preview unavailable",
                message: "The sidecar returned preview data that could not be decoded as a PDF."
            )
        }
    }
}
